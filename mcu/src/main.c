/*
File: main.c
Authors: Ishita Raje (MAX30102 test), Kathy Guo (FPGA link test, 1E)
Date: 11/16/2026

Bring-up tests for both MCU data paths, run together in one 10 ms loop.

  RUN_PPG: MAX30102 over I2C on PA9/PA10.
    No sensor: prints "No ACK from MAX30102" and keeps running the FPGA test.
    Sensor:    prints PART_ID (expect 0x15), then streams
               P,red,ir

  RUN_FPGA: reads the 16-byte GSR frame from the FPGA every 10 ms
    (FPGA_FRAME.c/.h). Prints one line per new GSR sample:
               G,seq,raw,filtered,baseline,delta,status,scr_count,scr_amp
    and every 100 frames (1 s) a stats line starting with "#".
    COUNTER_TEST = 1 checks every field against the pattern sent by
    fpga/src/top_1e_test.sv.
    1E passes when hdr_err, csum_err, seq_gaps and pattern_err stay 0 for 5 min.

  The "P," / "G," prefixes let a Python script split the two streams.
*/

#include <stdio.h>
#include "main.h"
#include "STM32L432KC_I2C.h"
#include "MAX30102.h"
#include "FPGA_FRAME.h"

#define RUN_PPG           0      // 1 = run the MAX30102 test
#define RUN_FPGA          1      // 1 = run the FPGA link test
#define COUNTER_TEST      0      // 1 = FPGA is running top_1e_test.sv
#define FRAME_PERIOD_MS   10
#define STATS_EVERY       100    // frames between stats lines (100 = 1 s)
#define PATTERN_BASELINE  0b0001001000110100   // must match top_1e_test.sv

static void printBinaryFrame(const uint8_t buf[FRAME_LEN]) {
    for (int i = 0; i < FRAME_LEN; i++) {
        for (int b = 7; b >= 0; b--) putchar((buf[i] >> b) & 1 ? '1' : '0');
        putchar(' ');
    }
    putchar('\n');
}

// Checks one counter-pattern sample. Returns 1 if every field matches.
static int checkPattern(const GsrFrame *f) {
    int16_t n = f->raw;
    return f->filtered  == (int16_t) (-n)
        && f->baseline  == (int16_t) PATTERN_BASELINE
        && f->delta     == (int16_t) (n - PATTERN_BASELINE)
        && f->scr_count == (uint8_t) n
        && f->scr_amp   == (uint16_t) n
        && ((f->status & STATUS_SCR_ACTIVE) != 0) == (n & 1);
}

int main(void) {
    configureFlash();
    configureClock();          // 80 MHz
    gpioEnable(GPIO_PORT_A);
    gpioEnable(GPIO_PORT_B);

    // ---------------- MAX30102 setup ----------------
    int ppg_ok = 0;
    uint32_t red[MAX_SAMPLES];
    uint32_t ir[MAX_SAMPLES];

#if RUN_PPG
    initI2C();
    int id = readPartID();
    if (id < 0) {
        printf("No ACK from MAX30102 (continuing without PPG)\n");
    } else {
        printf("PART_ID = 0x%02X (expect 0x15)\n", id);
        if (initMAX30102()) {
            printf("MAX30102 init failed (continuing without PPG)\n");
        } else {
            printf("MAX30102 configured: SpO2 mode, 100 samples/s\n");
            ppg_ok = 1;
        }
    }
#endif

    // ---------------- FPGA link setup ----------------
#if RUN_FPGA
    initFPGALink();
    printf("FPGA link: SPI1 mode 0, 1.25 MHz, frame every %d ms\n", FRAME_PERIOD_MS);
    printf("G,seq,raw,filtered,baseline,delta,status,scr_count,scr_amp\n");
#endif
    initFrameTimer(FRAME_PERIOD_MS);

    uint8_t  buf[FRAME_LEN];
    GsrFrame f;
    uint32_t frames = 0, hdr_err = 0, csum_err = 0, seq_gaps = 0;
    uint32_t samples = 0, sample_skips = 0, pattern_err = 0;
    int      have_prev = 0;       // have a good previous frame (for seq)
    int      have_prev_raw = 0;   // have a previous sample (for raw)
    uint8_t  prev_seq = 0;
    int16_t  prev_raw = 0;

    while (1) {
        waitFramePeriod();       // everything below runs once every 10 ms

        // ---------------- PPG: drain whatever the sensor has ----------------
        if (ppg_ok) {
            int n = readPPG(red, ir, MAX_SAMPLES);
            for (int i = 0; i < n; i++) {
                printf("P,%lu,%lu\n", red[i], ir[i]);
            }
        }

#if RUN_FPGA
        // ---------------- GSR: read one frame from the FPGA ----------------
        readFPGAFrame(buf);
        frames++;

        int result = parseFPGAFrame(buf, &f);
        if (result != FRAME_OK) {
            if (result == FRAME_BAD_HEADER) hdr_err++;
            else                            csum_err++;
            printf("BAD FRAME (%s): ", result == FRAME_BAD_HEADER ? "header" : "checksum");
            printBinaryFrame(buf);
            have_prev = 0;        // can't trust seq/raw after a bad frame
            have_prev_raw = 0;
            continue;
        }

        // Every frame the FPGA sends bumps seq by 1, so a gap means a frame
        // was lost on the wire (not just that the MCU was slow).
        if (have_prev && f.seq != (uint8_t) (prev_seq + 1)) seq_gaps++;
        prev_seq  = f.seq;
        have_prev = 1;

        if (f.status & STATUS_NEW_SAMPLE) {
            samples++;
#if COUNTER_TEST
            if (!checkPattern(&f)) {
                pattern_err++;
                printf("PATTERN ERROR: ");
                printBinaryFrame(buf);
            }
            // raw should go up by exactly 1 per sample; a bigger jump means
            // the MCU missed a sample (too slow), not a link error.
            if (have_prev_raw && f.raw != (int16_t) (prev_raw + 1)) sample_skips++;
#endif
            prev_raw      = f.raw;
            have_prev_raw = 1;
            printf("G,%u,%d,%d,%d,%d,%u,%u,%u\n",
                   f.seq, f.raw, f.filtered, f.baseline, f.delta,
                   f.status, f.scr_count, f.scr_amp);
        }

        if (frames % STATS_EVERY == 0) {
            printf("# frames=%lu samples=%lu hdr_err=%lu csum_err=%lu seq_gaps=%lu",
                   frames, samples, hdr_err, csum_err, seq_gaps);
#if COUNTER_TEST
            printf(" pattern_err=%lu sample_skips=%lu", pattern_err, sample_skips);
#endif
            printf("\n");
        }
#endif
    }
}
