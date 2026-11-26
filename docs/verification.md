# Verification plan and evidence

The self-checking ModelSim testbench covers:

- reset and safe output-enable state;
- no false fault or IRQ after reset with inactive-high `FAULT_N`;
- SPI mode-0 register reads and writes;
- two independent complementary PWM pairs;
- no simultaneous high/low output within either pair;
- both active phases across complete PWM periods;
- raw, asynchronous fault masking before a clock edge;
- synchronized fault latching, IRQ generation, sticky output masking and W1C interlock;
- forward and reverse x4 quadrature decoding on channel 0;
- independent counting on channel 1;
- illegal quadrature transition detection and sticky event flags;
- 100 ns input capture and timer compare events;
- `ena=0` masking all dedicated outputs and leaving all uio pins as inputs.

Run `vsim -c -do run_modelsim.do` from `test`. The expected marker is
`TINY_MCE_TEST_PASS`.

The official Tiny Tapeout run for commit `0ddd627` completed a 1x1 layout with
zero setup/hold, route/Magic DRC, LVS and antenna violations. The test, precheck,
gate-level test and documentation jobs also passed. Detailed metrics and the
remaining physical limitations are recorded in [performance.md](performance.md).
