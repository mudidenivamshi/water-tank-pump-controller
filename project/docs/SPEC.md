# Specification: Smart Water Tank Pump Controller with Overflow Protection

> Educational design. It is a digital controller only. Real probes, pump driver, isolation and electrical protection are outside this design.

## 1. Application
Overhead water tanks in homes and small buildings. A person switching the pump by hand either lets the tank overflow (wasting water and electricity) or stops too early. This chip does the decision logic automatically, with protection against noisy sensors, rapid pump restarts and impossible sensor readings.

## 2. Inputs and outputs
| Signal | Dir | Meaning |
|---|---|---|
| `clk` | in | clock (10 MHz) |
| `rst_n` | in | asynchronous, active-low reset |
| `low_sensor` | in | 0 = water below the LOW probe, 1 = at/above it |
| `full_sensor` | in | 1 = water has reached the FULL probe |
| `overflow_sensor` | in | 1 = water above the safe limit |
| `pump_on` | out | pump control (1 = ON) |
| `alarm` | out | overflow or invalid sensor combination |
| `level_low`, `level_full` | out | accepted (debounced) level indicators |
| `overflow_seen` | out | synchronised overflow input |
| `restart_wait` | out | pump wanted, restart lockout still running |
| `invalid_seen` | out | FULL without LOW |
| `state_dbg[1:0]` | out | FSM state |

## 3. Sequential logic
* 2-flop synchronisers on the three sensors (6 flops).
* 24-bit prescaler: 1 tick per 10,000,000 clocks (1 s at 10 MHz).
* Debounce: last-sample register, accepted-value register and a stability counter for `{full, low}`.
* 4-bit restart-lockout counter (counts ticks in IDLE).
* 2-bit state register, binary encoded.

## 4. FSM (Moore)
| State | Code | pump_on | alarm | Leaves when |
|---|---|---|---|---|
| IDLE | 0 (reset) | 0 | 0 | fault → ALARM; tank LOW and lockout done → FILL |
| FILL | 1 | 1 | 0 | fault → ALARM; FULL accepted → IDLE |
| ALARM | 2 | 0 | 1 | fault gone → IDLE |
| (unused) | 3 | 0 | 0 | → IDLE next clock (self-recovery) |

`fault = overflow (synchronised, not debounced) OR (FULL accepted AND NOT LOW accepted)`.

```
            tank LOW & lockout done
   IDLE ----------------------------> FILL
    ^  ^                               |  |
    |  +-------- FULL accepted --------+  |
    |                                     |
    |   fault (any time)                  | fault
    +--- fault gone --- ALARM <-----------+
                          ^---- fault from IDLE
```

## 5. Rules
| Water condition | Pump | Alarm |
|---|---|---|
| Below LOW (after lockout) | ON | OFF |
| Between LOW and FULL | keeps previous state | OFF |
| FULL | OFF | OFF |
| Overflow | OFF | ON |
| FULL without LOW (invalid) | OFF | ON |

Other properties: after reset the pump is OFF and cannot start for 10 ticks; after any stop it cannot restart for 10 ticks; the pump and alarm are never ON together; the pump is OFF within 3 clocks of an overflow.

## 6. Verification plan
Self-checking testbench T01–T15 (reset, power-on lockout, hysteresis, lockout after stop, overflow, overflow clear, invalid combination, glitch rejection, single-clock overflow glitch, reset during FILL / ALARM, illegal-state recovery, repeated cycles, closed-loop tank model, random stress) with always-on monitors; 18-bug mutation test; production-timing smoke test; cocotb wrapper tests; Verilator lint; gate-level comparison of the Yosys netlist.

## 7. Limitations
Educational controller: no dry-run or pump-fault detection, no maximum run-time timer, no independent hardware protection. Probes are assumed to give clean digital levels apart from ripple shorter than 3 ticks. A one-clock overflow glitch produces a one-clock alarm pulse (the pump is still held off through the lockout). Reset release is assumed synchronous to `clk`. Simulation covers the tested scenarios, not all input sequences (formal verification would be the next step).
