/*
 * Smart water tank pump controller with overflow protection
 * Tiny Tapeout wrapper around water_tank_ctrl (EDUCATIONAL DESIGN)
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_water_tank_ctrl (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

`ifdef FAST_SIM
    // Short timing for RTL simulation only: 1 tick = 4 clocks
    localparam integer CLK_DIV = 4;
    localparam integer PRE_W   = 3;
`else
    // Real timing: 10 MHz clock -> 1 tick = 1 second
    localparam integer CLK_DIV = 10_000_000;
    localparam integer PRE_W   = 24;
`endif

    wire       pump_on, alarm, level_low, level_full, overflow_seen, restart_wait, invalid_seen;
    wire [1:0] state_dbg;

    water_tank_ctrl #(
        .CLK_DIV(CLK_DIV),
        .PRE_W  (PRE_W),
        .T_DEB  (3),
        .T_REST (10)
    ) u_ctrl (
        .clk            (clk),
        .rst_n          (rst_n),
        .low_sensor     (ui_in[0]),
        .full_sensor    (ui_in[1]),
        .overflow_sensor(ui_in[2]),
        .pump_on        (pump_on),
        .alarm          (alarm),
        .level_low      (level_low),
        .level_full     (level_full),
        .overflow_seen  (overflow_seen),
        .restart_wait   (restart_wait),
        .invalid_seen   (invalid_seen),
        .state_dbg      (state_dbg)
    );

    assign uo_out  = {1'b0, invalid_seen, restart_wait, overflow_seen,
                      level_full, level_low, alarm, pump_on};

    // uio[1:0] = FSM state (debug), all other bidirectional pins are inputs
    assign uio_out = {6'b000000, state_dbg};
    assign uio_oe  = 8'b0000_0011;

    // List all unused inputs to prevent warnings
    wire _unused = &{ena, ui_in[7:3], uio_in, 1'b0};

endmodule
