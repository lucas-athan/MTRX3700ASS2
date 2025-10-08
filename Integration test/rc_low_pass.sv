`timescale 1ns/1ns
module rc_low_pass #(parameter W, W_FRAC, ALPHA) ( // E.g W=16, W_FRAC=8
    input clk,

    input [W-1:0] x_data,   //x_data fixed-point format: Q8.8 (e.g. W=16, W_FRAC=8)
    input         x_valid,
    output        x_ready,

    output [W-1:0] y_data,   //y_data fixed-point format: Q8.8 (e.g. W=16, W_FRAC=8)
    output         y_valid,
    input          y_ready
);

    // 1. Assign x_ready : we are ready for data if the module we output to (y_ready) is ready (this module does not exert backpressure).
    assign x_ready = y_ready;

    localparam ONE = 1 << W_FRAC; // 1.0 in fixed point
                                                                     //*** Fixed point formats: (e.g. W=16, W_FRAC=8)
    logic signed [2*W-1:0]     a1_mult; // Output of -a_1 multiplier //** multiply: 16.16 (= 8.8 * 8.8)
    logic signed [2*(W+1)-1:0] b0_mult; // Output of b_0 multiplier  //** multiply: 18.16 (= 9.8 * 9.8)
    logic signed [W:0]         add_input; // Output of left adder    //** add: 9.8 (= 8.8 + 8.8) (truncate a1_mult to 8.8)
    logic signed [W-1:0]       register_delay = 0; // z^-1 delay     //** 8.8 (truncate to be same as inputs)
                                                                     //** You could choose larger widths with less truncation to decrease truncation error.
                                                                     //** The above are the minimum widths needed for passing the testcases with enough accuracy_

    // 2. always_ff to create the z^-1 register_delay_ Only enable this register when x_valid =1 & x_ready = 1.
    // Hint: Make sure to use signed'() on add_input if you truncate it from 9.8 to 8.8.
    always_ff @(posedge clk) begin
        if (x_valid && x_ready) begin
            register_delay <= y_data;
        end
    end

    // 3. always_comb to set adder `add_input` and multipliers `a1_mult` and `b0_mult`
    // Hint: Make sure to use signed'() on x_data, ALPHA, ONE and any variable that you truncate. E.g. signed'(x_data)
    // Hint: When setting add_input, you can truncate a1_mult from 16.16 to 8.8. Remember to use signed'() on this!
    always_comb begin
        a1_mult = signed'(ONE - ALPHA) * signed'(register_delay);
        b0_mult = signed'(ALPHA) * signed'(x_data);

        add_input = signed'(a1_mult[W+W_FRAC-1:W_FRAC])+ signed'(b0_mult[W+W_FRAC-1:W_FRAC]);
    end

    // 4. Assign y_data (truncate b0_mult from 18.16 to 8.8)
    assign y_data = signed'(add_input[W-1:0]);

    // 5. Assign y_valid: this should just be equal to x_valid.
    assign y_valid = x_valid;

    // IMPORTANT: make sure to make everything signed by using the signed'() cast!!!

endmodule
