// -----------------------------------------------------------------------------
// mldsa_modadd32.v
// ML-DSA modular addition for q=8380417. Inputs are normalized residues.
// -----------------------------------------------------------------------------
`include "phoenix_defs.vh"
`default_nettype none

module mldsa_modadd32 (
    input  wire [31:0] a_i,
    input  wire [31:0] b_i,
    output wire [31:0] c_o
);
    wire [32:0] sum = {1'b0, a_i} + {1'b0, b_i};
    wire [32:0] sum_minus_q = sum - {1'b0, `MLDSA_Q};
    assign c_o = (sum >= {1'b0, `MLDSA_Q}) ? sum_minus_q[31:0] : sum[31:0];
endmodule

`default_nettype wire
