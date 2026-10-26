"""Draw waveforms from gls/rtl_vs_gls.vcd (simulation output) with matplotlib. Not a GTKWave screenshot."""
import re, sys
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
vcd = open("gls/rtl_vs_gls.vcd").read().split("\n")
ids, names, cur = {}, {}, {}
scope = []
for ln in vcd:
    if ln.startswith("$scope"): scope.append(ln.split()[2])
    elif ln.startswith("$upscope"): scope.pop()
    elif ln.startswith("$var") and len(scope) == 1:
        p = ln.split(); ids.setdefault(p[3], []).append(p[4]); names[p[4]] = p[3]
    elif ln.startswith("$enddefinitions"): break
sig = {n: [] for n in names}      # name -> [(time,value)]
t = 0
body = vcd[vcd.index(next(l for l in vcd if l.startswith("$enddefinitions"))) + 1:]
for ln in body:
    if not ln or ln.startswith("$"): continue
    if ln[0] == "#": t = int(ln[1:]); continue
    if ln[0] == "b":
        v, i = ln[1:].split(); val = int(v, 2) if "x" not in v and "z" not in v else -1
    else: val, i = (int(ln[0]) if ln[0] in "01" else -1), ln[1:]
    for n in ids.get(i, []): sig[n].append((t // 1000, val))   # ns
end = max(tt for s in sig.values() for tt, _ in s)
def steps(n):
    xs, ys = [], []
    for tt, v in sig[n]: xs.append(tt); ys.append(v)
    xs.append(end); ys.append(ys[-1]); return xs, ys
def draw(prefix, title, fn):
    rows = ["clk","rst_n","low","full","ovf", prefix+"pump", prefix+"alarm", prefix+"ll", prefix+"lf",
            prefix+"os", prefix+"rw", prefix+"iv", prefix+"st"]
    label = {"low":"low_sensor (0=LOW)","full":"full_sensor","ovf":"overflow_sensor",
             "pump":"pump_on","alarm":"alarm","ll":"level_low","lf":"level_full","os":"overflow_seen",
             "rw":"restart_wait","iv":"invalid_seen","st":"state_dbg"}
    fig, ax = plt.subplots(len(rows), 1, figsize=(16, 9), sharex=True)
    for a, r in zip(ax, rows):
        x, y = steps(r); a.step(x, y, where="post", lw=1.2)
        a.set_ylabel(label.get(r.replace(prefix, ""), r), rotation=0, ha="right", va="center", fontsize=8)
        a.set_yticks([]); a.set_ylim(-0.5, 3.5 if r.endswith("st") else 1.5)
        for s_ in ("top","right"): a.spines[s_].set_visible(False)
        if r.endswith("st"):
            for i in range(len(x)-1):
                if x[i+1] > x[i] and y[i] >= 0: a.text((x[i]+x[i+1])/2, 1.5, str(y[i]), ha="center", fontsize=7)
    ax[-1].set_xlabel("time (ns)  -  short simulation timing (1 tick = 4 clocks)")
    fig.suptitle(title + "\nState codes: 0 IDLE (pump off), 1 FILL (pump on), 2 ALARM", fontsize=10)
    fig.tight_layout(); fig.savefig(fn, dpi=130); plt.close(fig)
draw("r_", "RTL simulation waveform (drawn from the Icarus Verilog VCD)", "gls/images/RTL_waveform.png")
draw("g_", "Gate-level simulation (GLS) waveform of the Yosys netlist (drawn from the VCD)", "gls/images/GLS_waveform.png")
