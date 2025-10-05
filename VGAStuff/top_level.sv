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
	 // Pixel clock
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
        .reset   (~KEY[0]), // still keep KEY[0] reset if you want
        .hcount  (hcount),
        .vcount  (vcount),
        .visible (visible),
        .hsync   (VGA_HS),
        .vsync   (VGA_VS),
        .blank_n (VGA_BLANK_N)
    );

    assign VGA_SYNC_N = 1'b0;

    // ============================================================
    // Producer
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
	// Brighten Filter Stage (using pixel_wise_filter)
	// ============================================================
	wire [7:0] bright_pix_out;
	wire       bright_valid_out;
	wire       bright_module_ready;
	wire [7:0] bright_value;
	wire [23:0] bright_mult;
	localparam int BPM_CONST = 150; //Placeholder value until integration

	pixel_wise_filter brighten_stage (
		 .clk            (pix_clk),
		 .reset          (~KEY[0]),

		 .pix_in         (pixel),
		 .valid_in       (valid),
		 .module_ready   (bright_module_ready), 

		 .filter_enable  (~KEY[1]),             // KEY[1] enables brighten filter
		 .filter_mode    (1'b1),                // 1 = additive mode
		 .BPM_estimate   (BPM_CONST),          

		 .pix_out        (bright_pix_out),
		 .output_ready   (1'b1),                // always ready (no downstream backpressure yet)
		 .valid_out      (bright_valid_out),
		 .brightness     (bright_value),
		 .brightness_mult(bright_mult)
	);

	// For now, module is always "ready" since downstream is always accepting pixels.
	assign bright_module_ready = 1'b1;

	 
	 //==============================================================
	 // Pixel Wise Filter Stage Two ()
	 //==============================================================
	 
	 
    // ============================================================
    // Pixel → VGA RGB
    // ============================================================
    assign VGA_R = (visible && valid) ? bright_pix_out : 8'd0;
    assign VGA_G = (visible && valid) ? bright_pix_out : 8'd0;
    assign VGA_B = (visible && valid) ? bright_pix_out : 8'd0;

endmodule
