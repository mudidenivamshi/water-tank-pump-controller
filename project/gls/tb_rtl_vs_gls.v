`timescale 1ns/1ps
// Runs the SAME stimulus on the RTL and on the Yosys gate-level netlist (short timing) and compares
// every output at every clock. Part 1 = a scripted scenario (dumped to the VCD for the waveform images);
// part 2 = random sensor stress (compared, not dumped).
module tb_rtl_vs_gls;
    reg clk = 0, rst_n = 0, low = 1, full = 0, ovf = 0;
    wire r_pump, r_alarm, r_ll, r_lf, r_os, r_rw, r_iv; wire [1:0] r_st;
    wire g_pump, g_alarm, g_ll, g_lf, g_os, g_rw, g_iv; wire [1:0] g_st;
    water_tank_ctrl #(.CLK_DIV(4), .PRE_W(3), .T_DEB(3), .T_REST(10)) rtl (
        .clk(clk), .rst_n(rst_n), .low_sensor(low), .full_sensor(full), .overflow_sensor(ovf),
        .pump_on(r_pump), .alarm(r_alarm), .level_low(r_ll), .level_full(r_lf), .overflow_seen(r_os),
        .restart_wait(r_rw), .invalid_seen(r_iv), .state_dbg(r_st));
    water_tank_gls gls (
        .clk(clk), .rst_n(rst_n), .low_sensor(low), .full_sensor(full), .overflow_sensor(ovf),
        .pump_on(g_pump), .alarm(g_alarm), .level_low(g_ll), .level_full(g_lf), .overflow_seen(g_os),
        .restart_wait(g_rw), .invalid_seen(g_iv), .state_dbg(g_st));
    always #5 clk = ~clk;

    integer cycle = 0, checks = 0, errors = 0;
    always @(negedge clk) begin
        cycle = cycle + 1;
        checks = checks + 1;
        if ({r_pump,r_alarm,r_ll,r_lf,r_os,r_rw,r_iv,r_st} !== {g_pump,g_alarm,g_ll,g_lf,g_os,g_rw,g_iv,g_st}) begin
            errors = errors + 1;
            if (errors < 10) $display("MISMATCH clock %0d: RTL st=%0d GLS st=%0d", cycle, r_st, g_st);
        end
    end
    task cycles(input integer n); begin repeat (n) @(negedge clk); end endtask
    task sens(input l, input f, input o); begin @(negedge clk); #2; low = l; full = f; ovf = o; end endtask
    integer i;
    initial begin
        $dumpfile("gls/rtl_vs_gls.vcd"); $dumpvars(0, tb_rtl_vs_gls);
        cycles(3); rst_n = 1;                              // reset released, tank between levels
        cycles(20);
        sens(0, 0, 0); cycles(70);                         // tank LOW -> lockout -> pump ON
        sens(1, 0, 0); cycles(60);                         // water above LOW: pump keeps running
        sens(1, 1, 0); cycles(40);                         // FULL -> pump OFF
        sens(1, 0, 0); cycles(30);                         // level falls: pump stays off
        sens(0, 0, 0); cycles(70);                         // LOW again -> pump ON
        sens(1, 1, 1); cycles(30);                         // OVERFLOW -> pump OFF + alarm
        sens(1, 1, 0); cycles(20);                         // overflow gone -> alarm clears
        sens(0, 1, 0); cycles(40);                         // impossible combination -> alarm
        sens(1, 0, 0); cycles(60);
        $dumpoff;
        for (i = 0; i < 6000; i = i + 1) begin             // random stress (compared only)
            sens($random, $random, ($random % 6) == 0); cycles(1 + ({$random} % 20));
            if ({$random} % 300 == 0) begin @(negedge clk); #2 rst_n = 0; cycles(2); @(negedge clk); #2 rst_n = 1; end
        end
        $display("RTL vs GLS: %0d clock samples compared, %0d mismatches -> %0s", checks, errors, errors==0 ? "PASS" : "FAIL");
        $finish;
    end
endmodule
