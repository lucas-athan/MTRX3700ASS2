// BPM Energy Detector - Method A (Simple Energy/Envelope Method)
// This implements the simple energy/envelope method for beat detection:
// 1. Detect peaks in signal_rms (energy envelope) that exceed a threshold
// 2. Record these as onset/beat events
// 3. Calculate BPM from inter-beat interval (time between consecutive beats)

`timescale 1ns/1ns

module bpm_energy_detector #(
    parameter SAMPLE_WIDTH = 16,
    parameter CLOCK_FREQ   = 18_432_000,   // Clock frequency (Hz)
    parameter SAMPLE_RATE  = 30_720,       // Audio sample rate (Hz)
    parameter BPM_WIDTH    = 16
)(
    input  logic clk,
    input  logic reset,
    
    // Energy/envelope input
    input  logic [SAMPLE_WIDTH-1:0] signal_rms,     // RMS energy from SNR calculator
    input  logic [SAMPLE_WIDTH-1:0] snr_db,         // SNR in dB (0-42 range)
    input  logic sample_valid,
    
    output logic [BPM_WIDTH-1:0] bpm_val,
    output logic beat_detected
);

    // Step 1: Adaptive Threshold for Beat Detection
    // Track average and variance of energy to set adaptive threshold
    localparam SNR_THRESHOLD = 35;  // Detect beats above 35 dB (loud transients)
    
    logic [15:0] energy_avg;
    logic [15:0] energy_threshold;
    logic beat_pulse;
    
    // Moving average of signal energy
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            energy_avg <= 100;  // Initialize to reasonable value
        end else if (sample_valid) begin
            // Exponential moving average: avg = 0.95*avg + 0.05*current
            energy_avg <= (energy_avg - (energy_avg >>> 5)) + (signal_rms >>> 5);
        end
    end
    
    // Adaptive threshold: 1.5x average energy
    always_comb begin
        energy_threshold = energy_avg + (energy_avg >>> 1);
    end
    
    // Step 2: Peak Detection
    // Detect when signal exceeds threshold and hasn't detected a beat recently
    localparam DEBOUNCE_SAMPLES = 9216;  // ~300ms debounce @ 30.72kHz (prevent double-triggers)
    
    logic [15:0] debounce_counter;
    logic peak_detected;
    
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            beat_pulse <= 0;
            debounce_counter <= 0;
            peak_detected <= 0;
        end else if (sample_valid) begin
            // Countdown debounce timer
            if (debounce_counter > 0) begin
                debounce_counter <= debounce_counter - 1;
                beat_pulse <= 0;
            end
            // Detect peak: energy exceeds threshold AND dB exceeds SNR threshold
            else if (signal_rms > energy_threshold && snr_db > SNR_THRESHOLD) begin
                if (!peak_detected) begin
                    // Rising edge - beat detected!
                    beat_pulse <= 1;
                    peak_detected <= 1;
                    debounce_counter <= DEBOUNCE_SAMPLES;
                end else begin
                    beat_pulse <= 0;
                end
            end
            // Falling edge - reset peak detector
            else if (signal_rms < (energy_threshold - (energy_threshold >>> 2))) begin
                peak_detected <= 0;
                beat_pulse <= 0;
            end
            else begin
                beat_pulse <= 0;
            end
        end else begin
            beat_pulse <= 0;
        end
    end
    
    // Step 3: BPM Calculation from Inter-Beat Interval
    localparam MIN_BPM = 40;    // 
    localparam MAX_BPM = 200; 
    localparam MIN_INTERVAL = CLOCK_FREQ * 60 / MAX_BPM;  // ~6.1M cycles
    localparam MAX_INTERVAL = CLOCK_FREQ * 60 / MIN_BPM;  // ~18.4M cycles
    
    logic [31:0] cycle_counter;
    logic [31:0] last_beat_cycle;
    logic [31:0] beat_interval;
    logic [15:0] bpm_raw;
    logic [31:0] bpm_sum;
    logic [3:0]  beat_count;
    logic [3:0]  valid_beat_count;
    
    // Free-running counter for timing
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            cycle_counter <= 0;
        end else begin
            cycle_counter <= cycle_counter + 1;
        end
    end
    
    // Calculate BPM from beat intervals
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            last_beat_cycle <= 0;
            beat_interval <= 0;
            bpm_raw <= 0;
            bpm_sum <= 0;
            beat_count <= 0;
            valid_beat_count <= 0;
            bpm_val <= 0;
        end else if (beat_pulse) begin
            // Calculate time since last beat
            beat_interval = cycle_counter - last_beat_cycle;
            last_beat_cycle <= cycle_counter;
            
            // Validate interval is in reasonable BPM range
            if (beat_interval >= MIN_INTERVAL && beat_interval <= MAX_INTERVAL) begin
                // BPM = 60 * CLOCK_FREQ / interval
                // 60 * 18_432_000 = 1_105_920_000
                bpm_raw = 1_105_920_000 / beat_interval;
                
                // Accumulate beats for moving average (last 8 beats)
                if (beat_count < 8) begin
                    bpm_sum <= bpm_sum + bpm_raw;
                    beat_count <= beat_count + 1;
                end else begin
                    // Sliding window: remove oldest (approximate) and add newest
                    bpm_sum <= bpm_sum - (bpm_sum >>> 3) + (bpm_raw >>> 3);
                end
                
                // Build confidence with consecutive valid beats
                if (valid_beat_count < 15)
                    valid_beat_count <= valid_beat_count + 1;
                
                // Output averaged BPM after collecting enough beats
                if (beat_count >= 3) begin
                    bpm_val <= bpm_sum / beat_count;
                end
            end else begin
                // Invalid interval - could be noise or missed beats
                if (valid_beat_count > 0)
                    valid_beat_count <= valid_beat_count - 1;
            end
        end else begin
            // Timeout: if no beat for too long, reset averaging
            if ((cycle_counter - last_beat_cycle) > (MAX_INTERVAL * 3)) begin
                if (valid_beat_count > 0)
                    valid_beat_count <= valid_beat_count - 1;
                    
                // Reset if we've lost confidence
                if (valid_beat_count <= 2) begin
                    beat_count <= 0;
                    bpm_sum <= 0;
                end
            end
        end
    end
    
    assign beat_detected = beat_pulse;

endmodule 