// -----------------------------------------------------------------------------
// sar_logic.sv : SAR control FSM for the 6-bit, 1 MS/s SAR ADC
//
// One conversion = 8 clock cycles (8 MHz clock -> 1 us):
//   SAMPLE  : 1 cycle  - track & hold switch closed, CDAC reset
//   CONVERT : 6 cycles - binary search, MSB -> LSB
//   DONE    : 1 cycle  - result valid, eoc asserted
//
// Comparator convention: comp_out = 1 when Vin >= Vdac (trial voltage), i.e.
// the bit under test is kept. During CONVERT, dac_code drives the CDAC with the
// current result register, where the bit under test is set to 1 and all lower
// bits are 0.
// -----------------------------------------------------------------------------
module sar_logic #(
  parameter int N = 6
) (
  input  logic         clk,
  input  logic         rst_n,     // active-low asynchronous reset
  input  logic         comp_out,  // comparator decision (1: Vin >= Vdac)
  output logic         sample,    // 1 = track/sample Vin onto the CDAC
  output logic [N-1:0] dac_code,  // trial code applied to the CDAC
  output logic [N-1:0] dout,      // converted result, held until next conversion
  output logic         eoc        // end of conversion, high for one cycle
);

  typedef enum logic [1:0] {SAMPLE, CONVERT, DONE} state_t;

  state_t              state;
  logic [N-1:0]        result;    // successive-approximation register
  logic [$clog2(N)-1:0] bit_idx;  // index of the bit under test

  // The SAR register drives the CDAC directly
  assign dac_code = result;
  assign sample   = (state == SAMPLE);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state   <= SAMPLE;
      result  <= '0;
      bit_idx <= N-1;
      dout    <= '0;
      eoc     <= 1'b0;
    end else begin
      eoc <= 1'b0;

      unique case (state)
        SAMPLE: begin
          // Start of conversion: try MSB = 1, all other bits 0
          result  <= '0;
          result[N-1] <= 1'b1;
          bit_idx <= N-1;
          state   <= CONVERT;
        end

        CONVERT: begin
          // Keep or drop the bit under test, then set the next one
          result[bit_idx] <= comp_out;
          if (bit_idx == 0) begin
            dout  <= {result[N-1:1], comp_out};
            eoc   <= 1'b1;
            state <= DONE;
          end else begin
            result[bit_idx-1] <= 1'b1;
            bit_idx           <= bit_idx - 1'b1;
          end
        end

        DONE: begin
          state <= SAMPLE;
        end

        default: state <= SAMPLE;
      endcase
    end
  end

endmodule
