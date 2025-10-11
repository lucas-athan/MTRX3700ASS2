`timescale 1ns/1ns

module snr_calculator_tb;

    // Parameters
    localparam DATA_WIDTH = 16;
    localparam SNR_WIDTH = 16;
    localparam CLK_PERIOD = 20; // 50 MHz clock
    
    // Testbench signals
    logic clk;
    logic reset;
    logic quiet_period;
    logic [DATA_WIDTH-1:0] audio_input;
    logic audio_input_valid;
    logic audio_input_ready;
    logic [SNR_WIDTH-1:0] snr_db;
    logic [DATA_WIDTH-1:0] signal_rms;
    logic [DATA_WIDTH-1:0] noise_rms;
    logic output_valid;
    logic output_ready;
    
    // Instantiate DUT
    snr_calculator #(
        .DATA_WIDTH(DATA_WIDTH),
        .SNR_WIDTH(SNR_WIDTH)
    ) dut (
        .clk(clk),
        .reset(reset),
        .quiet_period(quiet_period),
        .audio_input(audio_input),
        .audio_input_valid(audio_input_valid),
        .audio_input_ready(audio_input_ready),
        .snr_db(snr_db),
        .signal_rms(signal_rms),
        .noise_rms(noise_rms),
        .output_valid(output_valid),
        .output_ready(output_ready)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // Test stimulus
    initial begin
        // Initialize signals
        reset = 1;
        quiet_period = 1;
        audio_input = 0;
        audio_input_valid = 0;
        output_ready = 1;
        
        // Wait for a few cycles
        repeat(5) @(posedge clk);
        reset = 0;
        
        $display("=== Test 1: Noise Floor Calibration ===");
        // Simulate quiet period with low-level noise
        quiet_period = 1;
        repeat(100) begin
            @(posedge clk);
            audio_input = $random % 200; // Small noise ~200 amplitude
            audio_input_valid = 1;
        end
        
        $display("After calibration: noise_rms = %d", noise_rms);
        
        $display("\n=== Test 2: Signal with Higher Amplitude ===");
        // End quiet period and apply signal
        quiet_period = 0;
        repeat(200) begin
            @(posedge clk);
            // Simulate larger signal (clap/beat)
            audio_input = $random % 5000; // Larger amplitude
            audio_input_valid = 1;
        end
        
        $display("With signal: signal_rms = %d, noise_rms = %d, snr_db = %d", 
                 signal_rms, noise_rms, snr_db);
        
        $display("\n=== Test 3: Return to Low Signal ===");
        // Return to quiet
        repeat(100) begin
            @(posedge clk);
            audio_input = $random % 200; // Back to noise level
            audio_input_valid = 1;
        end
        
        $display("Back to quiet: signal_rms = %d, snr_db = %d", signal_rms, snr_db);
        
        $display("\n=== Test 4: Edge Cases ===");
        // Test zero input
        audio_input = 0;
        audio_input_valid = 1;
        repeat(20) @(posedge clk);
        $display("Zero input: signal_rms = %d, noise_rms = %d, snr_db = %d", 
                 signal_rms, noise_rms, snr_db);
        
        // Test negative input (signed)
        audio_input = -16'sd1000;
        repeat(20) @(posedge clk);
        $display("Negative input: signal_rms = %d (should be positive)", signal_rms);
        
        $display("\n=== Test Complete ===");
        $display("Verify:");
        $display("1. noise_rms increases during quiet_period");
        $display("2. signal_rms responds quickly to signal changes");
        $display("3. SNR increases when signal >> noise");
        $display("4. Absolute value works for negative inputs");
        
        $stop;
    end
    
    // Monitor key signals
    initial begin
        $monitor("Time=%0t | audio=%d valid=%b quiet=%b | sig_rms=%d noise_rms=%d snr=%d", 
                 $time, audio_input, audio_input_valid, quiet_period, 
                 signal_rms, noise_rms, snr_db);
    end

endmodule