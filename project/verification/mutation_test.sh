#!/bin/bash
# Mutation test: inject deliberate bugs into a copy of the RTL and confirm the
# testbench FAILS for each one. A surviving mutant means a hole in the testbench.
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
run() {  # name  "exact old text"  "new text"
  python3 - "$2" "$3" "$TMP/$1.v" <<'PY'
import sys
old, new, out = sys.argv[1:4]
s = open("src/water_tank_ctrl.v").read()
open(out, "w").write(s.replace(old, new, 1))
PY
  if cmp -s $TMP/$1.v src/water_tank_ctrl.v; then echo "$1: MUTATION DID NOT APPLY"; return; fi
  iverilog -g2012 -o $TMP/$1.vvp $TMP/$1.v verification/tb_water_tank_ctrl.v 2>/dev/null
  out=$(timeout 120 vvp $TMP/$1.vvp 2>&1)
  if echo "$out" | grep -q "ALL TESTS PASSED"; then echo "$1: SURVIVED  <-- testbench hole"; else echo "$1: caught"; fi
}
run m01_no_debounce            'if (stab == DEB_M1) acc <= last;'                 'acc <= last;'
run m02_overflow_ignored       'wire ovf = sync_o[1];'                            "wire ovf = 1'b0;"
run m03_invalid_not_a_fault    'wire fault     = ovf | (acc_full & ~acc_low);'    'wire fault     = ovf;'
run m04_no_restart_lockout     'wire rest_done = (rest >= REST);'                 "wire rest_done = 1'b1;"
run m05_no_hysteresis          'else if (acc_full)             state_next = S_IDLE;' 'else if (acc_full | acc_low) state_next = S_IDLE;'
run m06_start_without_low      'else if (!acc_low && rest_done)'                  'else if (rest_done)'
run m07_fill_ignores_fault     'S_FILL:  if (fault)'                              "S_FILL:  if (1'b0)"
run m08_alarm_never_clears     'S_ALARM: if (!fault)'                             "S_ALARM: if (1'b0)"
run m09_bad_illegal_recovery   'default: state_next = S_IDLE;'                    'default: state_next = S_FILL;'
run m10_reset_state_is_fill    'if (!rst_n) state <= S_IDLE;'                     'if (!rst_n) state <= S_FILL;'
run m11_restart_lamp_wrong     '& ~acc_low & ~rest_done & ~fault;'                '& ~acc_low & ~fault;'
run m12_lockout_not_restarted  'else if (state != S_IDLE)            rest <= 4'"'"'d0;' 'else if (1'"'"'b0) rest <= 4'"'"'d0;'
run m13_debounce_not_restarted 'begin last <= samp; stab <= 3'"'"'d0; end'        'begin last <= samp; end'
run m14_pump_on_in_alarm       'assign pump_on       = (state == S_FILL);'        'assign pump_on       = (state != S_IDLE);'
run m15_tick_too_short         'wire tick = (pre == TICK_LAST);'                  "wire tick = (pre == TICK_LAST - {{(PRE_W-1){1'b0}}, 1'b1});"
run m16_full_never_stops_pump  'else if (acc_full)             state_next = S_IDLE;' "else if (1'b0)             state_next = S_IDLE;"
run m17_alarm_exit_to_fill     'S_ALARM: if (!fault)                    state_next = S_IDLE;' 'S_ALARM: if (!fault)                    state_next = S_FILL;'
run m18_alarm_in_illegal_state 'assign alarm         = (state == S_ALARM);'       "assign alarm         = (state == S_ALARM) | (state == 2'd3);"
rm -rf $TMP
