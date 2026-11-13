// gsr_filter.sv — first-order IIR low-pass (exponential moving average).
//
//   y[n] = y[n-1] + (x[n] - y[n-1]) / 2^K        (K = 3 → alpha = 1/8)
//
// Why IIR instead of an 8-tap moving average:
//   - one accumulator register instead of 8 stored samples + an adder tree
//   - similar smoothing (time constant ~8 samples = 0.25 s at 32 Hz),
//     fast enough to keep the shape of an SCR (1–3 s rise)
//
// Fixed-point detail: if you store y as a plain 16-bit integer and do
// y += (x - y) >>> 3, any difference smaller than 8 codes shifts to 0 and y
// gets stuck up to 7 codes away from the input (a "dead band"). To avoid that,
// keep K extra fractional bits: acc holds y * 2^K.
//
//   acc[n] = acc[n-1] + x[n] - (acc[n-1] >>> K)
//   y[n]   = acc[n] >>> K
//
// The first sample after reset loads acc = x << K, so the output starts at
// the input level instead of ramping up from 0.
//
// The Python script scripts/gen_filter_vectors.py implements this exact
// integer math, so the testbench can demand bit-exact matches.
module gsr_filter #(
    parameter int K = 3            // alpha = 1 / 2^K
) (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               in_valid,   // 1-cycle pulse: new sample on x
    input  logic signed [15:0] x,          // raw ADC code
    output logic               out_valid,  // 1-cycle pulse: y updated
    output logic signed [15:0] y           // filtered code
);
    logic signed [15+K:0] acc;             // y scaled by 2^K (19 bits for K=3)
    logic                 primed;          // 0 until the first sample arrives

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc       <= '0;
            primed    <= 1'b0;
            out_valid <= 1'b0;
        end else begin
            out_valid <= in_valid;
            if (in_valid) begin
                if (!primed) begin
                    acc    <= $signed(x) <<< K;
                    primed <= 1'b1;
                end else begin
                    acc <= acc + x - (acc >>> K);
                end
            end
        end
    end

    assign y = acc >>> K;   // upper 16 bits; valid on the cycle out_valid is high
endmodule
