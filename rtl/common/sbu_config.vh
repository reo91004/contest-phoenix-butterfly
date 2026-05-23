// -----------------------------------------------------------------------------
// sbu_config.vh
// SuperButterfly 9-bit mode codes. The original physical bit layout is kept,
// but sel[8] now selects the lattice scheme instead of the removed binary-field
// path.
//
//   sel[8]   = opmode  (0 = ML-KEM, 1 = ML-DSA)
//   sel[7]   = addsub  (0 = add, 1 = sub)
//   sel[6]   = intt    (0 = no /2, 1 = INTT_GS modular div-by-2)
//   sel[5]   = pwm     (ML-KEM PWM cascade data arrangement)
//   sel[4:0] = routed SBU mux controls
// -----------------------------------------------------------------------------
`ifndef SBU_CONFIG_VH
`define SBU_CONFIG_VH

`define SBU_NTT_CT      9'b010010011
`define SBU_INTT_GS     9'b011000100
`define SBU_PWM0        9'b000010100
`define SBU_PWM1        9'b000110000
`define SBU_MOD_ADD     9'b000000000
`define SBU_MLDSA_NTT   9'b110010011
`define SBU_MLDSA_INTT  9'b111000100
`define SBU_MLDSA_PWM   9'b100010100

// 필드 디코더 (sel[8:0] 비트 추출). 인자는 식별자/배열워드여야 함.
`define SBU_OPMODE(sel)  (sel[8])
`define SBU_ADDSUB(sel)  (sel[7])
`define SBU_INTT(sel)    (sel[6])
`define SBU_PWMSEL(sel)  (sel[5])

// Current routed SBU external latency. The Phase-A multiplier/reducer is
// internally pipelined so the host/top-level alignment derives from here.
`define SBU_LATENCY       13
`define SBU_COMP3_LATENCY 8

`endif // SBU_CONFIG_VH
