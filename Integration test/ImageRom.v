`timescale 1 ps / 1 ps

module ImageRom (
    input  wire [18:0] address,
    input  wire        clock,
    output reg  [7:0]  q
);

`ifdef SIMULATION
    // ============================================================
    // Simulation Mode: Simple behavioral ROM using $readmemh
    // ============================================================
    reg [7:0] mem [0:307199]; // 640 x 480 = 307,200 pixels

    initial begin
        $display("🧪 [SIM] Loading image_gray8_padded.hex for simulation...");
        $readmemh("image_gray8_padded.hex", mem);
    end

    always @(posedge clock) begin
        q <= mem[address];
    end

`else
    // ============================================================
    // Synthesis Mode: Quartus altsyncram ROM
    // ============================================================
    wire [7:0] sub_wire0;
    wire [7:0] q_wire = sub_wire0[7:0];

    altsyncram altsyncram_component (
        .address_a (address),
        .clock0    (clock),
        .q_a       (sub_wire0),
        .aclr0 (1'b0),
        .aclr1 (1'b0),
        .address_b (1'b1),
        .addressstall_a (1'b0),
        .addressstall_b (1'b0),
        .byteena_a (1'b1),
        .byteena_b (1'b1),
        .clock1 (1'b1),
        .clocken0 (1'b1),
        .clocken1 (1'b1),
        .clocken2 (1'b1),
        .clocken3 (1'b1),
        .data_a ({8{1'b1}}),
        .data_b (1'b1),
        .eccstatus (),
        .q_b (),
        .rden_a (1'b1),
        .rden_b (1'b1),
        .wren_a (1'b0),
        .wren_b (1'b0)
    );

    defparam
        altsyncram_component.address_aclr_a = "NONE",
        altsyncram_component.clock_enable_input_a = "BYPASS",
        altsyncram_component.clock_enable_output_a = "BYPASS",
        altsyncram_component.init_file = "image_gray8_padded.mif",
        altsyncram_component.intended_device_family = "Cyclone IV E",
        altsyncram_component.lpm_hint = "ENABLE_RUNTIME_MOD=NO",
        altsyncram_component.lpm_type = "altsyncram",
        altsyncram_component.numwords_a = 307200,
        altsyncram_component.operation_mode = "ROM",
        altsyncram_component.outdata_aclr_a = "NONE",
        altsyncram_component.outdata_reg_a = "CLOCK0",
        altsyncram_component.ram_block_type = "M9K",
        altsyncram_component.widthad_a = 19,
        altsyncram_component.width_a = 8,
        altsyncram_component.width_byteena_a = 1;

    always @(posedge clock) begin
        q <= q_wire;
    end

`endif

endmodule
