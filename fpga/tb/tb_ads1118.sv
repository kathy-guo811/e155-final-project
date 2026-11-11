// tb_ads1118.sv — tick_gen + ads1118_spi against the behavioral model.
// Checks: config word, bit order, captured data (with the 1-sample latency),
// and that SCLK never exceeds 4 MHz.
`timescale 1ns/1ps
module tb_ads1118;
    localparam int NTXN = 200;

    logic clk = 0, rst_n = 0;
    always #41.667 clk = ~clk;   // 12 MHz

    logic tick, cs_n, sclk, mosi, miso, data_valid, busy;
    logic [15:0] data;

    // Shorten the tick period in sim (real hardware: 375_000).
    tick_gen #(.PERIOD(400)) u_tick (.clk, .rst_n, .tick);

    ads1118_spi u_spi (
        .clk, .rst_n, .start(tick),
        .cs_n, .sclk, .mosi, .miso,
        .data, .data_valid, .busy
    );

    ads1118_model u_adc (.cs_n, .sclk, .din(mosi), .dout(miso));

    // SCLK period check
    realtime last_rise = 0, min_period = 1e9;
    always @(posedge sclk) begin
        if (last_rise > 0 && !cs_n && ($realtime - last_rise) < min_period)
            min_period = $realtime - last_rise;
        last_rise = $realtime;
    end

    // Data check: read k returns sample[k-1]; read 0 returns 0.
    integer k = 0, errors = 0;
    logic [15:0] expected;
    integer f;
    initial f = $fopen("captured.csv", "w");
    always @(posedge clk) if (data_valid) begin
        expected = (k == 0) ? 16'h0000 : u_adc.samples[k-1];
        if (data !== expected) begin
            $display("MISMATCH read %0d: got 0x%04h, expected 0x%04h", k, data, expected);
            errors = errors + 1;
        end
        $fwrite(f, "%0d,%0d\n", k, $signed(data));
        k = k + 1;
    end

    initial begin
        $dumpfile("tb_ads1118.vcd");
        $dumpvars(0, tb_ads1118);
        repeat (5) @(posedge clk);
        rst_n = 1;
        wait (k == NTXN);
        $fclose(f);
        $display("--------------------------------------------");
        $display("transactions : %0d", k);
        $display("data errors  : %0d", errors);
        $display("config errors: %0d", u_adc.cfg_errors);
        $display("min SCLK per : %0.1f ns (%0.2f MHz, limit 4 MHz)", min_period, 1000.0/min_period);
        $display("%s", (errors == 0 && u_adc.cfg_errors == 0 && min_period >= 250) ? "PASS" : "FAIL");
        $finish;
    end
endmodule
