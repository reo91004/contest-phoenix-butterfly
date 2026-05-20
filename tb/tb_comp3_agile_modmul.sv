// -----------------------------------------------------------------------------
// tb_comp3_agile_modmul.sv
// COMP3 tests for ML-KEM lane products and ML-DSA Montgomery products.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
`default_nettype none

module tb_comp3_agile_modmul;
    localparam integer KQ = 3329;
    localparam longint unsigned DQ = 64'd8380417;
    localparam longint unsigned RINV = 64'd8265825;
    integer n, k, errors, checks;
    reg  [31:0] a, b;
    reg  [31:0] da, db;
    reg         opm;
    wire [31:0] c;

    comp3_agile_modmul u_dut (
        .a_i(a),
        .b_i(b),
        .dummy_a_i(da),
        .dummy_b_i(db),
        .opmode_i(opm),
        .c_o(c)
    );

    function [15:0] kmul(input [15:0] x, input [15:0] y);
        begin kmul = (x * y) % KQ; end
    endfunction

    function [31:0] dmul_mont(input [31:0] x, input [31:0] y);
        longint unsigned raw;
        longint unsigned red;
        begin
            raw = x * y;
            red = ((raw % DQ) * RINV) % DQ;
            dmul_mont = red[31:0];
        end
    endfunction

    task chk_kem;
        input [15:0] a0, a1, b0, b1;
        reg [31:0] exp;
        begin
            a = {a1, a0};
            b = {b1, b0};
            da = $urandom;
            db = $urandom;
            opm = 1'b0;
            exp = {kmul(a1,b1), kmul(a0,b0)};
            #1;
            checks = checks + 1;
            if (c !== exp) begin
                errors = errors + 1;
                if (errors <= 20) $display("[FAIL KEM] got=%h exp=%h a=%h b=%h", c, exp, a, b);
            end
        end
    endtask

    task chk_dsa;
        input [31:0] xa, xb;
        reg [31:0] exp;
        begin
            a = xa;
            b = xb;
            da = $urandom;
            db = $urandom;
            opm = 1'b1;
            exp = dmul_mont(xa, xb);
            #1;
            checks = checks + 1;
            if (c !== exp) begin
                errors = errors + 1;
                if (errors <= 20) $display("[FAIL DSA] got=%h exp=%h a=%h b=%h", c, exp, a, b);
            end
        end
    endtask

    function [31:0] rq_dsa;
        input integer dummy;
        begin rq_dsa = $urandom % DQ; end
    endfunction

    initial begin
        errors = 0;
        checks = 0;
        if (!$value$plusargs("NRAND=%d", n)) n = 200000;
        $display("[tb_comp3_agile_modmul] NRAND=%0d", n);
        chk_kem(0,0,0,0);
        chk_kem(KQ-1,KQ-1,KQ-1,KQ-1);
        chk_kem(1,KQ-1,KQ-1,1);
        chk_dsa(0,0);
        chk_dsa(DQ-1,DQ-1);
        chk_dsa(1,DQ-1);
        for (k = 0; k < n; k = k + 1) begin
            chk_kem(($random & 32'h7fffffff) % KQ, ($random & 32'h7fffffff) % KQ,
                    ($random & 32'h7fffffff) % KQ, ($random & 32'h7fffffff) % KQ);
            chk_dsa(rq_dsa(0), rq_dsa(0));
        end
        $display("[tb_comp3_agile_modmul] checks=%0d errors=%0d %s",
                 checks, errors, (errors == 0) ? "PASS" : "FAIL");
        $finish;
    end
endmodule

`default_nettype wire
