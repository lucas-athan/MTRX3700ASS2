`timescale 1ns/1ns
module bpm_energy_detector #(
    parameter SAMPLE_WIDTH = 16,
    parameter CLOCK_FREQ   = 50_000_000, 
    parameter BPM_WIDTH    = 16
)(
    input  logic clk,
    input  logic reset,
    
    // Input: signal_rms from SNR calculator (energy envelope)
    input  logic [SAMPLE_WIDTH-1:0] signal_rms,
    input  logic signal_rms_valid,
    
    output logic [BPM_WIDTH-1:0] bpm_val,
    output logic beat_detected
);

    // STEP 1: Adaptive Threshold Calculation
    localparam logic [31:0] ALPHA_THRESHOLD = 32'd2048; // 0.03125 
    
    logic signed [31:0] threshold_temp;
    logic [15:0] threshold;
    
    rc_low_pass #(
        .W(32),
        .W_FRAC(16),
        .ALPHA(ALPHA_THRESHOLD)
    ) u_threshold_ma (
        .clk(clk),
        .x_data({signal_rms, 16'd0}),
        .x_valid(signal_rms_valid),
        .x_ready(),
        .y_data(threshold_temp),
        .y_valid(),
        .y_ready(1'b1)
    );
    
    assign threshold = threshold_temp[31:16];

    // STEP 2: Beat Detection (Energy Threshold)
    localparam THRESHOLD_MULT = 2;  // Beat threshold = 2x average
    localparam DEBOUNCE_MS = 50;    // 50ms minimum between beats
    localparam DEBOUNCE_CYCLES = (CLOCK_FREQ / 1000) * DEBOUNCE_MS;
    
    logic [31:0] debounce_counter;
    logic beat_pulse;
    logic last_above_threshold;
    
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            beat_pulse <= 0;
            debounce_counter <= 0;
            last_above_threshold <= 0;
        end else if (signal_rms_valid) begin
            // Default: no beat
            beat_pulse <= 0;
            
            // Check if we're in debounce period
            if (debounce_counter > 0) begin
                debounce_counter <= debounce_counter - 1;
            end 
            // Detect rising edge above threshold
            else if (signal_rms > (threshold * THRESHOLD_MULT) && !last_above_threshold) begin
                // Beat detected!
                beat_pulse <= 1;
                debounce_counter <= DEBOUNCE_CYCLES;
            end
            
            // Track threshold crossing
            last_above_threshold <= (signal_rms > (threshold * THRESHOLD_MULT));
        end else begin
            beat_pulse <= 0;
        end
    end

    // STEP 3: BPM Calculation via Inter-Beat Interval
    localparam MIN_BPM = 40;
    localparam MAX_BPM = 200;
    localparam MIN_INTERVAL = CLOCK_FREQ * 60 / MAX_BPM;
    localparam MAX_INTERVAL = CLOCK_FREQ * 60 / MIN_BPM;
    
    logic [31:0] cycle_counter;
    logic [31:0] last_beat_cycle;
    logic [31:0] beat_interval;
    logic [15:0] bpm_raw;
    logic [15:0] bpm_filtered;
    logic [3:0]  valid_beat_count;
    
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
            beat_interval = cycle_counter - last_beat_cycle;
            last_beat_cycle <= cycle_counter;
            
            // Validate interval is in reasonable BPM range
            if (beat_interval >= MIN_INTERVAL && beat_interval <= MAX_INTERVAL) begin
                // BPM = 60 * CLOCK_FREQ / interval
                bpm_raw <= (60 * CLOCK_FREQ) / beat_interval;
                
                // Build confidence
                if (valid_beat_count < 8)
                    valid_beat_count <= valid_beat_count + 1;
                
                // Exponential moving average for smoothing
                bpm_filtered <= (3 * bpm_filtered + bpm_raw) >> 2;
                
                // Only output after building confidence
                if (valid_beat_count >= 2)
                    bpm_val <= bpm_filtered;
            end else begin
                // Invalid interval
                if (valid_beat_count > 0)
                    valid_beat_count <= valid_beat_count - 1;
            end
        end else begin
            // Timeout: reset if no beat for too long
            if ((cycle_counter - last_beat_cycle) > (MAX_INTERVAL * 2)) begin
                valid_beat_count <= 0;
                bpm_filtered <= 0;
            end
        end
    end
    
    assign beat_detected = beat_pulse;

endmodule
