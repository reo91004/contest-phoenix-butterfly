// -----------------------------------------------------------------------------
// mldsa_montgomery_reduce.v
// Montgomery reduction for ML-DSA q=8380417 using the FIPS 204 QINV value.
// Computes a_i * 2^-32 mod q and returns a normalized residue.
// No Verilog multiply operator is used in this datapath.
// -----------------------------------------------------------------------------
`include "phoenix_defs.vh"
`default_nettype none

module mldsa_montgomery_reduce (
    input  wire [63:0] a_i,
    output wire [31:0] r_o
);
    wire [63:0] a_low = {32'b0, a_i[31:0]};
    wire [63:0] qinv_prod = (a_low << 25) + (a_low << 24) +
                            (a_low << 23) + (a_low << 13) + a_low;
    wire [31:0] t = qinv_prod[31:0];
    wire [63:0] t_ext = {32'b0, t};
    wire [63:0] tq = (t_ext << 23) - (t_ext << 13) + t_ext;
    wire [63:0] diff = a_i - tq;

    wire signed [31:0] r_signed = diff[63:32];
    wire signed [32:0] r_plus_q_signed = {r_signed[31], r_signed} + {1'b0, `MLDSA_Q};
    wire [31:0] r_nonneg = r_signed[31] ? r_plus_q_signed[31:0] : r_signed[31:0];
    wire [31:0] r_minus_q = r_nonneg - `MLDSA_Q;
    assign r_o = (r_nonneg >= `MLDSA_Q) ? r_minus_q : r_nonneg;
endmodule

`default_nettype wire
