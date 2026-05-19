// -----------------------------------------------------------------------------
// bank_decoder_4way.v  (구 bank_decoder.v — 재배치, 로직 보존)
// Conflict-free memory bank decoder (paper §4.2.2, [MRW+22]).
//
// PHOENIX uses w_PE = 2 (two SBUs) and b = 4 banks per polynomial memory side.
// Each side stores up to 1024 32-bit words across 4 dual-port BRAMs.
//
//   bank(index)    = (sum of base-4 digits of index) mod 4
//   address(index) = floor(index / 4)
//
// Hard-coded for b = 4. A 12-bit index covers 4096 coefficient words,
// yielding a 10-bit per-bank address after division by four.
// -----------------------------------------------------------------------------
`default_nettype none

module bank_decoder_4way #(
    parameter integer INDEX_W = 12,   // 0..4095
    parameter integer DIGITS  = 6     // ceil(11/2) = 6 base-4 digits cover 12 bits
)(
    input  wire [INDEX_W-1:0] index,
    output wire [1:0]         bank,
    output wire [INDEX_W-3:0] address
);

    // Sum of base-4 digits modulo 4 (kept narrow to avoid carry overflow).
    // 6 digits each in [0,3] sum up to 18, which would overflow a 4-bit
    // accumulator, so we mask to 2 bits at every step.
    reg [1:0] digit_sum;
    integer k;
    always @* begin
        digit_sum = 2'b0;
        for (k = 0; k < DIGITS; k = k + 1) begin
            digit_sum = digit_sum + ((index >> (2*k)) & 2'b11);
        end
    end

    assign bank    = digit_sum;
    assign address = index[INDEX_W-1:2];

endmodule

`default_nettype wire
