// -----------------------------------------------------------------------------
// kyber_modsub16_csa.v
// ML-KEM modular 뺄셈 (논문 Figure 7, Eq.(8) / 핸드오버 §5.2,§7.2). 조합회로.
//   입력 계약: 0 <= a,b < q
//   d_t = a + (b̄ + 1)              // 2의 보수 a - b
//   d   = (a >= b) ? d_t : d_t + q  // underflow 시 q 보정
// 구조: CSA(a, ~b, 1) → ripple = d_t, 그리고 d_t + q 보정 경로를 select.
// -----------------------------------------------------------------------------
`default_nettype none

module kyber_modsub16_csa #(
    parameter integer Q     = 3329,
    parameter integer WIDTH = 16
)(
    input  wire [WIDTH-1:0] a_i,
    input  wire [WIDTH-1:0] b_i,
    output wire [WIDTH-1:0] c_o
);
    localparam integer VAL_W = 12;  // q=3329 < 2^12, lane 상위 4-bit는 container padding
    localparam integer DIFF_W = 13; // two's-complement subtract + q 보정용 2^13 ring
    localparam [DIFF_W-1:0] QW = Q[DIFF_W-1:0];

    wire [DIFF_W-1:0] a_v = {{(DIFF_W-VAL_W){1'b0}}, a_i[VAL_W-1:0]};
    wire [DIFF_W-1:0] b_v = {{(DIFF_W-VAL_W){1'b0}}, b_i[VAL_W-1:0]};

    // d_t = a + ~b + 1   (CSA 3-항 → ripple)
    wire [DIFF_W-1:0] ds;
    wire [DIFF_W:0]   dc;
    csa3_16 #(.WIDTH(DIFF_W)) u_csa (
        .x_i (a_v), .y_i (~b_v), .z_i ({{(DIFF_W-1){1'b0}}, 1'b1}),
        .sum_o (ds), .carry_o (dc)
    );
    wire [DIFF_W-1:0] dt;
    wire             dt_cout;
    ripple_adder #(.WIDTH(DIFF_W)) u_dt (
        .a_i (ds), .b_i (dc[DIFF_W-1:0]), .cin_i (1'b0),
        .sum_o (dt), .cout_o (dt_cout)
    );

    // d_t + q  (음수였을 때 보정)
    wire [DIFF_W-1:0] fix;
    wire             fix_cout;
    ripple_adder #(.WIDTH(DIFF_W)) u_fix (
        .a_i (dt), .b_i (QW), .cin_i (1'b0),
        .sum_o (fix), .cout_o (fix_cout)
    );

    wire a_ge_b = (a_v >= b_v);
    wire [DIFF_W-1:0] red = a_ge_b ? dt : fix;
    assign c_o = {{(WIDTH-VAL_W){1'b0}}, red[VAL_W-1:0]};
endmodule

`default_nettype wire
