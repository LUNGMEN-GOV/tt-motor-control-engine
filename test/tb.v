`timescale 1ns/1ps
`default_nettype none

module tb;
  reg clk = 1'b0;
  reg rst_n = 1'b0;
  reg ena = 1'b1;
  reg [7:0] ui_in = 8'b0000_1001;  // FAULT_N=1, SPI_CS_N=1
  reg [7:0] uio_in = 8'h00;
  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;

  integer failures = 0;
  integer high0_seen;
  integer low0_seen;
  integer high1_seen;
  integer low1_seen;
  integer i;
  reg [7:0] value;
  reg [7:0] value_hi;

  always #50 clk = ~clk;  // 10 MHz

  tt_um_lungmen_gov_tiny_mce dut (
      .ui_in(ui_in),
      .uo_out(uo_out),
      .uio_in(uio_in),
      .uio_out(uio_out),
      .uio_oe(uio_oe),
      .ena(ena),
      .clk(clk),
      .rst_n(rst_n)
  );

  task check;
    input condition;
    input [8*80-1:0] message;
    begin
      if (!condition) begin
        failures = failures + 1;
        $display("FAIL: %0s at %0t", message, $time);
      end
    end
  endtask

  task spi_begin;
    begin
      ui_in[1] = 1'b0;
      ui_in[0] = 1'b0;
      #1000;
    end
  endtask

  task spi_end;
    begin
      ui_in[0] = 1'b1;
      ui_in[1] = 1'b0;
      ui_in[2] = 1'b0;
      #1000;
    end
  endtask

  task spi_byte;
    input [7:0] tx;
    output [7:0] rx;
    integer bit_index;
    begin
      rx = 8'h00;
      for (bit_index = 7; bit_index >= 0; bit_index = bit_index - 1) begin
        ui_in[2] = tx[bit_index];
        #500;
        ui_in[1] = 1'b1;
        #300;
        rx[bit_index] = uo_out[7];
        #200;
        ui_in[1] = 1'b0;
        #500;
      end
    end
  endtask

  task spi_write;
    input [6:0] address;
    input [7:0] data;
    reg [7:0] ignored;
    begin
      spi_begin;
      spi_byte({1'b0, address}, ignored);
      spi_byte(data, ignored);
      spi_end;
    end
  endtask

  task spi_read;
    input [6:0] address;
    output [7:0] data;
    reg [7:0] ignored;
    begin
      spi_begin;
      spi_byte({1'b1, address}, ignored);
      spi_byte(8'h00, data);
      spi_end;
    end
  endtask

  task enc0_state;
    input a;
    input b;
    begin
      ui_in[4] = a;
      ui_in[5] = b;
      #600;
    end
  endtask

  task enc1_state;
    input a;
    input b;
    begin
      ui_in[6] = a;
      ui_in[7] = b;
      #600;
    end
  endtask

  initial begin
    $dumpfile("tiny_mce.vcd");
    $dumpvars(0, tb);

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (5) @(posedge clk);

    check(uo_out[3:0] == 4'b0000, "gate outputs are safe after reset");
    check(uio_oe == 8'h00, "all bidirectional pins remain inputs");

    spi_read(7'h00, value);
    check(value == 8'hc2, "CHIP_ID read through SPI");
    spi_read(7'h01, value);
    check(value == 8'h20, "VERSION read through SPI");
    spi_read(7'h17, value);
    check(value == 8'h23, "BUILD feature bitmap");

    /* Configure two complementary PWM pairs and exercise one complete period. */
    spi_write(7'h04, 8'd64);
    spi_write(7'h05, 8'd192);
    spi_write(7'h06, 8'd0);
    spi_write(7'h07, 8'd3);
    spi_write(7'h08, 8'h1f);
    spi_write(7'h02, 8'h01);

    high0_seen = 0;
    low0_seen = 0;
    high1_seen = 0;
    low1_seen = 0;
    for (i = 0; i < 700; i = i + 1) begin
      @(posedge clk);
      check(!(uo_out[0] && uo_out[1]), "PWM0 complementary outputs never overlap");
      check(!(uo_out[2] && uo_out[3]), "PWM1 complementary outputs never overlap");
      if (uo_out[0]) high0_seen = high0_seen + 1;
      if (uo_out[1]) low0_seen = low0_seen + 1;
      if (uo_out[2]) high1_seen = high1_seen + 1;
      if (uo_out[3]) low1_seen = low1_seen + 1;
    end
    check(high0_seen > 100 && low0_seen > 100, "PWM0 generates both phases");
    check(high1_seen > 100 && low1_seen > 100, "PWM1 generates both phases");

    /* The raw fault input must suppress all four gates before the next clk. */
    #17;
    ui_in[3] = 1'b0;
    #1;
    check(uo_out[3:0] == 4'b0000, "asynchronous fault shutdown");
    repeat (5) @(posedge clk);
    check(uo_out[4] == 1'b1, "fault event latches");
    check(uo_out[5] == 1'b1, "fault event drives IRQ when unmasked");

    spi_write(7'h09, 8'h01);
    spi_read(7'h09, value);
    check(value[0] == 1'b1, "active fault cannot be cleared");
    ui_in[3] = 1'b1;
    repeat (5) @(posedge clk);
    spi_write(7'h09, 8'h01);
    spi_read(7'h09, value);
    check(value[0] == 1'b0, "inactive fault clears with W1C");

    /* Quadrature channel 0 forward x4, then reverse x4. */
    spi_write(7'h16, 8'h01);
    enc0_state(0, 0);
    enc0_state(1, 0);
    enc0_state(1, 1);
    enc0_state(0, 1);
    enc0_state(0, 0);
    spi_read(7'h0a, value);
    spi_read(7'h0b, value_hi);
    check({value_hi, value} == 16'd4, "ENC0 forward sequence counts +4");
    enc0_state(0, 1);
    enc0_state(1, 1);
    enc0_state(1, 0);
    enc0_state(0, 0);
    spi_read(7'h0a, value);
    spi_read(7'h0b, value_hi);
    check({value_hi, value} == 16'd0, "ENC0 reverse sequence counts -4");

    /* Channel 1 is independent. */
    spi_write(7'h16, 8'h02);
    enc1_state(0, 0);
    enc1_state(1, 0);
    enc1_state(1, 1);
    enc1_state(0, 1);
    enc1_state(0, 0);
    spi_read(7'h0c, value);
    spi_read(7'h0d, value_hi);
    check({value_hi, value} == 16'd4, "ENC1 forward sequence counts +4");

    /* A two-bit jump is rejected and counted as an encoder error. */
    spi_write(7'h16, 8'h01);
    enc0_state(0, 0);
    enc0_state(1, 1);
    spi_read(7'h14, value);
    check(value == 8'd1, "illegal quadrature transition increments error count");
    spi_read(7'h09, value);
    check(value[3] == 1'b1, "illegal ENC0 transition raises event flag");

    /* Input capture latches the 100 ns timer and raises its event. */
    uio_in[0] = 1'b0;
    repeat (4) @(posedge clk);
    uio_in[0] = 1'b1;
    repeat (5) @(posedge clk);
    uio_in[0] = 1'b0;
    spi_read(7'h0e, value);
    spi_read(7'h0f, value_hi);
    check({value_hi, value} != 16'h0000, "capture register stores timer value");
    spi_read(7'h09, value);
    check(value[1] == 1'b1, "capture event flag is set");

    /* Compare=0 followed by timer clear produces a deterministic match. */
    spi_write(7'h09, 8'h1e);
    spi_write(7'h12, 8'h00);
    spi_write(7'h13, 8'h00);
    spi_write(7'h02, 8'h03);
    spi_write(7'h16, 8'h04);
    repeat (5) @(posedge clk);
    spi_read(7'h09, value);
    check(value[2] == 1'b1, "timer compare event is set");
    check(uo_out[5] == 1'b1, "compare event drives IRQ");

    /* ena must make all externally visible outputs safe. */
    ena = 1'b0;
    #1;
    check(uo_out == 8'h00, "ena=0 masks all dedicated outputs");
    check(uio_oe == 8'h00, "ena=0 keeps bidirectional pins high impedance");

    if (failures == 0)
      $display("TINY_MCE_TEST_PASS");
    else
      $display("TINY_MCE_TEST_FAIL count=%0d", failures);
    $finish;
  end

endmodule

`default_nettype none
