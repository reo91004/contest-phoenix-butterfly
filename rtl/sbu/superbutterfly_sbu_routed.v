// -----------------------------------------------------------------------------
// superbutterfly_sbu_routed.v
// Routed SBU for ML-KEM and ML-DSA. The COMP1/2/3/4 sharing shape and
// external 8-cycle latency are inherited from PHOENIX, while the removed
// binary-field modes are replaced by ML-DSA NTT, inverse NTT, and pointwise
// multiplication.
//
// Pipeline:
//   s1 : 입력 레지스터 + COMP2(Phase A) + COMP3 피연산자 mux
//   s2 : legacy COMP3/COMP2 결과, a/b/c/control 정렬 레지스터
//        masked ML-KEM/ML-DSA COMP3는 내부 partial-product register를 함께 사용
//   s3 : masked COMP3 출력과 legacy datapath/control을 한 단계 재정렬
//   s4-s7 : delay_line DEPTH=4 (datapath/valid 동기, 비활성 경로 포함 §12.2)
//   s7(comb) : COMP1/COMP4(Phase B) + 출력 mux
//   s8 : 출력 레지스터
//   latency = v_i →v1(+1)→v2(+1)→v3(+1)→dV(+4)→vr(+1) = 8
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
    input  wire [31:0] a_mask_i,
    input  wire [31:0] b_mask_i,
    input  wire [31:0] c_mask_i,
    input  wire [31:0] rand_i,
    output wire        valid_o,
    output wire [31:0] y0_o,
    output wire [31:0] y1_o,
    output wire [31:0] y0_mask_o,
    output wire [31:0] y1_mask_o
);
    localparam [8:0] SEL_BLANK = `SBU_MOD_ADD;
    localparam       USE_PRD_INVALID_BLANKING = 1'b1;
    localparam       USE_PRD_COMP3_INTERNAL_DUMMY = 1'b1;

    // Deterministic PRD source for invalid-cycle pipeline flushing. This is
    // public, unkeyed, and not a replacement for masking; it only prevents
    // invalid SBU stages from retaining the previous functional operands.
    reg [31:0] blank_lfsr;
    wire blank_lfsr_fb = blank_lfsr[31] ^ blank_lfsr[21] ^ blank_lfsr[1] ^ blank_lfsr[0];
    wire [31:0] blank_lfsr_next = {blank_lfsr[30:0], blank_lfsr_fb};
    wire [31:0] blank_a = blank_lfsr;
    wire [31:0] blank_b = {blank_lfsr[15:0], blank_lfsr[31:16]} ^ 32'hA5A55A5A;
    wire [31:0] blank_c = {blank_lfsr[7:0], blank_lfsr[31:8]} ^ 32'h3C6EF372;
    wire use_prd_candidate = `SBU_OPMODE(sel_i);
    wire use_prd_blank = USE_PRD_INVALID_BLANKING && !valid_i && use_prd_candidate;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            blank_lfsr <= 32'h6D2B79F5;
        end else if (use_prd_blank) begin
            blank_lfsr <= blank_lfsr_next;
        end
    end

    // ===== s1: 입력 레지스터 =====
    reg [8:0]  sel1; reg [31:0] a1,b1,c1,a1m,b1m,c1m,r1; reg v1;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin sel1<=9'b0;a1<=0;b1<=0;c1<=0;a1m<=0;b1m<=0;c1m<=0;r1<=0;v1<=1'b0; end
        else if (valid_i) begin
            sel1<=sel_i;a1<=a_i;b1<=b_i;c1<=c_i;
            a1m<=a_mask_i;b1m<=b_mask_i;c1m<=c_mask_i;r1<=rand_i;
            v1<=1'b1;
        end
        else if (use_prd_blank) begin
            sel1 <= sel_i;
            a1   <= blank_a;
            b1   <= blank_b;
            c1   <= blank_c;
            a1m  <= 32'b0;
            b1m  <= 32'b0;
            c1m  <= 32'b0;
            r1   <= 32'b0;
            v1   <= 1'b0;
        end else begin sel1<=SEL_BLANK;a1<=32'b0;b1<=32'b0;c1<=32'b0;a1m<=32'b0;b1m<=32'b0;c1m<=32'b0;r1<=32'b0;v1<=1'b0; end
    end
    wire opmode1 = `SBU_OPMODE(sel1);

    // Public dummy source for COMP3 internal inactive sub-cone experiments.
    // Stage 2 of this matrix uses it only inside COMP3's inactive DSA
    // Karatsuba cone during ML-KEM mode; active output paths stay real.
    reg [31:0] comp3_internal_dummy_lfsr;
    wire comp3_internal_dummy_fb = comp3_internal_dummy_lfsr[31] ^
                                   comp3_internal_dummy_lfsr[22] ^
                                   comp3_internal_dummy_lfsr[2] ^
                                   comp3_internal_dummy_lfsr[1];
    wire [31:0] comp3_internal_dummy_next =
        {comp3_internal_dummy_lfsr[30:0], comp3_internal_dummy_fb};
    wire [31:0] comp3_internal_dummy_a = USE_PRD_COMP3_INTERNAL_DUMMY ?
                                         comp3_internal_dummy_lfsr : 32'b0;
    wire [31:0] comp3_internal_dummy_b = USE_PRD_COMP3_INTERNAL_DUMMY ?
                                         ({comp3_internal_dummy_lfsr[14:0],
                                           comp3_internal_dummy_lfsr[31:15]} ^
                                          32'hB4BCD35C) : 32'b0;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            comp3_internal_dummy_lfsr <= 32'h243F6A88;
        end else if (valid_i) begin
            comp3_internal_dummy_lfsr <= comp3_internal_dummy_next;
        end
    end

    // ----- COMP2 (Phase A) : pre-multiply subtraction for inverse transforms -----
    reg [31:0] c2a, c2b; reg c2_sub, c2_intt;
    always @* begin
        c2a=32'b0; c2b=32'b0; c2_sub=1'b0; c2_intt=1'b0;
        case (sel1)
            `SBU_INTT_GS,
            `SBU_MLDSA_INTT: begin c2a=b1; c2b=a1; c2_sub=1'b1; c2_intt=1'b1; end
            default: begin c2a=32'b0; c2b=32'b0; c2_sub=1'b0; c2_intt=1'b0; end
        endcase
    end
    wire [31:0] comp2_y;
    comp2_agile_modarith_div2 u_comp2 (
        .a_i(c2a), .b_i(c2b),
        .opmode_i(opmode1),
        .addsub_i(c2_sub), .intt_i(c2_intt), .c_o(comp2_y)
    );

    reg [31:0] c2am, c2bm;
    always @* begin
        c2am=32'b0; c2bm=32'b0;
        case (sel1)
            `SBU_INTT_GS,
            `SBU_MLDSA_INTT: begin c2am=b1m; c2bm=a1m; end
            default: begin c2am=32'b0; c2bm=32'b0; end
        endcase
    end
    wire [31:0] comp2m_y;
    comp2_agile_modarith_div2 u_comp2_mask (
        .a_i(c2am), .b_i(c2bm),
        .opmode_i(opmode1),
        .addsub_i(c2_sub), .intt_i(c2_intt), .c_o(comp2m_y)
    );

    // ----- COMP3 (s1 to s2) : multiplier operand mux -----
    reg [31:0] mA, mB;
    reg [31:0] mAm, mBm;
    reg        m_mask_lo, m_mask_hi, m_mask_dsa;
    always @* begin
        mA=c1; mB=b1;
        mAm=c1m; mBm=b1m; m_mask_lo=1'b0; m_mask_hi=1'b0; m_mask_dsa=1'b0;
        case (sel1)
            `SBU_PWM0    : begin
                mA={b1[15:0],a1[15:0]};  mB={b1[31:16],a1[31:16]};
                mAm={b1m[15:0],a1m[15:0]}; mBm={b1m[31:16],a1m[31:16]};
                m_mask_lo=1'b1; m_mask_hi=1'b1;
            end
            `SBU_PWM1    : begin
                mA={b1[31:16],a1[15:0]}; mB={c1[15:0], a1[31:16]};
                mAm={b1m[31:16],a1m[15:0]}; mBm={c1m[15:0], a1m[31:16]};
                m_mask_lo=1'b1; m_mask_hi=1'b0;
            end
            `SBU_INTT_GS,
            `SBU_MLDSA_INTT: begin mA=c1; mB=comp2_y; mAm=c1m; mBm=comp2m_y; end
            `SBU_MLDSA_PWM: begin mA=c1; mB=b1; mAm=c1m; mBm=b1m; m_mask_dsa=1'b1; end
            default      : begin mA=c1; mB=b1; mAm=c1m; mBm=b1m; end
        endcase
    end
    wire [31:0] comp3_p;
    comp3_agile_modmul u_comp3 (
        .a_i(32'b0),
        .b_i(32'b0),
        .dummy_a_i(comp3_internal_dummy_a),
        .dummy_b_i(comp3_internal_dummy_b),
        .opmode_i(opmode1),
        .c_o(comp3_p)
    );

    wire [31:0] comp3_mask_p0;
    wire [31:0] comp3_mask_p1;
    comp3_mlkem_masked_mul_pipe u_comp3_mask (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .a0_i(mA),
        .b0_i(mB),
        .a1_i(mAm),
        .b1_i(mBm),
        .rand_i(r1),
        .mask_lo_i(m_mask_lo),
        .mask_hi_i(m_mask_hi),
        .p0_o(comp3_mask_p0),
        .p1_o(comp3_mask_p1)
    );

    wire [31:0] comp3_dsa_mask_p0;
    wire [31:0] comp3_dsa_mask_p1;
    comp3_mldsa_masked_mul_pipe u_comp3_dsa_mask (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .a0_i(mA),
        .b0_i(mB),
        .a1_i(mAm),
        .b1_i(mBm),
        .rand_i(r1),
        .mask_i(m_mask_dsa),
        .p0_o(comp3_dsa_mask_p0),
        .p1_o(comp3_dsa_mask_p1)
    );

    // ===== s2: COMP3/COMP2 결과 + 데이터 정렬 레지스터 =====
    reg [31:0] p2,q2,a2,b2,c2,p2m,q2m,a2m,b2m,c2m; reg [8:0] sel2; reg v2;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin p2<=0;q2<=0;a2<=0;b2<=0;c2<=0;p2m<=0;q2m<=0;a2m<=0;b2m<=0;c2m<=0;sel2<=9'b0;v2<=1'b0; end
        else begin
            p2<=comp3_p; q2<=comp2_y; a2<=a1; b2<=b1; c2<=c1;
            p2m<=32'b0; q2m<=comp2m_y; a2m<=a1m; b2m<=b1m; c2m<=c1m;
            sel2<=sel1; v2<=v1;
        end
    end
    wire opmode2 = `SBU_OPMODE(sel2);

    // ===== s3: pipelined ML-KEM masked COMP3 output alignment =====
    reg [31:0] p3,q3,a3,b3,c3,p3m,q3m,a3m,b3m,c3m; reg [8:0] sel3; reg v3;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            p3<=0;q3<=0;a3<=0;b3<=0;c3<=0;p3m<=0;q3m<=0;a3m<=0;b3m<=0;c3m<=0;sel3<=9'b0;v3<=1'b0;
        end else begin
            p3 <= opmode2 ? comp3_dsa_mask_p0 : comp3_mask_p0;
            q3 <= q2;
            a3 <= a2;
            b3 <= b2;
            c3 <= c2;
            p3m <= opmode2 ? comp3_dsa_mask_p1 : comp3_mask_p1;
            q3m <= q2m;
            a3m <= a2m;
            b3m <= b2m;
            c3m <= c2m;
            sel3 <= sel2;
            v3 <= v2;
        end
    end

    // ===== s4..s7: 정렬 지연 (곱결과 p / COMP2결과 q / a / b / c / sel / valid) =====
    wire [31:0] p6,q6,a6,b6,c6,p6m,q6m,a6m,b6m,c6m; wire [8:0] sel6; wire v6;
    delay_line #(.WIDTH(32),.DEPTH(4)) dP (.clk_i(clk_i),.rst_ni(rst_ni),.d_i(p3),  .d_o(p6));
    delay_line #(.WIDTH(32),.DEPTH(4)) dQ (.clk_i(clk_i),.rst_ni(rst_ni),.d_i(q3),  .d_o(q6));
    delay_line #(.WIDTH(32),.DEPTH(4)) dA (.clk_i(clk_i),.rst_ni(rst_ni),.d_i(a3),  .d_o(a6));
    delay_line #(.WIDTH(32),.DEPTH(4)) dB (.clk_i(clk_i),.rst_ni(rst_ni),.d_i(b3),  .d_o(b6));
    delay_line #(.WIDTH(32),.DEPTH(4)) dC (.clk_i(clk_i),.rst_ni(rst_ni),.d_i(c3),  .d_o(c6));
    delay_line #(.WIDTH(32),.DEPTH(4)) dPm (.clk_i(clk_i),.rst_ni(rst_ni),.d_i(p3m), .d_o(p6m));
    delay_line #(.WIDTH(32),.DEPTH(4)) dQm (.clk_i(clk_i),.rst_ni(rst_ni),.d_i(q3m), .d_o(q6m));
    delay_line #(.WIDTH(32),.DEPTH(4)) dAm (.clk_i(clk_i),.rst_ni(rst_ni),.d_i(a3m), .d_o(a6m));
    delay_line #(.WIDTH(32),.DEPTH(4)) dBm (.clk_i(clk_i),.rst_ni(rst_ni),.d_i(b3m), .d_o(b6m));
    delay_line #(.WIDTH(32),.DEPTH(4)) dCm (.clk_i(clk_i),.rst_ni(rst_ni),.d_i(c3m), .d_o(c6m));
    delay_line #(.WIDTH(9), .DEPTH(4)) dS (.clk_i(clk_i),.rst_ni(rst_ni),.d_i(sel3),.d_o(sel6));
    delay_line #(.WIDTH(1), .DEPTH(4)) dV (.clk_i(clk_i),.rst_ni(rst_ni),.d_i(v3),  .d_o(v6));

    wire opmode6 = `SBU_OPMODE(sel6);

    // ----- COMP1 (Phase B) : post-multiply addition and optional scaling -----
    reg [31:0] c1a, c1b; reg c1_intt;
    always @* begin
        c1a=32'b0; c1b=32'b0; c1_intt=1'b0;
        case (sel6)
            `SBU_NTT_CT,
            `SBU_MLDSA_NTT : begin c1a=a6; c1b=p6; c1_intt=1'b0; end
            `SBU_INTT_GS,
            `SBU_MLDSA_INTT: begin c1a=a6; c1b=b6; c1_intt=1'b1; end
            `SBU_PWM1    : begin c1a={b6[15:0],b6[15:0]}; c1b={p6[31:16],b6[31:16]}; c1_intt=1'b0; end
            `SBU_PWM0,
            `SBU_MOD_ADD : begin c1a=a6; c1b=b6; c1_intt=1'b0; end
            default      : begin c1a=32'b0; c1b=32'b0; c1_intt=1'b0; end
        endcase
    end
    wire [31:0] comp1_y;
    comp1_agile_modadd_div2 u_comp1 (
        .a_i(c1a), .b_i(c1b), .opmode_i(opmode6), .intt_i(c1_intt), .c_o(comp1_y)
    );

    reg [31:0] c1am, c1bm; reg c1m_intt;
    always @* begin
        c1am=32'b0; c1bm=32'b0; c1m_intt=1'b0;
        case (sel6)
            `SBU_NTT_CT,
            `SBU_MLDSA_NTT : begin c1am=a6m; c1bm=p6m; c1m_intt=1'b0; end
            `SBU_INTT_GS,
            `SBU_MLDSA_INTT: begin c1am=a6m; c1bm=b6m; c1m_intt=1'b1; end
            `SBU_PWM1   : begin c1am={b6m[15:0],b6m[15:0]}; c1bm={p6m[31:16],b6m[31:16]}; c1m_intt=1'b0; end
            `SBU_PWM0,
            `SBU_MOD_ADD: begin c1am=a6m; c1bm=b6m; c1m_intt=1'b0; end
            default     : begin c1am=32'b0; c1bm=32'b0; c1m_intt=1'b0; end
        endcase
    end
    wire [31:0] comp1m_y;
    comp1_agile_modadd_div2 u_comp1_mask (
        .a_i(c1am), .b_i(c1bm), .opmode_i(opmode6), .intt_i(c1m_intt), .c_o(comp1m_y)
    );

    // ----- COMP4 (Phase B) : post-multiply subtraction -----
    reg [31:0] c4a, c4b;
    always @* begin
        c4a=32'b0; c4b=32'b0;
        case (sel6)
            `SBU_NTT_CT,
            `SBU_MLDSA_NTT : begin c4a=a6;                 c4b=p6;                  end
            `SBU_INTT_GS   : begin c4a=a6;                 c4b=p6;                  end
            `SBU_PWM1    : begin c4a={16'b0,p6[15:0]};   c4b={16'b0,comp1_y[15:0]}; end
            default      : begin c4a=32'b0;              c4b=32'b0;               end
        endcase
    end
    wire [31:0] comp4_y;
    comp4_agile_modarith u_comp4 (
        .a_i(c4a), .b_i(c4b), .opmode_i(opmode6), .addsub_i(1'b1), .c_o(comp4_y)
    );

    reg [31:0] c4am, c4bm;
    always @* begin
        c4am=32'b0; c4bm=32'b0;
        case (sel6)
            `SBU_NTT_CT,
            `SBU_MLDSA_NTT: begin c4am=a6m;             c4bm=p6m;                   end
            `SBU_INTT_GS: begin c4am=a6m;                c4bm=p6m;                   end
            `SBU_PWM1   : begin c4am={16'b0,p6m[15:0]}; c4bm={16'b0,comp1m_y[15:0]}; end
            default     : begin c4am=32'b0;              c4bm=32'b0;                 end
        endcase
    end
    wire [31:0] comp4m_y;
    comp4_agile_modarith u_comp4_mask (
        .a_i(c4am), .b_i(c4bm), .opmode_i(opmode6), .addsub_i(1'b1), .c_o(comp4m_y)
    );

    // ----- 출력 mux (sel6) -----
    reg [31:0] y0p, y1p, y0pm, y1pm;
    always @* begin
        y0p=32'b0; y1p=32'b0; y0pm=32'b0; y1pm=32'b0;
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
        case (sel6)
            `SBU_NTT_CT,
            `SBU_MLDSA_NTT : begin y0pm=comp1m_y;                    y1pm=comp4m_y; end
            `SBU_INTT_GS,
            `SBU_MLDSA_INTT: begin y0pm=comp1m_y;                    y1pm=p6m;      end
            `SBU_PWM0   : begin y0pm=comp1m_y;                       y1pm=p6m;      end
            `SBU_PWM1   : begin y0pm={comp4m_y[15:0],comp1m_y[31:16]}; y1pm=32'b0;  end
            `SBU_MOD_ADD: begin y0pm=comp1m_y;                       y1pm=32'b0;    end
            `SBU_MLDSA_PWM: begin y0pm=p6m;                          y1pm=32'b0;    end
            default     : begin y0pm=32'b0;                          y1pm=32'b0;    end
        endcase
    end

    // ===== s8: 출력 레지스터 =====
    reg [31:0] y0r,y1r,y0mr,y1mr; reg vr;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin y0r<=0;y1r<=0;y0mr<=0;y1mr<=0;vr<=1'b0; end
        else if (v6) begin y0r<=y0p; y1r<=y1p; y0mr<=y0pm; y1mr<=y1pm; vr<=1'b1; end
        else begin y0r<=32'b0; y1r<=32'b0; y0mr<=32'b0; y1mr<=32'b0; vr<=1'b0; end
    end
    assign y0_o=y0r; assign y1_o=y1r; assign y0_mask_o=y0mr; assign y1_mask_o=y1mr; assign valid_o=vr;
endmodule

`default_nettype wire
