// -----------------------------------------------------------------------------
// comp1_agile_modadd_div2.v
// COMP1: modular adder plus optional division by two.
//   opmode=0 ML-KEM: two 16-bit lanes modulo 3329
//   opmode=1 ML-DSA: one 32-bit residue modulo 8380417
// -----------------------------------------------------------------------------
`default_nettype none

module comp1_agile_modadd_div2 (
    input  wire [31:0] a_i,
    input  wire [31:0] b_i,
    input  wire        opmode_i, // 0: ML-KEM, 1: ML-DSA
    input  wire        intt_i,   // 1: modular div-by-2
    output wire [31:0] c_o
);
    wire [15:0] kem_lo_add, kem_hi_add, kem_lo_d, kem_hi_d;

    kyber_modadd16_csa u_kem_lo (.a_i(a_i[15:0]),  .b_i(b_i[15:0]),  .c_o(kem_lo_add));
    kyber_modadd16_csa u_kem_hi (.a_i(a_i[31:16]), .b_i(b_i[31:16]), .c_o(kem_hi_add));
    kyber_div2_16      u_kem_ld (.a_i(kem_lo_add), .c_o(kem_lo_d));
    kyber_div2_16      u_kem_hd (.a_i(kem_hi_add), .c_o(kem_hi_d));

    wire [31:0] kem_out = intt_i ? {kem_hi_d, kem_lo_d} : {kem_hi_add, kem_lo_add};

    wire [31:0] dsa_out;
    mldsa_modarith32 u_dsa (
        .a_i(a_i),
        .b_i(b_i),
        .addsub_i(1'b0),
        .intt_i(intt_i),
        .c_o(dsa_out)
    );

    assign c_o = opmode_i ? dsa_out : kem_out;
endmodule

`default_nettype wire
