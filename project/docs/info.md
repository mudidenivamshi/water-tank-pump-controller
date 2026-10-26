<!---
Datasheet text for Tiny Tapeout.
-->

## How it works

A smart water tank pump controller with overflow protection (educational design). Three water probes feed a small finite state machine (IDLE, FILL, ALARM) that switches a pump output and an alarm output. A prescaler divides the 10 MHz clock to a 1 s tick.

* Sensors: `ui[0]` low probe (0 = tank LOW), `ui[1]` full probe (1 = FULL), `ui[2]` overflow probe (1 = overflow). All three are synchronised.
* LOW and FULL are **debounced**: a new level is accepted only after it stays unchanged for 3 ticks, so water ripple does not toggle the pump. Overflow is not debounced: any overflow stops the pump at once.
* Tank LOW → the pump starts, but only after a **restart lockout** of 10 ticks since it last stopped (also applies after reset).
* Between LOW and FULL the pump keeps its previous state (hysteresis). FULL stops the pump.
* Overflow, or FULL without LOW (impossible water physics), → pump OFF and alarm ON. The alarm clears when the fault is gone.

Output pins: `uo[0]` pump_on, `uo[1]` alarm, `uo[2]` level_low, `uo[3]` level_full, `uo[4]` overflow_seen, `uo[5]` restart_wait, `uo[6]` invalid_seen. `uio[1:0]` is the FSM state (debug output): 0 IDLE, 1 FILL, 2 ALARM.

Full specification: `docs/SPEC.md`.

## How to test

Drive a 10 MHz clock, pulse `rst_n` low, then:
1. Keep `ui[0]` = 1, `ui[1]` = 0 (tank between levels): the pump stays off.
2. Set `ui[0]` = 0 (tank LOW): after about 10 s `uo[0]` (pump_on) goes high.
3. Set `ui[0]` = 1: the pump keeps running. Set `ui[1]` = 1 (FULL): after about 3 s the pump turns off.
4. Set `ui[2]` = 1 (overflow): the pump is off and `uo[1]` (alarm) is high within a few clocks.

Simulation (short timing): `make sim` in the repository root, and `cd test && make` for the cocotb tests.

## External hardware

None required for the chip itself. LEDs on `uo[6:0]` show the signals; switches on `ui[2:0]` stand in for the probes. A real pump needs an isolated driver and protection outside this chip.
