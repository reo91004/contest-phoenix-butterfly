// -----------------------------------------------------------------------------
// phoenix_defs.vh
// Global constants for the ML-KEM / ML-DSA accelerator.
//   - ML-KEM : q=3329, two 16-bit lanes per 32-bit word
//   - ML-DSA : q=8380417, one Montgomery residue per 32-bit word
// -----------------------------------------------------------------------------
`ifndef PHOENIX_DEFS_VH
`define PHOENIX_DEFS_VH

// ---- ML-KEM ----
`define KYBER_Q        16'd3329
`define KYBER_Q_HALF   16'd1665   // (3329+1)/2 = modular div-by-2 상수
`define KYBER_WORD_W   32
`define KYBER_LANE_W   16         // 계수는 12-bit면 충분하나 회로는 16-bit lane 처리

// ---- ML-DSA ----
`define MLDSA_Q        32'd8380417
`define MLDSA_Q_HALF   32'd4190209
`define MLDSA_QINV     32'd58728449
`define MLDSA_WORD_W   32
`define MLDSA_COEFF_W  24
`define MLDSA_R_MOD_Q  32'd4193792

`endif // PHOENIX_DEFS_VH
