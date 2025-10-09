`timescale 1ns/1ns
module snr_calculator #(
    parameter DATA_WIDTH = 16,   // Input audio width
    parameter SNR_WIDTH  = 16    // Output SNR width
)(
    input  logic                  clk,
    input  logic                  reset,
    input  logic                  quiet_period,    // HIGH = calibrate noise

    // Audio Input
    input  logic [DATA_WIDTH-1:0] audio_input,
    input  logic                  audio_input_valid,
    output logic                  audio_input_ready,

    // SNR results
    output logic [SNR_WIDTH-1:0]  snr_db,
    output logic [DATA_WIDTH-1:0] signal_rms,
    output logic [DATA_WIDTH-1:0] noise_rms,
    output logic                  output_valid,
    input  logic                  output_ready
);

    // abs value
    logic [DATA_WIDTH-1:0] abs_data;
    always_comb begin
        if (audio_input[DATA_WIDTH-1]) abs_data <= (~audio_input + 1);
        else abs_data <= audio_input;
    end

    // Extend to Q16.16 signed for filter
    logic signed [31:0] abs_data_ext;
    always_comb abs_data_ext = {abs_data, 16'd0}; // shift 16-bit to upper Q16 integer part

    // MA filter coefficients
    localparam logic [31:0] ALPHA_SIGNAL = 32'd16384; // 0.25 Q16
    localparam logic [31:0] ALPHA_NOISE  = 32'd512;   // 0.0078 Q16

    logic signed [31:0] signal_rms_temp;
    logic signed [31:0] noise_rms_temp;

    // Signal RMS (fast MA)
    rc_low_pass #(
        .W(32),
        .W_FRAC(16),
        .ALPHA(ALPHA_SIGNAL)
    ) u_signal_ma (
        .clk(clk),
        .x_data(abs_data_ext),
        .x_valid(audio_input_valid),
        .x_ready(audio_input_ready),
        .y_data(signal_rms_temp),
        .y_valid(),
        .y_ready(1'b1)
    );

    // Noise RMS (slow MA, only when quiet_period)
    rc_low_pass #(
        .W(32),
        .W_FRAC(16),
        .ALPHA(ALPHA_NOISE)
    ) u_noise_ma (
        .clk(clk),
        .x_data(abs_data_ext),
        .x_valid(audio_input_valid & quiet_period),
        .x_ready(audio_input_ready),
        .y_data(noise_rms_temp),
        .y_valid(),
        .y_ready(1'b1)
    );

    // Truncate to 16-bit integer for log10 calculation
    assign signal_rms = signal_rms_temp[31:16];
//    assign noise_rms  = noise_rms_temp[31:16];
//	 assign noise_rms  = (noise_rms_temp[31:16] < 16'd100) ? 16'd100 : noise_rms_temp[31:16];
	 assign noise_rms = 16'd100;

    // Log10 approximation
    function automatic [15:0] log10_approx(input [15:0] value);
        integer msb;
        reg [7:0] fraction;
    begin
        if (value == 0) log10_approx = 16'd0;
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

    // SNR Calculation (dB)
    logic signed [31:0] snr_calc;
    always_comb begin
        snr_calc = 20 * (signed'({16'd0, log_signal}) - signed'({16'd0, log_noise})) >>> 8;
        snr_db   = snr_calc;
    end

    // Handshake / Valid signals
    assign audio_input_ready = 1'b1;
    assign output_valid      = 1'b1;

endmodule
