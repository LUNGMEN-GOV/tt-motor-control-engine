# Performance and physical signoff

## ASIC target at 10 MHz

The following values were produced by the official Tiny Tapeout SKY130 GDS run
for RTL commit `0ddd627fdfcb5d5911252537a33f260d6bf21c0a`:

| Item | Result |
|---|---:|
| Tiny Tapeout size | 1x1 tile |
| Die template | 161 x 111.52 um |
| Synthesized standard-cell area | 10,217.299 um2 |
| Final instance utilization | 82.38% |
| Worst setup slack | +54.33 ns |
| Worst hold slack | +0.112 ns |
| Setup / hold violations | 0 / 0 |
| Routed DRC / Magic DRC | 0 / 0 |
| LVS / antenna violations | 0 / 0 |
| Routed wire length / vias | 41,623 um / 9,767 |

The official GDS, precheck, gate-level simulation and documentation jobs all
passed. Final utilization is deliberately high to retain the useful feature set
inside one tile, so the tapeout RTL should now be treated as frozen unless the
full physical flow is repeated.

The OpenLane report still records non-fatal maximum-slew warnings (worst count
209 at the slow 100 C / 1.60 V corner), one maximum-fanout warning and one
maximum-capacitance warning. They did not fail the official Tiny Tapeout
acceptance workflow, but they mean this is a Tiny Tapeout submission-ready
block rather than an independently qualified production ASIC. Silicon
characterization remains required.

The +54.33 ns setup margin on a 100 ns clock implies an approximate critical
path of 45.67 ns, or about 21.9 MHz. This is a timing-margin estimate, not a new
qualified operating point: the supported tapeout target remains 10 MHz.

## Functional throughput

At the supported 10 MHz clock:

- PWM carrier is 39.0625, 19.53125, 9.765625 or 4.8828125 kHz.
- PWM duty resolution is 8 bits (256 steps).
- Deadtime is programmable from 0 to 6.3 us in 100 ns steps.
- Timer/capture resolution is 100 ns and the 12-bit timer wraps in 409.6 us.
- SPI mode 0 is conservatively specified to 1 MHz.
- Each quadrature channel performs x4 decoding into a 12-bit wraparound count.

For asynchronous encoder inputs, use at least 500 ns between valid state
transitions as a conservative system-level limit (2 million transitions/s).
That corresponds to about 29,297 rpm for a 1,024-PPR encoder, or 14,648 rpm for
a 2,048-PPR encoder, when PPR is specified per channel before x4 decoding.
Signal integrity, encoder output bandwidth and cabling will normally set a lower
practical limit.

`FAULT_N` has a direct combinational mask to all four gate-control outputs, so
shutdown does not wait for a clock edge. The sticky status and IRQ pass through
synchronizers and therefore appear after approximately two to three 10 MHz
cycles, then continue masking the outputs until software clears the inactive
fault. The physical pad-to-output fault delay is not characterized by this
digital flow and must be measured on silicon.

## What the design does not drive

TinyMCE is a digital timing and protection engine, not a power stage. Its output
current, motor voltage and motor power are determined entirely by the external
gate driver, MOSFET bridge, current sensing, supply, thermal design and PCB. The
four PWM pins must never drive a motor or power MOSFET gate directly.
