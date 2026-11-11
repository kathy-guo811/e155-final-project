// tick_gen.sv — one-cycle pulse every PERIOD clocks.
// 12 MHz / 375,000 = 32 Hz exactly. In single-shot mode this tick, not the
// ADS1118 DR field, sets the sample rate.
// A 19-bit counter covers 0..524,287, so 375,000 fits.
module tick_gen #(
    parameter int PERIOD = 375_000,
    parameter int W      = $clog2(PERIOD)
) (
    input  logic clk,
    input  logic rst_n,
    output logic tick
);
    logic [W-1:0] cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt  <= '0;
            tick <= 1'b0;
        end else if (cnt == PERIOD - 1) begin
            cnt  <= '0;
            tick <= 1'b1;
        end else begin
            cnt  <= cnt + 1'b1;
            tick <= 1'b0;
        end
    end
endmodule
