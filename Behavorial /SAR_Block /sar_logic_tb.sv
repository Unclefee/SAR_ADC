// -----------------------------------------------------------------------------
// sar_logic_tb.sv : self-checking testbench for sar_logic
//
// The analog side is modelled behaviorally in the testbench:
//   - Vin is sampled while `sample` is high and held afterwards
//   - ideal CDAC:       Vdac = dac_code / 2^N * VREF
//   - ideal comparator: comp_out = (Vin_held >= Vdac)
// The ideal ADC output is floor(Vin / LSB), clamped to full scale.
//
// Tests: 1) code-centre input for every code   2) 0-1 V ramp
//        3) sine wave                           4) reset in mid-conversion
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module sar_logic_tb;

  localparam int  N      = 6;
  localparam real VREF   = 1.0;
  localparam real LSB    = VREF / (2.0**N);
  localparam real T_CLK  = 125.0;            // 8 MHz internal clock

  logic         clk = 0;
  logic         rst_n;
  logic         comp_out;
  logic         sample;
  logic [N-1:0] dac_code;
  logic [N-1:0] dout;
  logic         eoc;

  real vin = 0.0;
  real vin_held;
  real vdac;

  int errors = 0;
  int checks = 0;

  sar_logic #(.N(N)) dut (.*);

  always #(T_CLK/2) clk = ~clk;

  // ---------------- behavioral analog models ----------------
  // Track while sample is high, hold when it falls
  always @(*) if (sample) vin_held = vin;

  assign vdac     = (dac_code * VREF) / (2.0**N);
  assign comp_out = (vin_held >= vdac);

  // ---------------- helpers ----------------
  function automatic int ideal_code(real v);
    int c;
    c = int'($floor(v / LSB));
    if (c < 0)          c = 0;
    if (c > (2**N) - 1) c = (2**N) - 1;
    return c;
  endfunction

  // Apply vin, run one full conversion, compare with the ideal code
  task automatic convert_and_check(real v, string tag);
    int expected;
    vin = v;
    @(posedge eoc);
    @(negedge clk);
    expected = ideal_code(v);
    checks++;
    if (dout !== expected[N-1:0]) begin
      errors++;
      $error("[%s] vin=%0.5f V expected=%0d got=%0d", tag, v, expected, dout);
    end
  endtask

  // Wait for the sample phase before changing vin so it is tracked
  task automatic next_sample();
    @(negedge clk);
    while (!sample) @(negedge clk);
  endtask

  // ---------------- timing monitor: 8 cycles per conversion ----------------
  time t_last_eoc = 0;
  always @(negedge rst_n) t_last_eoc = 0;   // a reset restarts the timing check
  always @(posedge eoc) begin
    if (t_last_eoc != 0 && ($time - t_last_eoc) != 8*T_CLK) begin
      errors++;
      $error("Conversion period %0t, expected %0t", $time - t_last_eoc, 8*T_CLK);
    end
    t_last_eoc = $time;
  end

  // ---------------- stimulus ----------------
  initial begin
    $dumpfile("sar_logic_tb.vcd");
    $dumpvars(0, sar_logic_tb);

    rst_n = 0;
    repeat (3) @(negedge clk);
    rst_n = 1;

    // Test 1: centre of every code
    $display("Test 1: code-centre input for all %0d codes", 2**N);
    for (int k = 0; k < 2**N; k++) begin
      next_sample();
      convert_and_check((k + 0.5) * LSB, "centre");
    end

    // Test 2: ramp 0 -> VREF (inclusive: checks full-scale clamp), 1 mV step
    $display("Test 2: 0-1 V ramp");
    for (int k = 0; k <= 1000; k++) begin
      next_sample();
      convert_and_check(k / 1000.0, "ramp");
    end

    // Test 3: sine wave, 1 period over 64 conversions, 0.5 +/- 0.49 V
    $display("Test 3: sine wave");
    for (int k = 0; k < 64; k++) begin
      next_sample();
      convert_and_check(0.5 + 0.49 * $sin(2.0 * 3.14159265358979 * k / 64.0), "sine");
    end

    // Test 4: asynchronous reset in the middle of a conversion
    $display("Test 4: reset during conversion");
    next_sample();
    vin = 0.7;
    repeat (4) @(negedge clk);
    rst_n = 0;
    #1;
    checks++;
    if (!(sample && dac_code == 0 && dout == 0 && !eoc)) begin
      errors++;
      $error("Reset did not return the FSM to the SAMPLE state");
    end
    repeat (2) @(negedge clk);
    rst_n = 1;
    next_sample();
    convert_and_check(0.7, "post-reset");

    $display("----------------------------------------------");
    if (errors == 0) $display("PASS: %0d checks, 0 errors", checks);
    else             $display("FAIL: %0d checks, %0d errors", checks, errors);
    $display("----------------------------------------------");
    $finish;
  end

  // Watchdog
  initial begin
    #(5_000_000);
    $error("Timeout");
    $finish;
  end

endmodule
