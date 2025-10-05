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

	output [6:0] HEX0, HEX1, HEX2, HEX3,
	input  [3:0] KEY,
	input		AUD_ADCDAT,
	input    AUD_BCLK,     // 3.072 MHz clock from the WM8731
	output   AUD_XCK,      // 18.432 MHz sampling clock to the WM8731
	input    AUD_ADCLRCK,
	output  logic [17:0] LEDR
);
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
     .audio_input_ready  (audio_input_ready),

     .snr_db         (snr_db),
     .signal_rms     (signal_rms),
     .noise_rms      (noise_rms),
     .output_valid   (output_valid),
     .output_ready   ()
	);
	
	// Display:
	display u_display (
		.clk(adc_clk),
		.value(snr_db),
		.display0(HEX0),
		.display1(HEX1),
		.display2(HEX2),
		.display3(HEX3)
	);


endmodule


