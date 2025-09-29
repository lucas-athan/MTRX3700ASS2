module filter_stage (
    input  logic [7:0] pixel_in,
    input  logic       brighten_en,
    output logic [7:0] pixel_out
);

    always_comb begin
        if (brighten_en) begin
            // brighten: add 50, clamp at 255
            if (pixel_in + 8'd50 > 8'd255)
                pixel_out = 8'd255;
            else
                pixel_out = pixel_in + 8'd50;
        end else begin
            // passthrough
            pixel_out = pixel_in;
        end
    end

endmodule
