// gsr_features.sv — 1D: baseline, delta, and SCR detection.
//
// Sits between gsr_filter and gsr_frame:
//   gsr_filter.out_valid → in_valid,  gsr_filter.y → filtered
//   baseline / delta / scr_active / scr_count / scr_amp → gsr_frame inputs
//
// Baseline:
//   While cal is high (the 30 s calibration window), sum blocks of 512
//   filtered samples in a 25-bit accumulator. Each time a block completes,
//   baseline = sum / 512 (arithmetic shift right by 9). When cal drops,
//   baseline holds the average of the most recent complete block.
//   Why 25 bits: 512 samples x 16-bit signed = 2^9 * 2^15 = 2^24 worst case,
//   so the sum needs 24 bits + 1 sign bit.
//
// Delta:
//   filtered - baseline, signed. Pure subtraction, no state.
//
// SCR detector (one FSM step per 32 Hz sample, not per clock):
//   slope = filtered - prev (change since the previous sample)
//   IDLE   : slope > SLOPE_TH         → remember where the rise started
//                                       (onset = prev), go to RISING
//   RISING : track the highest value seen (peak);
//            slope <= 0 (stopped rising) → go to PEAK
//   PEAK   : amplitude = peak - onset, count + 1, back to IDLE
//
//   scr_active is high whenever the FSM is out of IDLE, which is what
//   gsr_frame puts in status bit [1].
//
// The detector is off during calibration (a deep breath during calibration
// shouldn't count as a response) and skips the very first sample after
// reset, when prev is still 0 and the slope would be garbage — the same
// "primed" trick gsr_filter uses for its first sample.
//
// SLOPE_TH = 8 codes/sample is a placeholder: tune it on real recordings
// (the [parts] task in 1D). CAL_SHIFT is a parameter only so the testbench
// can shrink calibration from 512 samples to 4.
module gsr_features #(
    parameter int                CAL_SHIFT = 9,      // 2^9 = 512 cal samples
    parameter logic signed [15:0] SLOPE_TH = 16'sd8  // min rise per sample
) (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               cal,         // high during the calibration window
    input  logic               in_valid,    // 1-cycle pulse from gsr_filter out_valid
    input  logic signed [15:0] filtered,    // y from gsr_filter

    output logic signed [15:0] baseline,
    output logic signed [15:0] delta,       // filtered - baseline
    output logic               scr_active,  // 1 while an SCR is in progress
    output logic        [7:0]  scr_count,   // SCRs seen so far (wraps at 255)
    output logic        [15:0] scr_amp      // peak - onset of the last SCR
);
    localparam int CAL_SAMPLES = 1 << CAL_SHIFT;

    //////////////////////////////////////////////////////////////////////////
    // Baseline: average of CAL_SAMPLES filtered samples during calibration
    //////////////////////////////////////////////////////////////////////////
    logic signed [15+CAL_SHIFT:0] acc;      // running sum (25 bits when CAL_SHIFT=9)
    logic        [CAL_SHIFT-1:0]  cal_cnt;  // samples in the current block (0..511)

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc      <= '0;
            cal_cnt  <= '0;
            baseline <= '0;
        end else if (!cal) begin
            acc     <= '0;                  // clear so the next calibration
            cal_cnt <= '0;                  // starts a fresh block
        end else if (in_valid) begin
            if (cal_cnt == CAL_SAMPLES - 1) begin
                // This sample completes the block: average it and start over.
                baseline <= (acc + filtered) >>> CAL_SHIFT;
                acc      <= '0;
                cal_cnt  <= '0;
            end else begin
                acc     <= acc + filtered;
                cal_cnt <= cal_cnt + 1;
            end
        end
    end

    //////////////////////////////////////////////////////////////////////////
    // Delta: how far the signal sits above (or below) the resting baseline
    //////////////////////////////////////////////////////////////////////////
    assign delta = filtered - baseline;

    //////////////////////////////////////////////////////////////////////////
    // SCR detector FSM
    //////////////////////////////////////////////////////////////////////////
    typedef enum logic [1:0] {IDLE, RISING, PEAK} statetype;
    statetype state;

    logic signed [15:0] prev;    // previous filtered sample
    logic signed [15:0] onset;   // value where the rise started
    logic signed [15:0] peak;    // highest value seen during the rise
    logic               primed;  // 0 until the first sample makes prev valid

    logic signed [15:0] slope;
    assign slope = filtered - prev;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            prev      <= '0;
            onset     <= '0;
            peak      <= '0;
            primed    <= 1'b0;
            scr_count <= '0;
            scr_amp   <= '0;
        end else if (in_valid) begin
            prev   <= filtered;
            primed <= 1'b1;
            if (primed && !cal) begin
                case (state)
                    IDLE:   if (slope > SLOPE_TH) begin
                                onset <= prev;        // where the rise began
                                peak  <= filtered;
                                state <= RISING;
                            end
                    RISING: begin
                                if (filtered > peak) peak <= filtered;
                                if (slope <= 16'sd0) state <= PEAK;
                            end
                    PEAK:   begin
                                scr_amp   <= peak - onset;
                                scr_count <= scr_count + 8'd1;
                                state     <= IDLE;
                            end
                    default: state <= IDLE;
                endcase
            end
        end
    end

    assign scr_active = (state != IDLE);
endmodule
