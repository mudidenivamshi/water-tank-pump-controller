`timescale 1ns/1ps
// Self-checking testbench for water_tank_ctrl (short timing: 1 tick = 4 clocks, debounce 3 ticks, lockout 10 ticks).
// Sensor convention: low_sensor=0 -> tank LOW; full_sensor=1 -> FULL; overflow_sensor=1 -> overflow.
module tb_water_tank_ctrl;
    localparam DIV = 4, DEB = 3, REST = 10;
    reg clk = 0, rst_n = 0, low = 1, full = 0, ovf = 0;
    wire pump, alarm, lvl_low, lvl_full, ovf_seen, rwait, inv; wire [1:0] st;
    water_tank_ctrl #(.CLK_DIV(DIV), .PRE_W(3), .T_DEB(DEB), .T_REST(REST)) dut (
        .clk(clk), .rst_n(rst_n), .low_sensor(low), .full_sensor(full), .overflow_sensor(ovf),
        .pump_on(pump), .alarm(alarm), .level_low(lvl_low), .level_full(lvl_full),
        .overflow_seen(ovf_seen), .restart_wait(rwait), .invalid_seen(inv), .state_dbg(st));
    always #5 clk = ~clk;

    integer checks = 0, errors = 0, cyc = 0;
    reg forcing = 0;
    task check(input cond, input [255:0] what);
        begin checks = checks + 1;
              if (!cond) begin errors = errors + 1; if (errors < 20) $display("FAIL @%0t clk %0d: %0s", $time, cyc, what); end end
    endtask
    task cycles(input integer n); begin repeat (n) @(negedge clk); end endtask
    task ticks(input integer n);  begin cycles(n*DIV); end endtask
    task sens(input l, input f, input o); begin @(negedge clk); #2; low = l; full = f; ovf = o; end endtask
    task do_reset; begin @(negedge clk); #2 rst_n = 0; cycles(3); @(negedge clk); #2 rst_n = 1; end endtask
    // wait until a condition becomes true, at most n clocks; returns clocks waited in 'waited'
    integer waited;
    task wait_pump(input want, input integer n);
        begin waited = 0; while ((pump !== want) && waited < n) begin @(negedge clk); waited = waited + 1; end end
    endtask

    // ------------------------------------------------------------------ monitors (run all the time)
    integer ovf_hold = 0, since_stop = 0; reg pump_q = 0, rwait_q = 0;
    always @(negedge clk) begin
        cyc = cyc + 1;
        if (rst_n) begin
            checks = checks + 5;
            if (pump && alarm)                         begin errors = errors + 1; $display("MON FAIL: pump and alarm together @%0t", $time); end
            if (^{pump, alarm, st} === 1'bx)           begin errors = errors + 1; $display("MON FAIL: X on outputs @%0t", $time); end
            if (!forcing && st == 2'd3)                begin errors = errors + 1; $display("MON FAIL: illegal state @%0t", $time); end
            ovf_hold = ovf ? ovf_hold + 1 : 0;
            if (ovf_hold >= 3 && (pump || !alarm))     begin errors = errors + 1; $display("MON FAIL: overflow not handled @%0t", $time); end
            if (pump && !pump_q && since_stop < (REST-1)*DIV) begin errors = errors + 1; $display("MON FAIL: pump restarted after only %0d clocks @%0t", since_stop, $time); end
            since_stop = pump ? 0 : since_stop + 1;
            if (rwait_q && pump) begin errors = errors + 1; $display("MON FAIL: restart-wait lamp on just before pump start @%0t", $time); end
            rwait_q = rwait;
            pump_q = pump;
        end else begin ovf_hold = 0; since_stop = 0; pump_q = 0; rwait_q = 0; end
    end

    // ------------------------------------------------------------------ closed-loop tank model (used by T14)
    integer level = 50, model_on = 0, max_level = 0, min_level = 100, rises = 0; reg pump_prev = 0;
    always @(negedge clk) if (model_on) begin
        if (pump && (cyc % 8 == 0) && level < 120)  level = level + 1;     // pump adds water
        if (!pump || 1) if (cyc % 20 == 0 && level > 0) level = level - 1; // household use
        if (level > max_level) max_level = level;
        if (level < min_level) min_level = level;
        if (pump && !pump_prev) rises = rises + 1;
        pump_prev = pump;
        #2; low = (level >= 20); full = (level >= 90); ovf = (level >= 100);
    end

    integer i, t0, n_rise, seen;
    initial begin
        $dumpfile("sim/water_tank.vcd"); $dumpvars(0, tb_water_tank_ctrl);
        // ---- T01 reset values (asynchronous: checked while reset is held)
        cycles(2); check(pump === 0 && alarm === 0 && st === 2'd0, "T01 reset values");
        cycles(3); @(negedge clk); #2 rst_n = 1;
        cycles(2); check(pump === 0 && alarm === 0 && st === 2'd0, "T01 after release, tank OK");
        check(lvl_low === 0 && lvl_full === 0, "T01 indicators");
        ticks(15); check(pump === 0 && alarm === 0, "T01 idle stays off with tank between LOW and FULL");

        // ---- T02 power-on lockout: tank LOW at start -> pump must wait for the restart lockout
        do_reset; sens(0, 0, 0);
        ticks(6); check(rwait === 1 && pump === 0 && lvl_low === 1, "T02 restart-wait lamp on during lockout");
        wait_pump(1, 200); waited = waited + 6*DIV;
        check(waited >= (REST-1)*DIV && waited <= (REST+2)*DIV, "T02 lockout length after reset");
        check(rwait === 0 && pump === 1, "T02 pump on after lockout");

        // ---- T03 hysteresis: water rises above LOW, pump keeps running; FULL stops it
        sens(1, 0, 0); ticks(30);
        check(pump === 1 && alarm === 0, "T03 pump holds between LOW and FULL");
        sens(1, 1, 0);
        t0 = cyc; wait_pump(0, 100);
        check(waited >= DEB*DIV && waited <= (DEB+3)*DIV, "T03 pump off after debounce at FULL");
        check(alarm === 0, "T03 no alarm at FULL");

        // ---- T04 level falls from FULL: pump stays off (hysteresis)
        sens(1, 0, 0); ticks(40);
        check(pump === 0 && alarm === 0, "T04 stays off between FULL and LOW");

        // ---- T05 restart lockout after a stop: demand again right after the pump stopped
        sens(0, 0, 0); ticks(2);                       // tank LOW again, pump may start after debounce+lockout
        wait_pump(1, 200);
        check(pump === 1, "T05 pump restarts for low tank");
        sens(1, 1, 0); wait_pump(0, 100); check(pump === 0, "T05 pump stopped at full");
        t0 = cyc; sens(0, 0, 0);                       // immediately low again
        wait_pump(1, 200);
        check((cyc - t0) >= (REST-1)*DIV, "T05 no restart inside lockout window");
        check(pump === 1, "T05 restart after lockout");

        // ---- T06 overflow while filling: pump off and alarm within 3 clocks
        sens(1, 1, 1); cycles(3);
        check(pump === 0 && alarm === 1, "T06 overflow -> pump off + alarm");
        cycles(40); check(pump === 0 && alarm === 1, "T06 alarm holds while overflow persists");

        // ---- T07 overflow clears: alarm clears, pump stays off through lockout
        sens(1, 1, 0); cycles(4);
        check(alarm === 0 && pump === 0, "T07 alarm cleared after overflow gone");
        ticks(3);
        sens(1, 0, 0); ticks(20); check(pump === 0, "T07 pump off while tank between levels");

        // ---- T08 invalid sensor combination (FULL without LOW)
        sens(0, 1, 0); ticks(2);
        check(alarm === 0, "T08 invalid combo is debounced (not immediate)");
        ticks(DEB + 3);
        check(alarm === 1 && pump === 0 && inv === 1, "T08 invalid combination -> alarm");
        sens(1, 1, 0); ticks(DEB + 3);
        check(alarm === 0, "T08 alarm clears when combination valid again");
        sens(1, 0, 0); ticks(25);

        // ---- T09 glitch rejection while filling and idle
        sens(0, 0, 0); wait_pump(1, 200); sens(1, 0, 0); ticks(5);
        sens(1, 1, 0); ticks(3); sens(1, 0, 0); ticks(10);
        check(pump === 1 && alarm === 0, "T09 3-tick FULL glitch ignored");
        sens(1, 1, 0); ticks(DEB + 4);
        check(pump === 0, "T09 longer FULL really stops the pump");
        sens(1, 0, 0); ticks(25);
        sens(0, 0, 0); ticks(3); sens(1, 0, 0); ticks(20);
        check(pump === 0, "T09 3-tick LOW glitch does not start the pump");

        // ---- T10 one-clock overflow glitch is treated as a fault (fail-safe) and recovers
        sens(0, 0, 0); wait_pump(1, 200); sens(1, 0, 0); ticks(3);
        sens(1, 0, 1); sens(1, 0, 0);
        seen = 0; for (i = 0; i < 8; i = i + 1) begin @(negedge clk); if (alarm) seen = seen + 1; if (i >= 3) check(pump === 0, "T10 pump off after glitch"); end
        check(seen >= 1, "T10 overflow glitch -> alarm pulse (fail-safe)");
        check(alarm === 0 && pump === 0, "T10 alarm gone, pump off");
        ticks(REST+3);
        sens(0, 0, 0); ticks(DEB+2); wait_pump(1, 200); check(pump === 1, "T10 normal operation resumes");

        // ---- T11 reset during FILL and during ALARM
        @(negedge clk); #2 rst_n = 0; #1;
        check(pump === 0 && alarm === 0 && st === 2'd0, "T11 async reset during FILL");
        cycles(2); @(negedge clk); #2 rst_n = 1;
        sens(1, 1, 1); cycles(5); check(alarm === 1, "T11 alarm set");
        @(negedge clk); #2 rst_n = 0; #1; check(alarm === 0 && st === 2'd0, "T11 async reset during ALARM");
        cycles(2); @(negedge clk); #2 rst_n = 1; sens(1, 0, 0); ticks(3);

        // ---- T12 illegal state recovery
        sens(1, 0, 0); ticks(2);
        forcing = 1; force dut.state = 2'd3; cycles(2);
        check(pump === 0 && alarm === 0, "T12 illegal state: pump stays off");
        release dut.state; cycles(2); forcing = 0;
        check(st === 2'd0 && pump === 0, "T12 recovers to IDLE");

        // ---- T13 repeated fill cycles with scripted sensors
        do_reset; sens(1, 0, 0); ticks(2); n_rise = 0;
        for (i = 0; i < 6; i = i + 1) begin
            sens(0, 0, 0); wait_pump(1, 300); check(pump === 1, "T13 cycle fill starts");
            ticks(6); sens(1, 0, 0); ticks(6); sens(1, 1, 0); wait_pump(0, 100); check(pump === 0, "T13 cycle fill stops");
            ticks(3); sens(1, 0, 0); ticks(3);
        end

        // ---- T14 closed-loop tank model: level must stay between probes, never overflow
        do_reset; level = 50; max_level = 50; min_level = 50; rises = 0; model_on = 1;
        cycles(40000); model_on = 0;
        check(max_level < 100, "T14 tank never reaches overflow");
        check(min_level > 0,  "T14 tank never runs completely dry");
        check(rises >= 5, "T14 pump cycled several times");
        check(alarm === 0, "T14 no alarm in normal use");
        $display("      closed-loop tank: level stayed between %0d and %0d, pump started %0d times", min_level, max_level, rises);

        // ---- T15 random sensor stress: only the monitors judge (no overlap, no X, overflow handled, lockout kept)
        do_reset;
        for (i = 0; i < 4000; i = i + 1) begin
            sens($random, $random, ($random % 8) == 0); cycles(1 + ({$random} % 25));
            if ({$random} % 400 == 0) begin @(negedge clk); #2 rst_n = 0; cycles(2); @(negedge clk); #2 rst_n = 1; end
        end

        if (errors == 0) $display("ALL TESTS PASSED (%0d checks, 0 errors)", checks);
        else             $display("TESTS FAILED (%0d errors in %0d checks)", errors, checks);
        $finish;
    end
    initial begin #50_000_000; $display("TIMEOUT"); $finish; end
endmodule
