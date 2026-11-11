// ads1118_model.sv — behavioral ADS1118 for simulation only.
//
// - Shifts DOUT on SCLK rising edges, captures DIN on falling edges (mode 1).
// - Returns the conversion from the PREVIOUS transaction (like the real part).
// - The signal is a slow ramp plus an SCR-shaped bump (fast rise, slow decay)
//   so later stages (filter, baseline, SCR detector) can reuse this model.
// - Checks every config word it receives against EXPECT_CFG.
`timescale 1ns/1ps
module ads1118_model #(
    parameter logic [15:0] EXPECT_CFG = 16'hC36B,
    parameter int          NSAMP      = 256
) (
    input  logic cs_n,
    input  logic sclk,
    input  logic din,
    output logic dout
);
    logic signed [15:0] samples [0:NSAMP-1];
    logic        [15:0] conv_result;   // what the next read returns
    logic        [15:0] shift_out, shift_in;
    integer             n_txn, n_bits, cfg_errors;
    bit                 in_txn = 0;

    // Build the test signal: ~1.0 V baseline (8000 codes) with a slow drift,
    // plus an SCR bump starting at sample 100: ~1.5 s rise, ~4 s decay at 32 Hz.
    initial begin : build
        integer i;
        real t, bump;
        for (i = 0; i < NSAMP; i = i + 1) begin
            bump = 0.0;
            if (i >= 100) begin
                t    = (i - 100) / 32.0;                 // seconds since onset
                bump = 2000.0 * (1.0 - $exp(-t / 0.5)) * $exp(-t / 4.0);
            end
            samples[i] = $rtoi(8000.0 + 2.0 * i + bump);
        end
        conv_result = 16'h0000;  // power-up: first read returns 0
        n_txn       = 0;
        cfg_errors  = 0;
        dout        = 1'b1;      // DOUT/DRDY high (pulled up) while idle
    end

    // CS falls: load the previous conversion into the output shifter.
    always @(negedge cs_n) begin
        shift_out = conv_result;
        n_bits    = 0;
        in_txn    = 1;
    end

    // Rising edge: present the next bit (MSB first).
    always @(posedge sclk) if (!cs_n) begin
        dout      <= #20 shift_out[15];   // small clock-to-out delay
        shift_out =  {shift_out[14:0], 1'b0};
    end

    // Falling edge: capture DIN.
    always @(negedge sclk) if (!cs_n) begin
        shift_in = {shift_in[14:0], din};
        n_bits   = n_bits + 1;
    end

    // CS rises: check the config, "start" a conversion for next time.
    always @(posedge cs_n) if (in_txn) begin   // ignore the X->1 edge at reset
        in_txn = 0;
        if (n_bits != 16) $display("[%0t] MODEL: expected 16 SCLKs, got %0d", $time, n_bits);
        if (shift_in != EXPECT_CFG) begin
            $display("[%0t] MODEL: bad config 0x%04h (expected 0x%04h)", $time, shift_in, EXPECT_CFG);
            cfg_errors = cfg_errors + 1;
        end
        if (shift_in[15]) conv_result = samples[n_txn % NSAMP];
        n_txn = n_txn + 1;
        dout  = 1'b1;
    end
endmodule
