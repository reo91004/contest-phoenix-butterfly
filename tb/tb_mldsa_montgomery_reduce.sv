// -----------------------------------------------------------------------------
// tb_mldsa_montgomery_reduce.sv
// ML-DSA Montgomery reduction regression.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
`default_nettype none

module tb_mldsa_montgomery_reduce;
    localparam longint unsigned Q = 64'd8380417;
    localparam longint unsigned RINV = 64'd8265825;
    integer n, k, errors, checks;
    reg  [63:0] a;
    wire [31:0] r;

    mldsa_montgomery_reduce u_dut (.a_i(a), .r_o(r));

    function [31:0] exp_red;
        input [63:0] x;
        longint unsigned xm;
        longint unsigned y;
        begin
            xm = x % Q;
            y = (xm * RINV) % Q;
            exp_red = y[31:0];
        end
    endfunction

    task chk;
        input [63:0] x;
        reg [31:0] exp;
        begin
            a = x;
            exp = exp_red(x);
            #1;
            checks = checks + 1;
            if (r !== exp) begin
                errors = errors + 1;
                if (errors <= 20) $display("[FAIL] a=%h got=%h exp=%h", x, r, exp);
            end
        end
    endtask

    initial begin
        errors = 0;
        checks = 0;
        if (!$value$plusargs("NRAND=%d", n)) n = 200000;
        $display("[tb_mldsa_montgomery_reduce] NRAND=%0d", n);
        chk(64'd0);
        chk(64'd1);
        chk((Q-1) * (Q-1));
        chk(64'h00003fffffffffff);
        for (k = 0; k < n; k = k + 1) begin
            chk(({$urandom, $urandom}) & 64'h00003fffffffffff);
        end
        $display("[tb_mldsa_montgomery_reduce] checks=%0d errors=%0d %s",
                 checks, errors, (errors == 0) ? "PASS" : "FAIL");
        $finish;
    end
endmodule

`default_nettype wire
