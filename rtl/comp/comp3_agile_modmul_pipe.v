// -----------------------------------------------------------------------------
// comp3_agile_modmul_pipe.v
// Pipelined COMP3 multiplier/reducer for the routed SBU. The combinational
// COMP3 is kept for unit/reference use; this version spends eight cycles on
// Phase A so 8 ns implementation targets do not see multiply+reduction as one
// monolithic path.
// -----------------------------------------------------------------------------
`default_nettype none

module comp3_agile_modmul_pipe (
    input  wire        clk_i,
    input  wire [31:0] a_i,
    input  wire [31:0] b_i,
    input  wire        opmode_i, // 0: ML-KEM, 1: ML-DSA
    output wire [31:0] c_o
);
    localparam [31:0] MLDSA_Q32 = 32'd8380417;

    wire [31:0] kem_lo_raw4;
    wire [31:0] kem_hi_raw4;
    array_schoolbook_unsigned_pipe4 #(.A_W(16), .B_W(16), .P_W(32)) u_kem_lo_mul (
        .clk_i(clk_i),
        .a_i(a_i[15:0]),
        .b_i(b_i[15:0]),
        .p_o(kem_lo_raw4)
    );
    array_schoolbook_unsigned_pipe4 #(.A_W(16), .B_W(16), .P_W(32)) u_kem_hi_mul (
        .clk_i(clk_i),
        .a_i(a_i[31:16]),
        .b_i(b_i[31:16]),
        .p_o(kem_hi_raw4)
    );

    wire [11:0] dsa_a0 = a_i[11:0];
    wire [10:0] dsa_a1 = a_i[22:12];
    wire [11:0] dsa_b0 = b_i[11:0];
    wire [10:0] dsa_b1 = b_i[22:12];
    wire [12:0] dsa_a_sum = {1'b0, dsa_a0} + {2'b0, dsa_a1};
    wire [12:0] dsa_b_sum = {1'b0, dsa_b0} + {2'b0, dsa_b1};

    wire [23:0] dsa_z0_4;
    wire [21:0] dsa_z1_4;
    wire [25:0] dsa_z2_4;
    array_schoolbook_unsigned_pipe4 #(.A_W(12), .B_W(12), .P_W(24)) u_dsa_m0 (
        .clk_i(clk_i),
        .a_i(dsa_a0),
        .b_i(dsa_b0),
        .p_o(dsa_z0_4)
    );
    array_schoolbook_unsigned_pipe4 #(.A_W(11), .B_W(11), .P_W(22)) u_dsa_m1 (
        .clk_i(clk_i),
        .a_i(dsa_a1),
        .b_i(dsa_b1),
        .p_o(dsa_z1_4)
    );
    array_schoolbook_unsigned_pipe4 #(.A_W(13), .B_W(13), .P_W(26)) u_dsa_m2 (
        .clk_i(clk_i),
        .a_i(dsa_a_sum),
        .b_i(dsa_b_sum),
        .p_o(dsa_z2_4)
    );

    function [11:0] kyber_barrett_t;
        input [23:0] a_v;
        reg [37:0] a_ext;
        reg [37:0] am_pos;
        reg [37:0] am_neg;
        reg [37:0] am;
        begin
            a_ext = {14'b0, a_v};
            am_pos = (a_ext << 14) + (a_ext << 12);
            am_neg = (a_ext << 8) + (a_ext << 6) + (a_ext << 1);
            am = am_pos - am_neg;
            kyber_barrett_t = am[37:26];
        end
    endfunction

    function [15:0] kyber_barrett_finish;
        input [11:0] a_low_v;
        input [11:0] t_v;
        reg [11:0] tq_l;
        reg [11:0] r0;
        reg [11:0] r1;
        begin
            tq_l = (t_v << 11) + (t_v << 10) + (t_v << 8) + t_v;
            r0 = a_low_v - tq_l;
            r1 = (r0 >= 12'd3329) ? (r0 - 12'd3329) : r0;
            kyber_barrett_finish = {4'b0, r1};
        end
    endfunction

    wire [25:0] dsa_mid4 = dsa_z2_4 - {2'b0, dsa_z0_4} - {4'b0, dsa_z1_4};
    wire [47:0] dsa_raw4 = ({26'b0, dsa_z1_4} << 24) +
                           ({22'b0, dsa_mid4} << 12) +
                           {24'b0, dsa_z0_4};

    reg [6:0]  opmode_d;
    reg [11:0] kem_lo_a5, kem_hi_a5;
    reg [11:0] kem_lo_t5, kem_hi_t5;
    reg [31:0] kem_out6, kem_out7;
    reg [47:0] dsa_raw5, dsa_raw6;
    reg [31:0] dsa_t6;
    reg signed [31:0] dsa_r7;
    reg [31:0] c_r;

    wire [63:0] dsa_low5 = {32'b0, dsa_raw5[31:0]};
    wire [63:0] dsa_qinv_prod5 = (dsa_low5 << 25) + (dsa_low5 << 24) +
                                 (dsa_low5 << 23) + (dsa_low5 << 13) +
                                 dsa_low5;
    wire [31:0] dsa_t5 = dsa_qinv_prod5[31:0];

    wire [63:0] dsa_t_ext6 = {32'b0, dsa_t6};
    wire [63:0] dsa_tq6 = (dsa_t_ext6 << 23) - (dsa_t_ext6 << 13) + dsa_t_ext6;
    wire [63:0] dsa_diff6 = {16'b0, dsa_raw6} - dsa_tq6;
    wire signed [31:0] dsa_r_signed6 = dsa_diff6[63:32];

    wire [31:0] dsa_r_nonneg7 = dsa_r7[31] ? (dsa_r7 + MLDSA_Q32) : dsa_r7;
    wire [31:0] dsa_r_minus_q7 = dsa_r_nonneg7 - MLDSA_Q32;
    wire [31:0] dsa_final7 = (dsa_r_nonneg7 >= MLDSA_Q32) ? dsa_r_minus_q7
                                                          : dsa_r_nonneg7;

    always @(posedge clk_i) begin
        opmode_d <= {opmode_d[5:0], opmode_i};

        kem_lo_a5 <= kem_lo_raw4[11:0];
        kem_hi_a5 <= kem_hi_raw4[11:0];
        kem_lo_t5 <= kyber_barrett_t(kem_lo_raw4[23:0]);
        kem_hi_t5 <= kyber_barrett_t(kem_hi_raw4[23:0]);
        kem_out6 <= {kyber_barrett_finish(kem_hi_a5, kem_hi_t5),
                     kyber_barrett_finish(kem_lo_a5, kem_lo_t5)};
        kem_out7 <= kem_out6;

        dsa_raw5 <= dsa_raw4;
        dsa_raw6 <= dsa_raw5;
        dsa_t6   <= dsa_t5;
        dsa_r7   <= dsa_r_signed6;

        c_r <= opmode_d[6] ? dsa_final7 : kem_out7;
    end

    assign c_o = c_r;
endmodule

`default_nettype wire
