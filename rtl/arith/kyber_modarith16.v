// -----------------------------------------------------------------------------
// kyber_modarith16.v
// ML-KEM 16-bit lane 공유 산술 (COMP2/COMP4 공통, 핸드오버 §5.2). 조합회로.
//   addsub=0 : c = (a + b) mod q
//   addsub=1 : c = (a - b) mod q
//   intt=1   : 위 결과에 modular div-by-2 적용 (COMP4 는 intt 미사용 → 0 고정)
// Scheme selection is handled by the upper COMP modules. 입력 계약 0<=a,b<q.
// -----------------------------------------------------------------------------
`default_nettype none

module kyber_modarith16 #(
    parameter integer Q     = 3329,
    parameter integer WIDTH = 16
)(
    input  wire [WIDTH-1:0] a_i,
    input  wire [WIDTH-1:0] b_i,
    input  wire             addsub_i, // 0=add, 1=sub
    input  wire             intt_i,   // 1=div-by-2
    output wire [WIDTH-1:0] c_o
);
    wire [WIDTH-1:0] add_r, sub_r;
    kyber_modadd16_csa #(.Q(Q), .WIDTH(WIDTH)) u_add (
        .a_i (a_i), .b_i (b_i), .c_o (add_r)
    );
    kyber_modsub16_csa #(.Q(Q), .WIDTH(WIDTH)) u_sub (
        .a_i (a_i), .b_i (b_i), .c_o (sub_r)
    );
    wire [WIDTH-1:0] as_r = addsub_i ? sub_r : add_r;

    wire [WIDTH-1:0] div_r;
    kyber_div2_16 #(.Q(Q), .WIDTH(WIDTH)) u_div2 (
        .a_i (as_r), .c_o (div_r)
    );

    assign c_o = intt_i ? div_r : as_r;
endmodule

`default_nettype wire
