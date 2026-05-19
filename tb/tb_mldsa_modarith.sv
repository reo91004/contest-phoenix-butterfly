// -----------------------------------------------------------------------------
// tb_mldsa_modarith.sv
// Direct ML-DSA modular arithmetic tests.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
`default_nettype none

module tb_mldsa_modarith;
    localparam longint unsigned Q = 64'd8380417;
    integer n, k, errors, checks;
    reg [31:0] a, b;
    wire [31:0] add_o, sub_o, div_o, arith_o;
    reg addsub, intt;

    mldsa_modadd32 u_add (.a_i(a), .b_i(b), .c_o(add_o));
    mldsa_modsub32 u_sub (.a_i(a), .b_i(b), .c_o(sub_o));
    mldsa_div2_32 u_div (.a_i(a), .c_o(div_o));
    mldsa_modarith32 u_arith (.a_i(a), .b_i(b), .addsub_i(addsub), .intt_i(intt), .c_o(arith_o));

    function [31:0] f_add(input [31:0] x, input [31:0] y);
        longint unsigned s;
        begin s = x + y; if (s >= Q) s = s - Q; f_add = s[31:0]; end
    endfunction
    function [31:0] f_sub(input [31:0] x, input [31:0] y);
        longint unsigned s;
        begin s = (x >= y) ? (x - y) : (x + Q - y); f_sub = s[31:0]; end
    endfunction
    function [31:0] f_div(input [31:0] x);
        longint unsigned s;
        begin s = x[0] ? (x + Q) : x; f_div = (s >> 1); end
    endfunction

    task chk;
        input [31:0] x;
        input [31:0] y;
        begin
            a = x; b = y; #1;
            checks = checks + 3;
            if (add_o !== f_add(x,y)) begin errors = errors + 1; if (errors <= 20) $display("[FAIL add]"); end
            if (sub_o !== f_sub(x,y)) begin errors = errors + 1; if (errors <= 20) $display("[FAIL sub]"); end
            if (div_o !== f_div(x)) begin errors = errors + 1; if (errors <= 20) $display("[FAIL div]"); end
            addsub = 0; intt = 0; #1; checks = checks + 1; if (arith_o !== f_add(x,y)) errors = errors + 1;
            addsub = 1; intt = 0; #1; checks = checks + 1; if (arith_o !== f_sub(x,y)) errors = errors + 1;
            addsub = 1; intt = 1; #1; checks = checks + 1; if (arith_o !== f_div(f_sub(x,y))) errors = errors + 1;
        end
    endtask

    function [31:0] rq;
        input integer dummy;
        begin rq = $urandom % Q; end
    endfunction

    initial begin
        errors = 0;
        checks = 0;
        addsub = 0;
        intt = 0;
        if (!$value$plusargs("NRAND=%d", n)) n = 200000;
        $display("[tb_mldsa_modarith] NRAND=%0d", n);
        chk(0,0);
        chk(Q-1,Q-1);
        chk(1,Q-1);
        for (k = 0; k < n; k = k + 1) chk(rq(0), rq(0));
        $display("[tb_mldsa_modarith] checks=%0d errors=%0d %s",
                 checks, errors, (errors == 0) ? "PASS" : "FAIL");
        $finish;
    end
endmodule

`default_nettype wire
