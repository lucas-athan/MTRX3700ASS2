`timescale 1ns/1ns
module bpm_energy_detector #(
    parameter SAMPLE_WIDTH = 16,
    parameter CLOCK_FREQ   = 50_000_000,   // FPGA system clock (Hz)
    parameter SAMPLE_RATE  = 30_720,       // audio sample rate (Hz)
    parameter WINDOW_SIZE  = 614,          // ~20ms window at 30.72kHz
    parameter ENERGY_WIDTH = 32,
    parameter BPM_WIDTH    = 16
)(
    input  logic clk,
    input  logic reset,
    input  logic signed [SAMPLE_WIDTH-1:0] audio_sample,
    input  logic sample_valid,
    output logic [BPM_WIDTH-1:0] bpm_val,
    output logic beat_detected
);

    // 1. Energy accumulation per window
    logic [$clog2(WINDOW_SIZE):0] sample_count;
    logic [ENERGY_WIDTH-1:0] window_energy;
    logic [ENERGY_WIDTH-1:0] avg_energy;
    logic beat_pulse;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            sample_count  <= 0;
            window_energy <= 0;
            avg_energy    <= 0;
            beat_pulse    <= 0;
        end else if (sample_valid) begin
            // Accumulate |sample|^2
            window_energy <= window_energy + audio_sample * audio_sample;
            sample_count  <= sample_count + 1;

            // End of window: update threshold & detect beat
            if (sample_count == WINDOW_SIZE-1) begin
                sample_count <= 0;

                // Adaptive threshold (low-pass)
                avg_energy <= (avg_energy + window_energy) >> 1;

                // Beat detection: if energy > 1.5× average
                if (window_energy > (avg_energy + (avg_energy >> 1)))
                    beat_pulse <= 1;
                else
                    beat_pulse <= 0;

                // Reset energy accumulator
                window_energy <= 0;
            end else begin
                beat_pulse <= 0;
            end
        end
    end

    // 2. BPM calculation (interval between beats)
    logic [31:0] counter;
    logic [31:0] last_beat_time;
    logic [31:0] interval;
    logic [31:0] bpm_calc;

    always_ff @(posedge clk or posedge reset) begin
        if (reset)
            counter <= 0;
        else
            counter <= counter + 1;
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            last_beat_time <= 0;
            bpm_calc       <= 0;
            bpm_val        <= 0;
        end else if (beat_pulse) begin
            if (last_beat_time != 0) begin
                interval = counter - last_beat_time;
                if (interval > 0 && interval < (CLOCK_FREQ * 60 / 30)) begin
                    // Compute BPM = 60 * Fclk / interval
                    bpm_calc = (60 * CLOCK_FREQ) / interval;

                    // Smooth output (simple moving average)
                    bpm_val <= (bpm_val + bpm_calc) >> 1;
                end
            end
            last_beat_time <= counter;
        end
    end

    assign beat_detected = beat_pulse;

endmodule
