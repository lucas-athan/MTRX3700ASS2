module pad #(
  parameter int WIDTH  = 6,
  parameter int HEIGHT = 6
)(
  input  logic       clk,
  input  logic       reset,
  input  logic [7:0] data_in,
  input  logic       valid_in,
  output logic       ready_out,
  output logic [7:0] data_out,
  output logic       valid_out,
  input  logic       ready_in
);

  localparam int PW = WIDTH  + 2;
  localparam int PH = HEIGHT + 2;

  typedef enum logic [2:0] {
    S_TOP, S_LEFT, S_PIX, S_RIGHT, S_BOTTOM
  } state_t;
  state_t st;

  logic [$clog2(WIDTH) :0]  x_in;
  logic [$clog2(HEIGHT):0]  y_in;
  logic [$clog2(PW)    :0]  x_out;
  logic [$clog2(PH)    :0]  y_out;

  assign ready_out = (st == S_PIX) && ready_in;

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      st        <= S_TOP;
      x_in      <= '0;
      y_in      <= '0;
      x_out     <= '0;
      y_out     <= '0;
      data_out  <= 8'd0;
      valid_out <= 1'b0;
    end else begin
      valid_out <= 1'b0;
      data_out  <= 8'd0;

      unique case (st)

        S_TOP: if (ready_in) begin
          data_out  <= 8'd0;
          valid_out <= 1'b1;
          x_out     <= x_out + 1;
          if (x_out == PW - 1) begin
            x_out <= 0;
            y_out <= 1;
            st    <= S_LEFT;
          end
        end

        S_LEFT: if (ready_in) begin
          data_out  <= 8'd0;
          valid_out <= 1'b1;
          x_out     <= 1;
          x_in      <= 0;
          st        <= S_PIX;
        end

        S_PIX: begin
          if (valid_in && ready_out) begin
            data_out  <= data_in;
            valid_out <= 1'b1;
            x_out     <= x_out + 1;
            x_in      <= x_in + 1;
            if (x_in == WIDTH - 1) begin
              st <= S_RIGHT;
            end
          end
        end

        S_RIGHT: if (ready_in) begin
          data_out  <= 8'd0;
          valid_out <= 1'b1;
          x_out     <= 0;
          y_out     <= y_out + 1;
          if (y_in == HEIGHT - 1) begin
            y_in <= 0;
            st   <= S_BOTTOM;
          end else begin
            y_in <= y_in + 1;
            st   <= S_LEFT;
          end
        end

        S_BOTTOM: if (ready_in) begin
          data_out  <= 8'd0;
          valid_out <= 1'b1;
          x_out     <= x_out + 1;
          if (x_out == PW - 1) begin
            x_out <= 0;
            y_out <= 0;
            st    <= S_TOP;
          end
        end

      endcase
    end
  end

endmodule
