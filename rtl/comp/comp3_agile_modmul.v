// -----------------------------------------------------------------------------
// comp3_agile_modmul.v
// COMP3: modular multiplier plus reduction.
//
//   opmode=0 ML-KEM: two independent 16-bit lane products, each reduced mod 3329
//   opmode=1 ML-DSA: one 24x24 integer product, Montgomery-reduced mod 8380417
//
// The SBU inserts pipeline registers around this combinational block.
// -----------------------------------------------------------------------------
`default_nettype none

module comp3_agile_modmul (
    input  wire [31:0] a_i,
    input  wire [31:0] b_i,
    input  wire        opmode_i, // 0: ML-KEM, 1: ML-DSA
    output wire [31:0] c_o
);
    wire [31:0] kem_lo_raw;
    wire [31:0] kem_hi_raw;
    array_schoolbook_agile16 #(.CARRY_GATED_ARRAY(0)) u_kem_lo_mul (
        .a_i(a_i[15:0]),
        .b_i(b_i[15:0]),
        .carry_en_i(1'b1),
        .p_o(kem_lo_raw)
    );
    array_schoolbook_agile16 #(.CARRY_GATED_ARRAY(0)) u_kem_hi_mul (
        .a_i(a_i[31:16]),
        .b_i(b_i[31:16]),
        .carry_en_i(1'b1),
        .p_o(kem_hi_raw)
    );

    wire [15:0] kem_lo_red;
    wire [15:0] kem_hi_red;
    kyber_barrett_reduce_24 u_kem_lo_red (.a_i(kem_lo_raw[23:0]), .r_o(kem_lo_red));
    kyber_barrett_reduce_24 u_kem_hi_red (.a_i(kem_hi_raw[23:0]), .r_o(kem_hi_red));
    wire [31:0] kem_out = {kem_hi_red, kem_lo_red};

    wire [47:0] dsa_raw48;
    mldsa_karatsuba24 u_dsa_mul (
        .a_i(a_i[23:0]),
        .b_i(b_i[23:0]),
        .p_o(dsa_raw48)
    );
    wire [31:0] dsa_out;
    mldsa_montgomery_reduce u_dsa_red (
        .a_i({16'b0, dsa_raw48}),
        .r_o(dsa_out)
    );

    assign c_o = opmode_i ? dsa_out : kem_out;
endmodule

`default_nettype wire
