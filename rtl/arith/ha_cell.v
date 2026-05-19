// -----------------------------------------------------------------------------
// ha_cell.v
// 1-bit 반가산기 (primitive, 핸드오버 §5.2). 조합회로.
//   sum   = a ^ b
//   carry = a & b
// 검증: 입력 4가지 exhaustive.
// -----------------------------------------------------------------------------
`default_nettype none

module ha_cell (
    input  wire a_i,
    input  wire b_i,
    output wire sum_o,
    output wire carry_o
);
    assign sum_o   = a_i ^ b_i;   // 합 비트
    assign carry_o = a_i & b_i;   // 자리올림
endmodule

`default_nettype wire
