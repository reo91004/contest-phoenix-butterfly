// -----------------------------------------------------------------------------
// comp2_agile_modarith_div2.v
// COMP2: modular add/subtract plus optional division by two.
//   opmode=0 ML-KEM: two 16-bit lanes modulo 3329
//   opmode=1 ML-DSA: one 32-bit residue modulo 8380417
// -----------------------------------------------------------------------------
`default_nettype none

module comp2_agile_modarith_div2 (
    input  wire [31:0] a_i,
    input  wire [31:0] b_i,
    input  wire        opmode_i,
    input  wire        addsub_i, // 0:add, 1:sub
    input  wire        intt_i,
    output wire [31:0] c_o
);
    wire [15:0] kem_lo, kem_hi;
    kyber_modarith16 u_kem_lo (.a_i(a_i[15:0]),  .b_i(b_i[15:0]),  .addsub_i(addsub_i), .intt_i(intt_i), .c_o(kem_lo));
    kyber_modarith16 u_kem_hi (.a_i(a_i[31:16]), .b_i(b_i[31:16]), .addsub_i(addsub_i), .intt_i(intt_i), .c_o(kem_hi));

    wire [31:0] kem_out = {kem_hi, kem_lo};

    wire [31:0] dsa_out;
    mldsa_modarith32 u_dsa (
        .a_i(a_i),
        .b_i(b_i),
        .addsub_i(addsub_i),
        .intt_i(intt_i),
        .c_o(dsa_out)
    );

    assign c_o = opmode_i ? dsa_out : kem_out;
endmodule

`default_nettype wire
