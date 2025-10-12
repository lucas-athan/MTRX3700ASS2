`timescale 1ns/1ps

module vga_sync_tb;

    // VGA 640x480@60Hz timing parameters
    parameter H_VISIBLE = 640;
    parameter H_FRONT   = 16;
    parameter H_SYNC    = 96;
    parameter H_BACK    = 48;
    parameter H_TOTAL   = 800;
    parameter V_VISIBLE = 480;
    parameter V_FRONT   = 10;
    parameter V_SYNC    = 2;
    parameter V_BACK    = 33;
    parameter V_TOTAL   = 525;
    
    // 25 MHz pixel clock
    parameter CLK_PERIOD = 40; // 40ns = 25MHz

    // Testbench signals
    logic       clk;
    logic       reset;
    logic [9:0] hcount;
    logic [9:0] vcount;
    logic       visible;
    logic       hsync;
    logic       vsync;
    logic       blank_n;

    // Instantiate DUT
    vga_sync #(
        .H_VISIBLE(H_VISIBLE),
        .H_FRONT(H_FRONT),
        .H_SYNC(H_SYNC),
        .H_BACK(H_BACK),
        .H_TOTAL(H_TOTAL),
        .V_VISIBLE(V_VISIBLE),
        .V_FRONT(V_FRONT),
        .V_SYNC(V_SYNC),
        .V_BACK(V_BACK),
        .V_TOTAL(V_TOTAL)
    ) dut (
        .clk(clk),
        .reset(reset),
        .hcount(hcount),
        .vcount(vcount),
        .visible(visible),
        .hsync(hsync),
        .vsync(vsync),
        .blank_n(blank_n)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Test stimulus - OPTIMIZED FOR SCREENSHOTS
    initial begin
        $dumpfile("vga_sync_screenshot.vcd");
        $dumpvars(0, vga_sync_tb);

        $display("=== VGA Sync Generator - Screenshot Testbench ===");
        $display("H_TOTAL = %0d, V_TOTAL = %0d", H_TOTAL, V_TOTAL);
        $display("HSYNC: pixels %0d-%0d", H_VISIBLE+H_FRONT, H_VISIBLE+H_FRONT+H_SYNC-1);
        $display("VSYNC: lines %0d-%0d\n", V_VISIBLE+V_FRONT, V_VISIBLE+V_FRONT+V_SYNC-1);
        
        reset = 1;
        repeat(5) @(posedge clk);
        reset = 0;
        $display("[%0t] Reset released\n", $time);

        // ===== SEQUENCE 1: Start of visible region =====
        $display("[%0t] === Sequence 1: First 50 pixels of line 0 ===", $time);
        // Let it run naturally from (0,0)
        repeat(50) @(posedge clk);

        // ===== SEQUENCE 2: End of visible, into front porch =====
        $display("\n[%0t] === Sequence 2: End of visible → front porch ===", $time);
        // Fast forward to near end of visible region
        wait(hcount == 630);
        $display("  At hcount=630 (near end of visible)");
        repeat(30) @(posedge clk);  // Will cross into front porch

        // ===== SEQUENCE 3: HSYNC pulse region =====
        $display("\n[%0t] === Sequence 3: HSYNC pulse (active low) ===", $time);
        // Fast forward to just before HSYNC
        wait(hcount == H_VISIBLE + H_FRONT - 2);
        $display("  Before HSYNC at hcount=%0d", hcount);
        repeat(H_SYNC + 4) @(posedge clk);  // Show full HSYNC pulse plus margins

        // ===== SEQUENCE 4: Complete horizontal line =====
        $display("\n[%0t] === Sequence 4: Complete horizontal scanline ===", $time);
        wait(hcount == 0 && vcount > 0);
        $display("  Starting line %0d at hcount=0", vcount);
        
        // Show complete line with all regions
        for (int i = 0; i < H_TOTAL; i += 10) begin  // Sample every 10 pixels
            wait(hcount == i);
            if (i < H_VISIBLE)
                $display("    hcount=%0d: VISIBLE", i);
            else if (i < H_VISIBLE + H_FRONT)
                $display("    hcount=%0d: FRONT PORCH", i);
            else if (i < H_VISIBLE + H_FRONT + H_SYNC)
                $display("    hcount=%0d: HSYNC (should be LOW)", i);
            else
                $display("    hcount=%0d: BACK PORCH", i);
        end

        // ===== SEQUENCE 5: Vertical transitions =====
        $display("\n[%0t] === Sequence 5: Vertical line transitions ===", $time);
        // Show transitions between several lines
        for (int line = 0; line < 5; line++) begin
            wait(hcount == 0);
            $display("  Line %0d started", vcount);
            repeat(20) @(posedge clk);  // Show start of each line
        end

        // ===== SEQUENCE 6: End of visible lines → vertical front porch =====
        $display("\n[%0t] === Sequence 6: Last visible line → V front porch ===", $time);
        wait(vcount == V_VISIBLE - 2);
        wait(hcount == 0);
        
        // Show transition through last visible lines
        for (int i = 0; i < 3; i++) begin
            $display("  Line %0d: visible=%0b", vcount, visible);
            wait(hcount == H_TOTAL - 1);
            @(posedge clk);
        end

        // ===== SEQUENCE 7: VSYNC pulse =====
        $display("\n[%0t] === Sequence 7: VSYNC pulse (active low) ===", $time);
        wait(vcount == V_VISIBLE + V_FRONT - 1);
        wait(hcount == 0);
        $display("  Before VSYNC at vcount=%0d", vcount);
        
        // Show VSYNC transition
        for (int i = 0; i < V_FRONT + V_SYNC + 2; i++) begin
            wait(hcount == H_TOTAL - 1);
            @(posedge clk);
            if (vcount >= V_VISIBLE + V_FRONT && vcount < V_VISIBLE + V_FRONT + V_SYNC)
                $display("  Line %0d: VSYNC=LOW (active)", vcount);
            else
                $display("  Line %0d: VSYNC=HIGH (inactive)", vcount);
        end

        // ===== SEQUENCE 8: Corner positions =====
        $display("\n[%0t] === Sequence 8: Testing corner positions ===", $time);
        
        // Wait for frame start
        wait(vcount == 0 && hcount == 0);
        $display("  Top-left (0,0): visible=%0b", visible);
        repeat(5) @(posedge clk);
        
        // Jump to top-right
        wait(hcount == H_VISIBLE - 5);
        $display("  Near top-right (%0d,0): visible=%0b", hcount, visible);
        repeat(10) @(posedge clk);
        $display("  Past top-right (%0d,0): visible=%0b", hcount, visible);

        // ===== SEQUENCE 9: Continuous operation showing all signals =====
        $display("\n[%0t] === Sequence 9: 100 cycles of continuous operation ===", $time);
        wait(hcount == 100 && vcount == 10);
        $display("  Starting continuous capture at (%0d,%0d)", hcount, vcount);
        repeat(100) @(posedge clk);

        $display("\n[%0t] === Testbench Complete ===", $time);
        $display("\nSCREENSHOT RECOMMENDATIONS:");
        $display("============================================");
        $display("SCREENSHOT 1: Horizontal Timing Overview");
        $display("  - Show complete scanline (32us / 800 pixels)");
        $display("  - Zoom: 0-35us to see one complete line");
        $display("  - Should clearly show: visible, front porch, HSYNC LOW, back porch");
        $display("  - Signals to display: hcount, hsync, visible, blank_n");
        $display("");
        $display("SCREENSHOT 2: HSYNC Pulse Detail");
        $display("  - Zoom to HSYNC region: ~25-30us");
        $display("  - Show hcount transitioning through:");
        $display("    * 640-655 (front porch, hsync HIGH)");
        $display("    * 656-751 (sync pulse, hsync LOW)");
        $display("    * 752-799 (back porch, hsync HIGH)");
        $display("  - Signals: hcount, hsync, visible");
        $display("");
        $display("SCREENSHOT 3: Visible Region Transitions");
        $display("  - Show hcount around 638-642 (visible edge)");
        $display("  - visible should go LOW at hcount=640");
        $display("  - Signals: hcount, vcount, visible, blank_n");
        $display("");
        $display("SCREENSHOT 4: Counter Operation");
        $display("  - Show hcount wrapping from 799→0 and vcount incrementing");
        $display("  - Zoom to line transition");
        $display("  - Signals: hcount, vcount, hsync, vsync");
        $display("");
        $display("SCREENSHOT 5: Vertical Timing (Advanced)");
        $display("  - Show multiple lines including VSYNC");
        $display("  - Zoom out to see ~20-30 lines");
        $display("  - Signals: vcount, vsync, visible");
        $display("  - Should show vsync going LOW during lines 490-491");
        $display("============================================");

        repeat(10) @(posedge clk);
        $finish;
    end

    // Monitor to help identify key events
    always @(posedge clk) begin
        // Mark HSYNC transitions
        if (hcount == H_VISIBLE + H_FRONT)
            $display("[%0t] HSYNC starts (LOW) at hcount=%0d", $time, hcount);
        if (hcount == H_VISIBLE + H_FRONT + H_SYNC)
            $display("[%0t] HSYNC ends (HIGH) at hcount=%0d", $time, hcount);
            
        // Mark VSYNC transitions
        if (vcount == V_VISIBLE + V_FRONT && hcount == 0)
            $display("[%0t] VSYNC starts (LOW) at vcount=%0d", $time, vcount);
        if (vcount == V_VISIBLE + V_FRONT + V_SYNC && hcount == 0)
            $display("[%0t] VSYNC ends (HIGH) at vcount=%0d", $time, vcount);
            
        // Mark visible region boundaries
        if (hcount == H_VISIBLE - 1)
            $display("[%0t] End of visible pixels on line %0d", $time, vcount);
        if (vcount == V_VISIBLE - 1 && hcount == 0)
            $display("[%0t] Last visible line", $time);
    end

endmodule