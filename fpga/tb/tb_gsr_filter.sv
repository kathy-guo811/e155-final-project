// tb_gsr_filter.sv — feeds Python-generated noisy samples into gsr_filter
// and checks every output against the Python reference, bit for bit.
//
// Generate the vectors first (from this folder):
//   python3 ../../scripts/gen_filter_vectors.py .
`timescale 1ns/1ps
module tb_gsr_filter;
    localparam int N   = 1024;   // must match N in gen_filter_vectors.py
    localparam int GAP = 10;     // clk cycles between samples (real hw: 375,000)

    logic clk = 0, rst_n = 0;
    always #41.667 clk = ~clk;   // 12 MHz

    logic               in_valid = 0, out_valid;
    logic signed [15:0] x = 0, y;

    gsr_filter dut (.clk, .rst_n, .in_valid, .x, .out_valid, .y);

    logic [15:0] vin  [0:N-1];
    logic [15:0] vexp [0:N-1];

    integer n_out = 0, errors = 0;

    // Check each output as it comes out
    always @(posedge clk) if (out_valid) begin
        if (y !== $signed(vexp[n_out])) begin
            if (errors < 10)
                $display("MISMATCH sample %0d: in=%0d got=%0d expected=%0d",
                         n_out, $signed(vin[n_out]), y, $signed(vexp[n_out]));
            errors = errors + 1;
        end
        n_out = n_out + 1;
    end

    initial begin
        $readmemh("filter_in.hex", vin);
        $readmemh("filter_expected.hex", vexp);
        if (vin[0] === 16'bx) begin
            $display("ERROR: filter_in.hex not found. Run gen_filter_vectors.py first.");
            $finish;
        end
        $dumpfile("tb_gsr_filter.vcd");
        $dumpvars(0, tb_gsr_filter);

        repeat (5) @(posedge clk);
        rst_n = 1;

        // Drive one sample every GAP cycles, like data_valid from ads1118_spi
        for (int i = 0; i < N; i++) begin
            @(posedge clk);
            x        <= vin[i];
            in_valid <= 1;
            @(posedge clk);
            in_valid <= 0;
            repeat (GAP - 2) @(posedge clk);
        end
        repeat (5) @(posedge clk);

        $display("--------------------------------------------");
        $display("samples checked: %0d / %0d", n_out, N);
        $display("mismatches     : %0d", errors);
        $display("%s", (errors == 0 && n_out == N) ? "PASS" : "FAIL");
        $finish;
    end
endmodule
