// final_project.sv — FPGA top level: the full GSR path (1A–1E).
//
//   HSOSC 12 MHz
//   tick_gen (32 Hz) → ads1118_spi ──data──┬→ gsr_buffer (BRAM, 1024 samples)
//                       ↕ ADC SPI          └→ gsr_filter → gsr_features (1D)
//                                                              │
//   STM32 SPI ↔ gsr_frame ← raw (newest sample read back from BRAM),
//                           filtered, baseline, delta, SCR fields
//
// Calibration: the MCU drives mcu_cal high for the 30 s calibration window
// (session state machine, 4B). While it is high, gsr_features averages the
// filtered signal into the baseline and the SCR detector is off.
//
// Clock: internal 48 MHz HSOSC / 4 = 12 MHz. Reset: internal power-on reset.
module final_project #(
    parameter int                 TICK_PERIOD = 375_000,  // 12 MHz / 375,000 = 32 Hz
    parameter int                 CAL_SHIFT   = 9,        // baseline = average of 512 samples
    parameter logic signed [15:0] SLOPE_TH    = 16'sd8    // SCR rise threshold (tune on real data)
) (
    // ADS1118 (FPGA is SPI master, mode 1)
    output logic adc_cs_n,
    output logic adc_sclk,
    output logic adc_din,      // to ADS1118 DIN
    input  logic adc_dout,     // from ADS1118 DOUT/DRDY

    // STM32 (FPGA is SPI slave, mode 0)
    input  logic mcu_sclk,     // STM32 PA5
    input  logic mcu_cs_n,     // STM32 PA8
    output logic mcu_miso,     // STM32 PA6
    input  logic mcu_cal,      // STM32 GPIO: high during calibration

    output logic led           // on while an SCR is in progress
);
    // ---------------- clock and power-on reset ----------------
    logic clk;
    HSOSC #(.CLKHF_DIV("0b10")) hf_osc (       // 48 MHz / 4 = 12 MHz
        .CLKHFPU(1'b1), .CLKHFEN(1'b1), .CLKHF(clk)
    );

    logic [3:0] por_cnt = 4'b0000;             // FFs start at 0 after configuration
    logic       rst_n;
    always_ff @(posedge clk)
        if (por_cnt != 4'b1111) por_cnt <= por_cnt + 4'b0001;
    assign rst_n = (por_cnt == 4'b1111);

    // mcu_cal comes from the STM32's clock domain: synchronize it
    logic [1:0] cal_s;
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) cal_s <= 2'b00;
        else        cal_s <= {cal_s[0], mcu_cal};

    // ---------------- 1A: sample the ADC at 32 Hz ----------------
    logic        tick, data_valid;
    logic [15:0] adc_data;

    logic        adc_valid, first_done;

    tick_gen #(.PERIOD(TICK_PERIOD)) u_tick (.clk, .rst_n, .tick);

    ads1118_spi u_adc (
        .clk, .rst_n, .start(tick),
        .cs_n(adc_cs_n), .sclk(adc_sclk), .mosi(adc_din), .miso(adc_dout),
        .data(adc_data), .data_valid(adc_valid), .busy()
    );

    // Drop the very first ADC reading. Because each read returns the PREVIOUS
    // conversion, the first read after power-up is always 0. Letting it
    // through starts the filter at 0, and its climb to the real level looks
    // like a huge SCR.
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)         first_done <= 1'b0;
        else if (adc_valid) first_done <= 1'b1;
    assign data_valid = adc_valid & first_done;

    // ---------------- 1B: store raw samples in block RAM ----------------
    logic [9:0]         wptr, newest_addr;
    logic [15:0]        buf_newest;
    logic signed [15:0] raw;
    assign newest_addr = wptr - 10'd1;          // newest sample is at wptr - 1
    assign raw         = buf_newest;

    gsr_buffer #(.AW(10)) u_buf (
        .clk, .rst_n,
        .we(data_valid), .wdata(adc_data),
        .raddr(newest_addr),
        .rdata(buf_newest), .wptr
    );

    // ---------------- 1C: filter ----------------
    logic               filt_valid;
    logic signed [15:0] filtered;

    gsr_filter #(.K(3)) u_filt (
        .clk, .rst_n,
        .in_valid(data_valid), .x(adc_data),
        .out_valid(filt_valid), .y(filtered)
    );

    // ---------------- 1D: baseline, delta, SCR ----------------
    logic signed [15:0] baseline, delta;
    logic               scr_active;
    logic        [7:0]  scr_count;
    logic        [15:0] scr_amp;

    gsr_features #(.CAL_SHIFT(CAL_SHIFT), .SLOPE_TH(SLOPE_TH)) u_feat (
        .clk, .rst_n,
        .cal(cal_s[1]),
        .in_valid(filt_valid), .filtered,
        .baseline, .delta, .scr_active, .scr_count, .scr_amp
    );

    // ---------------- 1E: frame to the MCU ----------------
    // After data_valid, every block needs at most 2 clocks to settle:
    //   buffer read-back, filter (1 clock), features (1 more clock).
    // Wait 3 clocks, then hand the whole set to gsr_frame at once.
    logic [2:0] dv_d;
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) dv_d <= 3'b000;
        else        dv_d <= {dv_d[1:0], data_valid};

    gsr_frame u_frame (
        .clk, .rst_n,
        .sample_valid(dv_d[2]),
        .raw,
        .filtered, .baseline, .delta,
        .scr_active, .scr_count, .scr_amp,
        .sclk(mcu_sclk), .cs_n(mcu_cs_n), .miso(mcu_miso)
    );

    assign led = scr_active;
endmodule
