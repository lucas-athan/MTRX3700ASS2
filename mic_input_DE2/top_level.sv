module top_level #(
	parameter int DE1_SOC=0 // !!!IMPORTANT: Set this to 1 for DE1 or 0 for DE2
) (
	input CLOCK_50,

	// DE1-SoC I2C to WM8731:
	output         FPGA_I2C_SCLK,
	inout          FPGA_I2C_SDAT,
	// DE2-115 I2C to WM8731:
	output         I2C_SCLK,
	inout          I2C_SDAT,

	input         AUD_ADCDAT,
	input         AUD_BCLK,
	output        AUD_XCK,
	input         AUD_ADCLRCK,

	output  logic [17:0] LEDR,
	output [6:0]  HEX0, HEX1, HEX2, HEX3 // Four 7-segment displays
);
	localparam W	= 16;

	logic [15:0] DE_LEDR; // Accounts for the different number of LEDs on the DE1-Soc vs. DE2-115.

	logic adc_clk; adc_pll adc_pll_u (.areset(1'b0),.inclk0(CLOCK_50),.c0(adc_clk)); // generate 18.432 MHz clock
	logic i2c_clk; i2c_pll i2c_pll_u (.areset(1'b0),.inclk0(CLOCK_50),.c0(i2c_clk)); // generate 20 kHz clock
	
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

	logic [W-1:0] data;
		
    mic_load #(.N(W)) u_mic_load (
      .adclrc(AUD_ADCLRCK),
      .bclk(AUD_BCLK),
      .adcdat(AUD_ADCDAT),
      .sample_data(data)
	);
	
	assign AUD_XCK = adc_clk;
		
	always_comb begin
		if (data[W-1]) DE_LEDR <= (~data + 1); // magnitude of a negative number (2's complement).
		else DE_LEDR <= data;
	end
	
	// Control signals
   logic reset_n;
   assign reset_n = 1'b1;   // can use pushbutton if you want manual reset

   logic quiet_period;
   assign quiet_period = 1'b0;

   // Handshake signals
   logic audio_input_valid;
   logic audio_input_ready;
   logic output_valid;
   logic output_ready;

   // Results
   logic [W-1:0] snr_db;
   logic [W-1:0] signal_rms;
   logic [W-1:0] noise_rms;

   // currently set to always be ready
   assign audio_input_valid = 1'b1;
   assign output_ready      = 1'b1;
	
	snr_calculator #(.DATA_WIDTH(W), .SNR_WIDTH(W)) u_snr_calculator (
        .clk            (CLOCK_50),
        .reset          (~reset_n),

        .quiet_period   (quiet_period), // Indicates quiet period for calibration

        .audio_input        (data),
        .audio_input_valid  (audio_input_valid),
        .audio_input_ready  (audio_input_ready),

        .snr_db         (snr_db),
        .signal_rms     (signal_rms),
        .noise_rms      (noise_rms),
        .output_valid   (output_valid),
        .output_ready   (output_ready)
    );

	 display u_display (
        .clk(CLOCK_50),
//        .value(DE_LEDR),
		  .value(snr_db),
        .display0(HEX0),
        .display1(HEX1),
        .display2(HEX2),
        .display3(HEX3)
    );
	

endmodule

