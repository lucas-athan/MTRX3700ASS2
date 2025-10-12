`timescale 1ns/1ps

module brightness_filter_tb;

    // Parameters
    parameter int BITS = 8;
    parameter int MAX_BPM = 200;
    parameter int CLK_PERIOD = 10;

    // Testbench signals
    logic                           clk;
    logic                           reset;
    logic [BITS-1:0]                pix_in;
    logic                           valid_in;
    logic                           module_ready;
    logic                           output_ready;
    logic                           filter_enable;
    logic [$clog2(MAX_BPM+1)-1:0]   BPM_estimate;
    logic [BITS-1:0]                pix_out;
    logic                           valid_out;
    logic [BITS-1:0]                brightness;

    // Instantiate DUT
    brightness_filter #(
        .BITS(BITS),
        .MAX_BPM(MAX_BPM)
    ) dut (
        .clk(clk),
        .reset(reset),
        .pix_in(pix_in),
        .valid_in(valid_in),
        .module_ready(module_ready),
        .output_ready(output_ready),
        .filter_enable(filter_enable),
        .BPM_estimate(BPM_estimate),
        .pix_out(pix_out),
        .valid_out(valid_out),
        .brightness(brightness)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Test stimulus - OPTIMIZED FOR SCREENSHOTS
    initial begin
        $dumpfile("brightness_filter_screenshot.vcd");
        $dumpvars(0, brightness_filter_tb);

        $display("=== Brightness Filter - Screenshot Testbench ===\n");

        // Initialize
        reset = 1;
        pix_in = 0;
        valid_in = 0;
        module_ready = 1;
        filter_enable = 0;
        BPM_estimate = 0;

        repeat(3) @(posedge clk);
        reset = 0;
        $display("[%0t] Reset released", $time);

        // ===== SEQUENCE 1: Transparent mode (filter disabled) =====
        $display("\n[%0t] === Sequence 1: Transparent Mode (filter OFF) ===", $time);
        filter_enable = 0;
        BPM_estimate = 100; // brightness = ~127, but filter is off
        
        @(posedge clk);
        @(posedge clk);
        
        // Send pixels that pass through unchanged
        send_pixel(50);
        send_pixel(100);
        send_pixel(150);
        send_pixel(200);
        send_pixel(255);

        // ===== SEQUENCE 2: Filter enabled with low brightness =====
        $display("\n[%0t] === Sequence 2: Filter ON, BPM=50 (brightness~63) ===", $time);
        filter_enable = 1;
        BPM_estimate = 50;
        
        @(posedge clk);
        @(posedge clk);
        
        send_pixel(0);    // 0 + 63 = 63
        send_pixel(50);   // 50 + 63 = 113
        send_pixel(100);  // 100 + 63 = 163
        send_pixel(150);  // 150 + 63 = 213
        send_pixel(192);  // 192 + 63 = 255 (saturate)
        send_pixel(200);  // 200 + 63 = 255 (saturate)

        // ===== SEQUENCE 3: Filter with medium brightness =====
        $display("\n[%0t] === Sequence 3: Filter ON, BPM=100 (brightness~127) ===", $time);
        BPM_estimate = 100;
        
        @(posedge clk);
        @(posedge clk);
        
        send_pixel(0);    // 0 + 127 = 127
        send_pixel(50);   // 50 + 127 = 177
        send_pixel(100);  // 100 + 127 = 227
        send_pixel(128);  // 128 + 127 = 255 (saturate)
        send_pixel(150);  // 150 + 127 = 255 (saturate)

        // ===== SEQUENCE 4: Filter with high brightness =====
        $display("\n[%0t] === Sequence 4: Filter ON, BPM=150 (brightness~191) ===", $time);
        BPM_estimate = 150;
        
        @(posedge clk);
        @(posedge clk);
        
        send_pixel(0);    // 0 + 191 = 191
        send_pixel(50);   // 50 + 191 = 241
        send_pixel(64);   // 64 + 191 = 255 (saturate)
        send_pixel(100);  // 100 + 191 = 255 (saturate)
        send_pixel(200);  // 200 + 191 = 255 (saturate)

        // ===== SEQUENCE 5: Toggle filter on/off =====
        $display("\n[%0t] === Sequence 5: Toggle filter enable ===", $time);
        BPM_estimate = 100;
        
        filter_enable = 1;
        @(posedge clk);
        send_pixel(50);  // With filter: 50+127=177
        
        filter_enable = 0;
        @(posedge clk);
        send_pixel(50);  // Without filter: 50
        
        filter_enable = 1;
        @(posedge clk);
        send_pixel(50);  // With filter: 177
        
        filter_enable = 0;
        @(posedge clk);
        send_pixel(50);  // Without filter: 50

        // ===== SEQUENCE 6: Backpressure demo =====
        $display("\n[%0t] === Sequence 6: Backpressure (module_ready=0) ===", $time);
        filter_enable = 1;
        BPM_estimate = 100;
        
        @(posedge clk);
        module_ready = 1;
        send_pixel(100);  // Should output
        
        @(posedge clk);
        module_ready = 0;  // Downstream not ready
        pix_in = 100;
        valid_in = 1;
        repeat(3) @(posedge clk);  // Hold for 3 cycles
        
        module_ready = 1;  // Release
        @(posedge clk);
        valid_in = 0;

        // ===== SEQUENCE 7: Continuous stream =====
        $display("\n[%0t] === Sequence 7: Continuous 10-pixel stream ===", $time);
        filter_enable = 1;
        BPM_estimate = 80;  // brightness ~102
        module_ready = 1;
        
        @(posedge clk);
        @(posedge clk);
        
        for (int i = 0; i < 10; i++) begin
            send_pixel(i * 20);
        end

        $display("\n[%0t] === Testbench Complete ===", $time);
        $display("\nSCREENSHOT RECOMMENDATIONS:");
        $display("1. Sequence 1 (100-200ns) - Shows transparent mode");
        $display("2. Sequence 2 (250-400ns) - Shows brightness addition & saturation");
        $display("3. Sequence 5 (700-850ns) - Shows filter enable toggling");
        $display("4. Sequence 6 (900-1000ns) - Shows backpressure handling");

        repeat(5) @(posedge clk);
        $finish;
    end

    // Helper task
    task send_pixel(input logic [7:0] value);
        @(posedge clk);
        pix_in = value;
        valid_in = 1;
        @(posedge clk);
        valid_in = 0;
    endtask

endmodule