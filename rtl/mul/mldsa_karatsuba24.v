// -----------------------------------------------------------------------------
// mldsa_karatsuba24.v
// ML-DSA coefficient multiplier. The external word uses a 24-bit container,
// but normalized ML-DSA residues are < q = 0x7fe001 and therefore fit in
// 23 bits. The split is low 12 bits plus high 11 bits, using three carrying
// schoolbook multipliers:
//   M0 = a0*b0, M1 = a1*b1, M2 = (a0+a1)*(b0+b1).
// The middle term is integer arithmetic, never a binary-field term.
// -----------------------------------------------------------------------------
`default_nettype none

module mldsa_karatsuba24 (
    input  wire [23:0] a_i,
    input  wire [23:0] b_i,
    output wire [47:0] p_o
);
    wire [11:0] a0 = a_i[11:0];
    wire [10:0] a1 = a_i[22:12];
    wire [11:0] b0 = b_i[11:0];
    wire [10:0] b1 = b_i[22:12];

    wire [23:0] z0;
    wire [21:0] z1;
    array_schoolbook_unsigned #(.A_W(12), .B_W(12), .P_W(24)) u_m0 (
        .a_i(a0), .b_i(b0), .p_o(z0)
    );
    array_schoolbook_unsigned #(.A_W(11), .B_W(11), .P_W(22)) u_m1 (
        .a_i(a1), .b_i(b1), .p_o(z1)
    );

    wire [12:0] a_sum = {1'b0, a0} + {2'b0, a1};
    wire [12:0] b_sum = {1'b0, b0} + {2'b0, b1};
    wire [25:0] z2_full;
    array_schoolbook_unsigned #(.A_W(13), .B_W(13), .P_W(26)) u_m2 (
        .a_i(a_sum), .b_i(b_sum), .p_o(z2_full)
    );

    wire [25:0] mid = z2_full - {2'b0, z0} - {4'b0, z1};
    assign p_o = ({26'b0, z1} << 24) + ({22'b0, mid} << 12) + {24'b0, z0};
endmodule

`default_nettype wire
