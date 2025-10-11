module top_level #(
	parameter int DE1_SOC = 0,
	parameter int IMG_W = 640,
	parameter int IMG_H = 480
) (
	input       CLOCK_50,
	output	   FPGA_I2C_SCLK,
	inout       FPGA_I2C_SDAT,
	output      I2C_SCLK,
	inout       I2C_SDAT,
	output [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7,
	input  [3:0] KEY,
	input		AUD_ADCDAT,
	input    AUD_BCLK,
	output   AUD_XCK,
	input    AUD_ADCLRCK,
	output  logic [17:0] LEDR,
	output logic [7:0] LEDG,
    output [7:0] VGA_R,
    output [7:0] VGA_G,
    output [7:0] VGA_B,
    output       VGA_HS,
    output       VGA_VS,
    output       VGA_CLK,
    output       VGA_BLANK_N,
    output       VGA_SYNC_N
);
    // CLOCKS
    wire pix_clk;
	`ifdef SIMULATION
    assign pix_clk = CLOCK_50;
	`else
    pll25 pll_inst (.inclk0(CLOCK_50), .c0(pix_clk));
	`endif
    assign VGA_CLK = pix_clk;

	localparam W = 16;
	localparam NSamples = 1024;

	logic i2c_clk; 
	i2c_pll i2c_pll_u (.areset(1'b0),.inclk0(CLOCK_50),.c0(i2c_clk));
	
	logic adc_clk; 
	adc_pll adc_pll_u (.areset(1'b0),.inclk0(CLOCK_50),.c0(adc_clk));
	
	logic audio_clk; 
	assign audio_clk = AUD_BCLK;
	assign AUD_XCK = adc_clk;

    // BOARD-SPECIFIC I2C
	generate
		if (DE1_SOC) begin : DE1_SOC_VS_DE2_115_CHANGES
			set_audio_encoder set_codec_de1_soc (.i2c_clk(i2c_clk), .I2C_SCLK(FPGA_I2C_SCLK), .I2C_SDAT(FPGA_I2C_SDAT));
			assign LEDR[9:0]   = DE_LEDR[15:6];
			assign LEDR[17:10] = 8'hFF;
			assign I2C_SCLK = 1'b1;
			assign I2C_SDAT = 1'bZ;
		end else begin
			set_audio_encoder set_codec_de2_115 (.i2c_clk(i2c_clk), .I2C_SCLK(I2C_SCLK), .I2C_SDAT(I2C_SDAT));
			assign LEDR = {2'b0, DE_LEDR};
			assign FPGA_I2C_SCLK = 1'b1;
			assign FPGA_I2C_SDAT = 1'bZ;
		end
	endgenerate

	logic reset; 
	assign reset = ~KEY[0];

    // AUDIO FRONTEND - Mic Input
	logic [W-1:0] audio_input_data;
	logic audio_input_valid;
	
	mic_load #(.N(W)) u_mic_load (
		.adclrc(AUD_ADCLRCK),
		.bclk(AUD_BCLK),
		.adcdat(AUD_ADCDAT),
		.sample_data(audio_input_data),
		.valid(audio_input_valid)
	);

    // DECIMATION 
	logic [W-1:0] decimated_data;
	logic decimated_valid;
	
	decimate #(.W(W), .DECIMATE_FACTOR(4)) u_decimate (
		.clk(audio_clk),
		.x_data(audio_input_data),
		.x_valid(audio_input_valid),
		.x_ready(),
		.y_data(decimated_data),
		.y_valid(decimated_valid),
		.y_ready(1'b1)
	);

   // SNR CALCULATOR - Uses Decimated Raw Audio
	logic quiet_period;
	logic calibration_done;
	logic [31:0] q_counter;
	
	// 1 second calibration period
	always_ff @(posedge CLOCK_50 or posedge reset) begin 
		if (reset) begin 
			quiet_period <= 1'b1; 
			calibration_done <= 1'b0;
			q_counter <= 0; 
		end 
		else if (quiet_period) begin 
			if (q_counter < 50_000_000) begin
				q_counter <= q_counter + 1; 
			end
			else begin 
				quiet_period <= 1'b0;
				calibration_done <= 1'b1; 
			end 
		end
	end

	logic audio_input_ready;
	logic output_valid;
	logic [W-1:0] snr_db;
	logic [W-1:0] signal_rms;
	logic [W-1:0] noise_rms;
	
	snr_calculator #(.DATA_WIDTH(W), .SNR_WIDTH(W)) u_snr_calculator (
		.clk(CLOCK_50),
		.reset(reset),
		.quiet_period(quiet_period),
		
		// decimated audio
		.audio_input(decimated_data),
		.audio_input_valid(decimated_valid),
		.audio_input_ready(audio_input_ready),
		
		.snr_db(snr_db),
		.signal_rms(signal_rms),
		.noise_rms(noise_rms),
		.output_valid(output_valid),
		.output_ready(1'b1)
	);

   // BPM DETECTOR - Uses signal_rms from SNR (Energy Method)
	logic [W-1:0] bpm_val;
	logic beat_detected;
	
	bpm_energy_detector #(
		.SAMPLE_WIDTH(W),
		.CLOCK_FREQ(50_000_000),  
		.BPM_WIDTH(W)
	) u_bpm_energy_detector (
		.clk(CLOCK_50),
		.reset(reset),
		
		.signal_rms(signal_rms),
		.signal_rms_valid(output_valid),
		
		.bpm_val(bpm_val),
		.beat_detected(beat_detected)
	);

    // BEAT PULSE from SNR threshold (for LEd)
	logic beat_pulse;
	
	beat_pulse #(.SNR_WIDTH(16), .THRESHOLD(25)) u_beat_pulse (
		.snr_db(snr_db),
		.beat_pulse(beat_pulse)
	);

    // LED INDICATORS
	assign LEDG[1] = quiet_period;   // Calibration stat
	assign LEDG[0] = beat_pulse && calibration_done && (signal_rms > 100);

   //DISPLAYS
	logic [W-1:0] DE_LEDR;
	always_comb begin
		if (audio_input_data[W-1]) DE_LEDR <= (~audio_input_data + 1);
		else DE_LEDR <= audio_input_data;
	end

	display u_display_db (
		.clk(adc_clk),
		.value(snr_db),
		.display0(HEX0),
		.display1(HEX1),
		.display2(HEX2),
		.display3(HEX3)
	);

	display u_display_bpm (
		.clk(adc_clk),
		.value(bpm_val),
		.display0(HEX4),
		.display1(HEX5),
		.display2(HEX6),
		.display3(HEX7)
	);

    // VGA PIPELINE
    wire [9:0] hcount, vcount;
    wire visible;

    vga_sync sync_inst (
        .clk(pix_clk),
        .reset(~KEY[0]), 
        .hcount(hcount),
        .vcount(vcount),
        .visible(visible),
        .hsync(VGA_HS),
        .vsync(VGA_VS),
        .blank_n(VGA_BLANK_N)
    );
    assign VGA_SYNC_N = 1'b0;
    
	 // Filter Pipeline (using proper handshake interface)
    wire [7:0] thresh_pix_out;
    wire       thresh_valid_out;
    wire       thresh_output_ready;

    wire [7:0] bright_pix_out;
    wire       bright_valid_out;
    wire       bright_output_ready;

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
	 
	 // Image Producer (grayscale source)
    grayscale_producer producer (
        .clk(pix_clk),
        .reset(~KEY[0]),
        .hcount(hcount),
        .vcount(vcount),
        .visible(visible),
        .pixel_out(pixel),
        .valid(valid)
    );

    // Stage 1: Threshold 
    threshold_filter thresh_stage (
        .clk(pix_clk),
        .reset(~KEY[0]),
        .pix_in(pixel),
        .valid_in(valid),
        .module_ready(bright_output_ready),
        .output_ready(thresh_output_ready),
        .filter_enable(~KEY[1]),
        .BPM_estimate(bpm_val[7:0]),
        .pix_out(thresh_pix_out),
        .valid_out(thresh_valid_out),
        .brightness()
    );
	 
    //Stage 2: Brightness 
    brightness_filter bright_stage (
        .clk(pix_clk),
        .reset(~KEY[0]),
        .pix_in(thresh_pix_out),
        .valid_in(thresh_valid_out),
        .module_ready(adsr_output_ready),
        .output_ready(bright_output_ready),
        .filter_enable(~KEY[3]),
        .BPM_estimate(bpm_val[7:0]),
        .pix_out(bright_pix_out),
        .valid_out(bright_valid_out),
        .brightness()
    );
	 
    //  Stage 3: ADSR Filter 
    adsr_filter #(
        .ATTACK(255), .DECAY(255), .SUSTAIN(255), .RELEASE(255),
        .MIN_BPM(40), .MAX_BPM(200), .BITS(8),
        .IMAGE_WIDTH(640), .IMAGE_HEIGHT(480)
    ) adsr_stage (
        .clk(pix_clk),
        .reset(~KEY[0]),
        .pix_in(bright_pix_out),
        .valid_in(bright_valid_out),
        .module_ready(pad_ready_out),
        .output_ready(adsr_output_ready),
        .filter_enable(beat_detected),  // Use actual beat detector output
        .beat_trigger(beat_detected),
        .BPM_estimate(bpm_val[7:0]),
        .pulse_amplitude(8'd255),
        .pix_out(adsr_pix_out),
        .valid_out(adsr_valid_out),
        .bpm_brightness_gain(),
        .env_brightness_gain(),
        .bpm_brightness_mult(),
        .brightness_gain()
    );
	 
    // Stage 4: Padding (zero-pad 1 px border)

    pad #(.WIDTH(IMG_W), .HEIGHT(IMG_H)) pad_stage (
        .clk(pix_clk),
        .reset(~KEY[0]),
        .data_in(adsr_pix_out),
        .valid_in(adsr_valid_out),
        .ready_out(pad_ready_out),
        .data_out(pad_pix_out),
        .valid_out(pad_valid_out),
        .ready_in(conv_ready_upstream)
    );
	 //  Stage 5: 3x3 Convolution 
    // Kernel coefficients (identity or edge detection based on a future KEY)
    // For now, using identity kernel (center = 1, rest = 0)
    wire signed [7:0] k11 = (~KEY[2]) ? -8'sd1 : 8'sd0;
    wire signed [7:0] k12 = (~KEY[2]) ?  8'sd0 : 8'sd0;
    wire signed [7:0] k13 = (~KEY[2]) ?  8'sd1 : 8'sd0;
    wire signed [7:0] k21 = (~KEY[2]) ? -8'sd2 : 8'sd0;
    wire signed [7:0] k22 = (~KEY[2]) ?  8'sd0 : 8'sd1;
    wire signed [7:0] k23 = (~KEY[2]) ?  8'sd2 : 8'sd0;
    wire signed [7:0] k31 = (~KEY[2]) ? -8'sd1 : 8'sd0;
    wire signed [7:0] k32 = (~KEY[2]) ?  8'sd0 : 8'sd0;
    wire signed [7:0] k33 = (~KEY[2]) ?  8'sd1 : 8'sd0;

    convolution_2d_filter #(.WIDTH(IMG_W+2), .HEIGHT(IMG_H+2)) conv_stage (
        .clk(pix_clk),
        .reset(~KEY[0]),
        .k11(k11), .k12(k12), .k13(k13),
        .k21(k21), .k22(k22), .k23(k23),
        .k31(k31), .k32(k32), .k33(k33),
        .data_in(pad_pix_out),
        .startofpacket_in(1'b0),
        .endofpacket_in(1'b0),
        .valid_in(pad_valid_out),
        .ready_out(conv_ready_upstream),
        .data_out(conv_pix_out),
        .startofpacket_out(conv_sop),
        .endofpacket_out(conv_eop),
        .valid_out(conv_valid_out),
        .ready_in(1'b1)
    );
	 
    // Pixel to VGA RGB Output (now from convolution stage)
    assign VGA_R = (visible && conv_valid_out) ? conv_pix_out : 8'd0;
    assign VGA_G = (visible && conv_valid_out) ? conv_pix_out : 8'd0;
    assign VGA_B = (visible && conv_valid_out) ? conv_pix_out : 8'd0;

endmodule 