# TinyMCE — 1x1 Tiny Tapeout motor-control engine

TinyMCE is a deterministic hardware companion for small motor-control systems.
It replaces polling and software-timed PWM with two quadrature decoders, two
complementary PWM pairs, programmable deadtime, timestamp capture, timer
compare, interrupt flags and immediate hardware fault shutdown.

Author: Jackson Haley

## Pinout

| Pin | Function | Pin | Function |
|---|---|---|---|
| ui0 | SPI_CS_N | uo0 | PWM0_H |
| ui1 | SPI_SCLK | uo1 | PWM0_L |
| ui2 | SPI_MOSI | uo2 | PWM1_H |
| ui3 | FAULT_N | uo3 | PWM1_L |
| ui4/ui5 | ENC0_A/B | uo4 | FAULT_LATCHED |
| ui6/ui7 | ENC1_A/B | uo5 | IRQ |
| uio0 | CAPTURE_IN | uo6 | PWM_SYNC |
| uio1..7 | reserved inputs | uo7 | SPI_MISO |

The PWM pins are logic signals only. They must feed a proper half-bridge gate
driver; never connect a motor or MOSFET gate directly to a Tiny Tapeout pin.
FAULT_N is active low and should be pulled low by the gate driver or protection
circuit on overcurrent, undervoltage or overtemperature.

## Nominal performance at 10 MHz

- PWM carrier: 39.0625, 19.53125, 9.765625 or 4.8828125 kHz;
- duty resolution: 8 bits;
- deadtime: 0 to 6.3 us in 100 ns steps, independent of PWM divider;
- timer/capture resolution: 100 ns, 409.6 us wrap interval;
- quadrature counters: 12-bit wraparound, x4 edge decoding;
- SPI: mode 0, maximum recommended SCLK 1 MHz;
- fault response: direct combinational output mask plus synchronized sticky
  interlock; PWM remains disabled until software clears the inactive fault.

The official 1x1 SKY130 flow is clean at 10 MHz: worst setup/hold slack is
+55.04/+0.11 ns, with zero setup/hold, routed DRC, Magic DRC, LVS and antenna
violations. See [performance and physical signoff](docs/performance.md) for the
full evidence and the limits of the estimate.

See [registers](docs/registers.md), [verification](docs/verification.md) and the
[Chinese usage guide](docs/USAGE_zh.md).

## Quick start

1. Hold FAULT_N high and reset the design.
2. Write PWM0_DUTY/PWM1_DUTY, PWM_CFG and DEADTIME through SPI.
3. Optionally enable event sources in IRQ_MASK.
4. Set CONTROL bit 0 to start both PWM pairs.
5. If FAULT_N falls, all four PWM outputs go low immediately. Diagnose the
   cause, release FAULT_N, then clear IRQ_FLAGS bit 0 with W1C. Outputs remain
   low between releasing FAULT_N and clearing the sticky flag.

## License

Apache-2.0.
