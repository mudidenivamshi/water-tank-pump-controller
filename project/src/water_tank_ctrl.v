/*
 * Smart Water Tank Pump Controller with Overflow Protection (EDUCATIONAL DESIGN)
 * Moore FSM with 3 states:  IDLE (pump off) -> FILL (pump on) -> IDLE ... , ALARM on a fault.
 *
 * Sensor convention: 1 = water has reached that probe.
 *   low_sensor      : 0 means the tank is LOW (below the low probe)
 *   full_sensor     : 1 means the tank is FULL
 *   overflow_sensor : 1 means water is above the safe limit
 *
 * Protection features:
 *   - 2-flop synchronisers on all three sensors
 *   - debounce: LOW/FULL must stay unchanged for T_DEB ticks (water ripple is ignored)
 *   - overflow is NOT debounced (fail-safe: any overflow stops the pump at once)
 *   - restart lockout: the pump cannot start again until T_REST ticks after it stopped
 *   - fault = overflow, or FULL without LOW (impossible combination) -> pump off + alarm
 * SPDX-License-Identifier: Apache-2.0
 */
`default_nettype none

module water_tank_ctrl #(
    parameter integer CLK_DIV = 10_000_000,  // clocks per tick (10 MHz -> 1 s)
    parameter integer PRE_W   = 24,          // prescaler counter width
    parameter integer T_DEB   = 3,           // sensor debounce, in ticks (1..6)
    parameter integer T_REST  = 10           // pump restart lockout, in ticks (1..14)
) (
    input  wire       clk,
    input  wire       rst_n,            // asynchronous, active low
    input  wire       low_sensor,
    input  wire       full_sensor,
    input  wire       overflow_sensor,
    output wire       pump_on,
    output wire       alarm,
    output wire       level_low,        // accepted level is LOW
    output wire       level_full,       // accepted level is FULL
    output wire       overflow_seen,    // synchronised overflow input
    output wire       restart_wait,     // pump wanted but restart lockout still running
    output wire       invalid_seen,     // FULL without LOW
    output wire [1:0] state_dbg
);
    localparam [1:0] S_IDLE = 2'd0, S_FILL = 2'd1, S_ALARM = 2'd2;
    // sized copies of the parameters (keeps comparisons the same width as the counters)
    localparam [31:0] TICK_LAST_W = CLK_DIV - 1;
    localparam [PRE_W-1:0] TICK_LAST = TICK_LAST_W[PRE_W-1:0];
    localparam [31:0] DEB_W  = T_DEB;
    localparam [31:0] REST_W = T_REST;
    localparam [2:0] DEB     = DEB_W[2:0];
    localparam [2:0] DEB_M1  = DEB - 3'd1;
    localparam [3:0] REST    = REST_W[3:0];

    // ---- 2-flop synchronisers (reset to the safe "not low, not full, no overflow") ----
    reg [1:0] sync_l, sync_f, sync_o;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin sync_l <= 2'b11; sync_f <= 2'b00; sync_o <= 2'b00; end
        else begin
            sync_l <= {sync_l[0], low_sensor};
            sync_f <= {sync_f[0], full_sensor};
            sync_o <= {sync_o[0], overflow_sensor};
        end
    end
    wire ovf = sync_o[1];

    // ---- tick generator ----
    reg [PRE_W-1:0] pre;
    wire tick = (pre == TICK_LAST);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)    pre <= {PRE_W{1'b0}};
        else if (tick) pre <= {PRE_W{1'b0}};
        else           pre <= pre + 1'b1;
    end

    // ---- debounce of {full, low}: accept a new value after it was stable for T_DEB ticks ----
    reg [1:0] last, acc;      // last sampled value, accepted value  ({full, low})
    reg [2:0] stab;           // ticks the sample has been unchanged
    wire [1:0] samp = {sync_f[1], sync_l[1]};
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin last <= 2'b01; acc <= 2'b01; stab <= 3'd0; end
        else if (tick) begin
            if (samp != last) begin last <= samp; stab <= 3'd0; end
            else begin
                if (stab == DEB_M1) acc <= last;
                if (stab != DEB)     stab <= stab + 3'd1;
            end
        end
    end
    wire acc_low  = acc[0];
    wire acc_full = acc[1];

    // ---- FSM ----
    reg [1:0] state, state_next;
    reg [3:0] rest;                                   // ticks spent in IDLE
    wire rest_done = (rest >= REST);
    wire fault     = ovf | (acc_full & ~acc_low);

    always @(*) begin
        state_next = state;
        case (state)
            S_IDLE:  if (fault)                     state_next = S_ALARM;
                     else if (!acc_low && rest_done) state_next = S_FILL;
            S_FILL:  if (fault)                     state_next = S_ALARM;
                     else if (acc_full)             state_next = S_IDLE;
            S_ALARM: if (!fault)                    state_next = S_IDLE;
            default: state_next = S_IDLE;   // illegal-state recovery (pump stays off)
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= state_next;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)                          rest <= 4'd0;
        else if (state != S_IDLE)            rest <= 4'd0;
        else if (tick && !rest_done)         rest <= rest + 4'd1;
    end

    // ---- outputs (Moore: depend on state; indicators come from registers) ----
    assign pump_on       = (state == S_FILL);
    assign alarm         = (state == S_ALARM);
    assign level_low     = ~acc_low;
    assign level_full    = acc_full;
    assign overflow_seen = ovf;
    assign restart_wait  = (state == S_IDLE) & ~acc_low & ~rest_done & ~fault;
    assign invalid_seen  = acc_full & ~acc_low;
    assign state_dbg     = state;
endmodule
