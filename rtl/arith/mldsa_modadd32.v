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
    localparam [23:0] Q24 = 24'd8380417;

    wire [23:0] a_v = {1'b0, a_i[22:0]};
    wire [23:0] b_v = {1'b0, b_i[22:0]};
    wire [23:0] sum = a_v + b_v;
    wire [23:0] sum_minus_q = sum - Q24;
    wire [23:0] red = (sum >= Q24) ? sum_minus_q : sum;

    assign c_o = {9'b0, red[22:0]};
endmodule

`default_nettype wire
