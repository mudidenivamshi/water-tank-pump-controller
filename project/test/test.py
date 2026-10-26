# SPDX-License-Identifier: Apache-2.0
# cocotb tests for tt_um_water_tank_ctrl
#   RTL run  : short timing (FAST_SIM, 1 tick = 4 clocks) -> full behavioural tests
#   GL run   : (GATES=yes) real timing -> only the reset/start-up state is checked,
#              because full-size phases last millions of clock cycles.
# ui_in : bit0 low_sensor (0 = LOW), bit1 full_sensor (1 = FULL), bit2 overflow_sensor
# uo_out: bit0 pump_on, 1 alarm, 2 level_low, 3 level_full, 4 overflow_seen, 5 restart_wait, 6 invalid_seen
# uio_out[1:0] = state_dbg: 0 IDLE, 1 FILL, 2 ALARM

import os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

GL = os.environ.get("GATES") == "yes"
DIV = 4
DEB, REST = 3, 10
PUMP, ALARM, LLOW, LFULL, OVF, RWAIT, INV = (1 << i for i in range(7))
IDLE, FILL, ALARMED = range(3)
LOW_OK, FULL, OVERFLOW = 0b001, 0b010, 0b100      # ui_in bits; bit0 = 1 means water above LOW probe


def state(dut):
    return int(dut.uio_out.value) & 3


def outs(dut):
    return int(dut.uo_out.value)


async def reset(dut):
    cocotb.start_soon(Clock(dut.clk, 100, unit="ns").start())
    dut.ena.value = 1
    dut.ui_in.value = LOW_OK        # tank between LOW and FULL
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1


async def wait_pump(dut, want, max_cycles):
    n = 0
    while bool(outs(dut) & PUMP) != want and n < max_cycles:
        await ClockCycles(dut.clk, 1)
        n += 1
    assert bool(outs(dut) & PUMP) == want, f"pump never became {want}"
    return n


@cocotb.test()
async def test_reset_state(dut):
    """After reset the pump and alarm are off and the FSM is in IDLE."""
    await reset(dut)
    await ClockCycles(dut.clk, 3)
    assert not (outs(dut) & (PUMP | ALARM)), f"reset outputs {outs(dut):#04x}"
    assert state(dut) == IDLE
    assert int(dut.uio_oe.value) == 0x03


if not GL:

    @cocotb.test()
    async def test_fill_hold_and_stop(dut):
        await reset(dut)
        dut.ui_in.value = 0                                   # tank LOW
        n = await wait_pump(dut, True, 20 * DIV)
        assert n >= (REST - 1) * DIV, f"restart lockout too short ({n} clocks)"
        dut.ui_in.value = LOW_OK                              # water above LOW: pump keeps running
        await ClockCycles(dut.clk, 30 * DIV)
        assert outs(dut) & PUMP and not (outs(dut) & ALARM)
        dut.ui_in.value = LOW_OK | FULL                       # tank FULL
        await wait_pump(dut, False, 10 * DIV)
        dut.ui_in.value = LOW_OK                              # level falls: pump must stay off
        await ClockCycles(dut.clk, 40 * DIV)
        assert not (outs(dut) & PUMP)

    @cocotb.test()
    async def test_overflow_alarm(dut):
        await reset(dut)
        dut.ui_in.value = 0
        await wait_pump(dut, True, 20 * DIV)
        dut.ui_in.value = LOW_OK | FULL | OVERFLOW
        await ClockCycles(dut.clk, 4)
        assert not (outs(dut) & PUMP) and (outs(dut) & ALARM), "overflow must stop the pump and raise the alarm"
        assert state(dut) == ALARMED
        dut.ui_in.value = LOW_OK | FULL                       # overflow gone
        await ClockCycles(dut.clk, 5)
        assert not (outs(dut) & ALARM) and not (outs(dut) & PUMP)

    @cocotb.test()
    async def test_invalid_combination(dut):
        """FULL without LOW is impossible water physics: pump off + alarm after debounce."""
        await reset(dut)
        dut.ui_in.value = FULL                                # low probe dry but full probe wet
        await ClockCycles(dut.clk, 2 * DIV)
        assert not (outs(dut) & ALARM), "invalid combination must be debounced"
        await ClockCycles(dut.clk, (DEB + 3) * DIV)
        assert (outs(dut) & ALARM) and (outs(dut) & INV) and not (outs(dut) & PUMP)
        dut.ui_in.value = LOW_OK | FULL
        await ClockCycles(dut.clk, (DEB + 3) * DIV)
        assert not (outs(dut) & ALARM)

    @cocotb.test()
    async def test_glitch_is_ignored(dut):
        await reset(dut)
        dut.ui_in.value = 0
        await wait_pump(dut, True, 20 * DIV)
        dut.ui_in.value = LOW_OK
        await ClockCycles(dut.clk, 5 * DIV)
        dut.ui_in.value = LOW_OK | FULL                       # 3-tick FULL glitch
        await ClockCycles(dut.clk, DEB * DIV)
        dut.ui_in.value = LOW_OK
        await ClockCycles(dut.clk, 10 * DIV)
        assert outs(dut) & PUMP, "short FULL glitch must not stop the pump"

    @cocotb.test()
    async def test_reset_mid_fill(dut):
        await reset(dut)
        dut.ui_in.value = 0
        await wait_pump(dut, True, 20 * DIV)
        dut.rst_n.value = 0
        await ClockCycles(dut.clk, 2)
        assert not (outs(dut) & (PUMP | ALARM)), "reset must switch the pump off"
        dut.rst_n.value = 1
        await ClockCycles(dut.clk, 5 * DIV)
        assert not (outs(dut) & PUMP), "restart lockout must apply after reset"
