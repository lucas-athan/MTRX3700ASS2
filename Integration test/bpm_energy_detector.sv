`timescale 1ns/1ns
module bpm_energy_detector #(
    parameter SAMPLE_WIDTH = 16,
    parameter CLOCK_FREQ   = 18_432_000,   // Must match adc_clk frequency!
    parameter SAMPLE_RATE  = 30_720,       // audio sample rate (Hz)
    parameter WINDOW_SIZE  = 614,          // ~20ms window at 30.72kHz (not used in new implementation)
    parameter ENERGY_WIDTH = 32,
    parameter BPM_WIDTH    = 16
)(
    input  logic clk,
    input  logic reset,
    input  logic [SAMPLE_WIDTH-1:0] audio_sample,  // Changed to unsigned - this is pitch data
    input  logic sample_valid,
    output logic [BPM_WIDTH-1:0] bpm_val,
    output logic beat_detected
);

    // ========================================
    // Beat Detection: Trigger when pitch > 80
    // ========================================
    localparam PITCH_THRESHOLD = 80;
    localparam DEBOUNCE_SAMPLES = 30;  // ~1ms debounce at 30.72kHz
    
    logic pitch_above_threshold;
    logic beat_pulse;
    logic [$clog2(DEBOUNCE_SAMPLES+1)-1:0] debounce_count;
    logic last_beat_state;
    
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            pitch_above_threshold <= 0;
            beat_pulse <= 0;
            debounce_count <= 0;
            last_beat_state <= 0;
        end else if (sample_valid) begin
            // Check if pitch exceeds threshold
            pitch_above_threshold <= (audio_sample > PITCH_THRESHOLD);
            
            // Detect rising edge with debounce
            if (pitch_above_threshold && !last_beat_state) begin
                if (debounce_count < DEBOUNCE_SAMPLES) begin
                    debounce_count <= debounce_count + 1;
                    beat_pulse <= 0;
                end else begin
                    // Confirmed beat!
                    beat_pulse <= 1;
                    last_beat_state <= 1;
                    debounce_count <= 0;
                end
            end else if (!pitch_above_threshold && last_beat_state) begin
                // Falling edge - reset state
                last_beat_state <= 0;
                beat_pulse <= 0;
                debounce_count <= 0;
            end else begin
                beat_pulse <= 0;
            end
        end else begin
            beat_pulse <= 0;
        end
    end
    
    // ========================================
    // BPM Calculation: Measure interval between beats
    // ========================================
    localparam MIN_BPM = 30;   // Minimum realistic BPM (2 second interval)
    localparam MAX_BPM = 240;  // Maximum realistic BPM (0.25 second interval)
    localparam MIN_INTERVAL = CLOCK_FREQ * 60 / MAX_BPM;  // ~4.6M cycles
    localparam MAX_INTERVAL = CLOCK_FREQ * 60 / MIN_BPM;  // ~36.8M cycles
    
    logic [31:0] cycle_counter;
    logic [31:0] last_beat_cycle;
    logic [31:0] beat_interval;
    logic [15:0] bpm_raw;
    logic [15:0] bpm_filtered;
    logic [3:0]  valid_beat_count;  // Count consecutive valid beats for stability
    
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            cycle_counter <= 0;
        end else begin
            cycle_counter <= cycle_counter + 1;
        end
    end
    
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            last_beat_cycle <= 0;
            beat_interval <= 0;
            bpm_raw <= 0;
            bpm_filtered <= 0;
            bpm_val <= 0;
            valid_beat_count <= 0;
        end else if (beat_pulse) begin
            // Calculate interval since last beat
            beat_interval = cycle_counter - last_beat_cycle;
            last_beat_cycle <= cycle_counter;
            
            // Only update BPM if interval is in valid range
            if (beat_interval >= MIN_INTERVAL && beat_interval <= MAX_INTERVAL) begin
                // BPM = 60 * CLOCK_FREQ / interval
                // To avoid overflow, calculate: (60 * CLOCK_FREQ) / interval
                // 60 * 18_432_000 = 1_105_920_000
                bpm_raw <= 1_105_920_000 / beat_interval;
                
                // Build confidence with consecutive valid beats
                if (valid_beat_count < 8)
                    valid_beat_count <= valid_beat_count + 1;
                    
                // Simple exponential moving average for smoothing
                // bpm_filtered = (3*old + 1*new) / 4
                bpm_filtered <= (3 * bpm_filtered + bpm_raw) >> 2;
                
                // Output filtered value once we have confidence
                if (valid_beat_count >= 2)
                    bpm_val <= bpm_filtered;
            end else begin
                // Invalid interval - could be noise or tempo change
                if (valid_beat_count > 0)
                    valid_beat_count <= valid_beat_count - 1;
            end
        end else begin
            // Timeout detection: if no beat for too long, reset confidence
            if ((cycle_counter - last_beat_cycle) > (MAX_INTERVAL * 2)) begin
                valid_beat_count <= 0;
                bpm_filtered <= 0;
            end
        end
    end
    
    assign beat_detected = beat_pulse;

endmodule