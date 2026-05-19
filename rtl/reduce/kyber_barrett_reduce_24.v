// -----------------------------------------------------------------------------
// kyber_barrett_reduce_24.v
// ML-KEM modified Barrett reduction, q=3329 ([XL21], 핸드오버 §9.7). 조합회로.
//
//   입력 계약: 0 <= a_i <= 3328*3329 ... 실제는 3328*3328=11,075,584 < 2^24
//   m = floor(2^26 / q) = 20158
//   t = (a * m) >> 26 ;  r = a - t*q ;  if (r >= q) r -= q
//
// 상수곱은 shift/add/sub 네트워크로 전개 (`*` 미사용, DSP=0). 출력은 16-bit
// lane container (값 < q, 상위 4-bit 0).
// -----------------------------------------------------------------------------
`default_nettype none

module kyber_barrett_reduce_24 #(
    parameter integer Q = 3329
)(
    input  wire [23:0] a_i,
    output wire [15:0] r_o
);
    localparam integer WIDTH = 24;
    localparam integer M_W   = 15;            // 20158 < 2^15
    localparam integer SHIFT = 26;
    localparam integer T_W   = 12;            // product 계약상 t <= 3326
    localparam integer AM_W  = SHIFT + T_W;   // t 추출에 필요한 bit 37:26까지만 보존
    localparam [T_W-1:0] QW  = Q[T_W-1:0];

    // a*m, m=20158 = 2^14 + 2^12 - 2^8 - 2^6 - 2^1 (CSD-style sparse form)
    wire [AM_W-1:0] a_am   = {{(AM_W-WIDTH){1'b0}}, a_i};
    wire [AM_W-1:0] am_pos = (a_am << 14) + (a_am << 12);
    wire [AM_W-1:0] am_neg = (a_am << 8)  + (a_am << 6) + (a_am << 1);
    wire [AM_W-1:0] am     = am_pos - am_neg;

    wire [T_W-1:0]  t    = am[SHIFT+T_W-1:SHIFT];
    // t*q mod 2^12, q=3329 = 2048+1024+256+1. valid range에서는
    // r0=a-t*q 가 항상 0..3797 이므로 lower 12-bit subtraction 만으로 충분.
    wire [T_W-1:0] tq_l = (t << 11) + (t << 10) + (t << 8) + t;
    wire [T_W-1:0] r0   = a_i[T_W-1:0] - tq_l;
    wire [T_W-1:0] r1   = (r0 >= QW) ? (r0 - QW) : r0;

    assign r_o = {4'b0, r1};   // 16-bit lane container, 값 < q
endmodule

`default_nettype wire
