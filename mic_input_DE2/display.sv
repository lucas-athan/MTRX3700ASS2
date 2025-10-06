module display (
    input         clk,
    input  [15:0] value,   // 16-bit input
    output [6:0]  display0,
    output [6:0]  display1,
    output [6:0]  display2,
    output [6:0]  display3
);

    /*** FSM Controller ***/
    enum {Initialise, Add3, Shift, Result} next_state, current_state = Initialise;
    logic init, add, done;
    logic [4:0] count = 0;  // 5 bits enough for 16 iterations

    always_comb begin
        case(current_state)
            Initialise: next_state = Add3;
            Add3:       next_state = Shift;
            Shift:      next_state = (count == 15) ? Result : Add3; // 16 iterations
            Result:     next_state = Initialise;
            default:    next_state = Initialise;
        endcase
    end

    always_ff @(posedge clk) begin
        current_state <= next_state;
        if (current_state == Shift) count <= count + 1;
        else if (current_state == Initialise) count <= 0;
    end

    always_comb begin
        init = 0; add = 0; done = 0;
        case(current_state)
            Initialise: init = 1;
            Add3:       add  = 1;
            Result:     done = 1;
        endcase
    end

    /*** Shift-Add3 Logic ***/
    logic [3:0] bcd0, bcd1, bcd2, bcd3;
    logic [15:0] temp_value;

    always_ff @(posedge clk) begin
        if (init) begin
            {bcd3, bcd2, bcd1, bcd0, temp_value} <= {16'b0, value}; // 16-bit input + 16-bit temp_value
        end else begin
            if (add) begin
                bcd0 <= bcd0 > 4 ? bcd0 + 3 : bcd0;
                bcd1 <= bcd1 > 4 ? bcd1 + 3 : bcd1;
                bcd2 <= bcd2 > 4 ? bcd2 + 3 : bcd2;
                bcd3 <= bcd3 > 4 ? bcd3 + 3 : bcd3;
            end else begin
                {bcd3, bcd2, bcd1, bcd0, temp_value} <= {bcd3, bcd2, bcd1, bcd0, temp_value} << 1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (done) begin
            digit0 <= bcd0;
            digit1 <= bcd1;
            digit2 <= bcd2;
            digit3 <= bcd3;
        end
    end

    /*** Seven-Segment Display ***/
    logic [3:0] digit0, digit1, digit2, digit3;
    seven_seg u0 (.bcd(digit0), .segments(display0));
    seven_seg u1 (.bcd(digit1), .segments(display1));
    seven_seg u2 (.bcd(digit2), .segments(display2));
    seven_seg u3 (.bcd(digit3), .segments(display3));

endmodule
