// -----------------------------------------------------------------------------
// csa3_16.v
// 3:2 Carry-Save Adder (논문 Figure 6/7 CSA, 핸드오버 §5.2). 조합회로.
// 비트별 fa_cell 배열, 최종 carry-propagate 없음 → 결과는 redundant {sum,carry}.
//   sum[i]   = x[i]^y[i]^z[i]
//   carry    = majority(x,y,z) << 1   (carry[0]=0, carry 폭은 WIDTH+1)
// 소비측에서 ripple_adder 로 sum+carry 를 합쳐 정규 표현으로 만든다.
// WIDTH 기본 16 (ML-KEM 16-bit lane). 모듈명은 핸드오버 §4 레이아웃을 따른다.
// -----------------------------------------------------------------------------
`default_nettype none

module csa3_16 #(
    parameter integer WIDTH = 16
)(
    input  wire [WIDTH-1:0] x_i,
    input  wire [WIDTH-1:0] y_i,
    input  wire [WIDTH-1:0] z_i,
    output wire [WIDTH-1:0] sum_o,
    output wire [WIDTH:0]   carry_o
);
    wire [WIDTH-1:0] maj;   // 각 비트 자리올림 (majority)

    genvar i;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : g_fa
            fa_cell u_fa (
                .a_i     (x_i[i]),
                .b_i     (y_i[i]),
                .cin_i   (z_i[i]),
                .sum_o   (sum_o[i]),
                .carry_o (maj[i])
            );
        end
    endgenerate

    // carry 는 한 자리 왼쪽으로 이동 (CSA 항등식), carry[0]=0
    assign carry_o = {maj, 1'b0};
endmodule

`default_nettype wire
