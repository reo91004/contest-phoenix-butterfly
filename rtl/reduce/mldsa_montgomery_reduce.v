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
    function [31:0] mul_const_low32;
        input [31:0] x;
        input [31:0] c;
        reg [63:0] acc;
        integer i;
        begin
            acc = 64'b0;
            for (i = 0; i < 32; i = i + 1) begin
                if (c[i]) begin
                    acc = acc + ({32'b0, x} << i);
                end
            end
            mul_const_low32 = acc[31:0];
        end
    endfunction

    function [63:0] mul_const_full32;
        input [31:0] x;
        input [31:0] c;
        reg [63:0] acc;
        integer i;
        begin
            acc = 64'b0;
            for (i = 0; i < 32; i = i + 1) begin
                if (c[i]) begin
                    acc = acc + ({32'b0, x} << i);
                end
            end
            mul_const_full32 = acc;
        end
    endfunction

    wire [31:0] t = mul_const_low32(a_i[31:0], `MLDSA_QINV);
    wire [63:0] tq = mul_const_full32(t, `MLDSA_Q);
    wire [63:0] diff = a_i - tq;

    wire signed [31:0] r_signed = diff[63:32];
    wire signed [32:0] r_plus_q_signed = {r_signed[31], r_signed} + {1'b0, `MLDSA_Q};
    wire [31:0] r_nonneg = r_signed[31] ? r_plus_q_signed[31:0] : r_signed[31:0];
    wire [31:0] r_minus_q = r_nonneg - `MLDSA_Q;
    assign r_o = (r_nonneg >= `MLDSA_Q) ? r_minus_q : r_nonneg;
endmodule

`default_nettype wire
