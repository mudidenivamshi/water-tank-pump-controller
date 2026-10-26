![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg)

# Smart Water Tank Pump Controller with Overflow Protection

RTL design, verification, synthesis and RTL-to-GDS implementation (Sky130) of a **water tank pump controller** in Verilog.

> **Educational design.** It is a digital controller only. A real pump needs isolated drivers and protection. Simulation does not prove physical correctness.

## Problem and solution

Manual pump switching wastes water and electricity or lets the tank overflow. This chip reads three level probes (LOW, FULL, OVERFLOW) and switches a pump output and an alarm output. It **ignores water ripple** (debounce), **keeps the pump state between LOW and FULL** (hysteresis), **will not restart the pump for 10 ticks after it stopped** (restart lockout), and **stops the pump and raises the alarm** on overflow or on an impossible reading (FULL without LOW).

* Sequential logic: 3-state Moore FSM (IDLE, FILL, ALARM), clock prescaler, 2-flop input synchronisers, debounce registers and counter, restart-lockout counter.
* Inputs: `clk`, `rst_n`, `low_sensor`, `full_sensor`, `overflow_sensor`. Outputs: `pump_on`, `alarm`, level / overflow / restart-wait / invalid indicators, `state_dbg[1:0]`.
* Full specification, FSM and verification plan: [`docs/SPEC.md`](docs/SPEC.md).

## Repository layout

| Path | Content |
|---|---|
| `src/water_tank_ctrl.v` | the design (RTL) |
| `src/project.v` | Tiny Tapeout pin wrapper `tt_um_water_tank_ctrl` |
| `verification/tb_water_tank_ctrl.v` | self-checking testbench (Icarus) |
| `verification/mutation_test.sh` | injects 18 deliberate bugs; testbench must fail for each |
| `verification/tb_fullsize_smoke.v` | smoke test with the real 10 MHz timing |
| `test/` | cocotb tests of the wrapper (RTL + gate level in CI) |
| `synthesis/` | Yosys scripts (generic + Sky130 mapped) and reports |
| `gls/` | gate-level simulation of the Yosys netlist vs RTL, waveform images |
| `docs/SPEC.md`, `docs/RESULTS.md` | specification; all results with sources |
| `physical_design/` | final GDS, LEF, netlist, layout picture, flow reports |
| `info.yaml`, `src/config.json` | Tiny Tapeout / LibreLane flow configuration |

## Reproduce

```bash
sudo apt install iverilog yosys verilator          # Ubuntu / WSL
make sim      # self-checking testbench  -> prints "ALL TESTS PASSED"
make lint     # Verilator -Wall
make mutate   # bug-injection check of the testbench
make synth    # Yosys: generic + Sky130-mapped reports in synthesis/
cd test && pip install -r requirements.txt && make     # cocotb tests
```

## Results (all numbers come from tool runs; details in [`docs/RESULTS.md`](docs/RESULTS.md))

| Item | Result |
|---|---|
| Self-checking testbench | 486,759 checks, 0 errors |
| Bug-injection (mutation) test | 18 / 18 detected |
| cocotb tests | 6 / 6 pass (RTL); gate-level reset test passes in the flow |
| Verilator `-Wall` lint | clean |
| Production-timing smoke test | pump starts 100,000,001 clocks (10 s @ 10 MHz) after reset |
| RTL vs gate-level netlist | 69,136 samples, 0 mismatches |
| Yosys (Sky130 HD, before placement) | 154 cells, 43 flip-flops, 1759.2 µm² |
| Chip synthesis in the flow | 180 cells, 43 flip-flops, 2258.4 µm² |
| **Final GDS** | `physical_design/tt_um_water_tank_ctrl.gds`, die 161 × 111.5 µm |
| Post-layout timing (20 ns constraint) | setup slack +9.75 ns worst corner, hold +0.105 ns, 0 violations in 9 corners |
| DRC / LVS / antenna | 0 / match / 0 |
| Tiny Tapeout precheck | 15 / 15 |

## Limitations

No dry-run or pump-fault detection, no maximum-run timer, no independent hardware protection. Probes assumed to be clean apart from ripple shorter than 3 ticks. A one-clock overflow glitch gives a one-clock alarm pulse. Simulation covers the tested scenarios, not all input sequences. Power is a tool estimate; nothing was fabricated.
