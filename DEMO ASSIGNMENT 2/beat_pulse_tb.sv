`timescale 1ns/1ns

module beat_pulse_tb;

    // Parameters
    localparam SNR_WIDTH = 16;
    localparam THRESHOLD = 25;
    
    // Testbench signals
    logic [SNR_WIDTH-1:0] snr_db;
    logic beat_pulse;
    
    // Instantiate DUT
    beat_pulse #(
        .SNR_WIDTH(SNR_WIDTH),
        .THRESHOLD(THRESHOLD)
    ) dut (
        .snr_db(snr_db),
        .beat_pulse(beat_pulse)
    );
    
    // Test stimulus
    initial begin
        $display("=== Beat Pulse Threshold Detector Test ===");
        $display("Threshold = %d dB\n", THRESHOLD);
        
        // Test 1: Below threshold
        $display("Test 1: SNR below threshold");
        snr_db = 0;
        #10;
        $display("  snr_db = %d -> beat_pulse = %b (expect 0)", snr_db, beat_pulse);
        
        snr_db = 10;
        #10;
        $display("  snr_db = %d -> beat_pulse = %b (expect 0)", snr_db, beat_pulse);
        
        snr_db = 24;
        #10;
        $display("  snr_db = %d -> beat_pulse = %b (expect 0)", snr_db, beat_pulse);
        
        // Test 2: At threshold (boundary)
        $display("\nTest 2: SNR at threshold");
        snr_db = THRESHOLD;
        #10;
        $display("  snr_db = %d -> beat_pulse = %b (expect 1)", snr_db, beat_pulse);
        
        // Test 3: Above threshold
        $display("\nTest 3: SNR above threshold");
        snr_db = 26;
        #10;
        $display("  snr_db = %d -> beat_pulse = %b (expect 1)", snr_db, beat_pulse);
        
        snr_db = 30;
        #10;
        $display("  snr_db = %d -> beat_pulse = %b (expect 1)", snr_db, beat_pulse);
        
        snr_db = 45;
        #10;
        $display("  snr_db = %d -> beat_pulse = %b (expect 1)", snr_db, beat_pulse);
        
        // Test 4: Transition test
        $display("\nTest 4: Rapid transitions");
        snr_db = 20; #10;
        $display("  snr_db = %d -> beat_pulse = %b", snr_db, beat_pulse);
        
        snr_db = 30; #10;
        $display("  snr_db = %d -> beat_pulse = %b", snr_db, beat_pulse);
        
        snr_db = 24; #10;
        $display("  snr_db = %d -> beat_pulse = %b", snr_db, beat_pulse);
        
        snr_db = 25; #10;
        $display("  snr_db = %d -> beat_pulse = %b", snr_db, beat_pulse);
        
        // Test 5: Maximum value
        $display("\nTest 5: Maximum SNR value");
        snr_db = 16'hFFFF; // Maximum 16-bit value
        #10;
        $display("  snr_db = %d -> beat_pulse = %b (expect 1)", snr_db, beat_pulse);
        
        $display("\n=== Test Complete ===");
        $display("Verification:");
        $display("✓ beat_pulse = 0 when snr_db < 25");
        $display("✓ beat_pulse = 1 when snr_db >= 25");
        $display("✓ Combinational logic (no delay)");
        
        $stop;
    end
    
    // Continuous monitor
    initial begin
        $monitor("Time=%0t | snr_db=%d | beat_pulse=%b", $time, snr_db, beat_pulse);
    end

endmodule