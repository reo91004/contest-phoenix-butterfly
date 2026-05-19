// -----------------------------------------------------------------------------
// kyber_div2_16.v
// ML-KEM modular division-by-2 (논문 Figure 6/7 div2 / 핸드오버 §5.2,§6.3).
//   c = (a >> 1) + (a[0] ? (q+1)/2 : 0)
// 절대 단순 a>>1 로 처리하지 않는다 (REQ / 오류 3). 입력 계약: 0 <= a < q.
// INTT_GS butterfly per-stage 정규화(sel[6]=intt)에 쓰인다. 조합회로.
// -----------------------------------------------------------------------------
`default_nettype none

module kyber_div2_16 #(
    parameter integer Q     = 3329,
    parameter integer WIDTH = 16
)(
    input  wire [WIDTH-1:0] a_i,
    output wire [WIDTH-1:0] c_o
);
    localparam integer VAL_W = 12;                 // q=3329 < 2^12
    localparam [VAL_W-1:0] HALF_Q = (Q + 1) / 2;   // 1665 (q=3329)

    wire [VAL_W-1:0] a_v     = a_i[VAL_W-1:0];
    wire [VAL_W-1:0] shifted = {1'b0, a_v[VAL_W-1:1]};
    wire [VAL_W-1:0] addend  = a_v[0] ? HALF_Q : {VAL_W{1'b0}};

    wire [VAL_W-1:0] sum;
    wire             sum_cout;
    ripple_adder #(.WIDTH(VAL_W)) u_add (
        .a_i (shifted), .b_i (addend), .cin_i (1'b0),
        .sum_o (sum), .cout_o (sum_cout)
    );

    // 입력 0<=a<q 이면 최대 (3327>>1)+1665 = 3328 < q 이므로 보정 subtract 불필요.
    assign c_o = {{(WIDTH-VAL_W){1'b0}}, sum};
endmodule

`default_nettype wire
