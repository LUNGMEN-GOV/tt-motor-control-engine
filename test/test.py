# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer


async def reset_dut(dut):
    dut.ena.value = 1
    dut.ui_in.value = 0x09  # CS_N=1, FAULT_N=1
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)


async def spi_byte(dut, value):
    result = 0
    for bit in range(7, -1, -1):
        ui = int(dut.ui_in.value)
        ui = (ui & ~0x04) | (((value >> bit) & 1) << 2)
        dut.ui_in.value = ui
        await Timer(500, unit="ns")
        dut.ui_in.value = int(dut.ui_in.value) | 0x02
        await Timer(300, unit="ns")
        result |= ((int(dut.uo_out.value) >> 7) & 1) << bit
        await Timer(200, unit="ns")
        dut.ui_in.value = int(dut.ui_in.value) & ~0x02
        await Timer(500, unit="ns")
    return result


async def spi_write(dut, address, data):
    dut.ui_in.value = int(dut.ui_in.value) & ~0x01
    await Timer(1, unit="us")
    await spi_byte(dut, address & 0x7F)
    await spi_byte(dut, data)
    dut.ui_in.value = int(dut.ui_in.value) | 0x01
    await Timer(1, unit="us")


async def spi_read(dut, address):
    dut.ui_in.value = int(dut.ui_in.value) & ~0x01
    await Timer(1, unit="us")
    await spi_byte(dut, 0x80 | (address & 0x7F))
    result = await spi_byte(dut, 0)
    dut.ui_in.value = int(dut.ui_in.value) | 0x01
    await Timer(1, unit="us")
    return result


async def set_encoder(dut, channel, a, b):
    ui = int(dut.ui_in.value)
    shift = 4 if channel == 0 else 6
    ui &= ~(0x3 << shift)
    ui |= ((a | (b << 1)) & 0x3) << shift
    dut.ui_in.value = ui
    await Timer(600, unit="ns")


@cocotb.test()
async def test_tiny_mce(dut):
    cocotb.start_soon(Clock(dut.clk, 100, unit="ns").start())
    await reset_dut(dut)

    assert int(dut.uio_oe.value) == 0
    assert int(dut.uo_out.value) & 0x30 == 0
    assert await spi_read(dut, 0x00) == 0xC2
    assert await spi_read(dut, 0x01) == 0x20
    assert await spi_read(dut, 0x17) == 0x23

    await spi_write(dut, 0x04, 64)
    await spi_write(dut, 0x05, 192)
    await spi_write(dut, 0x07, 3)
    await spi_write(dut, 0x08, 0x1F)
    await spi_write(dut, 0x02, 1)

    seen = [False] * 4
    for _ in range(700):
        await RisingEdge(dut.clk)
        outputs = int(dut.uo_out.value)
        assert outputs & 0x03 != 0x03
        assert outputs & 0x0C != 0x0C
        for index in range(4):
            seen[index] |= bool(outputs & (1 << index))
    assert all(seen)

    dut.ui_in.value = int(dut.ui_in.value) & ~0x08
    await Timer(1, unit="ns")
    assert int(dut.uo_out.value) & 0x0F == 0
    await ClockCycles(dut.clk, 5)
    assert int(dut.uo_out.value) & 0x30 == 0x30
    await spi_write(dut, 0x09, 1)
    assert await spi_read(dut, 0x09) & 1
    dut.ui_in.value = int(dut.ui_in.value) | 0x08
    await ClockCycles(dut.clk, 5)
    assert int(dut.uo_out.value) & 0x0F == 0
    await spi_write(dut, 0x09, 1)
    assert await spi_read(dut, 0x09) & 1 == 0

    await spi_write(dut, 0x16, 1)
    for state in ((0, 0), (1, 0), (1, 1), (0, 1), (0, 0)):
        await set_encoder(dut, 0, *state)
    enc0 = await spi_read(dut, 0x0A) | (await spi_read(dut, 0x0B) << 8)
    assert enc0 == 4

    for state in ((0, 1), (1, 1), (1, 0), (0, 0)):
        await set_encoder(dut, 0, *state)
    enc0 = await spi_read(dut, 0x0A) | (await spi_read(dut, 0x0B) << 8)
    assert enc0 == 0

    await spi_write(dut, 0x16, 1)
    await set_encoder(dut, 0, 0, 0)
    await set_encoder(dut, 0, 1, 1)
    assert await spi_read(dut, 0x14) == 1
    assert await spi_read(dut, 0x09) & 0x08

    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 4)
    dut.uio_in.value = 1
    await ClockCycles(dut.clk, 5)
    dut.uio_in.value = 0
    captured = await spi_read(dut, 0x0E) | (await spi_read(dut, 0x0F) << 8)
    assert captured != 0
    assert await spi_read(dut, 0x09) & 0x02

    dut.ena.value = 0
    await Timer(1, unit="ns")
    assert int(dut.uo_out.value) == 0
    assert int(dut.uio_oe.value) == 0
