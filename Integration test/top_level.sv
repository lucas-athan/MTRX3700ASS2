module top_level #(
	parameter int DE1_SOC = 0, // !!!IMPORTANT: Set this to 1 for DE1-SoC or 0 for DE2-115
	parameter int IMG_W = 640,
	parameter int IMG_H = 480
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
    // Clock Generation
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
	
	
    // Audio Processing Parameters and Clocks
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
	logic pitch_output_valid;
	
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
	 
    // SNR Calculation
//	logic quiet_period;
//	assign quiet_period = 1'b0;
	
	 // SNR Calculation
	logic [23:0] calibration_counter;
	logic quiet_period;

	// Mic samples at: 3.072 MHz BCLK / 32 bits = 96 kHz
	// 10 seconds @ 96 kHz = 960,000 samples
	localparam CALIBRATION_SAMPLES = 24'd960_000;

	always_ff @(posedge audio_clk or posedge reset) begin
    if (reset) begin
        calibration_counter <= 0;
        quiet_period <= 1'b1;  // Start in calibration mode
    end else if (audio_input_valid) begin
        if (calibration_counter < CALIBRATION_SAMPLES) begin
            calibration_counter <= calibration_counter + 1;
            quiet_period <= 1'b1;  // Calibrating noise floor
        end else begin
            quiet_period <= 1'b0;  // Calibration complete
        end
    end
	end

	// Debug: Show calibration status
	assign LEDG[7] = quiet_period;  // LED ON = calibrating

   logic audio_input_ready;
   logic output_valid;
   logic output_ready;

   logic [W-1:0] snr_db;
   logic [W-1:0] signal_rms;
   logic [W-1:0] noise_rms;
	
	// SNR calculator
	snr_calculator #(.DATA_WIDTH(W), .SNR_WIDTH(W)) u_snr_calculator (
     .clk            (audio_clk),
     .reset          (reset),

     .quiet_period   (quiet_period),

//     .audio_input        (pitch_output_data),       // pitch output
//     .audio_input_valid  (pitch_output_valid), 
	  .audio_input        (audio_input_data),       // raw input
     .audio_input_valid  (audio_input_valid), 
     .audio_input_ready  (audio_input_ready),

     .snr_db         (snr_db),
     .signal_rms     (signal_rms),
     .noise_rms      (noise_rms),
     .output_valid   (output_valid),
     .output_ready   ()
	);
	
	// Display SNR:
	display u_display_db (
		.clk(audio_clk),
		.value(snr_db),
		.display0(HEX0),
		.display1(HEX1),
		.display2(HEX2),
		.display3(HEX3)
	);
	
	logic beat_pulse;
	beat_pulse u_beat_pulse (
		.snr_db(snr_db),
		.beat_pulse(beat_pulse)
	);
	
	assign LEDG[0] = beat_pulse;
	
    // BPM Energy Detector (using corrected pitch_output_data)
	logic [W-1:0] bpm_val;
	logic beat_detected;

	bpm_energy_detector #(
    .SAMPLE_WIDTH(W),
    .CLOCK_FREQ(18_432_000),   // same as adc_clk frequency
    .SAMPLE_RATE(30_720),
    .BPM_WIDTH(W)
	) u_bpm_energy_detector (
    .clk(audio_clk),              // Use audio_clk (3.072 MHz)
    .reset(reset),
    .signal_rms(signal_rms),      // Energy envelope from SNR calculator
    .snr_db(snr_db),              // SNR in dB for threshold check
    .sample_valid(audio_input_valid),  
    .bpm_val(bpm_val),
    .beat_detected(beat_detected)
	);

	// Display BPM:
	display u_display_bpm (
		.clk(adc_clk),
		.value(bpm_val),
		.display0(HEX4),
		.display1(HEX5),
		.display2(HEX6),
		.display3(HEX7)
	);
	
	assign LEDG[1] = beat_detected;


    // VGA Sync Generator
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


    // Image Producer (grayscale source)
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

    // Filter Pipeline (using proper handshake interface)
    wire [7:0] thresh_pix_out;
    wire       thresh_valid_out;
    wire       thresh_output_ready;

    wire [7:0] bright_pix_out;
    wire       bright_valid_out;
    wire       bright_output_ready;

    wire [7:0] blur_pix_out;
    wire       blur_valid_out;
    wire       blur_output_ready;

    wire [7:0] adsr_pix_out;
    wire       adsr_valid_out;
    wire       adsr_output_ready;

    wire [7:0] pad_pix_out;
    wire       pad_valid_out;
    wire       pad_ready_out;

    wire [7:0] conv_pix_out;
    wire       conv_valid_out;
    wire       conv_ready_upstream;
    wire       conv_sop, conv_eop;

    // Stage 1: Threshold 
    threshold_filter thresh_stage (
        .clk           (pix_clk),
        .reset         (~KEY[0]),

        .pix_in        (pixel),
        .valid_in      (valid),

        .module_ready  (bright_output_ready),   // downstream ready
        .output_ready  (thresh_output_ready),   // upstream ready

        .filter_enable (~KEY[1]),
        .BPM_estimate  (bpm_val[7:0]),          // Use actual BPM from detector (8-bit)

        .pix_out       (thresh_pix_out),
        .valid_out     (thresh_valid_out),
        .brightness    ()
    );

    //Stage 2: Brightness 
    brightness_filter bright_stage (
        .clk           (pix_clk),
        .reset         (~KEY[0]),

        .pix_in        (thresh_pix_out),
        .valid_in      (thresh_valid_out),

        .module_ready  (blur_output_ready),     // downstream ready (ADSR stage)
        .output_ready  (bright_output_ready),   // drives upstream stage

        .filter_enable (~KEY[3]),
        .BPM_estimate  (bpm_val[7:0]),          // Use actual BPM from detector (8-bit)

        .pix_out       (bright_pix_out),
        .valid_out     (bright_valid_out),
        .brightness    ()
    );

    // Stage 3: Blur Filter
    blur_filter_3 blur_inst (
        .clk(clk),
        .reset(reset),
        .module_ready(adsr_output_ready),
        .output_ready(blur_output_ready),
        .pixel_in(bright_pix_out),
        .pixel_in_valid(bright_valid_out),
        .beat_detected(),
        .pixel_out(blur_pix_out),
        .pixel_out_valid(blur_valid_out)
    );

    //  Stage 4: ADSR Filter 
    adsr_filter #(
        .ATTACK        (255),
        .DECAY         (255),
        .SUSTAIN       (255),
        .RELEASE       (255),
        .MIN_BPM       (40),
        .MAX_BPM       (200),
        .BITS          (8),
        .IMAGE_WIDTH   (640),
        .IMAGE_HEIGHT  (480)
    ) adsr_stage (
        .clk           (pix_clk),
        .reset         (~KEY[0]),

        .pix_in        (blur_pix_out),
        .valid_in      (blur_valid_out),

        .module_ready  (pad_ready_out),         // downstream ready (padding stage)
        .output_ready  (adsr_output_ready),     // drives upstream stage

        .filter_enable (beat_pulse),            // Trigger on beat pulse
        .beat_trigger  (beat_pulse),            // Beat trigger input
        .BPM_estimate  (bpm_val[7:0]),          // Use actual BPM (8-bit)
        .pulse_amplitude (8'd255),              // Full amplitude

        .pix_out       (adsr_pix_out),
        .valid_out     (adsr_valid_out),

        // Debug outputs (not connected for now)
        .bpm_brightness_gain (),
        .env_brightness_gain (),
        .bpm_brightness_mult (),
        .brightness_gain     ()
    );

    // Stage 4: Padding (zero-pad 1 px border)
    pad #(
        .WIDTH  (IMG_W),
        .HEIGHT (IMG_H)
    ) pad_stage (
        .clk       (pix_clk),
        .reset     (~KEY[0]),
        .data_in   (adsr_pix_out),
        .valid_in  (adsr_valid_out),
        .ready_out (pad_ready_out),             // back to ADSR
        .data_out  (pad_pix_out),
        .valid_out (pad_valid_out),
        .ready_in  (conv_ready_upstream)        // from convolution
    );

    //  Stage 5: 3x3 Convolution 
    // Kernel coefficients (identity or edge detection based on a future KEY)
    // For now, using identity kernel (center = 1, rest = 0)
		wire signed [7:0] k11 = (~KEY[2]) ? -8'sd1 : 8'sd0;
		wire signed [7:0] k12 = (~KEY[2]) ?  8'sd0 : 8'sd0;
		wire signed [7:0] k13 = (~KEY[2]) ?  8'sd1 : 8'sd0;
		wire signed [7:0] k21 = (~KEY[2]) ? -8'sd2 : 8'sd0;
		wire signed [7:0] k22 = (~KEY[2]) ?  8'sd0 : 8'sd1;   // center pixel
		wire signed [7:0] k23 = (~KEY[2]) ?  8'sd2 : 8'sd0;
		wire signed [7:0] k31 = (~KEY[2]) ? -8'sd1 : 8'sd0;
		wire signed [7:0] k32 = (~KEY[2]) ?  8'sd0 : 8'sd0;
		wire signed [7:0] k33 = (~KEY[2]) ?  8'sd1 : 8'sd0;


    convolution_2d_filter #(
        .WIDTH  (IMG_W + 2),
        .HEIGHT (IMG_H + 2)
    ) conv_stage (
        .clk   (pix_clk),
        .reset (~KEY[0]),

        .k11(k11), .k12(k12), .k13(k13),
        .k21(k21), .k22(k22), .k23(k23),
        .k31(k31), .k32(k32), .k33(k33),

        .data_in          (pad_pix_out),
        .startofpacket_in (1'b0),
        .endofpacket_in   (1'b0),
        .valid_in         (pad_valid_out),
        .ready_out        (conv_ready_upstream),

        .data_out         (conv_pix_out),
        .startofpacket_out(conv_sop),
        .endofpacket_out  (conv_eop),
        .valid_out        (conv_valid_out),
        .ready_in         (1'b1)                // VGA sink always ready
    );


    // Pixel to VGA RGB Output (now from convolution stage)
    assign VGA_R = (visible && conv_valid_out) ? conv_pix_out : 8'd0;
    assign VGA_G = (visible && conv_valid_out) ? conv_pix_out : 8'd0;
    assign VGA_B = (visible && conv_valid_out) ? conv_pix_out : 8'd0;

endmodule