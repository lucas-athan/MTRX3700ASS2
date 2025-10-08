module top_level (
    input        CLOCK_50,        // DE2-115 50 MHz onboard clock
    input  [3:0] KEY,             // Pushbuttons (KEY[0] used for reset)

    // VGA outputs
    output [7:0] VGA_R,
    output [7:0] VGA_G,
    output [7:0] VGA_B,
    output       VGA_HS,
    output       VGA_VS,
    output       VGA_CLK,
    output       VGA_BLANK_N,
    output       VGA_SYNC_N
);

    // ============================================================
    // Pixel clock generation
    // ============================================================
    wire pix_clk;

`ifdef SIMULATION
    // Bypass PLL during simulation — just use 50 MHz directly
    assign pix_clk = CLOCK_50;
`else
    pll25 pll_inst (
        .inclk0 (CLOCK_50),
        .c0     (pix_clk)
    );
`endif

    assign VGA_CLK = pix_clk;


		 // ============================================================
		 // VGA sync generator
		 // ============================================================
		 wire [9:0] hcount, vcount;
		 wire       visible;

		 vga_sync sync_inst (
			  .clk     (pix_clk),
			  .reset   (~KEY[0]), 
			  .hcount  (hcount),
			  .vcount  (vcount),
			  .visible (visible),
			  .hsync   (VGA_HS),
			  .vsync   (VGA_VS),
			  .blank_n (VGA_BLANK_N)
		 );

		 assign VGA_SYNC_N = 1'b0;


		 // ============================================================
		 // Image producer (grayscale source)
		 // ============================================================
		 wire [7:0] pixel;
		 wire       valid;

		 grayscale_producer producer (
			  .clk       (pix_clk),
			  .reset     (~KEY[0]),
			  .hcount    (hcount),
			  .vcount    (vcount),
			  .visible   (visible),
			  .pixel_out (pixel),
			  .valid     (valid)
		 );


		 // ============================================================
		 // Filter pipeline (using proper handshake interface)
		 // ============================================================
		 wire [7:0] thresh_pix_out;
		 wire       thresh_valid_out;
		 wire       thresh_output_ready;

		 wire [7:0] bright_pix_out;
		 wire       bright_valid_out;
		 wire       bright_output_ready;

		 // ---------- Stage 1: Threshold ----------
		 threshold_filter thresh_stage (
			  .clk           (pix_clk),
			  .reset         (~KEY[0]),

			  .pix_in        (pixel),
			  .valid_in      (valid),

			  .module_ready  (bright_output_ready),   // downstream ready
			  .output_ready  (thresh_output_ready),   // upstream ready

			  .filter_enable (~KEY[1]),
			  .BPM_estimate  (8'd80),

			  .pix_out       (thresh_pix_out),
			  .valid_out     (thresh_valid_out),
			  .brightness    ()
		 );

		 // ---------- Stage 2: Brightness ----------
		 brightness_filter bright_stage (
			  .clk           (pix_clk),
			  .reset         (~KEY[0]),

			  .pix_in        (thresh_pix_out),
			  .valid_in      (thresh_valid_out),

			  .module_ready  (1'b1),                  // VGA sink always ready
			  .output_ready  (bright_output_ready),   // drives upstream stage

			  .filter_enable (~KEY[2]),
			  .BPM_estimate  (8'd150),

			  .pix_out       (bright_pix_out),
			  .valid_out     (bright_valid_out),
			  .brightness    ()
		 );


		 // ============================================================
		 // Pixel → VGA RGB output
		 // ============================================================
		 assign VGA_R = (visible && bright_valid_out) ? bright_pix_out : 8'd0;
		 assign VGA_G = (visible && bright_valid_out) ? bright_pix_out : 8'd0;
		 assign VGA_B = (visible && bright_valid_out) ? bright_pix_out : 8'd0;

endmodule
