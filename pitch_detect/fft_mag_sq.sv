module fft_mag_sq #(
    parameter W = 16
) (
    input                clk,
    input                reset,
    input                fft_valid,
    input        [W-1:0] fft_imag,
    input        [W-1:0] fft_real,
    output logic [W*2:0] mag_sq,
    output logic         mag_valid
);

    logic signed [W*2-1:0] multiply_stage_real, multiply_stage_imag;
    logic signed [W*2:0]   add_stage;
    
    always_ff @(posedge clk) begin : multiply_stage
       //TODO Your code here!
       // We want to implement the 2 pipeline stages, similar to task 1.2.
       // When multiplying, make sure to use the signed function, e.g: signed'(fft_real)*signed'(fft_real);
       // Remember to use reset.
       if (reset) begin
            multiply_stage_real <= 0;
            multiply_stage_imag <= 0;
       end
       multiply_stage_real <= signed'(fft_real)*signed'(fft_real);
       multiply_stage_imag <= signed'(fft_imag)*signed'(fft_imag);
    end

    always_ff @(posedge clk) begin : add_stage_1
        if (reset) begin
            add_stage <= 0;
        end
        add_stage <= multiply_stage_real + multiply_stage_imag;
    end

    logic valid_pipe;

    always_ff @(posedge clk) begin : valid_control
        if (reset) begin
            valid_pipe <= 0;
            mag_valid <= 0;
        end
        else begin
            valid_pipe <= fft_valid;
            mag_valid <= valid_pipe;
        end
    end

    assign mag_sq    = add_stage;
    // assign mag_valid = 1;//TODO set to `1` when mag_sq valid **this should be 2 cycles after valid input!**
    // Hint: you can use a shift register to implement valid.

endmodule
