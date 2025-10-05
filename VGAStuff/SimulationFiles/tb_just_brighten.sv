`timescale 1ns/1ps

module tb_just_brighten;

    // ============================================================
    // Clock & Reset
    // ============================================================
    localparam real CLK_PERIOD_NS = 40.0;  // 25 MHz (simulated PLL output)

    logic CLOCK_50;
    logic [3:0] KEY;

    // 50 MHz clock → PLL stub will output this directly
    initial begin
        CLOCK_50 = 0;
        forever #(CLK_PERIOD_NS/2.0) CLOCK_50 = ~CLOCK_50;
    end

    // Active-low reset using KEY[0]
    initial begin
        KEY = 4'b1111;
        #200;
        KEY[0] = 1'b0;   // assert reset
        #200;
        KEY[0] = 1'b1;   // release reset

        // 🔸 Enable brighten filter (active low)
        KEY[1] = 1'b0;   
    end


    // ============================================================
    // DUT Instantiation
    // ============================================================
    top_level dut (
        .CLOCK_50    (CLOCK_50),
        .KEY         (KEY),
        .VGA_R       (),
        .VGA_G       (),
        .VGA_B       (),
        .VGA_HS      (),
        .VGA_VS      (),
        .VGA_CLK     (),
        .VGA_BLANK_N (),
        .VGA_SYNC_N  ()
    );

    // ============================================================
    // VCD dump for waveform viewing (optional in ModelSim)
    // ============================================================
    initial begin
        $dumpfile("tb_top_level.vcd");
        $dumpvars(0, tb_just_brighten);
    end

    // ============================================================
    // Frame buffer capture for PPM output
    // ============================================================
    localparam IMG_W = 640;
    localparam IMG_H = 480;

    integer pre_fd, post_fd;
    integer x, y;

    logic [7:0] pre_frame  [0:IMG_W*IMG_H-1];
    logic [7:0] post_frame [0:IMG_W*IMG_H-1];

    // Capture pre- and post-filter pixels during visible periods
    always @(posedge dut.VGA_CLK) begin
        if (dut.sync_inst.visible && dut.producer.valid) begin
            int idx;
            idx = dut.sync_inst.vcount * IMG_W + dut.sync_inst.hcount;

            pre_frame[idx]  <= dut.producer.pixel_out; // pre-filter (ROM output)
            post_frame[idx] <= dut.VGA_R;              // post-filter (final VGA)
        end
    end

    // ============================================================
    // Run 1 frame, then write the images, then finish
    // ============================================================
    localparam int TOTAL_PIXELS = 800 * 525;  // one VGA frame at 640x480@60Hz

    initial begin
        // run ~1 frame (plus a tiny guard) so the capture array fills
        #(TOTAL_PIXELS * CLK_PERIOD_NS + 1000);

        $display("📝 Writing pre_filter.ppm and post_filter.ppm...");

        // ---------- PRE FILTER ----------
        pre_fd = $fopen("pre_filter.ppm", "wb");
        if (pre_fd) begin
            $fwrite(pre_fd, "P6\n%d %d\n255\n", IMG_W, IMG_H);
            for (y = 0; y < IMG_H; y = y + 1) begin
                for (x = 0; x < IMG_W; x = x + 1) begin
                    int idx; byte pix;
                    idx = y * IMG_W + x;
                    pix = pre_frame[idx];
                    $fwrite(pre_fd, "%c%c%c", pix, pix, pix);
                end
            end
            $fclose(pre_fd);
            $display("✅ Wrote pre_filter.ppm");
        end else begin
            $display("❌ Failed to open pre_filter.ppm for writing.");
        end

        // ---------- POST FILTER ----------
        post_fd = $fopen("post_filter.ppm", "wb");
        if (post_fd) begin
            $fwrite(post_fd, "P6\n%d %d\n255\n", IMG_W, IMG_H);
            for (y = 0; y < IMG_H; y = y + 1) begin
                for (x = 0; x < IMG_W; x = x + 1) begin
                    int idx; byte pix;
                    idx = y * IMG_W + x;
                    pix = post_frame[idx];
                    $fwrite(post_fd, "%c%c%c", pix, pix, pix);
                end
            end
            $fclose(post_fd);
            $display("✅ Wrote post_filter.ppm");
        end else begin
            $display("❌ Failed to open post_filter.ppm for writing.");
        end

        $display("✅ Simulation finished after one frame.");
        $finish; // use finish (clean exit)
    end

    // ============================================================
    // Optional Debug Pixel Tap (VGA_R only)
    // ============================================================
    always @(posedge dut.VGA_CLK) begin
        if (dut.sync_inst.visible &&
            dut.sync_inst.hcount == 100 &&
            dut.sync_inst.vcount == 100) begin
            $display("[%0t] Pixel(100,100): pre=%0d VGA_R=%0d valid=%b",
                     $time,
                     dut.producer.pixel_out,
                     dut.VGA_R,
                     dut.producer.valid);
        end
    end

endmodule
