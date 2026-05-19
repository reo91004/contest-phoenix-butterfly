// -----------------------------------------------------------------------------
// kyber_modadd16_csa.v
// ML-KEM modular 가산 (논문 Figure 6, Eq.(7) / 핸드오버 §5.2,§6.2). 조합회로.
//   입력 계약: 0 <= a,b < q   (16-bit lane container, 값은 12-bit 범위)
//   ct = a + b
//   c  = (ct >= q) ? ct - q : ct
// 구조: Fig.6 처럼 CSA 로 3-항 (a + b + (q̄+1)) 을 모은 뒤 ripple_adder 로
// carry-propagate, raw(a+b) 와 conditional select. q̄+1 = -q (2의 보수).
// -----------------------------------------------------------------------------
`default_nettype none

module kyber_modadd16_csa #(
    parameter integer Q     = 3329,
    parameter integer WIDTH = 16
)(
    input  wire [WIDTH-1:0] a_i,
    input  wire [WIDTH-1:0] b_i,
    output wire [WIDTH-1:0] c_o
);
    localparam integer VAL_W = 12;  // q=3329 < 2^12, lane 상위 4-bit는 container padding
    localparam integer SUM_W = 13;  // a+b < 2q < 2^13
    localparam [SUM_W-1:0] QW    = Q[SUM_W-1:0];
    localparam [SUM_W-1:0] NEG_Q = (~QW) + {{(SUM_W-1){1'b0}}, 1'b1}; // -q mod 2^SUM_W

    wire [SUM_W-1:0] a_v = {{(SUM_W-VAL_W){1'b0}}, a_i[VAL_W-1:0]};
    wire [SUM_W-1:0] b_v = {{(SUM_W-VAL_W){1'b0}}, b_i[VAL_W-1:0]};

    // raw = a + b  (SUM_W+1 비트로 비교)
    wire [SUM_W-1:0] raw_sum;
    wire             raw_cout;
    ripple_adder #(.WIDTH(SUM_W)) u_raw (
        .a_i (a_v), .b_i (b_v), .cin_i (1'b0),
        .sum_o (raw_sum), .cout_o (raw_cout)
    );
    wire [SUM_W:0] raw = {raw_cout, raw_sum};

    // corrected = a + b - q  via CSA(a,b,-q) → ripple
    wire [SUM_W-1:0] cs;
    wire [SUM_W:0]   cc;
    csa3_16 #(.WIDTH(SUM_W)) u_csa (
        .x_i (a_v), .y_i (b_v), .z_i (NEG_Q),
        .sum_o (cs), .carry_o (cc)
    );
    wire [SUM_W-1:0] corr;
    wire             corr_cout;
    ripple_adder #(.WIDTH(SUM_W)) u_corr (
        .a_i (cs), .b_i (cc[SUM_W-1:0]), .cin_i (1'b0),
        .sum_o (corr), .cout_o (corr_cout)
    );

    wire ge_q = (raw >= {1'b0, QW});
    wire [SUM_W-1:0] red = ge_q ? corr : raw_sum;
    assign c_o = {{(WIDTH-VAL_W){1'b0}}, red[VAL_W-1:0]};
endmodule

`default_nettype wire
