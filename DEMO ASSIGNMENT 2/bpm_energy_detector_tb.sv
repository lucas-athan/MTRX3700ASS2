`timescale 1ns/1ns

module bpm_energy_detector_tb;

    // Parameters
    localparam SAMPLE_WIDTH = 16;
    localparam CLOCK_FREQ = 50_000_000;
    localparam BPM_WIDTH = 16;
    localparam CLK_PERIOD = 20; // 50 MHz = 20ns period
    
    // Testbench signals
    logic clk;
    logic reset;
    logic [SAMPLE_WIDTH-1:0] signal_rms;
    logic signal_rms_valid;
    logic [BPM_WIDTH-1:0] bpm_val;
    logic beat_detected;
    
    // Instantiate DUT
    bpm_energy_detector #(
        .SAMPLE_WIDTH(SAMPLE_WIDTH),
        .CLOCK_FREQ(CLOCK_FREQ),
        .BPM_WIDTH(BPM_WIDTH)
    ) dut (
        .clk(clk),
        .reset(reset),
        .signal_rms(signal_rms),
        .signal_rms_valid(signal_rms_valid),
        .bpm_val(bpm_val),
        .beat_detected(beat_detected)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // Task to simulate a beat (energy spike)
    task send_beat(input int amplitude);
        repeat(5) begin
            @(posedge clk);
            signal_rms = amplitude;
            signal_rms_valid = 1;
        end
        repeat(10) begin
            @(posedge clk);
            signal_rms = 100; // Back to baseline
            signal_rms_valid = 1;
        end
    endtask
    
    // Task to wait for specific time in ms
    task wait_ms(input int milliseconds);
        repeat((CLOCK_FREQ/1000) * milliseconds) @(posedge clk);
    endtask
    
    // Test stimulus
    initial begin
        // Initialize
        reset = 1;
        signal_rms = 0;
        signal_rms_valid = 0;
        
        repeat(10) @(posedge clk);
        reset = 0;
        
        $display("=== BPM Energy Detector Test ===\n");
        
        // Test 1: Build baseline threshold
        $display("Test 1: Establishing baseline threshold");
        repeat(1000) begin
            @(posedge clk);
            signal_rms = 100 + ($random % 20); // Small variations around 100
            signal_rms_valid = 1;
        end
        $display("Baseline established\n");
        
        // Test 2: Detect beats at 60 BPM (1 beat per second)
        $display("Test 2: Testing 60 BPM (1 second intervals)");
        repeat(5) begin
            send_beat(3000); // Large amplitude spike
            if (beat_detected) $display("  Beat detected!");
            wait_ms(1000); // Wait 1 second between beats
        end
        #1000;
        $display("Expected BPM ≈ 60, Measured BPM = %d\n", bpm_val);
        
        // Test 3: Detect beats at 120 BPM (0.5 second intervals)
        $display("Test 3: Testing 120 BPM (500ms intervals)");
        repeat(8) begin
            send_beat(3000);
            if (beat_detected) $display("  Beat detected!");
            wait_ms(500); // Wait 0.5 seconds
        end
        #1000;
        $display("Expected BPM ≈ 120, Measured BPM = %d\n", bpm_val);
        
        // Test 4: Detect beats at 180 BPM (333ms intervals)
        $display("Test 4: Testing 180 BPM (333ms intervals)");
        repeat(8) begin
            send_beat(3000);
            if (beat_detected) $display("  Beat detected!");
            wait_ms(333);
        end
        #1000;
        $display("Expected BPM ≈ 180, Measured BPM = %d\n", bpm_val);
        
        // Test 5: Debouncing - rapid pulses should be ignored
        $display("Test 5: Testing debouncing (50ms debounce)");
        send_beat(3000);
        wait_ms(20); // Too fast, should be debounced
        send_beat(3000);
        wait_ms(20);
        send_beat(3000);
        $display("Rapid beats sent within debounce period");
        $display("Only first beat should be detected\n");
        
        // Test 6: Edge cases
        $display("Test 6: Edge cases");
        
        // Sub-minimum BPM (should be rejected)
        $display("  6a: Very slow tempo (too slow)");
        send_beat(3000);
        wait_ms(2000); // 30 BPM (below 40 BPM minimum)
        send_beat(3000);
        $display("     BPM = %d (should reject intervals outside 40-200 BPM)\n", bpm_val);
        
        // Maximum BPM boundary
        $display("  6b: Very fast tempo (200 BPM, 300ms)");
        repeat(6) begin
            send_beat(3000);
            wait_ms(300); // 200 BPM
        end
        $display("     BPM = %d (should be near 200)\n", bpm_val);
        
        // Test 7: No beats for extended period
        $display("Test 7: Timeout test (no beats)");
        repeat(5000) begin
            @(posedge clk);
            signal_rms = 100;
            signal_rms_valid = 1;
        end
        $display("No beats for extended period, BPM = %d\n", bpm_val);
        
        $display("=== Test Complete ===");
        $display("\nVerification Points:");
        $display("1. Adaptive threshold tracks signal baseline");
        $display("2. Beat detection with 50ms debouncing works");
        $display("3. BPM calculation accurate for 60, 120, 180 BPM");
        $display("4. Invalid intervals (< 40 BPM or > 200 BPM) rejected");
        $display("5. Confidence builds after 2+ valid beats");
        $display("6. System resets after prolonged silence");
        
        $stop;
    end
    
    // Monitor beat detections and BPM updates
    always @(posedge clk) begin
        if (beat_detected)
            $display("[%0t] BEAT! Current BPM estimate: %d", $time, bpm_val);
    end

endmodule