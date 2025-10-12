module convolution_2d_filter #(
    parameter WIDTH  = 4,
    parameter HEIGHT = 4
)(
    input  logic        clk,
    input  logic        reset,

    // Kernel 3x3
    input  logic signed [7:0] k11, k12, k13,
                              k21, k22, k23,
                              k31, k32, k33,

    // Avalon-ST Input
    input  logic [7:0]  data_in,           
    input  logic        startofpacket_in,
    input  logic        endofpacket_in,
    input  logic        valid_in,
    output logic        ready_out,

    // Avalon-ST Output
    output logic [7:0]  data_out,          
    output logic        startofpacket_out,
    output logic        endofpacket_out,
    output logic        valid_out,
    input  logic        ready_in
);

  
    // *********************3 line buffers

    logic [7:0] line0 [0:WIDTH-1];  
    logic [7:0] line1 [0:WIDTH-1];  
    logic [7:0] line2 [0:WIDTH-1];  

    // *********************Position counters
    logic [$clog2(WIDTH)-1:0]  col_count;
    logic [$clog2(HEIGHT)-1:0] row_count;

    assign ready_out = ready_in;

    // *********************tracking pixels

    integer i;
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            col_count <= '0;
            row_count <= '0;
            for (i = 0; i < WIDTH; i++) begin
                line0[i] <= '0;
                line1[i] <= '0;
                line2[i] <= '0;
            end
        end else if (valid_in && ready_out) begin
            line2[col_count] <= data_in;

            if (col_count == WIDTH-1) begin
                col_count <= '0;

               
                for (i = 0; i < WIDTH; i++) begin
                    line0[i] <= line1[i];
                    line1[i] <= line2[i];
                end

                if (row_count < HEIGHT-1)
                    row_count <= row_count + 1;
            end else begin
                col_count <= col_count + 1;
            end
        end
    end

    // *********************Piwel window

    logic [7:0] t11, t12, t13;
    logic [7:0] t21, t22, t23;
    logic [7:0] t31, t32, t33;

    wire [$clog2(WIDTH)-1:0] c   = col_count;
    wire [$clog2(WIDTH)-1:0] cm1 = col_count - 1'b1;
    wire [$clog2(WIDTH)-1:0] cm2 = col_count - 2'd2;

    always_comb begin
        t11 = '0; t12 = '0; t13 = '0;
        t21 = '0; t22 = '0; t23 = '0;
        t31 = '0; t32 = '0; t33 = '0;
        if ((row_count >= 2) && (col_count >= 2)) begin
            
            t11 = line0[cm2]; t12 = line0[cm1]; t13 = line0[c];
            t21 = line1[cm2]; t22 = line1[cm1]; t23 = line1[c];
            t31 = line2[cm2]; t32 = line2[cm1]; t33 = data_in; 
        end
    end

    // *********************Convolution

    logic signed [19:0] sum;
    always_comb begin
        sum = (k11 * $signed({1'b0,t11})) + (k12 * $signed({1'b0,t12})) + (k13 * $signed({1'b0,t13})) +
              (k21 * $signed({1'b0,t21})) + (k22 * $signed({1'b0,t22})) + (k23 * $signed({1'b0,t23})) +
              (k31 * $signed({1'b0,t31})) + (k32 * $signed({1'b0,t32})) + (k33 * $signed({1'b0,t33}));
    end


    // *********************valid ouput

    logic window_valid_raw;
    assign window_valid_raw = (row_count >= 2) && (col_count >= 2);
    logic last_center_raw; 
    assign last_center_raw = (row_count == HEIGHT-1) && (col_count == WIDTH-1);

   
    logic window_valid_q, window_valid_q_d;
    logic last_center_q;
    logic signed [19:0] sum_q;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            window_valid_q   <= 1'b0;
            window_valid_q_d <= 1'b0;
            last_center_q    <= 1'b0;
            sum_q            <= '0;
        end else begin
            if (valid_in && ready_out) begin
                window_valid_q   <= window_valid_raw;
                last_center_q    <= last_center_raw;
                sum_q            <= sum;
            end
            window_valid_q_d <= window_valid_q;
        end
    end


    // *********************Output

     always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            data_out          <= 8'd0;
            valid_out         <= 1'b0;
            startofpacket_out <= 1'b0;
            endofpacket_out   <= 1'b0;
        end else begin
            valid_out <= window_valid_q;

            if (window_valid_q) begin
                
                if (sum_q < 20'sd0)
                    data_out <= 8'd0;
                else if (sum_q > 20'sd255)
                    data_out <= 8'd255;
                else
                    data_out <= sum_q[7:0];
            end

            // SOP on rising edge of valid
            startofpacket_out <= (window_valid_q && !window_valid_q_d);

            // EOP on last center
            endofpacket_out   <= (window_valid_q && last_center_q);
        end
    end
endmodule
