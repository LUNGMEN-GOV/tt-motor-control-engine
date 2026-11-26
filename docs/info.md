## How it works

TinyMCE is a deterministic dual-channel motor-control companion. Two x4
quadrature decoders maintain independent 16-bit position counters. Two 8-bit
PWM channels each generate a complementary high/low pair with programmable
deadtime. A 16-bit 100 ns timer supports rising-edge input capture and one
compare event. An SPI mode-0 register port configures the engine and reads all
telemetry.

FAULT_N has two paths: the raw pin masks all four PWM outputs combinationally,
while a synchronized copy sets a sticky diagnostic flag and optional IRQ. The
fault flag cannot be cleared until the external fault input is released.

## How to test

1. Drive a 10 MHz clock, hold FAULT_N and SPI_CS_N high, assert reset low for
   at least one rising edge, then release it.
2. Read register 0x00 over SPI and expect 0xC2.
3. Write duty cycles to 0x04/0x05, deadtime to 0x07, then write 0x01 to
   CONTROL (0x02). Observe complementary PWM on uo0..uo3.
4. Apply 00, 01, 11, 10, 00 to an encoder A/B pair. Its 16-bit count increases
   by four. A direct 00 to 11 jump increments the associated error register.
5. Pull FAULT_N low. All PWM pins must go low immediately and uo4 must latch
   high after synchronization. Release the fault, then W1C IRQ_FLAGS bit 0.

The repository includes both a ModelSim self-checking testbench and the
official cocotb/gate-level test path.

## External hardware

PWM outputs are logic-level control signals. Use an external gate-driver IC,
MOSFET bridge, current sensing and appropriate independent protection. Do not
connect a motor or MOSFET gate directly to a Tiny Tapeout I/O pin.

The project targets one 1x1 tile at 10 MHz. Only the official GDS workflow for
the selected shuttle can confirm physical fit and signoff.
