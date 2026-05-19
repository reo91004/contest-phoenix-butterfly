// -----------------------------------------------------------------------------
// mldsa_div2_32.v
// Modular division by two over q=8380417.
// -----------------------------------------------------------------------------
`include "phoenix_defs.vh"
`default_nettype none

module mldsa_div2_32 (
    input  wire [31:0] a_i,
    output wire [31:0] c_o
);
    wire [32:0] odd_adjusted = {1'b0, a_i} + {1'b0, `MLDSA_Q};
    assign c_o = a_i[0] ? odd_adjusted[32:1] : {1'b0, a_i[31:1]};
endmodule

`default_nettype wire
