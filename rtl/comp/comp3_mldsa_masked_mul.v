// -----------------------------------------------------------------------------
// comp3_mldsa_masked_mul.v
// ML-DSA two-share Montgomery-domain multiplication helper.
//
// Shares live in the existing ML-DSA Montgomery residue domain:
//   x = x0 + x1 mod q, y = y0 + y1 mod q
//
// Each product term is Montgomery-reduced, so the cross-term expansion is
// linear modulo q:
//   z0 = Mont(x0*y0) + r
//   z1 = Mont(x0*y1) + Mont(x1*y0) + Mont(x1*y1) - r
//
// When mask_i is 0, r is ignored. This covers public-constant multiplication
// where one input share is zero but the other operand remains shared.
// -----------------------------------------------------------------------------
`default_nettype none

module mldsa_mulred24_lut (
    input  wire [23:0] a_i,
    input  wire [23:0] b_i,
    output wire [31:0] r_o
);
    wire [47:0] raw;
    mldsa_karatsuba24 u_mul (
        .a_i(a_i),
        .b_i(b_i),
        .p_o(raw)
    );
    mldsa_montgomery_reduce u_red (
        .a_i({16'b0, raw}),
        .r_o(r_o)
    );
endmodule

module comp3_mldsa_masked_mul_pipe (
    input  wire        clk_i,
    input  wire        rst_ni,
    input  wire [31:0] a0_i,
    input  wire [31:0] b0_i,
    input  wire [31:0] a1_i,
    input  wire [31:0] b1_i,
    input  wire [31:0] rand_i,
    input  wire        mask_i,
    output wire [31:0] p0_o,
    output wire [31:0] p1_o
);
    wire [31:0] p00_w, p01_w, p10_w, p11_w;
    mldsa_mulred24_lut u_p00 (.a_i(a0_i[23:0]), .b_i(b0_i[23:0]), .r_o(p00_w));
    mldsa_mulred24_lut u_p01 (.a_i(a0_i[23:0]), .b_i(b1_i[23:0]), .r_o(p01_w));
    mldsa_mulred24_lut u_p10 (.a_i(a1_i[23:0]), .b_i(b0_i[23:0]), .r_o(p10_w));
    mldsa_mulred24_lut u_p11 (.a_i(a1_i[23:0]), .b_i(b1_i[23:0]), .r_o(p11_w));

    reg [31:0] p00_r, p01_r, p10_r, p11_r;
    reg [31:0] rand_r;
    reg        mask_r;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            p00_r <= 32'b0;
            p01_r <= 32'b0;
            p10_r <= 32'b0;
            p11_r <= 32'b0;
            rand_r <= 32'b0;
            mask_r <= 1'b0;
        end else begin
            p00_r <= p00_w;
            p01_r <= p01_w;
            p10_r <= p10_w;
            p11_r <= p11_w;
            rand_r <= rand_i;
            mask_r <= mask_i;
        end
    end

    wire [31:0] cross01_sum;
    wire [31:0] cross_sum;
    mldsa_modadd32 u_cross01 (.a_i(p01_r), .b_i(p10_r), .c_o(cross01_sum));
    mldsa_modadd32 u_cross   (.a_i(cross01_sum), .b_i(p11_r), .c_o(cross_sum));

    wire [31:0] z0_masked;
    wire [31:0] z1_masked;
    mldsa_modadd32 u_z0 (.a_i(p00_r), .b_i(rand_r), .c_o(z0_masked));
    mldsa_modsub32 u_z1 (.a_i(cross_sum), .b_i(rand_r), .c_o(z1_masked));

    assign p0_o = mask_r ? z0_masked : p00_r;
    assign p1_o = mask_r ? z1_masked : cross_sum;
endmodule

`default_nettype wire
