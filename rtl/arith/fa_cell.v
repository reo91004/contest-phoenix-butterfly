// -----------------------------------------------------------------------------
// fa_cell.v
// 1-bit 전가산기 (primitive, 핸드오버 §5.2). 조합회로.
//   sum   = a ^ b ^ cin
//   carry = (a & b) | (a & cin) | (b & cin)   (majority)
// 검증: 입력 8가지 exhaustive. M0/M1 array-schoolbook, CSA, RCA 의 기본 셀.
// -----------------------------------------------------------------------------
`default_nettype none

module fa_cell (
    input  wire a_i,
    input  wire b_i,
    input  wire cin_i,
    output wire sum_o,
    output wire carry_o
);
    assign sum_o   = a_i ^ b_i ^ cin_i;
    assign carry_o = (a_i & b_i) | (a_i & cin_i) | (b_i & cin_i);
endmodule

`default_nettype wire
