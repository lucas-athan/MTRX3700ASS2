module snr_calculator #(
    parameter DATA_WIDTH,
    parameter SNR_WIDTH
)(
    input  logic clk,
    input  logic reset,
    input  logic quiet_period,  // Indicates quiet period for calibration
    input  logic [DATA_WIDTH-1:0] audio_input,
    input  logic                  audio_input_valid,
    output logic                  audio_input_ready,
    output logic [SNR_WIDTH-1:0]  snr_db,
    output logic [DATA_WIDTH-1:0] signal_rms,
    output logic [DATA_WIDTH-1:0] noise_rms,
    output logic                  output_valid,
    input  logic                  output_ready
);

    logic [DATA_WIDTH-1:0] abs_data;
	 always_comb begin
		if (audio_input[DATA_WIDTH-1]) abs_data <= (~audio_input + 1); // magnitude of a negative number (2's complement).
		else abs_data <= audio_input;
	 end
	 
    // MA filter registers
    logic [31:0] signal_rms_temp;
    logic [31:0] noise_rms_temp;

    localparam logic [31:0] ALPHA_SIGNAL = 32'd16384; // 0.25 in Q16
    localparam logic [31:0] ALPHA_NOISE  = 32'd512;   // 0.0078 in Q16

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            signal_rms_temp <= 0;
            noise_rms_temp  <= 0;
        end else if (audio_input_valid) begin
            // Short MA (signal)
            signal_rms_temp <= signal_rms_temp + 
                               $signed((($signed(abs_data) - $signed(signal_rms_temp[15:0])) * $signed(ALPHA_SIGNAL)) >>> 16);
            // Long MA (noise)
            if (quiet_period)
                noise_rms_temp <= noise_rms_temp + 
                                  $signed((($signed(abs_data) - $signed(noise_rms_temp[15:0])) * $signed(ALPHA_NOISE)) >>> 16);
        end
    end

    assign signal_rms = signal_rms_temp[15:0];
    assign noise_rms  = noise_rms_temp[15:0];

    // Log10 approximation \_0_o_/
    function automatic [15:0] log10_approx(input [15:0] value);
        integer msb;
        reg [7:0] fraction;
    begin
        if (value == 0) log10_approx = 0;
        else begin
            for (msb=15; msb>=0; msb=msb-1)
                if (value[msb]) break;
            fraction = (value << (15-msb)) >> 8;
            log10_approx = (((msb << 8) + fraction) * 77) >>> 8; // Q8
        end
    end
    endfunction

    logic [15:0] log_signal;
    logic [15:0] log_noise;
    always_comb begin
        log_signal = log10_approx(signal_rms);
        log_noise  = log10_approx(noise_rms);
    end

    // snr calculation
    logic signed [SNR_WIDTH-1:0] snr_calc;
    always_comb begin
        snr_calc = 20 * ($signed(log_signal) - $signed(log_noise)); // Q8
        snr_db   = snr_calc >>> 8;
    end

    // handshake
    assign audio_input_ready = 1'b1;
    assign output_valid = audio_input_valid & output_ready;

endmodule 