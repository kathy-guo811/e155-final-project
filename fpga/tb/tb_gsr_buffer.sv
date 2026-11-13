// tb_gsr_buffer.sv — checks gsr_buffer wraps and reads back correctly.
//
// Uses AW = 3 (depth 8) so the wrap can be tested with a handful of
// hardcoded writes. The logic is identical for AW = 10.
//
// Writes 101..110 (10 samples) into an 8-deep buffer:
//   101..108 fill addresses 0..7, then 109 and 110 wrap to addresses 0 and 1.
// Expected contents afterwards:
//   addr: 0    1    2    3    4    5    6    7
//   data: 109  110  103  104  105  106  107  108
// and wptr = 2.
`timescale 1ns/1ps
module tb_gsr_buffer;
    logic        clk, rst_n, we;
    logic [15:0] wdata, rdata;
    logic [2:0]  raddr, wptr;
    integer      errors;

    gsr_buffer #(.AW(3)) dut (
        .clk(clk), .rst_n(rst_n), .we(we), .wdata(wdata),
        .raddr(raddr), .rdata(rdata), .wptr(wptr)
    );

    // 10 ns clock, rising edges at 5, 15, 25, ...
    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        errors = 0;
        rst_n = 0; we = 0; wdata = 0; raddr = 0;
        #12 rst_n = 1;

        // ---- Write 10 samples (each #10 contains one rising edge) ----
        we = 1;
        wdata = 16'd101; #10;
        wdata = 16'd102; #10;
        wdata = 16'd103; #10;
        wdata = 16'd104; #10;
        wdata = 16'd105; #10;
        wdata = 16'd106; #10;
        wdata = 16'd107; #10;
        wdata = 16'd108; #10;   // buffer full, wptr wraps to 0
        wdata = 16'd109; #10;   // overwrites addr 0
        wdata = 16'd110; #10;   // overwrites addr 1
        we = 0;

        if (wptr !== 3'd2) begin
            $display("ERROR: wptr = %0d, expected 2", wptr); errors = errors + 1;
        end

        // ---- Read back: set raddr, wait one edge, check rdata ----
        raddr = 3'd0; #10;
        if (rdata !== 16'd109) begin $display("ERROR addr 0: got %0d, expected 109", rdata); errors = errors + 1; end
        raddr = 3'd1; #10;
        if (rdata !== 16'd110) begin $display("ERROR addr 1: got %0d, expected 110", rdata); errors = errors + 1; end
        raddr = 3'd2; #10;
        if (rdata !== 16'd103) begin $display("ERROR addr 2: got %0d, expected 103", rdata); errors = errors + 1; end
        raddr = 3'd3; #10;
        if (rdata !== 16'd104) begin $display("ERROR addr 3: got %0d, expected 104", rdata); errors = errors + 1; end
        raddr = 3'd4; #10;
        if (rdata !== 16'd105) begin $display("ERROR addr 4: got %0d, expected 105", rdata); errors = errors + 1; end
        raddr = 3'd5; #10;
        if (rdata !== 16'd106) begin $display("ERROR addr 5: got %0d, expected 106", rdata); errors = errors + 1; end
        raddr = 3'd6; #10;
        if (rdata !== 16'd107) begin $display("ERROR addr 6: got %0d, expected 107", rdata); errors = errors + 1; end
        raddr = 3'd7; #10;
        if (rdata !== 16'd108) begin $display("ERROR addr 7: got %0d, expected 108", rdata); errors = errors + 1; end

        // ---- Newest sample is at wptr - 1 ----
        raddr = wptr - 3'd1; #10;
        if (rdata !== 16'd110) begin $display("ERROR newest: got %0d, expected 110", rdata); errors = errors + 1; end

        // ---- Reset clears wptr (memory keeps its contents) ----
        rst_n = 0; #10;
        if (wptr !== 3'd0) begin $display("ERROR: wptr = %0d after reset, expected 0", wptr); errors = errors + 1; end
        rst_n = 1;

        if (errors == 0) $display("PASS: all checks passed");
        else             $display("FAIL: %0d errors", errors);
        $finish;
    end
endmodule
