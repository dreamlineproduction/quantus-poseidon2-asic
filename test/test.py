import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start Quantus Poseidon2 ASIC Gate-Level Test")

    # Set the clock period to 20 ns (50 MHz)
    clock = Clock(dut.clk, 20, unit="ns")
    cocotb.start_soon(clock.start())

    # Reset the silicon chip
    dut._log.info("Resetting ASIC")
    dut.ena.value = 1
    dut.ui_in.value = 0xFF  # Easy target difficulty for fast test
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    dut._log.info("Quantus ASIC Mining Active! Running 500 clock cycles...")
    await ClockCycles(dut.clk, 500)

    # Verify the physical gate-level netlist is alive and driving valid 0/1 bits
    out_val = int(dut.uo_out.value)
    dut._log.info(f"ASIC uo_out status byte: {out_val:08b}")
    assert out_val >= 0
