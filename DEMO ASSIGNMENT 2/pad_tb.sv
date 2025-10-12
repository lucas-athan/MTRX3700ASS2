`timescale 1ns/1ps

module pad_tb;

  
  localparam int WIDTH   = 4;
  localparam int HEIGHT  = 4;
  localparam int PW      = WIDTH + 2;
  localparam int PH      = HEIGHT + 2;
  localparam int IN_PIX  = WIDTH*HEIGHT;
  localparam int OUT_PIX = PW*PH;

  
  logic        clk;
  logic        reset;
  logic [7:0]  data_in;
  logic        valid_in;
  logic        ready_out;
  logic [7:0]  data_out;
  logic        valid_out;
  logic        ready_in;

  
  pad #(
    .WIDTH (WIDTH),
    .HEIGHT(HEIGHT)
  ) dut (
    .clk,
    .reset,
    .data_in,
    .valid_in,
    .ready_out,
    .data_out,
    .valid_out,
    .ready_in
  );

  
  initial clk = 0;
  always  #5 clk = ~clk; 

  //  Test data 
 
  logic [7:0] in_img [0:IN_PIX-1];
  // Expected padded 6x6 image
  logic [7:0] gold   [0:PH-1][0:PW-1];

  
  integer out_count;
  integer i;


  
  initial begin
    
    valid_in  = 0;
    data_in   = '0;
    ready_in  = 1; 
    reset     = 1;
    out_count = 0;
  
    
    for (i = 0; i < IN_PIX; i = i + 1) in_img[i] = i+1;

    // Release reset
    repeat (3) @(posedge clk);
    reset = 0;
    @(posedge clk);


      // data stream
      begin : producer
        i = 0;
        valid_in = 0;
        @(posedge clk);
        while (i < IN_PIX) begin
          if (ready_out) begin
            data_in  <= in_img[i];
            valid_in <= 1'b1;
          end
          else begin
            valid_in <= 1'b0;
          end
          @(posedge clk);
          if (valid_in && ready_out) i = i + 1; 
        end
        valid_in <= 1'b0;
      end

      
		repeat (20) @(posedge clk);
		$finish;
		end 


endmodule
