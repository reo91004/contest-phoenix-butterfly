// -----------------------------------------------------------------------------
// superbutterfly_sbu_routed.v
// Routed SBU for ML-KEM and ML-DSA. The COMP1/2/3/4 sharing shape and
// external 8-cycle latency are inherited from PHOENIX, while the removed
// binary-field modes are replaced by ML-DSA NTT, inverse NTT, and pointwise
// multiplication.
//
// Pipeline:
//   s1 : 입력 레지스터 + COMP2(Phase A) + COMP3 피연산자 mux
//   s2 : COMP3 곱결과 / COMP2 결과 / a,b,c,sel,valid 정렬 레지스터
//   s3-s7 : delay_line DEPTH=5 (datapath/valid 동기, 비활성 경로 포함 §12.2)
//   s7(comb) : COMP1/COMP4(Phase B) + 출력 mux
//   s8 : 출력 레지스터
//   latency = v_i →v1(+1)→v2(+1)→dV(+5)→vr(+1) = 8
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
    localparam [8:0] SEL_BLANK = `SBU_MOD_ADD;
    localparam       USE_PRD_INVALID_BLANKING = 1'b1;

    // Deterministic PRD source for invalid-cycle pipeline flushing. This is
    // public, unkeyed, and not a replacement for masking; it only prevents
    // invalid SBU stages from retaining the previous functional operands.
    reg [31:0] blank_lfsr;
    wire blank_lfsr_fb = blank_lfsr[31] ^ blank_lfsr[21] ^ blank_lfsr[1] ^ blank_lfsr[0];
    wire [31:0] blank_lfsr_next = {blank_lfsr[30:0], blank_lfsr_fb};
    wire [31:0] blank_a = blank_lfsr;
    wire [31:0] blank_b = {blank_lfsr[15:0], blank_lfsr[31:16]} ^ 32'hA5A55A5A;
    wire [31:0] blank_c = {blank_lfsr[7:0], blank_lfsr[31:8]} ^ 32'h3C6EF372;
    wire use_prd_blank = USE_PRD_INVALID_BLANKING && !valid_i && `SBU_OPMODE(sel_i);

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            blank_lfsr <= 32'h6D2B79F5;
        end else if (use_prd_blank) begin
            blank_lfsr <= blank_lfsr_next;
        end
    end

    // ===== s1: 입력 레지스터 =====
    reg [8:0]  sel1; reg [31:0] a1,b1,c1; reg v1;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin sel1<=9'b0;a1<=0;b1<=0;c1<=0;v1<=1'b0; end
        else if (valid_i) begin sel1<=sel_i;a1<=a_i;b1<=b_i;c1<=c_i;v1<=1'b1; end
        else if (use_prd_blank) begin
            sel1 <= sel_i;
            a1   <= blank_a;
            b1   <= blank_b;
            c1   <= blank_c;
            v1   <= 1'b0;
        end else begin sel1<=SEL_BLANK;a1<=32'b0;b1<=32'b0;c1<=32'b0;v1<=1'b0; end
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

    // ----- COMP3 (s1 to s2) : multiplier operand mux -----
    reg [31:0] mA, mB;
    always @* begin
        mA=c1; mB=b1;
        case (sel1)
            `SBU_PWM0    : begin mA={b1[15:0],a1[15:0]};  mB={b1[31:16],a1[31:16]}; end
            `SBU_PWM1    : begin mA={b1[31:16],a1[15:0]}; mB={c1[15:0], a1[31:16]}; end
            `SBU_INTT_GS,
            `SBU_MLDSA_INTT: begin mA=c1; mB=comp2_y; end
            default      : begin mA=c1; mB=b1; end
        endcase
    end
    wire [31:0] comp3_p;
    comp3_agile_modmul u_comp3 (.a_i(mA), .b_i(mB), .opmode_i(opmode1), .c_o(comp3_p));

    // ===== s2: COMP3/COMP2 결과 + 데이터 정렬 레지스터 =====
    reg [31:0] p2,q2,a2,b2,c2; reg [8:0] sel2; reg v2;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin p2<=0;q2<=0;a2<=0;b2<=0;c2<=0;sel2<=9'b0;v2<=1'b0; end
        else begin p2<=comp3_p; q2<=comp2_y; a2<=a1; b2<=b1; c2<=c1; sel2<=sel1; v2<=v1; end
    end

    // ===== s3..s7: 정렬 지연 (곱결과 p / COMP2결과 q / a / b / c / sel / valid) =====
    wire [31:0] p6,q6,a6,b6,c6; wire [8:0] sel6; wire v6;
    delay_line #(.WIDTH(32),.DEPTH(5)) dP (.clk_i(clk_i),.rst_ni(rst_ni),.d_i(p2),  .d_o(p6));
    delay_line #(.WIDTH(32),.DEPTH(5)) dQ (.clk_i(clk_i),.rst_ni(rst_ni),.d_i(q2),  .d_o(q6));
    delay_line #(.WIDTH(32),.DEPTH(5)) dA (.clk_i(clk_i),.rst_ni(rst_ni),.d_i(a2),  .d_o(a6));
    delay_line #(.WIDTH(32),.DEPTH(5)) dB (.clk_i(clk_i),.rst_ni(rst_ni),.d_i(b2),  .d_o(b6));
    delay_line #(.WIDTH(32),.DEPTH(5)) dC (.clk_i(clk_i),.rst_ni(rst_ni),.d_i(c2),  .d_o(c6));
    delay_line #(.WIDTH(9), .DEPTH(5)) dS (.clk_i(clk_i),.rst_ni(rst_ni),.d_i(sel2),.d_o(sel6));
    delay_line #(.WIDTH(1), .DEPTH(5)) dV (.clk_i(clk_i),.rst_ni(rst_ni),.d_i(v2),  .d_o(v6));

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
    wire [31:0] comp1_y;
    comp1_agile_modadd_div2 u_comp1 (
        .a_i(c1a), .b_i(c1b), .opmode_i(opmode6), .intt_i(c1_intt), .c_o(comp1_y)
    );

    // ----- COMP4 (Phase B) : post-multiply subtraction -----
    reg [31:0] c4a, c4b;
    always @* begin
        c4a=a6; c4b=p6;
        case (sel6)
            `SBU_PWM1    : begin c4a={16'b0,p6[15:0]};   c4b={16'b0,comp1_y[15:0]}; end
            default      : begin c4a=a6;                 c4b=p6;                  end
        endcase
    end
    wire [31:0] comp4_y;
    comp4_agile_modarith u_comp4 (
        .a_i(c4a), .b_i(c4b), .opmode_i(opmode6), .addsub_i(1'b1), .c_o(comp4_y)
    );

    // ----- 출력 mux (sel6) -----
    reg [31:0] y0p, y1p;
    always @* begin
        y0p=32'b0; y1p=32'b0;
        case (sel6)
            `SBU_NTT_CT,
            `SBU_MLDSA_NTT : begin y0p=comp1_y;                       y1p=comp4_y; end
            `SBU_INTT_GS,
            `SBU_MLDSA_INTT: begin y0p=comp1_y;                       y1p=p6;      end
            `SBU_PWM0    : begin y0p=comp1_y;                         y1p=p6;      end
            `SBU_PWM1    : begin y0p={comp4_y[15:0],comp1_y[31:16]};  y1p=32'b0;   end
            `SBU_MOD_ADD : begin y0p=comp1_y;                         y1p=32'b0;   end
            `SBU_MLDSA_PWM: begin y0p=p6;                             y1p=32'b0;   end
            default      : begin y0p=32'b0;                           y1p=32'b0;   end
        endcase
    end

    // ===== s8: 출력 레지스터 =====
    reg [31:0] y0r,y1r; reg vr;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin y0r<=0;y1r<=0;vr<=1'b0; end
        else if (v6) begin y0r<=y0p; y1r<=y1p; vr<=1'b1; end
        else begin y0r<=32'b0; y1r<=32'b0; vr<=1'b0; end
    end
    assign y0_o=y0r; assign y1_o=y1r; assign valid_o=vr;
endmodule

`default_nettype wire
