// -----------------------------------------------------------------------------
// superbutterfly_sbu_routed.v
// Routed SBU for ML-KEM and ML-DSA. The COMP1/2/3/4 sharing shape and
// external latency is tracked by `SBU_LATENCY, while the removed
// binary-field modes are replaced by ML-DSA NTT, inverse NTT, and pointwise
// multiplication.
//
// Pipeline:
//   s1 : input register
//   s2 : COMP2(Phase A) result/data register
//   s3-s10 : registered COMP3 operand mux + pipelined multiply/reduce, with
//             aligned q/a/b/c/sel/valid delay
//   s11 : COMP1 input/control register
//   s12 : COMP1 result alignment register + COMP4/output mux
//   s13 : output register
//   latency = v_i -> v1(+1) -> v2(+1) -> dV(+8) -> v7(+1) -> v8(+1) -> vr(+1) = 13
// -----------------------------------------------------------------------------
`include "sbu_config.vh"
`default_nettype none

module superbutterfly_sbu_routed (
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
    // ===== s1: 입력 레지스터 =====
    reg [8:0]  sel1; reg [31:0] a1,b1,c1; reg v1;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin sel1<=9'b0;a1<=0;b1<=0;c1<=0;v1<=1'b0; end
        else begin sel1<=sel_i;a1<=a_i;b1<=b_i;c1<=c_i;v1<=valid_i; end
    end
    wire opmode1 = `SBU_OPMODE(sel1);

    // ----- COMP2 (Phase A) : pre-multiply subtraction for inverse transforms -----
    reg [31:0] c2a, c2b; reg c2_sub, c2_intt;
    always @* begin
        c2a=a1; c2b=b1; c2_sub=1'b0; c2_intt=1'b0;
        case (sel1)
            `SBU_INTT_GS,
            `SBU_MLDSA_INTT: begin c2a=b1; c2b=a1; c2_sub=1'b1; c2_intt=1'b1; end
            default: begin c2a=a1; c2b=b1; c2_sub=1'b0; c2_intt=1'b0; end
        endcase
    end
    wire [31:0] comp2_y;
    comp2_agile_modarith_div2 u_comp2 (
        .a_i(c2a), .b_i(c2b), .opmode_i(opmode1),
        .addsub_i(c2_sub), .intt_i(c2_intt), .c_o(comp2_y)
    );

    // ===== s2: COMP2 result / data alignment register =====
    reg [31:0] q2,a2,b2,c2; reg [8:0] sel2; reg v2;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            q2<=0; a2<=0; b2<=0; c2<=0; sel2<=9'b0; v2<=1'b0;
        end else begin
            q2<=comp2_y; a2<=a1; b2<=b1; c2<=c1; sel2<=sel1; v2<=v1;
        end
    end

    // Registering q2 before the COMP3 operand mux removes the previous
    // sel1 -> COMP2 carry chain -> mB2 endpoint path without changing latency.
    reg [31:0] mA2, mB2;
    always @* begin
        mA2=c2; mB2=b2;
        case (sel2)
            `SBU_PWM0    : begin mA2={b2[15:0],a2[15:0]};  mB2={b2[31:16],a2[31:16]}; end
            `SBU_PWM1    : begin mA2={b2[31:16],a2[15:0]}; mB2={c2[15:0], a2[31:16]}; end
            `SBU_INTT_GS,
            `SBU_MLDSA_INTT: begin mA2=c2; mB2=q2; end
            default      : begin mA2=c2; mB2=b2; end
        endcase
    end
    wire opmode2 = `SBU_OPMODE(sel2);

    wire [31:0] p6;
    comp3_agile_modmul_pipe u_comp3 (
        .clk_i(clk_i),
        .a_i(mA2),
        .b_i(mB2),
        .opmode_i(opmode2),
        .c_o(p6)
    );

    // ===== s3..s10: COMP3 pipe와 나머지 Phase-B 입력 정렬 =====
    wire [31:0] q6,a6,b6,c6; wire [8:0] sel6; wire v6;
    delay_line #(.WIDTH(32),.DEPTH(`SBU_COMP3_LATENCY),.RESETTABLE(0)) dQ (.clk_i(clk_i),.rst_ni(rst_ni),.d_i(q2),  .d_o(q6));
    delay_line #(.WIDTH(32),.DEPTH(`SBU_COMP3_LATENCY),.RESETTABLE(0)) dA (.clk_i(clk_i),.rst_ni(rst_ni),.d_i(a2),  .d_o(a6));
    delay_line #(.WIDTH(32),.DEPTH(`SBU_COMP3_LATENCY),.RESETTABLE(0)) dB (.clk_i(clk_i),.rst_ni(rst_ni),.d_i(b2),  .d_o(b6));
    delay_line #(.WIDTH(32),.DEPTH(`SBU_COMP3_LATENCY),.RESETTABLE(0)) dC (.clk_i(clk_i),.rst_ni(rst_ni),.d_i(c2),  .d_o(c6));
    delay_line #(.WIDTH(9), .DEPTH(`SBU_COMP3_LATENCY)) dS (.clk_i(clk_i),.rst_ni(rst_ni),.d_i(sel2),.d_o(sel6));
    delay_line #(.WIDTH(1), .DEPTH(`SBU_COMP3_LATENCY)) dV (.clk_i(clk_i),.rst_ni(rst_ni),.d_i(v2),  .d_o(v6));

    wire opmode6 = `SBU_OPMODE(sel6);

    // ----- COMP1 (Phase B) : post-multiply addition and optional scaling -----
    reg [31:0] c1a, c1b; reg c1_intt;
    always @* begin
        c1a=a6; c1b=b6; c1_intt=1'b0;
        case (sel6)
            `SBU_NTT_CT,
            `SBU_MLDSA_NTT : begin c1a=a6; c1b=p6; c1_intt=1'b0; end
            `SBU_INTT_GS,
            `SBU_MLDSA_INTT: begin c1a=a6; c1b=b6; c1_intt=1'b1; end
            `SBU_PWM1    : begin c1a={b6[15:0],b6[15:0]}; c1b={p6[31:16],b6[31:16]}; c1_intt=1'b0; end
            default      : begin c1a=a6; c1b=b6; c1_intt=1'b0; end
        endcase
    end

    // Split the Phase-B select/mux cone from the modular arithmetic carry chain.
    reg [31:0] c1a7, c1b7, p7, a7;
    reg [8:0]  sel7;
    reg        opmode7, c1_intt7, v7;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            c1a7 <= 0; c1b7 <= 0; p7 <= 0; a7 <= 0;
            sel7 <= 9'b0; opmode7 <= 1'b0; c1_intt7 <= 1'b0; v7 <= 1'b0;
        end else begin
            c1a7     <= c1a;
            c1b7     <= c1b;
            p7       <= p6;
            a7       <= a6;
            sel7     <= sel6;
            opmode7  <= opmode6;
            c1_intt7 <= c1_intt;
            v7       <= v6;
        end
    end

    wire [31:0] comp1_y;
    comp1_agile_modadd_div2 u_comp1 (
        .a_i(c1a7), .b_i(c1b7), .opmode_i(opmode7), .intt_i(c1_intt7), .c_o(comp1_y)
    );

    // ----- Phase-B register: split COMP1 and COMP4/PWM1 dependency -----
    reg [31:0] comp1_y8, p8, a8;
    reg [8:0]  sel8;
    reg        v8;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            comp1_y8 <= 0; p8 <= 0; a8 <= 0; sel8 <= 9'b0; v8 <= 1'b0;
        end else begin
            comp1_y8 <= comp1_y;
            p8       <= p7;
            a8       <= a7;
            sel8     <= sel7;
            v8       <= v7;
        end
    end

    // ----- COMP4 (Phase B) : post-multiply subtraction -----
    reg [31:0] c4a, c4b;
    always @* begin
        c4a=a8; c4b=p8;
        case (sel8)
            `SBU_PWM1    : begin c4a={16'b0,p8[15:0]};   c4b={16'b0,comp1_y8[15:0]}; end
            default      : begin c4a=a8;                 c4b=p8;                  end
        endcase
    end
    wire opmode8 = `SBU_OPMODE(sel8);
    wire [31:0] comp4_y;
    comp4_agile_modarith u_comp4 (
        .a_i(c4a), .b_i(c4b), .opmode_i(opmode8), .addsub_i(1'b1), .c_o(comp4_y)
    );

    // ----- 출력 mux (sel8) -----
    reg [31:0] y0p, y1p;
    always @* begin
        y0p=32'b0; y1p=32'b0;
        case (sel8)
            `SBU_NTT_CT,
            `SBU_MLDSA_NTT : begin y0p=comp1_y8;                      y1p=comp4_y; end
            `SBU_INTT_GS,
            `SBU_MLDSA_INTT: begin y0p=comp1_y8;                      y1p=p8;      end
            `SBU_PWM0    : begin y0p=comp1_y8;                        y1p=p8;      end
            `SBU_PWM1    : begin y0p={comp4_y[15:0],comp1_y8[31:16]}; y1p=32'b0;   end
            `SBU_MOD_ADD : begin y0p=comp1_y8;                        y1p=32'b0;   end
            `SBU_MLDSA_PWM: begin y0p=p8;                             y1p=32'b0;   end
            default      : begin y0p=32'b0;                           y1p=32'b0;   end
        endcase
    end

    // ===== s13: output register =====
    reg [31:0] y0r,y1r; reg vr;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin y0r<=0;y1r<=0;vr<=1'b0; end
        else begin y0r<=y0p; y1r<=y1p; vr<=v8; end
    end
    assign y0_o=y0r; assign y1_o=y1r; assign valid_o=vr;
endmodule

`default_nettype wire
