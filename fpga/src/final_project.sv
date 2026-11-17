// tb_final_project.sv — end-to-end test of final_project:
//   fake ADS1118 → FPGA (1A–1E) → fake STM32 reading frames at 1.25 MHz.
//
// Checks on every frame: header, checksum, seq +1, delta = filtered - baseline.
// Checks on every new sample:
//   raw      = the ADC model's samples, in order (through the BRAM buffer)
//   filtered = bit-exact IIR of raw (same math as gsr_filter)
// End checks: baseline set during calibration, the model's SCR bump detected.
//
// Timing scaled 50x (tick 625 us, frames every 200 us). Calibration shortened
// to 16 samples (CAL_SHIFT = 4).
`timescale 1ns/1ps
module tb_final_project;
    localparam int NSAMPLES  = 220;   // ADC model bump starts at sample 100
    localparam int CAL_START = 40;    // let the filter settle first
    localparam int CAL_END   = 70;

    logic adc_cs_n, adc_sclk, adc_din, adc_dout;
    logic mcu_sclk, mcu_cs_n, mcu_miso, mcu_cal = 0, led;
    logic [127:0] rx;
    int           n_frames;

    final_project #(.TICK_PERIOD(7_500), .CAL_SHIFT(4)) dut (.*);

    ads1118_model u_adc (.cs_n(adc_cs_n), .sclk(adc_sclk), .din(adc_din), .dout(adc_dout));

    stm32_spi_master_model #(.SCLK_HALF_NS(400.0)) u_mcu
        (.cs_n(mcu_cs_n), .sclk(mcu_sclk), .miso(mcu_miso), .rx, .n_frames);

    // ---------------- reference: expected raw and filtered ----------------
    // The ADC returns the previous conversion (read 0 gives 0, read k gives
    // samples[k-1]); final_project drops read 0, so sample k = samples[k].
    function automatic logic signed [15:0] exp_raw(int k);
        return u_adc.samples[k];
    endfunction

    logic signed [18:0] acc;      // IIR model, K = 3 (same as gsr_filter)

    // ---------------- frame checker ----------------
    int errors = 0, samples = 0, frames = 0, led_on = 0;
    logic [7:0] csum, prev_seq;
    logic signed [15:0] raw, filt, base, delta, exp_f;
    logic [7:0]  status, cnt;
    logic [15:0] amp;
    bit have_prev = 0;
    logic signed [15:0] base_after_cal = 0;
    logic [7:0] final_cnt; logic [15:0] final_amp;
    logic [7:0] cnt_before_bump = 0;

    task automatic err(string msg);
        if (errors < 15) $display("frame %0d: %s", frames, msg);
        errors++;
    endtask

    always @(n_frames) if (n_frames > 0) begin
        frames++;
        csum = 8'b0;
        for (int i = 0; i < 15; i++) csum ^= rx[127-8*i -: 8];
        {raw, filt, base, delta} = rx[111:48];
        status = rx[47:40]; cnt = rx[39:32]; amp = rx[31:16];

        if (rx[127:120] !== 8'b1010_0101) err("bad header");
        if (rx[7:0] !== csum)             err("bad checksum");
        if (have_prev && rx[119:112] !== prev_seq + 8'd1) err("seq gap");
        prev_seq = rx[119:112]; have_prev = 1;
        if (delta !== filt - base) err($sformatf("delta %0d != filtered %0d - baseline %0d", delta, filt, base));

        if (status[0]) begin
            if (raw !== exp_raw(samples))
                err($sformatf("sample %0d raw=%0d expected %0d", samples, raw, exp_raw(samples)));
            acc   = (samples == 0) ? (exp_raw(0) <<< 3) : acc + exp_raw(samples) - (acc >>> 3);
            exp_f = acc >>> 3;
            if (filt !== exp_f)
                err($sformatf("sample %0d filtered=%0d expected %0d", samples, filt, exp_f));
            if (samples == CAL_END + 5) base_after_cal = base;
            if (samples == 99) cnt_before_bump = cnt;       // bump starts at 100
            samples++;
        end
        final_cnt = cnt; final_amp = amp;
    end

    always @(posedge led) led_on++;

    // ---------------- calibration window (what the MCU will do) ----------------
    initial begin
        wait (samples == CAL_START); mcu_cal = 1;
        wait (samples == CAL_END);   mcu_cal = 0;
    end

    initial begin
        $dumpfile("tb_final_project.vcd");
        // Dump only what's worth looking at. Dumping everything (including the
        // 12 MHz clock for ~1.6M cycles) makes a waveform file of 100+ MB.
        $dumpvars(1, tb_final_project);          // ADC + MCU SPI wires, cal, led
        $dumpvars(0, tb_final_project.dut.raw);  // values that change once per sample
        $dumpvars(0, tb_final_project.dut.filtered);
        $dumpvars(0, tb_final_project.dut.baseline);
        $dumpvars(0, tb_final_project.dut.delta);
        $dumpvars(0, tb_final_project.dut.scr_active);
        $dumpvars(0, tb_final_project.dut.scr_count);
        $dumpvars(0, tb_final_project.dut.scr_amp);
        wait (samples == NSAMPLES);
        #1000;
        $display("--------------------------------------------");
        $display("frames checked   : %0d", frames);
        $display("samples checked  : %0d (raw + filtered bit-exact)", samples);
        $display("baseline after cal: %0d  (signal ~%0d at that point)", base_after_cal, exp_raw(CAL_END));
        $display("SCRs before bump : %0d  (expect 0)", cnt_before_bump);
        $display("SCRs detected    : %0d, last amplitude %0d codes, LED pulses %0d", final_cnt, final_amp, led_on);
        $display("errors           : %0d", errors);
        $display("%s", (errors == 0 && base_after_cal > 16'sd7000 && cnt_before_bump == 0 &&
                              final_cnt == 1 && final_amp > 16'd500 && final_amp < 16'd3000 && led_on >= 1) ? "PASS" : "FAIL");
        $finish;
    end
endmodule
