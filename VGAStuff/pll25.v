`timescale 1 ps / 1 ps

module pll25 (
    input  wire areset,
    input  wire inclk0,
    output wire c0,
    output wire locked
);

`ifndef SIMULATION
    // ============================================================
    // 🧠 Synthesis / FPGA version — use actual altpll megafunction
    // ============================================================

    wire [0:0] sub_wire2 = 1'h0;
    wire [4:0] sub_wire3;
    wire       sub_wire5;
    wire       sub_wire0 = inclk0;
    wire [1:0] sub_wire1 = {sub_wire2, sub_wire0};
    wire [0:0] sub_wire4 = sub_wire3[0:0];

    assign c0     = sub_wire4;
    assign locked = sub_wire5;

    altpll altpll_component (
        .areset (areset),
        .inclk (sub_wire1),
        .clk (sub_wire3),
        .locked (sub_wire5),
        .activeclock (),
        .clkbad (),
        .clkena ({6{1'b1}}),
        .clkloss (),
        .clkswitch (1'b0),
        .configupdate (1'b0),
        .enable0 (),
        .enable1 (),
        .extclk (),
        .extclkena ({4{1'b1}}),
        .fbin (1'b1),
        .fbmimicbidir (),
        .fbout (),
        .fref (),
        .icdrclk (),
        .pfdena (1'b1),
        .phasecounterselect ({4{1'b1}}),
        .phasedone (),
        .phasestep (1'b1),
        .phaseupdown (1'b1),
        .pllena (1'b1),
        .scanaclr (1'b0),
        .scanclk (1'b0),
        .scanclkena (1'b1),
        .scandata (1'b0),
        .scandataout (),
        .scandone (),
        .scanread (1'b0),
        .scanwrite (1'b0),
        .sclkout0 (),
        .sclkout1 (),
        .vcooverrange (),
        .vcounderrange ()
    );
    defparam
        altpll_component.bandwidth_type = "AUTO",
        altpll_component.clk0_divide_by = 2000,
        altpll_component.clk0_duty_cycle = 50,
        altpll_component.clk0_multiply_by = 1007,
        altpll_component.clk0_phase_shift = "0",
        altpll_component.compensate_clock = "CLK0",
        altpll_component.inclk0_input_frequency = 20000,
        altpll_component.intended_device_family = "Cyclone IV E",
        altpll_component.lpm_hint = "CBX_MODULE_PREFIX=pll25",
        altpll_component.lpm_type = "altpll",
        altpll_component.operation_mode = "NORMAL",
        altpll_component.pll_type = "AUTO",
        altpll_component.port_clk0 = "PORT_USED",
        altpll_component.port_areset = "PORT_USED",
        altpll_component.port_inclk0 = "PORT_USED",
        altpll_component.port_locked = "PORT_USED",
        altpll_component.self_reset_on_loss_lock = "OFF",
        altpll_component.width_clock = 5;

`else
    // ============================================================
    // 🧪 Simulation version — simple divide-by-2 clock
    // ============================================================
    reg [0:0] clk_div = 0;
    reg       lock_reg = 0;

    assign c0     = clk_div;
    assign locked = lock_reg;

    always @(posedge inclk0 or posedge areset) begin
        if (areset) begin
            clk_div  <= 1'b0;
            lock_reg <= 1'b0;
        end else begin
            clk_div  <= ~clk_div;
            lock_reg <= 1'b1;  // Pretend PLL locks immediately
        end
    end

`endif

endmodule
