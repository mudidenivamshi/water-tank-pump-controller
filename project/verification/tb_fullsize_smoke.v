`timescale 1ns/1ps
// Smoke test with the PRODUCTION parameters (10 MHz clock, 1 tick = 1 s):
// tank LOW at power-up -> the pump must wait for the restart lockout (10 ticks = 100,000,000 clocks).
module tb_fullsize_smoke;
    reg clk = 0, rst_n = 0;
    wire pump, alarm, ll, lf, os, rw, iv; wire [1:0] st;
    water_tank_ctrl dut(.clk(clk), .rst_n(rst_n), .low_sensor(1'b0), .full_sensor(1'b0), .overflow_sensor(1'b0),
        .pump_on(pump), .alarm(alarm), .level_low(ll), .level_full(lf), .overflow_seen(os),
        .restart_wait(rw), .invalid_seen(iv), .state_dbg(st));
    always #5 clk = ~clk;
    integer n = 0;
    initial begin
        repeat (3) @(negedge clk);
        #1 rst_n = 1;
        while (!pump && n < 110000000) begin @(negedge clk); n = n + 1; end
        $display("pump started %0d clocks after reset release (expected about 100000000 = 10 s at 10 MHz)", n);
        if (n >= 99999990 && n <= 100000010 && !alarm) $display("SMOKE TEST PASSED"); else $display("SMOKE TEST FAILED");
        $finish;
    end
endmodule
