// tb_gsr_features.sv — 1D testbench: step input and an SCR-shaped bump.
//
// CAL_SHIFT is overridden to 2, so calibration is 4 samples instead of 512
// and the whole test fits in a short, hand-written stimulus. SLOPE_TH stays
// at its default of 8.
//
// Test plan (each "sample" is one in_valid pulse):
//   1. cal = 1, feed 992, 1000, 1000, 1008  → baseline = 4000/4 = 1000
//   2. cal = 0, feed 1008                   → delta = 8, no SCR
//   3. step to 1208 and hold                → delta = 208, and the jump is one
//      SCR: amp = 1208 - 1008 = 200, count = 1
//   4. slow drift (+4)                      → slope under threshold, no SCR
//   5. bump: 1232, 1272, 1292, then falling → SCR with onset 1212, peak 1292:
//      amp = 80, count = 2
`timescale 1ns/1ps
module tb_gsr_features;
    logic clk = 0;
    always #5 clk = ~clk;   // period is arbitrary: everything moves on in_valid

    logic               rst_n = 0, cal = 0, in_valid = 0;
    logic signed [15:0] filtered = 0;
    logic signed [15:0] baseline, delta;
    logic               scr_active;
    logic        [7:0]  scr_count;
    logic        [15:0] scr_amp;

    integer errors = 0;

    gsr_features #(.CAL_SHIFT(2)) dut (
        .clk, .rst_n, .cal, .in_valid, .filtered,
        .baseline, .delta, .scr_active, .scr_count, .scr_amp
    );

    initial begin
        $dumpfile("tb_gsr_features.vcd");
        $dumpvars(0, tb_gsr_features);

        #20; rst_n = 1; cal = 1; #10;

        // ---- calibration: 4 samples averaging to 1000 ----
        filtered = 16'sd992;  in_valid = 1; #10; in_valid = 0; #30;
        filtered = 16'sd1000; in_valid = 1; #10; in_valid = 0; #30;
        filtered = 16'sd1000; in_valid = 1; #10; in_valid = 0; #30;
        filtered = 16'sd1008; in_valid = 1; #10; in_valid = 0; #30;

        if (baseline !== 16'sd1000) begin
            errors = errors + 1;
            $display("FAIL: baseline = %0d, expected 1000", baseline);
        end
        if (scr_count !== 8'd0) begin
            errors = errors + 1;
            $display("FAIL: scr_count = %0d during cal, expected 0", scr_count);
        end

        cal = 0; #10;

        // ---- flat sample: delta only ----
        filtered = 16'sd1008; in_valid = 1; #10; in_valid = 0; #30;
        if (delta !== 16'sd8) begin
            errors = errors + 1;
            $display("FAIL: delta = %0d, expected 8", delta);
        end

        // ---- step: 1008 -> 1208, slope 200 starts an SCR ----
        filtered = 16'sd1208; in_valid = 1; #10; in_valid = 0; #30;
        if (delta !== 16'sd208) begin
            errors = errors + 1;
            $display("FAIL: delta = %0d after step, expected 208", delta);
        end
        if (scr_active !== 1'b1) begin
            errors = errors + 1;
            $display("FAIL: scr_active = %b after step, expected 1", scr_active);
        end

        filtered = 16'sd1208; in_valid = 1; #10; in_valid = 0; #30; // slope 0 -> PEAK
        filtered = 16'sd1208; in_valid = 1; #10; in_valid = 0; #30; // PEAK latches result

        if (scr_amp !== 16'd200) begin
            errors = errors + 1;
            $display("FAIL: scr_amp = %0d for step, expected 200", scr_amp);
        end
        if (scr_count !== 8'd1) begin
            errors = errors + 1;
            $display("FAIL: scr_count = %0d after step, expected 1", scr_count);
        end
        if (scr_active !== 1'b0) begin
            errors = errors + 1;
            $display("FAIL: scr_active = %b back in idle, expected 0", scr_active);
        end

        // ---- slow drift: slope 4 is under the threshold of 8 ----
        filtered = 16'sd1212; in_valid = 1; #10; in_valid = 0; #30;
        if (scr_active !== 1'b0) begin
            errors = errors + 1;
            $display("FAIL: slow drift triggered the detector");
        end

        // ---- SCR bump: rise 1212 -> 1292, then fall ----
        filtered = 16'sd1232; in_valid = 1; #10; in_valid = 0; #30; // slope 20 -> RISING
        filtered = 16'sd1272; in_valid = 1; #10; in_valid = 0; #30; // slope 40
        filtered = 16'sd1292; in_valid = 1; #10; in_valid = 0; #30; // slope 20, peak
        filtered = 16'sd1282; in_valid = 1; #10; in_valid = 0; #30; // slope -10 -> PEAK
        filtered = 16'sd1262; in_valid = 1; #10; in_valid = 0; #30; // PEAK latches result

        if (scr_amp !== 16'd80) begin
            errors = errors + 1;
            $display("FAIL: scr_amp = %0d for bump, expected 80 (1292-1212)", scr_amp);
        end
        if (scr_count !== 8'd2) begin
            errors = errors + 1;
            $display("FAIL: scr_count = %0d after bump, expected 2", scr_count);
        end

        $display("--------------------------------------------");
        $display("errors: %0d", errors);
        $display("%s", (errors == 0) ? "PASS" : "FAIL");
        $finish;
    end
endmodule
