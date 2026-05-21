// -----------------------------------------------------------------------------
// comp3_mlkem_masked_mul.v
// ML-KEM two-share packed-lane multiplication helper for arithmetic masking.
//
// For each 16-bit lane modulo q=3329:
//   x = x0 + x1, y = y0 + y1
//   z0 = x0*y0 + r
//   z1 = x0*y1 + x1*y0 + x1*y1 - r
//
// When mask_lane_i is 0, r is ignored and the same cross-term expansion is used
// without refreshing. This covers public-constant multiplication where one input
// share is zero.
// -----------------------------------------------------------------------------
`default_nettype none

module kyber_mulred16_lut (
    input  wire [15:0] a_i,
    input  wire [15:0] b_i,
    output wire [15:0] r_o
);
    wire [31:0] raw;
    array_schoolbook_agile16 #(.CARRY_GATED_ARRAY(0)) u_mul (
        .a_i(a_i),
        .b_i(b_i),
        .carry_en_i(1'b1),
        .p_o(raw)
    );
    kyber_barrett_reduce_24 u_red (
        .a_i(raw[23:0]),
        .r_o(r_o)
    );
endmodule

module kyber_masked_lane_mul16 (
    input  wire [15:0] x0_i,
    input  wire [15:0] y0_i,
    input  wire [15:0] x1_i,
    input  wire [15:0] y1_i,
    input  wire [15:0] rand_i,
    input  wire        mask_lane_i,
    output wire [15:0] z0_o,
    output wire [15:0] z1_o
);
    wire [15:0] p00, p01, p10, p11;
    kyber_mulred16_lut u_p00 (.a_i(x0_i), .b_i(y0_i), .r_o(p00));
    kyber_mulred16_lut u_p01 (.a_i(x0_i), .b_i(y1_i), .r_o(p01));
    kyber_mulred16_lut u_p10 (.a_i(x1_i), .b_i(y0_i), .r_o(p10));
    kyber_mulred16_lut u_p11 (.a_i(x1_i), .b_i(y1_i), .r_o(p11));

    wire [15:0] cross01_sum;
    wire [15:0] cross_sum;
    kyber_modadd16_csa u_cross01 (.a_i(p01), .b_i(p10), .c_o(cross01_sum));
    kyber_modadd16_csa u_cross   (.a_i(cross01_sum), .b_i(p11), .c_o(cross_sum));

    wire [15:0] z0_masked;
    wire [15:0] z1_masked;
    kyber_modadd16_csa u_z0 (.a_i(p00),   .b_i(rand_i), .c_o(z0_masked));
    kyber_modsub16_csa u_z1 (.a_i(cross_sum), .b_i(rand_i), .c_o(z1_masked));

    assign z0_o = mask_lane_i ? z0_masked : p00;
    assign z1_o = mask_lane_i ? z1_masked : cross_sum;
endmodule

module kyber_public_const_lane_mul16 (
    input  wire [15:0] x0_i,
    input  wire [15:0] y0_i,
    input  wire [15:0] y1_i,
    output wire [15:0] z0_o,
    output wire [15:0] z1_o
);
    kyber_mulred16_lut u_p00 (.a_i(x0_i), .b_i(y0_i), .r_o(z0_o));
    kyber_mulred16_lut u_p01 (.a_i(x0_i), .b_i(y1_i), .r_o(z1_o));
endmodule

module comp3_mlkem_public_const_mul (
    input  wire [31:0] a0_i,
    input  wire [31:0] b0_i,
    input  wire [31:0] b1_i,
    output wire [31:0] p0_o,
    output wire [31:0] p1_o
);
    wire [15:0] lo0, lo1, hi0, hi1;
    kyber_public_const_lane_mul16 u_lo (
        .x0_i(a0_i[15:0]),
        .y0_i(b0_i[15:0]),
        .y1_i(b1_i[15:0]),
        .z0_o(lo0),
        .z1_o(lo1)
    );
    kyber_public_const_lane_mul16 u_hi (
        .x0_i(a0_i[31:16]),
        .y0_i(b0_i[31:16]),
        .y1_i(b1_i[31:16]),
        .z0_o(hi0),
        .z1_o(hi1)
    );

    assign p0_o = {hi0, lo0};
    assign p1_o = {hi1, lo1};
endmodule

module comp3_mlkem_masked_mul (
    input  wire [31:0] a0_i,
    input  wire [31:0] b0_i,
    input  wire [31:0] a1_i,
    input  wire [31:0] b1_i,
    input  wire [31:0] rand_i,
    input  wire        mask_lo_i,
    input  wire        mask_hi_i,
    output wire [31:0] p0_o,
    output wire [31:0] p1_o
);
    wire [15:0] lo0, lo1, hi0, hi1;
    kyber_masked_lane_mul16 u_lo (
        .x0_i(a0_i[15:0]),
        .y0_i(b0_i[15:0]),
        .x1_i(a1_i[15:0]),
        .y1_i(b1_i[15:0]),
        .rand_i(rand_i[15:0]),
        .mask_lane_i(mask_lo_i),
        .z0_o(lo0),
        .z1_o(lo1)
    );
    kyber_masked_lane_mul16 u_hi (
        .x0_i(a0_i[31:16]),
        .y0_i(b0_i[31:16]),
        .x1_i(a1_i[31:16]),
        .y1_i(b1_i[31:16]),
        .rand_i(rand_i[31:16]),
        .mask_lane_i(mask_hi_i),
        .z0_o(hi0),
        .z1_o(hi1)
    );

    assign p0_o = {hi0, lo0};
    assign p1_o = {hi1, lo1};
endmodule

module comp3_mlkem_masked_mul_pipe (
    input  wire        clk_i,
    input  wire        rst_ni,
    input  wire [31:0] a0_i,
    input  wire [31:0] b0_i,
    input  wire [31:0] a1_i,
    input  wire [31:0] b1_i,
    input  wire [31:0] rand_i,
    input  wire        mask_lo_i,
    input  wire        mask_hi_i,
    output wire [31:0] p0_o,
    output wire [31:0] p1_o
);
    wire [15:0] lo_p00_w, lo_p01_w, lo_p10_w, lo_p11_w;
    wire [15:0] hi_p00_w, hi_p01_w, hi_p10_w, hi_p11_w;

    kyber_mulred16_lut u_lo_p00 (.a_i(a0_i[15:0]),  .b_i(b0_i[15:0]),  .r_o(lo_p00_w));
    kyber_mulred16_lut u_lo_p01 (.a_i(a0_i[15:0]),  .b_i(b1_i[15:0]),  .r_o(lo_p01_w));
    kyber_mulred16_lut u_lo_p10 (.a_i(a1_i[15:0]),  .b_i(b0_i[15:0]),  .r_o(lo_p10_w));
    kyber_mulred16_lut u_lo_p11 (.a_i(a1_i[15:0]),  .b_i(b1_i[15:0]),  .r_o(lo_p11_w));
    kyber_mulred16_lut u_hi_p00 (.a_i(a0_i[31:16]), .b_i(b0_i[31:16]), .r_o(hi_p00_w));
    kyber_mulred16_lut u_hi_p01 (.a_i(a0_i[31:16]), .b_i(b1_i[31:16]), .r_o(hi_p01_w));
    kyber_mulred16_lut u_hi_p10 (.a_i(a1_i[31:16]), .b_i(b0_i[31:16]), .r_o(hi_p10_w));
    kyber_mulred16_lut u_hi_p11 (.a_i(a1_i[31:16]), .b_i(b1_i[31:16]), .r_o(hi_p11_w));

    reg [15:0] lo_p00_r, lo_p01_r, lo_p10_r, lo_p11_r;
    reg [15:0] hi_p00_r, hi_p01_r, hi_p10_r, hi_p11_r;
    reg [31:0] rand_r;
    reg        mask_lo_r, mask_hi_r;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            lo_p00_r <= 16'b0; lo_p01_r <= 16'b0; lo_p10_r <= 16'b0; lo_p11_r <= 16'b0;
            hi_p00_r <= 16'b0; hi_p01_r <= 16'b0; hi_p10_r <= 16'b0; hi_p11_r <= 16'b0;
            rand_r <= 32'b0;
            mask_lo_r <= 1'b0;
            mask_hi_r <= 1'b0;
        end else begin
            lo_p00_r <= lo_p00_w; lo_p01_r <= lo_p01_w; lo_p10_r <= lo_p10_w; lo_p11_r <= lo_p11_w;
            hi_p00_r <= hi_p00_w; hi_p01_r <= hi_p01_w; hi_p10_r <= hi_p10_w; hi_p11_r <= hi_p11_w;
            rand_r <= rand_i;
            mask_lo_r <= mask_lo_i;
            mask_hi_r <= mask_hi_i;
        end
    end

    wire [15:0] lo_cross01_sum;
    wire [15:0] lo_cross_sum;
    wire [15:0] lo_z0_masked;
    wire [15:0] lo_z1_masked;
    kyber_modadd16_csa u_lo_cross01 (.a_i(lo_p01_r), .b_i(lo_p10_r), .c_o(lo_cross01_sum));
    kyber_modadd16_csa u_lo_cross   (.a_i(lo_cross01_sum), .b_i(lo_p11_r), .c_o(lo_cross_sum));
    kyber_modadd16_csa u_lo_z0      (.a_i(lo_p00_r), .b_i(rand_r[15:0]), .c_o(lo_z0_masked));
    kyber_modsub16_csa u_lo_z1      (.a_i(lo_cross_sum), .b_i(rand_r[15:0]), .c_o(lo_z1_masked));

    wire [15:0] hi_cross01_sum;
    wire [15:0] hi_cross_sum;
    wire [15:0] hi_z0_masked;
    wire [15:0] hi_z1_masked;
    kyber_modadd16_csa u_hi_cross01 (.a_i(hi_p01_r), .b_i(hi_p10_r), .c_o(hi_cross01_sum));
    kyber_modadd16_csa u_hi_cross   (.a_i(hi_cross01_sum), .b_i(hi_p11_r), .c_o(hi_cross_sum));
    kyber_modadd16_csa u_hi_z0      (.a_i(hi_p00_r), .b_i(rand_r[31:16]), .c_o(hi_z0_masked));
    kyber_modsub16_csa u_hi_z1      (.a_i(hi_cross_sum), .b_i(rand_r[31:16]), .c_o(hi_z1_masked));

    wire [15:0] lo0 = mask_lo_r ? lo_z0_masked : lo_p00_r;
    wire [15:0] lo1 = mask_lo_r ? lo_z1_masked : lo_cross_sum;
    wire [15:0] hi0 = mask_hi_r ? hi_z0_masked : hi_p00_r;
    wire [15:0] hi1 = mask_hi_r ? hi_z1_masked : hi_cross_sum;

    assign p0_o = {hi0, lo0};
    assign p1_o = {hi1, lo1};
endmodule

`default_nettype wire
