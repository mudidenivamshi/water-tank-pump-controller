# Results (every number comes from a tool run; sources given)

## Verification
| Item | Result | Source |
|---|---|---|
| Self-checking testbench (Icarus Verilog 12.0), T01–T15 + monitors | 486,759 checks, 0 errors | `verification/sim_log.txt` |
| Mutation test | 18 / 18 injected bugs detected | `verification/mutation_results.txt` |
| Production-timing smoke test (10 MHz, 1 tick = 1 s) | pump starts 100,000,001 clocks (10 s) after reset with the tank LOW; expected 10 ticks of restart lockout | `verification/smoke_log.txt` |
| cocotb tests, RTL (6 tests) | 6 / 6 pass | `test/` (also the `test` GitHub Action) |
| cocotb gate-level test in the flow (reset state, real timing) | 1 / 1 pass | Actions `gl_test` job, `gatelevel_test_results.zip` |
| Verilator `-Wall` lint | clean | `make lint` |
| RTL vs Yosys gate-level netlist (zero-delay generic gates) | 69,136 clock samples compared, 0 mismatches | `gls/rtl_vs_gls_log.txt` |

The testbench passing shows no failure in the tested situations. It does not prove every possible input sequence.

## Synthesis
| Item | Result | Source |
|---|---|---|
| Yosys 0.33, Sky130 HD (tt corner), standalone, before placement | 154 cells, 43 flip-flops, 0 latches, cell area 1759.2 µm² | `synthesis/stat_sky130.txt` |
| Yosys generic gates | 207 cells | `synthesis/stat_generic.txt` |
| Synthesis inside the Tiny Tapeout flow (sky130A) | 180 cells (39 `dfrtp` + 4 `dfstp` flip-flops, 15 tie cells), 2258.4 µm² | `physical_design/reports/synthesis-stats.txt` |

## Physical design (Tiny Tapeout / LibreLane flow on GitHub Actions, sky130A, 20 ns clock constraint)
| Item | Result | Source |
|---|---|---|
| Die | 161.0 × 111.52 µm | `final_metrics.json` |
| Standard-cell instances | 459 (43 sequential), plus 225 tap and 3701 fill cells | `final_metrics.json` |
| Standard-cell area / utilisation | 3180.55 µm² / 19.3 % | `final_metrics.json` |
| Nets / routed wire length | 248 / 4103 µm | `final_metrics.json` |
| Setup slack, worst of 9 corners | +9.75 ns (max_ss_100C_1v60) | `final_metrics.json` |
| Setup slack, typical (nom_tt_025C_1v80) | +13.65 ns | `final_metrics.json` |
| Hold slack, worst of 9 corners | +0.105 ns (min_ff_n40C_1v95) | `final_metrics.json` |
| Setup / hold violations | 0 / 0 in all 9 corners | `final_metrics.json` |
| Magic DRC / routing DRC | 0 / 0 | `final_metrics.json`, `magic_drc.txt` |
| LVS | circuits match uniquely | `lvs.netgen.rpt` |
| Antenna | 0 violating nets | `final_metrics.json` |
| Tiny Tapeout precheck | all 15 checks pass | `precheck_results.md` |
| Estimated power | about 264 µW (tool estimate, not measured) | `final_metrics.json` |

Notes
* The flow uses 9 timing corners (min / nominal / max parasitics × tt / ss / ff). It did not produce a 16-corner report.
* Slack is measured against a 20 ns constraint. It does not mean 50 MHz is the maximum frequency.
* The flow reports 14 disconnected pins; these are consistent with the unused inputs of the Tiny Tapeout interface (`ui_in[7:3]`, `uio_in[7:0]`, `ena`). The disconnected-pins check did not fail.
* The cloud `viewer` job (3D layout viewer) failed only because GitHub Pages was not enabled for the repository. It does not affect the layout or the checks above.
* The GDS was generated and checked; no chip was fabricated.
