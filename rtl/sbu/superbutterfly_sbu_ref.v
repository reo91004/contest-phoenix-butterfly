// -----------------------------------------------------------------------------
// superbutterfly_sbu_ref.v
// Functional SBU reference for ML-KEM and ML-DSA modes. It mirrors the routed
// SBU equations directly and delays outputs by eight cycles.
// -----------------------------------------------------------------------------
`include "sbu_config.vh"
`default_nettype none

module superbutterfly_sbu_ref (
    input  wire        clk_i,
    input  wire        rst_ni,
    input  wire        valid_i,
    input  wire [8:0]  sel_i,
    input  wire [31:0] a_i,
    input  wire [31:0] b_i,
    input  wire [31:0] c_i,
    output wire        valid_o,
    output wire [31:0] y0_o,
    output wire [31:0] y1_o
);
    wire opmode = `SBU_OPMODE(sel_i);

    wire [31:0] pre_sub_scaled;
    comp2_agile_modarith_div2 u_pre_sub (
        .a_i(b_i),
        .b_i(a_i),
        .opmode_i(opmode),
        .addsub_i(1'b1),
        .intt_i(1'b1),
        .c_o(pre_sub_scaled)
    );

    reg [31:0] mul_a;
    reg [31:0] mul_b;
    always @* begin
        mul_a = c_i;
        mul_b = b_i;
        case (sel_i)
            `SBU_INTT_GS,
            `SBU_MLDSA_INTT: begin
                mul_a = c_i;
                mul_b = pre_sub_scaled;
            end
            `SBU_PWM0: begin
                mul_a = {b_i[15:0],  a_i[15:0]};
                mul_b = {b_i[31:16], a_i[31:16]};
            end
            `SBU_PWM1: begin
                mul_a = {b_i[31:16], a_i[15:0]};
                mul_b = {c_i[15:0],  a_i[31:16]};
            end
            default: begin
                mul_a = c_i;
                mul_b = b_i;
            end
        endcase
    end

    wire [31:0] prod;
    comp3_agile_modmul u_mul (
        .a_i(mul_a),
        .b_i(mul_b),
        .opmode_i(opmode),
        .c_o(prod)
    );

    wire [31:0] add_ab;
    comp1_agile_modadd_div2 u_add_ab (
        .a_i(a_i),
        .b_i(b_i),
        .opmode_i(opmode),
        .intt_i(1'b0),
        .c_o(add_ab)
    );

    wire [31:0] ct_add;
    comp1_agile_modadd_div2 u_ct_add (
        .a_i(a_i),
        .b_i(prod),
        .opmode_i(opmode),
        .intt_i(1'b0),
        .c_o(ct_add)
    );

    wire [31:0] ct_sub;
    comp4_agile_modarith u_ct_sub (
        .a_i(a_i),
        .b_i(prod),
        .opmode_i(opmode),
        .addsub_i(1'b1),
        .c_o(ct_sub)
    );

    wire [31:0] gs_add_scaled;
    comp1_agile_modadd_div2 u_gs_add (
        .a_i(a_i),
        .b_i(b_i),
        .opmode_i(opmode),
        .intt_i(1'b1),
        .c_o(gs_add_scaled)
    );

    wire [31:0] pwm1_add;
    comp1_agile_modadd_div2 u_pwm1_add (
        .a_i({b_i[15:0], b_i[15:0]}),
        .b_i({prod[31:16], b_i[31:16]}),
        .opmode_i(1'b0),
        .intt_i(1'b0),
        .c_o(pwm1_add)
    );

    wire [31:0] pwm1_sub;
    comp4_agile_modarith u_pwm1_sub (
        .a_i({16'b0, prod[15:0]}),
        .b_i({16'b0, pwm1_add[15:0]}),
        .opmode_i(1'b0),
        .addsub_i(1'b1),
        .c_o(pwm1_sub)
    );

    reg [31:0] y0c;
    reg [31:0] y1c;
    always @* begin
        y0c = 32'b0;
        y1c = 32'b0;
        case (sel_i)
            `SBU_NTT_CT,
            `SBU_MLDSA_NTT: begin
                y0c = ct_add;
                y1c = ct_sub;
            end
            `SBU_INTT_GS,
            `SBU_MLDSA_INTT: begin
                y0c = gs_add_scaled;
                y1c = prod;
            end
            `SBU_MOD_ADD: begin
                y0c = add_ab;
                y1c = 32'b0;
            end
            `SBU_PWM0: begin
                y0c = add_ab;
                y1c = prod;
            end
            `SBU_PWM1: begin
                y0c = {pwm1_sub[15:0], pwm1_add[31:16]};
                y1c = 32'b0;
            end
            `SBU_MLDSA_PWM: begin
                y0c = prod;
                y1c = 32'b0;
            end
            default: begin
                y0c = 32'b0;
                y1c = 32'b0;
            end
        endcase
    end

    delay_line #(.WIDTH(1),  .DEPTH(8)) u_dv (.clk_i(clk_i), .rst_ni(rst_ni), .d_i(valid_i), .d_o(valid_o));
    delay_line #(.WIDTH(32), .DEPTH(8)) u_d0 (.clk_i(clk_i), .rst_ni(rst_ni), .d_i(y0c),     .d_o(y0_o));
    delay_line #(.WIDTH(32), .DEPTH(8)) u_d1 (.clk_i(clk_i), .rst_ni(rst_ni), .d_i(y1c),     .d_o(y1_o));
endmodule

`default_nettype wire
