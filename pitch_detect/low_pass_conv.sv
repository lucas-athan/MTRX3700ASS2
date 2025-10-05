module low_pass_conv #(parameter W, W_FRAC) (
    input clk,

    input  logic x_valid,
    output logic x_ready,
    input  logic [W-1:0] x_data,
    output logic y_valid,
    input  logic y_ready,
    output logic [W-1:0] y_data
);

    // 1. Assign x_ready: we are ready for data if the module we output to (y_ready) is ready (this module does not exert backpressure).
    assign x_ready = y_ready;
    // Impulse response h[n]: (32-bit, 16-bit frac, 2's complement)
    localparam N = 41;
    logic signed [W-1:0] h [0:N-1] = '{32'h00000000, 32'h00000014, 32'h0000003f, 32'h00000050, 32'h00000000, 32'hffffff0b, 32'hfffffd56, 32'hfffffb08, 32'hfffff8a1, 32'hfffff6ee, 32'hfffff6f3, 32'hfffff9b5, 32'h00000000, 32'h00000a2d, 32'h000017f4, 32'h00002860, 32'h000039e3, 32'h00004a8b, 32'h0000584b, 32'h0000615d, 32'h00006488, 32'h0000615d, 32'h0000584b, 32'h00004a8b, 32'h000039e3, 32'h00002860, 32'h000017f4, 32'h00000a2d, 32'h00000000, 32'hfffff9b5, 32'hfffff6f3, 32'hfffff6ee, 32'hfffff8a1, 32'hfffffb08, 32'hfffffd56, 32'hffffff0b, 32'h00000000, 32'h00000050, 32'h0000003f, 32'h00000014, 32'h00000000};

    // 2. Make a shift register of depth = impulse response size. Feed x_data into this shift register when x_valid=1 and x_ready=1 (and shift all other data in the shift reg).
    logic signed [W-1:0] shift_reg [0:N-1];
    always_ff @(posedge clk) begin : h_shift_register
        // On a handshake (x_valid & x_ready), shift signed'(x_data) into shift_reg and shift everything.
        // Hint: use a for loop.
        if (x_valid & x_ready) begin
            for (int i = 0; i<N-1; i++) begin
                shift_reg[i+1] <= shift_reg[i];
            end
            shift_reg[0] <= signed'(x_data);
        end
    end

    // 3. Multiply each register in the shift register by its repsective h[n] value, for n = 0 to N.
    logic signed [2*W-1:0] mult_result [0:N-1];  // 2*W as the multiply doubles width
    always_comb begin : h_multiply
        // Set mult_result for each n value.
        // Hint: use a for loop.
        // Hint: make sure to use the signed'() cast on both variables. e.g. signed'(a).
        for (int i = 0; i<N-1; i++) begin
            mult_result[i] <= signed'(shift_reg[i]) * signed'(h[i]);
        end
    end

    // 4. Add all of the multiplication results together and shift the result into the output buffer.
    logic signed [$clog2(N)+2*W:0] macc; // $clog2(N)+1 to accomodate for overflows over the 41 additions.
    always_comb begin : MAC
        macc = 0;
        // Set macc to be the sum of all elements in mult_result.
        // Hint: use a for loop.
        for (int i = 0; i<N-1; i++) begin
            macc = macc + mult_result[i];
        end
    end

    // 5. Output reg: use y_data as a register, load the result of the MACC into y_data if x_valid and x_ready are high (i.e. data is moving).
    // y_valid should be set as a register here too.
    logic overflow; // Optional (not marked): detect for overflow.
    logic x_valid_q = 1'b0; // Delay x_valid by 1 clock cycle
    always_ff @(posedge clk) begin : output_reg
        if (y_ready) y_valid <= 0;
        if (x_valid & x_ready) begin
            y_data <= macc[W + W_FRAC - 1 : W_FRAC]; // **Remember to truncate the fixed point properly!!! Hint: see 1.5 Fixed Point Binary**
            //overflow <= FILL-IN; // (Optional) Check if our INTEGER truncation causes overflow (remember 2's complement!!!)
            x_valid_q <= 1'b1;    // Delay x_valid by 1 clock cycle
            y_valid <= x_valid_q; // 2 clock cycles for valid data to get from x to y
        end
    end

endmodule
