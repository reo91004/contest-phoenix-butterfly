// -----------------------------------------------------------------------------
// ripple_adder.v
// 파라미터화 Ripple-Carry Adder (multiplier MSb RCA / 최종 carry-propagate,
// 핸드오버 §5.2). fa_cell 체인으로 구성 — `+` 연산자 미사용 (REQ-RTL-002).
//   {cout, sum} = a + b + cin
// M0/M1 array-schoolbook 상위 비트 합산, modular 보정 가산에 재사용된다.
// -----------------------------------------------------------------------------
`default_nettype none

module ripple_adder #(
    parameter integer WIDTH = 16
)(
    input  wire [WIDTH-1:0] a_i,
    input  wire [WIDTH-1:0] b_i,
    input  wire             cin_i,
    output wire [WIDTH-1:0] sum_o,
    output wire             cout_o
);
    wire [WIDTH:0] carry;        // carry[0]=cin, carry[WIDTH]=cout
    assign carry[0] = cin_i;

    genvar i;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : g_fa
            fa_cell u_fa (
                .a_i     (a_i[i]),
                .b_i     (b_i[i]),
                .cin_i   (carry[i]),
                .sum_o   (sum_o[i]),
                .carry_o (carry[i+1])
            );
        end
    endgenerate

    assign cout_o = carry[WIDTH];
endmodule

`default_nettype wire
