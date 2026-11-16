// gsr_frame.sv — builds the 16-byte FPGA → MCU frame and sends it over SPI.
//
// Frame layout (byte 0 is sent first; multi-byte fields are high byte first):
//
//   Byte   Field        Notes
//   0      header       8'b1010_0101 (0xA5), lets the MCU find the frame start
//   1      seq          frame counter, +1 every frame (wraps 255 → 0)
//   2-3    raw          latest ADC code (signed)
//   4-5    filtered     IIR output (signed)
//   6-7    baseline     from 1D (signed)
//   8-9    delta        filtered − baseline, from 1D (signed)
//   10     status       [0] new_sample: a GSR sample arrived since last frame
//                       [1] scr_active: SCR detector is in an SCR (from 1D)
//                       [7:2] reserved, 0
//   11     scr_count    number of SCRs detected (from 1D)
//   12-13  scr_amp      amplitude of the last SCR (from 1D)
//   14     reserved     0
//   15     checksum     XOR of bytes 0–14
//
// The MCU reads a frame every 10 ms, but GSR updates every 31.25 ms, so about
// 2 of every 3 frames repeat the same data with new_sample = 0.
//
// Until 1D exists, tie baseline, delta, scr_active, scr_count and scr_amp to 0.
module gsr_frame (
    input  logic               clk,
    input  logic               rst_n,

    // GSR data in. All fields are captured together when sample_valid pulses.
    input  logic               sample_valid,  // 1-cycle pulse (e.g. filter out_valid)
    input  logic signed [15:0] raw,
    input  logic signed [15:0] filtered,
    input  logic signed [15:0] baseline,
    input  logic signed [15:0] delta,
    input  logic               scr_active,
    input  logic        [7:0]  scr_count,
    input  logic        [15:0] scr_amp,

    // SPI to the STM32
    input  logic               sclk,
    input  logic               cs_n,
    output logic               miso
);
    localparam logic [7:0] HEADER = 8'b1010_0101;

    // Hold the latest values so the frame stays stable between samples.
    logic signed [15:0] raw_r, filt_r, base_r, delta_r;
    logic               scr_active_r;
    logic        [7:0]  scr_count_r;
    logic        [15:0] scr_amp_r;
    logic        [7:0]  seq;
    logic               new_sample;
    logic               load;            // from spi_slave_tx: frame latched

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            raw_r <= '0; filt_r <= '0; base_r <= '0; delta_r <= '0;
            scr_active_r <= 1'b0; scr_count_r <= '0; scr_amp_r <= '0;
            seq        <= '0;
            new_sample <= 1'b0;
        end else begin
            if (sample_valid) begin
                raw_r        <= raw;
                filt_r       <= filtered;
                base_r       <= baseline;
                delta_r      <= delta;
                scr_active_r <= scr_active;
                scr_count_r  <= scr_count;
                scr_amp_r    <= scr_amp;
            end

            // new_sample: set by a new sample, cleared when a frame is sent.
            // If a sample arrives on the same cycle a frame is latched, it is
            // not in that frame, so it stays "new" for the next one.
            if (load)              new_sample <= sample_valid;
            else if (sample_valid) new_sample <= 1'b1;

            if (load) seq <= seq + 8'b0000_0001;
        end
    end

    // Assemble bytes 0–14, then the checksum.
    logic [7:0] status;
    assign status = {6'b000000, scr_active_r, new_sample};

    logic [119:0] body;
    assign body = { HEADER,
                    seq,
                    raw_r,
                    filt_r,
                    base_r,
                    delta_r,
                    status,
                    scr_count_r,
                    scr_amp_r,
                    8'b0000_0000 };          // reserved

    logic [7:0] checksum;
    always_comb begin
        checksum = 8'b0000_0000;
        for (int i = 0; i < 15; i++)
            checksum = checksum ^ body[119 - 8*i -: 8];
    end

    spi_slave_tx #(.NBITS(128)) u_slave (
        .clk, .rst_n, .sclk, .cs_n, .miso,
        .frame_in ({body, checksum}),
        .load
    );
endmodule
