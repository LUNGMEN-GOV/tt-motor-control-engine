/*
 * Copyright (c) 2026 Jackson Haley
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_lungmen_gov_tiny_mce (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

  wire pwm0_h;
  wire pwm0_l;
  wire pwm1_h;
  wire pwm1_l;
  wire fault_latched;
  wire irq;
  wire pwm_sync;
  wire spi_miso;

  tiny_mce core (
      .clk          (clk),
      .rst_n        (rst_n),
      .enable       (ena),
      .spi_cs_n     (ui_in[0]),
      .spi_sclk     (ui_in[1]),
      .spi_mosi     (ui_in[2]),
      .fault_n      (ui_in[3]),
      .enc0_a       (ui_in[4]),
      .enc0_b       (ui_in[5]),
      .enc1_a       (ui_in[6]),
      .enc1_b       (ui_in[7]),
      .capture_in   (uio_in[0]),
      .pwm0_h       (pwm0_h),
      .pwm0_l       (pwm0_l),
      .pwm1_h       (pwm1_h),
      .pwm1_l       (pwm1_l),
      .fault_latched(fault_latched),
      .irq          (irq),
      .pwm_sync     (pwm_sync),
      .spi_miso     (spi_miso)
  );

  /* The raw fault input masks the four gate outputs without waiting for clk. */
  wire gate_outputs_safe = ena && ui_in[3];
  assign uo_out[0] = gate_outputs_safe ? pwm0_h : 1'b0;
  assign uo_out[1] = gate_outputs_safe ? pwm0_l : 1'b0;
  assign uo_out[2] = gate_outputs_safe ? pwm1_h : 1'b0;
  assign uo_out[3] = gate_outputs_safe ? pwm1_l : 1'b0;
  assign uo_out[4] = ena ? fault_latched : 1'b0;
  assign uo_out[5] = ena ? irq           : 1'b0;
  assign uo_out[6] = ena ? pwm_sync      : 1'b0;
  assign uo_out[7] = ena ? spi_miso      : 1'b0;

  assign uio_out = 8'h00;
  assign uio_oe  = 8'h00;

  wire _unused = &{uio_in[7:1], 1'b0};

endmodule

`default_nettype none
