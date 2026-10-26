# Gate-level simulation (GLS): RTL vs synthesised netlist

- `synth_short.ys`: synthesises the same RTL with the short simulation timing (1 tick = 4 clocks) using Yosys' generic gates (87 cells).
- `water_tank_short_netlist.v` / `water_tank_gls.v`: the resulting gate-level netlist (module renamed `water_tank_gls`).
- `tb_rtl_vs_gls.v`: runs the same stimulus on RTL and netlist and compares every output at every clock. Part 1 is a scripted scenario (fill, hold, full, overflow, invalid sensors); part 2 is 6000 random sensor changes with random resets.
- `rtl_vs_gls_log.txt`: result. 69,136 clock samples compared, 0 mismatches.
- `make_waveforms.py` draws `images/RTL_waveform.png` and `images/GLS_waveform.png` from the simulation VCD (matplotlib, not GTKWave).

The comparison was also run against a deliberately broken RTL (overflow input forced to 0) and reported thousands of mismatches, so it is able to fail.

Limits: this GLS uses Yosys generic gates with zero delay, not the Sky130 cells with timing. It shows the synthesis step preserved the behaviour for this stimulus only.
Run: `yosys -q gls/synth_short.ys && sed 's/^module water_tank_ctrl(/module water_tank_gls(/' gls/water_tank_short_netlist.v > gls/water_tank_gls.v && iverilog -g2012 -o gls/rg.vvp gls/tb_rtl_vs_gls.v src/water_tank_ctrl.v gls/water_tank_gls.v && vvp gls/rg.vvp`
