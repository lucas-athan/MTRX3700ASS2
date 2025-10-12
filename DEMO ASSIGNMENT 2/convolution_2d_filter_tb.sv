`timescale 1ns/1ps

module convolution_2d_filter_tb;

    localparam int WIDTH  = 4;
    localparam int HEIGHT = 4;
		

    logic clk;
    logic reset;
    logic [7:0] data_in;
    logic startofpacket_in, endofpacket_in, valid_in;
    logic ready_out;

    logic [7:0] data_out;
    logic startofpacket_out, endofpacket_out, valid_out;
    logic ready_in;

    // Identity kernel
    logic signed [7:0] k11=0,k12=0,k13=0,
                       k21=0,k22=1,k23=0,
                       k31=0,k32=0,k33=0;

    // DUT
    convolution_2d_filter #(
        .WIDTH(WIDTH),
        .HEIGHT(HEIGHT)
    ) dut (
        .clk(clk),
        .reset(reset),
        .k11(k11), .k12(k12), .k13(k13),
        .k21(k21), .k22(k22), .k23(k23),
        .k31(k31), .k32(k32), .k33(k33),
        .data_in(data_in),
        .startofpacket_in(startofpacket_in),
        .endofpacket_in(endofpacket_in),
        .valid_in(valid_in),
        .ready_out(ready_out),
        .data_out(data_out),
        .startofpacket_out(startofpacket_out),
        .endofpacket_out(endofpacket_out),
        .valid_out(valid_out),
        .ready_in(ready_in)
    );

    // Clock
    always #5 clk = ~clk; 

    // Stimulus
    integer i;
    initial begin
        clk = 0;
        reset = 1;
        data_in = '0;
        startofpacket_in = 0;
        endofpacket_in   = 0;
        valid_in = 0;
        ready_in = 1;     
        repeat (4) @(posedge clk);
        reset = 0;

        // Stream 8x8 image: 1..64 (row-major)
        for (i = -1; i < WIDTH*HEIGHT; i++) begin
            @(posedge clk);
            valid_in         = 1'b1;
            data_in          = i + 1;                         // 0..64
            startofpacket_in = (i == -1);
            endofpacket_in   = (i == WIDTH*HEIGHT-1);
        end

        // stop driving
        @(posedge clk);
        valid_in = 1'b0;
        startofpacket_in = 1'b0;
        endofpacket_in   = 1'b0;

        // drain
        repeat (20) @(posedge clk);
        $finish;
    end



endmodule
