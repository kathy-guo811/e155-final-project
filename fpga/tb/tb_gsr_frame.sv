// tb_gsr_frame.sv — checks gsr_frame + spi_slave_tx against a fake STM32.
//
// For every frame the fake MCU receives, checks:
//   - header is 8'b1010_0101
//   - checksum (XOR of bytes 0–14) is correct
//   - seq goes up by exactly 1 each frame
//   - every field equals what the testbench fed in before that frame started
//   - new_sample is 1 only if a sample arrived since the previous frame
// Also forces one sample to land on the exact clock cycle a frame is latched,
// to check the frame stays consistent.
//
// Timing is scaled down 50x for a fast sim:
//   frames every 200 us (real: 10 ms), samples every 625 us (real: 31.25 ms).
`timescale 1ns/1ps
module tb_gsr_frame;
    localparam int  NFRAMES          = 60;
    localparam real SAMPLE_PERIOD_NS = 625_000.0;
    localparam int  COLLIDE_FRAME    = 20;   // frame where a sample hits the latch cycle

    logic clk = 0, rst_n = 0;
    always #41.667 clk = ~clk;   // 12 MHz

    // GSR inputs
    logic               sample_valid = 0;
    logic signed [15:0] raw = 0, filtered = 0, baseline = 0, delta = 0;
    logic               scr_active = 0;
    logic        [7:0]  scr_count = 0;
    logic        [15:0] scr_amp = 0;

    // SPI wires
    logic sclk, cs_n, miso;
    logic [127:0] rx;
    int           n_frames;

    gsr_frame dut (
        .clk, .rst_n, .sample_valid,
        .raw, .filtered, .baseline, .delta,
        .scr_active, .scr_count, .scr_amp,
        .sclk, .cs_n, .miso
    );

    stm32_spi_master_model u_mcu (.cs_n, .sclk, .miso, .rx, .n_frames);

    // ---------------- drive samples ----------------
    task automatic send_sample();
        @(posedge clk);
        raw          <= $random;
        filtered     <= $random;
        baseline     <= $random;
        delta        <= $random;            // includes negative values
        scr_active   <= $random;
        scr_count    <= $random;
        scr_amp      <= $random;
        sample_valid <= 1'b1;
        @(posedge clk);
        sample_valid <= 1'b0;
    endtask

    // Periodic samples, with a little jitter so they land at varied
    // points relative to the frames (before, during, between).
    initial begin
        wait (rst_n);
        forever begin
            #(SAMPLE_PERIOD_NS + ($urandom % 50_000));
            send_sample();
        end
    end

    // Directed collision: when the synchronized CS is about to show a falling
    // edge on the next cycle, fire a sample so sample_valid and the frame
    // latch happen on the SAME clock edge.
    logic collided = 0;
    always @(posedge clk) begin
        if (!collided && n_frames == COLLIDE_FRAME &&
            dut.u_slave.cs_s[0] == 1'b0 && dut.u_slave.cs_s[1] == 1'b1) begin
            raw <= 16'b0111_0111_0111_0111; filtered <= 16'b0001_0010_0011_0100;
            baseline <= 16'b0; delta <= -16'sd5; scr_active <= 1;
            scr_count <= 8'd99; scr_amp <= 16'd4242;
            sample_valid <= 1'b1;
            collided <= 1'b1;
        end else if (collided && sample_valid && n_frames == COLLIDE_FRAME) begin
            sample_valid <= 1'b0;
        end
    end

    // ---------------- reference model ----------------
    // Mirrors what the frame SHOULD contain, using only the values the
    // testbench sent (not the DUT's internal registers).
    logic signed [15:0] c_raw = 0, c_filt = 0, c_base = 0, c_delta = 0;
    logic               c_scr_active = 0, c_new = 0;
    logic        [7:0]  c_scr_count = 0;
    logic        [15:0] c_scr_amp = 0;

    logic [119:0] exp_q [$];     // expected bytes 0–14, one per frame
    logic         exp_new_q [$];
    int           frames_latched = 0;
    int           collisions_seen = 0;

    always @(posedge clk) if (rst_n) begin
        // 1. If a frame is latched on this edge, record what it should hold
        //    (values committed BEFORE this edge).
        if (dut.u_slave.cs_fall) begin
            exp_q.push_back({8'b1010_0101, frames_latched[7:0],
                             c_raw, c_filt, c_base, c_delta,
                             {6'b0, c_scr_active, c_new},
                             c_scr_count, c_scr_amp, 8'b0});
            if (sample_valid) collisions_seen++;
            frames_latched++;
        end
        // 2. Then apply this edge's sample (it shows up in the NEXT frame).
        if (dut.u_slave.cs_fall) c_new = sample_valid;
        else if (sample_valid)   c_new = 1'b1;
        if (sample_valid) begin
            c_raw = raw; c_filt = filtered; c_base = baseline; c_delta = delta;
            c_scr_active = scr_active; c_scr_count = scr_count; c_scr_amp = scr_amp;
        end
    end

    // ---------------- check each received frame ----------------
    int errors = 0, checked = 0, n_new = 0;
    logic [7:0] csum;
    logic [119:0] exp_body;

    function automatic string bytes_str(input logic [127:0] f);
        string s = "";
        for (int i = 0; i < 16; i++) s = {s, $sformatf("%08b ", f[127-8*i -: 8])};
        return s;
    endfunction

    always @(n_frames) if (n_frames > 0) begin
        exp_body = exp_q.pop_front();

        csum = 8'b0;
        for (int i = 0; i < 15; i++) csum ^= rx[127 - 8*i -: 8];

        if (rx[127:120] !== 8'b1010_0101) begin
            $display("frame %0d: bad header %08b", checked, rx[127:120]); errors++;
        end
        if (rx[7:0] !== csum) begin
            $display("frame %0d: bad checksum got %08b expected %08b", checked, rx[7:0], csum); errors++;
        end
        if (rx[127:8] !== exp_body) begin
            $display("frame %0d: contents mismatch", checked);
            $display("  got      %s", bytes_str(rx));
            $display("  expected %s", bytes_str({exp_body, 8'b0}));
            errors++;
        end
        if (rx[40]) n_new++;     // byte 10 (status) = rx[47:40]; bit 0 = new_sample
        checked++;
    end

    initial begin
        $dumpfile("tb_gsr_frame.vcd");
        $dumpvars(0, tb_gsr_frame);
        repeat (5) @(posedge clk);
        rst_n = 1;
        wait (n_frames == NFRAMES);
        #1000;
        $display("--------------------------------------------");
        $display("frames checked      : %0d", checked);
        $display("frames w/ new sample: %0d  (expect ~1 in 3)", n_new);
        $display("same-cycle collision: %0d  (expect 1)", collisions_seen);
        $display("errors              : %0d", errors);
        $display("%s", (errors == 0 && checked == NFRAMES && collisions_seen >= 1) ? "PASS" : "FAIL");
        $finish;
    end
endmodule
