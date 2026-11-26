/*
 * TinyMCE - compact deterministic motor-control engine
 * Copyright (c) 2026 Jackson Haley
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tiny_mce (
    input  wire clk,
    input  wire rst_n,
    input  wire enable,
    input  wire spi_cs_n,
    input  wire spi_sclk,
    input  wire spi_mosi,
    input  wire fault_n,
    input  wire enc0_a,
    input  wire enc0_b,
    input  wire enc1_a,
    input  wire enc1_b,
    input  wire capture_in,
    output wire pwm0_h,
    output wire pwm0_l,
    output wire pwm1_h,
    output wire pwm1_l,
    output wire fault_latched,
    output wire irq,
    output reg  pwm_sync,
    output wire spi_miso
);

  localparam [6:0] REG_CHIP_ID   = 7'h00;
  localparam [6:0] REG_VERSION   = 7'h01;
  localparam [6:0] REG_CONTROL   = 7'h02;
  localparam [6:0] REG_STATUS    = 7'h03;
  localparam [6:0] REG_PWM0_DUTY = 7'h04;
  localparam [6:0] REG_PWM1_DUTY = 7'h05;
  localparam [6:0] REG_PWM_CFG   = 7'h06;
  localparam [6:0] REG_DEADTIME  = 7'h07;
  localparam [6:0] REG_IRQ_MASK  = 7'h08;
  localparam [6:0] REG_IRQ_FLAGS = 7'h09;
  localparam [6:0] REG_ENC0_LO   = 7'h0a;
  localparam [6:0] REG_ENC0_HI   = 7'h0b;
  localparam [6:0] REG_ENC1_LO   = 7'h0c;
  localparam [6:0] REG_ENC1_HI   = 7'h0d;
  localparam [6:0] REG_CAP_LO    = 7'h0e;
  localparam [6:0] REG_CAP_HI    = 7'h0f;
  localparam [6:0] REG_TIMER_LO  = 7'h10;
  localparam [6:0] REG_TIMER_HI  = 7'h11;
  localparam [6:0] REG_CMP_LO    = 7'h12;
  localparam [6:0] REG_CMP_HI    = 7'h13;
  localparam [6:0] REG_ERR0      = 7'h14;
  localparam [6:0] REG_ERR1      = 7'h15;
  localparam [6:0] REG_COMMAND   = 7'h16;
  localparam [6:0] REG_BUILD     = 7'h17;

  reg [7:0] control;
  reg [7:0] pwm0_duty;
  reg [7:0] pwm1_duty;
  reg [1:0] pwm_prescale;
  reg [5:0] deadtime;
  reg [4:0] irq_mask;
  reg [4:0] event_flags;
  reg [11:0] enc0_count;
  reg [11:0] enc1_count;
  reg [11:0] timer_count;
  reg [11:0] capture_value;
  reg [7:0] timer_compare;

  wire pwm_enable = control[0];
  wire compare_enable = control[1];
  wire enc0_invert = control[2];
  wire enc1_invert = control[3];

  /* Synchronizers keep all state in the main 10 MHz clock domain. */
  reg fault_meta;
  reg fault_sync;
  reg [3:0] enc_meta;
  reg [3:0] enc_sync;
  reg capture_meta;
  reg capture_sync;
  reg capture_prev;
  reg [1:0] enc0_prev;
  reg [1:0] enc1_prev;

  always @(posedge clk) begin
    if (!rst_n) begin
      fault_meta  <= 1'b0;
      fault_sync  <= 1'b0;
      enc_meta    <= 4'b0000;
      enc_sync    <= 4'b0000;
      capture_meta <= 1'b0;
      capture_sync <= 1'b0;
      capture_prev <= 1'b0;
      enc0_prev   <= 2'b00;
      enc1_prev   <= 2'b00;
    end else begin
      fault_meta  <= fault_n;
      fault_sync  <= fault_meta;
      enc_meta    <= {enc1_b, enc1_a, enc0_b, enc0_a};
      enc_sync    <= enc_meta;
      capture_meta <= capture_in;
      capture_sync <= capture_meta;
      capture_prev <= capture_sync;
      enc0_prev   <= enc_sync[1:0];
      enc1_prev   <= enc_sync[3:2];
    end
  end

  wire capture_rise = capture_sync && !capture_prev;

  /* Compact quadrature decoder: a valid edge changes exactly one input. */
  wire [1:0] enc0_delta = enc_sync[1:0] ^ enc0_prev;
  wire [1:0] enc1_delta = enc_sync[3:2] ^ enc1_prev;
  wire enc0_changed = |enc0_delta;
  wire enc1_changed = |enc1_delta;
  wire enc0_invalid = enable && &enc0_delta;
  wire enc1_invalid = enable && &enc1_delta;
  wire enc0_forward = enable && enc0_changed && !enc0_invalid &&
                      (enc0_prev[1] ^ enc_sync[0]);
  wire enc0_reverse = enable && enc0_changed && !enc0_invalid &&
                      !(enc0_prev[1] ^ enc_sync[0]);
  wire enc1_forward = enable && enc1_changed && !enc1_invalid &&
                      (enc1_prev[1] ^ enc_sync[2]);
  wire enc1_reverse = enable && enc1_changed && !enc1_invalid &&
                      !(enc1_prev[1] ^ enc_sync[2]);

  /* SPI register interface. */
  wire spi_wr_en;
  wire [6:0] spi_addr;
  wire [7:0] spi_wr_data;
  reg  [7:0] spi_rd_data;

  tiny_mce_spi spi (
      .clk      (clk),
      .rst_n    (rst_n),
      .enable   (enable),
      .cs_n     (spi_cs_n),
      .sclk     (spi_sclk),
      .mosi     (spi_mosi),
      .miso     (spi_miso),
      .wr_en    (spi_wr_en),
      .addr     (spi_addr),
      .wr_data  (spi_wr_data),
      .rd_data  (spi_rd_data)
  );

  always @* begin
    case (spi_addr)
      REG_CHIP_ID:   spi_rd_data = 8'hc2;
      REG_VERSION:   spi_rd_data = 8'h20;
      REG_CONTROL:   spi_rd_data = control;
      REG_STATUS:    spi_rd_data = {fault_sync, pwm_enable, 1'b0, event_flags};
      REG_PWM0_DUTY: spi_rd_data = pwm0_duty;
      REG_PWM1_DUTY: spi_rd_data = pwm1_duty;
      REG_PWM_CFG:   spi_rd_data = {6'b000000, pwm_prescale};
      REG_DEADTIME:  spi_rd_data = {2'b00, deadtime};
      REG_IRQ_MASK:  spi_rd_data = {3'b000, irq_mask};
      REG_IRQ_FLAGS: spi_rd_data = {3'b000, event_flags};
      REG_ENC0_LO:   spi_rd_data = enc0_count[7:0];
      REG_ENC0_HI:   spi_rd_data = {4'h0, enc0_count[11:8]};
      REG_ENC1_LO:   spi_rd_data = enc1_count[7:0];
      REG_ENC1_HI:   spi_rd_data = {4'h0, enc1_count[11:8]};
      REG_CAP_LO:    spi_rd_data = capture_value[7:0];
      REG_CAP_HI:    spi_rd_data = {4'h0, capture_value[11:8]};
      REG_TIMER_LO:  spi_rd_data = timer_count[7:0];
      REG_TIMER_HI:  spi_rd_data = {4'h0, timer_count[11:8]};
      REG_CMP_LO:    spi_rd_data = timer_compare[7:0];
      REG_CMP_HI:    spi_rd_data = 8'h00;
      REG_ERR0:      spi_rd_data = {7'b0000000, event_flags[3]};
      REG_ERR1:      spi_rd_data = {7'b0000000, event_flags[4]};
      REG_COMMAND:   spi_rd_data = 8'h00;
      REG_BUILD:     spi_rd_data = 8'b0010_0011;
      default:       spi_rd_data = 8'h00;
    endcase
  end

  wire command_write = spi_wr_en && (spi_addr == REG_COMMAND);
  wire clear_enc0 = command_write && spi_wr_data[0];
  wire clear_enc1 = command_write && spi_wr_data[1];
  wire clear_timer = command_write && spi_wr_data[2];

  always @(posedge clk) begin
    if (!rst_n) begin
      control       <= 8'h00;
      pwm0_duty     <= 8'h00;
      pwm1_duty     <= 8'h00;
      pwm_prescale  <= 2'b00;
      deadtime      <= 6'd0;
      irq_mask      <= 5'b00000;
      timer_compare <= 8'hff;
    end else if (spi_wr_en) begin
      case (spi_addr)
        REG_CONTROL:   control       <= spi_wr_data & 8'h0f;
        REG_PWM0_DUTY: pwm0_duty     <= spi_wr_data;
        REG_PWM1_DUTY: pwm1_duty     <= spi_wr_data;
        REG_PWM_CFG:   pwm_prescale  <= spi_wr_data[1:0];
        REG_DEADTIME:  deadtime      <= spi_wr_data[5:0];
        REG_IRQ_MASK:  irq_mask      <= spi_wr_data[4:0];
        REG_CMP_LO:    timer_compare <= spi_wr_data;
        default: begin end
      endcase
    end
  end

  /* Free-running timer, input capture and quadrature counters. */
  always @(posedge clk) begin
    if (!rst_n) begin
      timer_count  <= 12'h000;
      capture_value <= 12'h000;
      enc0_count   <= 12'h000;
      enc1_count   <= 12'h000;
    end else begin
      if (enable)
        timer_count <= timer_count + 1'b1;
      if (clear_timer)
        timer_count <= 12'h000;
      if (enable && capture_rise)
        capture_value <= timer_count;

      if (clear_enc0) begin
        enc0_count  <= 12'h000;
      end else if (enable && enc0_forward) begin
        enc0_count <= enc0_invert ? enc0_count - 1'b1 : enc0_count + 1'b1;
      end else if (enable && enc0_reverse) begin
        enc0_count <= enc0_invert ? enc0_count + 1'b1 : enc0_count - 1'b1;
      end

      if (clear_enc1) begin
        enc1_count  <= 12'h000;
      end else if (enable && enc1_forward) begin
        enc1_count <= enc1_invert ? enc1_count - 1'b1 : enc1_count + 1'b1;
      end else if (enable && enc1_reverse) begin
        enc1_count <= enc1_invert ? enc1_count + 1'b1 : enc1_count - 1'b1;
      end
    end
  end

  wire compare_match = enable && compare_enable && (timer_count[7:0] == timer_compare);
  wire [4:0] clear_request =
      (spi_wr_en && (spi_addr == REG_IRQ_FLAGS)) ? spi_wr_data[4:0] : 5'b00000;
  wire [4:0] clear_allowed = {clear_request[4:1], clear_request[0] && fault_sync};
  wire [4:0] event_set = enable ?
      {enc1_invalid, enc0_invalid, compare_match, capture_rise, !fault_sync} : 5'b00000;

  always @(posedge clk) begin
    if (!rst_n)
      event_flags <= 5'b00000;
    else
      event_flags <= (event_flags & ~clear_allowed) | event_set;
  end

  assign fault_latched = event_flags[0];
  assign irq = |(event_flags & irq_mask);

  /* 8-bit edge-aligned PWM with divide-by-1/2/4/8 rate selection. */
  reg [7:0] pwm_phase;
  reg [2:0] pwm_divider;
  wire [2:0] pwm_div_limit = (3'd1 << pwm_prescale) - 1'b1;
  wire pwm_tick = (pwm_divider == pwm_div_limit);

  always @(posedge clk) begin
    if (!rst_n || !enable || !pwm_enable) begin
      pwm_phase   <= 8'h00;
      pwm_divider <= 3'h0;
      pwm_sync    <= 1'b0;
    end else begin
      pwm_sync <= 1'b0;
      if (pwm_tick) begin
        pwm_divider <= 3'h0;
        pwm_phase <= pwm_phase + 1'b1;
        if (pwm_phase == 8'hff)
          pwm_sync <= 1'b1;
      end else begin
        pwm_divider <= pwm_divider + 1'b1;
      end
    end
  end

  wire desired0_high = pwm_enable && (pwm0_duty != 8'h00) && (pwm_phase < pwm0_duty);
  wire desired1_high = pwm_enable && (pwm1_duty != 8'h00) && (pwm_phase < pwm1_duty);

  reg pwm0_h_reg;
  reg pwm0_l_reg;
  reg pwm1_h_reg;
  reg pwm1_l_reg;
  reg [5:0] dead0_count;
  reg [5:0] dead1_count;

  always @(posedge clk) begin
    if (!rst_n || !enable || !pwm_enable || !fault_sync) begin
      pwm0_h_reg <= 1'b0;
      pwm0_l_reg <= 1'b0;
      dead0_count <= 6'd0;
    end else if (pwm0_h_reg) begin
      if (!desired0_high) begin
        pwm0_h_reg <= 1'b0;
        if (deadtime == 0)
          pwm0_l_reg <= 1'b1;
        else
          dead0_count <= deadtime - 1'b1;
      end
    end else if (pwm0_l_reg) begin
      if (desired0_high) begin
        pwm0_l_reg <= 1'b0;
        if (deadtime == 0)
          pwm0_h_reg <= 1'b1;
        else
          dead0_count <= deadtime - 1'b1;
      end
    end else if (dead0_count != 0) begin
      dead0_count <= dead0_count - 1'b1;
    end else if (desired0_high) begin
      pwm0_h_reg <= 1'b1;
    end else begin
      pwm0_l_reg <= 1'b1;
    end
  end

  always @(posedge clk) begin
    if (!rst_n || !enable || !pwm_enable || !fault_sync) begin
      pwm1_h_reg <= 1'b0;
      pwm1_l_reg <= 1'b0;
      dead1_count <= 6'd0;
    end else if (pwm1_h_reg) begin
      if (!desired1_high) begin
        pwm1_h_reg <= 1'b0;
        if (deadtime == 0)
          pwm1_l_reg <= 1'b1;
        else
          dead1_count <= deadtime - 1'b1;
      end
    end else if (pwm1_l_reg) begin
      if (desired1_high) begin
        pwm1_l_reg <= 1'b0;
        if (deadtime == 0)
          pwm1_h_reg <= 1'b1;
        else
          dead1_count <= deadtime - 1'b1;
      end
    end else if (dead1_count != 0) begin
      dead1_count <= dead1_count - 1'b1;
    end else if (desired1_high) begin
      pwm1_h_reg <= 1'b1;
    end else begin
      pwm1_l_reg <= 1'b1;
    end
  end

  assign pwm0_h = pwm0_h_reg;
  assign pwm0_l = pwm0_l_reg;
  assign pwm1_h = pwm1_h_reg;
  assign pwm1_l = pwm1_l_reg;

endmodule


module tiny_mce_spi (
    input  wire clk,
    input  wire rst_n,
    input  wire enable,
    input  wire cs_n,
    input  wire sclk,
    input  wire mosi,
    output reg  miso,
    output reg  wr_en,
    output reg  [6:0] addr,
    output reg  [7:0] wr_data,
    input  wire [7:0] rd_data
);

  reg cs_meta;
  reg cs_sync;
  reg sclk_meta;
  reg sclk_sync;
  reg mosi_meta;
  reg mosi_sync;
  reg sclk_prev;
  reg [3:0] bit_count;
  reg [7:0] shift_reg;
  reg command_is_read;
  reg read_pending;

  wire sclk_rise = sclk_sync && !sclk_prev;
  wire sclk_fall = !sclk_sync && sclk_prev;
  wire [7:0] received_byte = {shift_reg[6:0], mosi_sync};

  always @(posedge clk) begin
    if (!rst_n) begin
      cs_meta    <= 1'b1;
      cs_sync    <= 1'b1;
      sclk_meta  <= 1'b0;
      sclk_sync  <= 1'b0;
      mosi_meta  <= 1'b0;
      mosi_sync  <= 1'b0;
      sclk_prev  <= 1'b0;
      bit_count  <= 4'd0;
      shift_reg  <= 8'h00;
      command_is_read <= 1'b0;
      read_pending <= 1'b0;
      miso        <= 1'b0;
      wr_en       <= 1'b0;
      addr        <= 7'h00;
      wr_data     <= 8'h00;
    end else begin
      cs_meta   <= cs_n;
      cs_sync   <= cs_meta;
      sclk_meta <= sclk;
      sclk_sync <= sclk_meta;
      mosi_meta <= mosi;
      mosi_sync <= mosi_meta;
      sclk_prev <= sclk_sync;
      wr_en <= 1'b0;

      if (!enable || cs_sync) begin
        bit_count <= 4'd0;
        shift_reg <= 8'h00;
        command_is_read <= 1'b0;
        read_pending <= 1'b0;
        miso <= 1'b0;
      end else begin
        if (read_pending) begin
          shift_reg <= rd_data;
          read_pending <= 1'b0;
        end

        if (sclk_rise) begin
          if (!command_is_read || bit_count < 4'd8)
            shift_reg <= received_byte;
          if (bit_count == 4'd7) begin
            command_is_read <= received_byte[7];
            addr <= received_byte[6:0];
            if (received_byte[7])
              read_pending <= 1'b1;
          end else if (bit_count == 4'd15) begin
            if (!command_is_read) begin
              wr_data <= received_byte;
              wr_en <= 1'b1;
            end
          end
          if (bit_count != 4'd15)
            bit_count <= bit_count + 1'b1;
        end

        if (sclk_fall && command_is_read && bit_count >= 4'd8) begin
          miso <= shift_reg[7];
          shift_reg <= {shift_reg[6:0], 1'b0};
        end
      end
    end
  end

endmodule

`default_nettype none
