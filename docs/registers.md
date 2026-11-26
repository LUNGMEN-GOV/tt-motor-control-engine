# TinyMCE register map

SPI uses mode 0, MSB first. Keep SCLK at or below 1 MHz with the nominal
10 MHz Tiny Tapeout clock. Each transaction is exactly two bytes while CS_N
is low:

- write: `{0, address[6:0]}`, then data;
- read: `{1, address[6:0]}`, then send any byte while sampling MISO.

| Address | Name | Access | Reset | Description |
|---:|---|---|---:|---|
| 0x00 | CHIP_ID | RO | 0xC2 | TinyMCE identifier |
| 0x01 | VERSION | RO | 0x20 | Version 2.0 |
| 0x02 | CONTROL | RW | 0 | bit 0 PWM enable; bit 1 compare enable; bits 2/3 invert encoder 0/1 direction |
| 0x03 | STATUS | RO | 0 | bits 4:0 event flags; bit 6 PWM enable; bit 7 synchronized FAULT_N |
| 0x04 | PWM0_DUTY | RW | 0 | Pair 0 duty, 0 to 255 |
| 0x05 | PWM1_DUTY | RW | 0 | Pair 1 duty, 0 to 255 |
| 0x06 | PWM_CFG | RW | 0 | bits 1:0 divider code: /1, /2, /4 or /8 |
| 0x07 | DEADTIME | RW | 0 | bits 5:0, deadtime in 100 ns units |
| 0x08 | IRQ_MASK | RW | 0 | enables IRQ for the corresponding event bits |
| 0x09 | IRQ_FLAGS | RO/W1C | 0 | bit 0 fault, 1 capture, 2 compare, 3 ENC0 error, 4 ENC1 error |
| 0x0A/0x0B | ENC0_LO/HI | RO | 0 | signed-wrap 12-bit quadrature count; high nibble reads zero |
| 0x0C/0x0D | ENC1_LO/HI | RO | 0 | signed-wrap 12-bit quadrature count; high nibble reads zero |
| 0x0E/0x0F | CAP_LO/HI | RO | 0 | most recent rising-edge capture timestamp |
| 0x10/0x11 | TIMER_LO/HI | RO | 0 | 12-bit, 100 ns free-running timer; high nibble reads zero |
| 0x12/0x13 | CMP_LO/HI | RW/RO | 0x00FF | low 8-bit periodic timer compare; high byte reads zero |
| 0x14 | ERR0 | RO | 0 | 1 when the ENC0 illegal-transition flag is set |
| 0x15 | ERR1 | RO | 0 | 1 when the ENC1 illegal-transition flag is set |
| 0x16 | COMMAND | WO | 0 | pulse bits: clear ENC0, clear ENC1, clear timer |
| 0x17 | BUILD | RO | 0x23 | feature bitmap for this build |

The 12-bit live counters are not snapshotted. For a coherent value, read high,
low, then high again and repeat if the two high bytes differ. Capture is stable
between capture edges and needs no such retry.

Fault flag clearing is deliberately interlocked: writing bit 0 to IRQ_FLAGS has
no effect while FAULT_N remains low. Event-set wins over clear in the same clock.
