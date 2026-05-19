// -----------------------------------------------------------------------------
// constant_memory.v
// Constant storage for ML-KEM and ML-DSA transform operations.
//
// ML-KEM:
//   - 256 16-bit twiddle entries per SBU, packed into both 16-bit lanes.
//   - 128 pointwise zeta entries for the ML-KEM two-step PWM path.
//
// ML-DSA:
//   - FIPS 204 zetas[1..255] derived from zeta=1753 and BitRev8.
//   - Forward constants and inverse signed constants are stored as normalized
//     Montgomery residues modulo 8380417.
// -----------------------------------------------------------------------------
`include "phoenix_defs.vh"
`default_nettype none

module constant_memory #(
    parameter integer NTT_DEPTH = 256
)(
    input  wire        clk,
    input  wire        scheme_i,     // 0 = ML-KEM, 1 = ML-DSA
    input  wire        inverse_i,
    input  wire [7:0]  ntt_addr0,
    input  wire [7:0]  ntt_addr1,
    input  wire [6:0]  pwm_addr,
    output reg  [31:0] ntt_q0,
    output reg  [31:0] ntt_q1,
    output reg  [31:0] pwm_q
);

    (* rom_style = "block" *)
    reg [15:0] kem_ntt_rom0 [0:NTT_DEPTH-1];
    (* rom_style = "block" *)
    reg [15:0] kem_ntt_rom1 [0:NTT_DEPTH-1];
    (* rom_style = "distributed" *)
    reg [15:0] kem_pwm_rom [0:127];

    (* rom_style = "block" *)
    reg [31:0] dsa_ntt_rom [0:NTT_DEPTH-1];
    (* rom_style = "block" *)
    reg [31:0] dsa_intt_rom [0:NTT_DEPTH-1];

    function integer bitrev7;
        input integer x;
        integer k;
        begin
            bitrev7 = 0;
            for (k = 0; k < 7; k = k + 1) begin
                if ((x & (1 << k)) != 0) bitrev7 = bitrev7 | (1 << (6 - k));
            end
        end
    endfunction

    function integer bitrev8;
        input integer x;
        integer k;
        begin
            bitrev8 = 0;
            for (k = 0; k < 8; k = k + 1) begin
                if ((x & (1 << k)) != 0) bitrev8 = bitrev8 | (1 << (7 - k));
            end
        end
    endfunction

    function [15:0] kem_pow_mod_q;
        input integer base;
        input integer exp;
        integer result;
        integer b;
        integer e;
        begin
            result = 1;
            b = base % 3329;
            e = exp;
            while (e > 0) begin
                if ((e & 1) != 0) result = (result * b) % 3329;
                b = (b * b) % 3329;
                e = e >> 1;
            end
            kem_pow_mod_q = result[15:0];
        end
    endfunction

    function [31:0] dsa_pow_mod_q;
        input integer base;
        input integer exp;
        reg [63:0] result;
        reg [63:0] b;
        integer e;
        begin
            result = 1;
            b = {32'b0, base} % 64'd8380417;
            e = exp;
            while (e > 0) begin
                if ((e & 1) != 0) result = (result * b) % 8380417;
                b = (b * b) % 8380417;
                e = e >> 1;
            end
            dsa_pow_mod_q = result[31:0];
        end
    endfunction

    function [31:0] dsa_to_mont;
        input [31:0] x;
        reg [63:0] tmp;
        begin
            tmp = ({32'b0, x} * 64'd4193792) % 64'd8380417;
            dsa_to_mont = tmp[31:0];
        end
    endfunction

    integer ni;
    reg [31:0] dsa_zeta;
    initial begin
        for (ni = 0; ni < 128; ni = ni + 1) begin
            kem_ntt_rom0[ni]       = kem_pow_mod_q(17, bitrev7(ni));
            kem_ntt_rom1[ni]       = kem_pow_mod_q(17, bitrev7(ni));
            kem_ntt_rom0[128 + ni] = kem_pow_mod_q(17, bitrev7(127 - ni));
            kem_ntt_rom1[128 + ni] = kem_pow_mod_q(17, bitrev7(127 - ni));
            kem_pwm_rom[ni]        = kem_pow_mod_q(17, 2 * bitrev7(ni) + 1);
        end

        dsa_ntt_rom[0] = 32'b0;
        dsa_intt_rom[0] = 32'b0;
        for (ni = 1; ni < 256; ni = ni + 1) begin
            dsa_zeta = dsa_pow_mod_q(1753, bitrev8(ni));
            dsa_ntt_rom[ni] = dsa_to_mont(dsa_zeta);
            dsa_intt_rom[ni] = dsa_to_mont((dsa_zeta == 0) ? 32'b0 : (`MLDSA_Q - dsa_zeta));
        end
    end

    always @(posedge clk) begin
        if (scheme_i) begin
            ntt_q0 <= inverse_i ? dsa_intt_rom[ntt_addr0] : dsa_ntt_rom[ntt_addr0];
            ntt_q1 <= inverse_i ? dsa_intt_rom[ntt_addr1] : dsa_ntt_rom[ntt_addr1];
            pwm_q  <= 32'b0;
        end else begin
            ntt_q0 <= {kem_ntt_rom0[ntt_addr0], kem_ntt_rom0[ntt_addr0]};
            ntt_q1 <= {kem_ntt_rom1[ntt_addr1], kem_ntt_rom1[ntt_addr1]};
            pwm_q  <= {4'b0, kem_pwm_rom[pwm_addr][11:0], 4'b0, kem_pwm_rom[pwm_addr][11:0]};
        end
    end
endmodule

`default_nettype wire
