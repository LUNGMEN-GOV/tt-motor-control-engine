# Verification plan and evidence

The self-checking ModelSim testbench covers:

- reset and safe output-enable state;
- SPI mode-0 register reads and writes;
- two independent complementary PWM pairs;
- no simultaneous high/low output within either pair;
- both active phases across complete PWM periods;
- raw, asynchronous fault masking before a clock edge;
- synchronized fault latching, IRQ generation and W1C interlock;
- forward and reverse x4 quadrature decoding on channel 0;
- independent counting on channel 1;
- illegal quadrature transition detection and sticky event flags;
- 100 ns input capture and timer compare events;
- `ena=0` masking all dedicated outputs and leaving all uio pins as inputs.

Run `vsim -c -do run_modelsim.do` from `test`. The expected marker is
`TINY_MCE_TEST_PASS`.

Physical signoff is a separate acceptance gate. A release candidate is only
submission-ready after the official Tiny Tapeout GDS workflow reports a 1x1
layout, zero setup/hold violations, zero route/Magic DRC violations, LVS clean,
antenna clean, and acceptable maximum slew/fanout reports.
