`timescale 1ns/1ps

module brightness_filter #(
    parameter int BITS    = 8,
    parameter int MAX_BPM = 200
)(
    input  logic                            clk,
    input  logic                            reset,
    input  logic [BITS-1:0]                 pixel_in,
    input  logic                            pixel_in_valid,
    input  logic [$clog2(MAX_BPM+1)-1:0]    BPM_estimate,

    output logic [BITS-1:0]                 pixel_out,
    output logic                            pixel_out_valid,
);

    logic [BITS-1:0] brightness;

    always_comb begin
        brightness = ((BPM_estimate * 8'd255) + (MAX_BPM/2)) / MAX_BPM;
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            pixel_out          <= 8'd0;
            pixel_out_valid    <= 0;
        end 
        else begin

            if (pixel_in_valid) begin
                logic [BITS:0] sum;
                sum = pixel_in + brightness;
                if (sum > 8'd255) begin
                    pixel_out <= 8'd255;
                end
                else begin
                    pixel_out <= sum[7:0];
                    
                end
                pixel_out_valid <= 1;
            end
            else begin
                pixel_out_valid <= 0;
            end
        end
    end

endmodule
