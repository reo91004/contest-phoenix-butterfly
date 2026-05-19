// -----------------------------------------------------------------------------
// mldsa_modsub32.v
// ML-DSA modular subtraction for q=8380417. Inputs are normalized residues.
// -----------------------------------------------------------------------------
`include "phoenix_defs.vh"
`default_nettype none

module mldsa_modsub32 (
    input  wire [31:0] a_i,
    input  wire [31:0] b_i,
    output wire [31:0] c_o
);
    wire [32:0] diff_pos = {1'b0, a_i} - {1'b0, b_i};
    wire [32:0] diff_wrap = {1'b0, a_i} + {1'b0, `MLDSA_Q} - {1'b0, b_i};
    assign c_o = (a_i >= b_i) ? diff_pos[31:0] : diff_wrap[31:0];
endmodule

`default_nettype wire
