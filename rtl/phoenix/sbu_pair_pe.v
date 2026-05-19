// -----------------------------------------------------------------------------
// processing_element.v
// PHOENIX Processing Element: two SuperButterfly Units in parallel.
//
// Two operating modes (paper §4.2.1):
//   - Independent  : SBU0 and SBU1 process distinct butterflies in parallel.
//                    Used for NTT, inverse NTT, MOD_ADD, and ML-DSA PWM.
//   - Cascade PWM  : SBU0 in PWM0, SBU1 in PWM1; SBU0 outputs feed SBU1
//                    inputs (with the swap shown in Fig 4(d)).
//
// The cascade routing is selected by `pwm_chain` (driven by phoenix_control).
// -----------------------------------------------------------------------------
// 핸드오버 정합 재배치: 구 processing_element → sbu_pair_pe.
// ML-KEM keeps the two-lane packed path. ML-DSA uses one 32-bit residue per
// word and does not use the cascade path.
`include "sbu_config.vh"
`default_nettype none

module sbu_pair_pe (
    input  wire        clk,
    input  wire        rst_n,

    // SBU0 inputs (independent mode) / PWM0 inputs (cascade mode)
    input  wire [8:0]  sel0,
    input  wire        valid0_in,
    input  wire [31:0] sbu0_a, sbu0_b, sbu0_c,

    // SBU1 inputs (independent mode); cascade mode overrides these via SBU0 outs
    input  wire [8:0]  sel1,
    input  wire        valid1_in,
    input  wire [31:0] sbu1_a, sbu1_b, sbu1_c,

    // Cascade enable (paper §4.2.1 PWM in NTT)
    input  wire        pwm_chain,

    output wire [31:0] sbu0_out0, sbu0_out1,
    output wire        sbu0_valid_out,
    output wire [31:0] sbu1_out0, sbu1_out1,
    output wire        sbu1_valid_out
);

    // ----- SBU0 ----- (신 superbutterfly_sbu, routed 기본, latency=8)
    superbutterfly_sbu u_sbu0 (
        .clk_i    (clk),
        .rst_ni   (rst_n),
        .sel_i    (sel0),
        .valid_i  (valid0_in),
        .a_i      (sbu0_a),
        .b_i      (sbu0_b),
        .c_i      (sbu0_c),
        .y0_o     (sbu0_out0),
        .y1_o     (sbu0_out1),
        .valid_o  (sbu0_valid_out)
    );

    // ----- SBU1 cascade routing -----
    // SBU0 outputs are registered; SBU1 samples them one cycle later. The
    // PWM1 zeta belongs to the same input transaction as the PWM0 data, so it
    // follows an equal-depth delay pipe (SBU latency + this cascade register).
    reg [31:0] cascade_a_r, cascade_b_r;
    (* shreg_extract = "no" *) reg [31:0] cascade_c_pipe [0:8];
    reg        cascade_valid_r;
    integer ci;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cascade_a_r     <= 32'b0;
            cascade_b_r     <= 32'b0;
            cascade_valid_r <= 1'b0;
            for (ci = 0; ci < 9; ci = ci + 1) begin
                cascade_c_pipe[ci] <= 32'b0;
            end
        end else begin
            cascade_a_r     <= sbu0_valid_out ? sbu0_out0 : 32'b0;
            cascade_b_r     <= sbu0_valid_out ? sbu0_out1 : 32'b0;
            cascade_valid_r <= sbu0_valid_out;
            cascade_c_pipe[0] <= valid0_in ? sbu0_c : 32'b0;
            for (ci = 1; ci < 9; ci = ci + 1) begin
                cascade_c_pipe[ci] <= cascade_c_pipe[ci-1];
            end
        end
    end

    // In cascade mode, SBU1 takes the rearranged outputs of SBU0 as its
    // (a, b) inputs. The packing convention is out0={s1,s0}, out1={m1,m0}.
    wire [31:0] sbu1_a_eff = pwm_chain ? cascade_a_r : sbu1_a;
    wire [31:0] sbu1_b_eff = pwm_chain ? cascade_b_r : sbu1_b;
    wire [31:0] sbu1_c_eff = pwm_chain ? cascade_c_pipe[8] : sbu1_c;
    wire        sbu1_valid_eff = pwm_chain ? cascade_valid_r : valid1_in;

    superbutterfly_sbu u_sbu1 (
        .clk_i    (clk),
        .rst_ni   (rst_n),
        .sel_i    (sel1),
        .valid_i  (sbu1_valid_eff),
        .a_i      (sbu1_a_eff),
        .b_i      (sbu1_b_eff),
        .c_i      (sbu1_c_eff),
        .y0_o     (sbu1_out0),
        .y1_o     (sbu1_out1),
        .valid_o  (sbu1_valid_out)
    );

endmodule

`default_nettype wire
