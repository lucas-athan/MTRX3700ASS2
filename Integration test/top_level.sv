module top_level #(
	parameter int DE1_SOC = 0 // !!!IMPORTANT: Set this to 1 for DE1-SoC or 0 for DE2-115
) (
	input       CLOCK_50,     // 50 MHz only used as input to the PLLs.

	// DE1-SoC I2C to WM8731:
	output	   FPGA_I2C_SCLK,
	inout       FPGA_I2C_SDAT,
	// DE2-115 I2C to WM8731:
	output      I2C_SCLK,
	inout       I2C_SDAT,

	output [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7,
	input  [3:0] KEY,
	input		AUD_ADCDAT,
	input    AUD_BCLK,     // 3.072 MHz clock from the WM8731
	output   AUD_XCK,      // 18.432 MHz sampling clock to the WM8731
	input    AUD_ADCLRCK,
	output  logic [17:0] LEDR,
	output logic [7:0] LEDG,
	
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
	
	
	
	localparam W        = 16;   //NOTE: To change this, you must also change the Twiddle factor initialisations in r22sdf/Twiddle.v. You can use r22sdf/twiddle_gen.pl.
	localparam NSamples = 1024; //NOTE: To change this, you must also change the SdfUnit instantiations in r22sdf/FFT.v accordingly.

	logic i2c_clk; i2c_pll i2c_pll_u (.areset(1'b0),.inclk0(CLOCK_50),.c0(i2c_clk)); // generate 20 kHz clock
	logic adc_clk; adc_pll adc_pll_u (.areset(1'b0),.inclk0(CLOCK_50),.c0(adc_clk)); // generate 18.432 MHz clock
	logic audio_clk; assign audio_clk = AUD_BCLK; // 3.072 MHz clock from the WM8731

	assign AUD_XCK = adc_clk; // The WM8731 needs a 18.432 MHz sampling clock from the FPGA. AUD_BCLK is then 1/6th of this.

	// Board-specific I2C connections:
	generate
		if (DE1_SOC) begin : DE1_SOC_VS_DE2_115_CHANGES
			set_audio_encoder set_codec_de1_soc (.i2c_clk(i2c_clk), .I2C_SCLK(FPGA_I2C_SCLK), .I2C_SDAT(FPGA_I2C_SDAT)); // Connected to the DE1-SoC I2C pins
			assign LEDR[9:0]   = DE_LEDR[15:6]; // Take the 10 most significant data bits for the 10x DE1-SoC LEDs (pad the left 8 with zeros)
			assign LEDR[17:10] = 8'hFF; // Tie-off these unecessary ports to one
			assign I2C_SCLK = 1'b1;
			assign I2C_SDAT = 1'bZ;
		end else begin
			set_audio_encoder set_codec_de2_115 (.i2c_clk(i2c_clk), .I2C_SCLK(I2C_SCLK), .I2C_SDAT(I2C_SDAT)); // Connected to the DE2-115 I2C pins
			assign LEDR = {2'b0, DE_LEDR}; // Use all 16 data bits for the 18x DE2-115 LEDs (pad the left with 2x zeros)
			assign FPGA_I2C_SCLK = 1'b1; // Tie-off these unecessary ports to one
			assign FPGA_I2C_SDAT = 1'bZ;
		end
	endgenerate
	// The above modules configure the WM8731 audio codec for microphone input. They are in set_audio_encoder.v and use the i2c_master module in i2c_master.sv.

	logic reset; assign reset = ~KEY[0];

	// Audio Input
	logic [W-1:0]              audio_input_data;
	logic                      audio_input_valid;
	mic_load #(.N(W)) u_mic_load (
		.adclrc(AUD_ADCLRCK),
		.bclk(AUD_BCLK),
		.adcdat(AUD_ADCDAT),
		.sample_data(audio_input_data),
		.valid(audio_input_valid)
	);

	
	logic [$clog2(NSamples)-1:0] pitch_output_data;
	
	fft_pitch_detect #(.W(W), .NSamples(NSamples)) u_fft_pitch_detect (
	    .audio_clk(audio_clk),
	    .fft_clk(adc_clk), // Reuse ADC sampling clock for the FFT pipeline.
	    .reset(reset),
	    .audio_input_data(audio_input_data),
	    .audio_input_valid(audio_input_valid),
	    .pitch_output_data(pitch_output_data),
	    .pitch_output_valid(pitch_output_valid)
	);
	
	logic [W-1:0] DE_LEDR; // Accounts for the different number of LEDs on the DE1-Soc vs. DE2-115.
	always_comb begin
		if (audio_input_data[W-1]) DE_LEDR <= (~audio_input_data + 1); // magnitude of a negative number (2's complement).
		else DE_LEDR <= audio_input_data;
	end
	 
	// for SNR Calc
	logic quiet_period;
	assign quiet_period = 1'b0;
//	logic [31:0] q_counter;
//	always_ff @(posedge CLOCK_50 or posedge reset) begin 
//		if (reset) begin 
//			quiet_period <= 1'b1; 
//			q_counter <= 0; 
//		end 
//		else if (quiet_period) begin 
//			if (q_counter < 50_000_000) begin // 1s calibration 
//			q_counter <= q_counter + 1; 
//			end
//			else begin 
//				quiet_period <= 1'b0; 
//			end 
//		end
//	end
   logic audio_input_ready;
   logic output_valid;
   logic output_ready;

   logic [W-1:0] snr_db;
   logic [W-1:0] signal_rms;
   logic [W-1:0] noise_rms;
	
	// SNR calculator
	snr_calculator #(.DATA_WIDTH(W), .SNR_WIDTH(W)) u_snr_calculator (
     .clk            (CLOCK_50),
     .reset          (reset),

     .quiet_period   (quiet_period),

     .audio_input        (pitch_output_data),       // pitch output
     .audio_input_valid  (pitch_output_valid), 
//	  .audio_input        (audio_input_data),       // normal audio output
//     .audio_input_valid  (audio_input_valid), 
     .audio_input_ready  (audio_input_ready),

     .snr_db         (snr_db),
     .signal_rms     (signal_rms),
     .noise_rms      (noise_rms),
     .output_valid   (output_valid),
     .output_ready   ()
	);
	
	// Display:
	display u_display_db (
		.clk(adc_clk),
		.value(snr_db),
		.display0(HEX0),
		.display1(HEX1),
		.display2(HEX2),
		.display3(HEX3)
	);
	
	beat_pulse u_beat_pulse (
		.snr_db(snr_db),
		.beat_pulse(beat_pulse)
	);
	
	assign LEDG[0] = beat_pulse;
	
	// --- BPM Energy Detector Instantiation ---
	logic [W-1:0] bpm_val;
	logic beat_detected;

	bpm_energy_detector #(
    .SAMPLE_WIDTH(W),
    .CLOCK_FREQ(18_432_000),   // same as adc_clk frequency
    .SAMPLE_RATE(30_720),
    .WINDOW_SIZE(614),         // 20 ms @ 30.72 kHz
    .ENERGY_WIDTH(32),
    .BPM_WIDTH(W)
	) u_bpm_energy_detector (
    .clk(adc_clk),
    .reset(reset),
    .audio_sample(audio_input_data),
    .sample_valid(audio_input_valid),
    .bpm_val(bpm_val),
    .beat_detected(beat_detected)
	);


	// HERE
	display u_display_bpm (
		.clk(adc_clk),
		.value(bpm_val),
		.display0(HEX4),
		.display1(HEX5),
		.display2(HEX6),
		.display3(HEX7)
	);
	
	assign LEDG[1] = beat_detected;



//endmodule



// HEREEE

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



