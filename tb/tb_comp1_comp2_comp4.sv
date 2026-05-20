// -----------------------------------------------------------------------------
// tb_comp1_comp2_comp4.sv
// COMP1/COMP2/COMP4 tests for ML-KEM lanes and ML-DSA 32-bit residues.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
`default_nettype none

module tb_comp1_comp2_comp4;
    localparam integer KQ = 3329;
    localparam longint unsigned DQ = 64'd8380417;
    integer n, k, errors, checks;
    reg  [31:0] a, b, dummy_a, dummy_b;
    reg         opm, asb, itt;
    wire [31:0] c1, c2, c4;

    comp1_agile_modadd_div2 u1 (.a_i(a), .b_i(b), .opmode_i(opm), .intt_i(itt), .c_o(c1));
    comp2_agile_modarith_div2 u2 (
        .a_i(a),
        .b_i(b),
        .dummy_a_i(dummy_a),
        .dummy_b_i(dummy_b),
        .opmode_i(opm),
        .addsub_i(asb),
        .intt_i(itt),
        .c_o(c2)
    );
    comp4_agile_modarith u4 (.a_i(a), .b_i(b), .opmode_i(opm), .addsub_i(asb), .c_o(c4));

    function [15:0] kadd(input integer x, input integer y); kadd = (x + y) % KQ; endfunction
    function [15:0] ksub(input integer x, input integer y); ksub = ((x - y) % KQ + KQ) % KQ; endfunction
    function [15:0] kd2(input integer x); kd2 = ((x >> 1) + ((x & 1) ? ((KQ + 1) / 2) : 0)) % KQ; endfunction

    function [31:0] dadd(input [31:0] x, input [31:0] y);
        longint unsigned s;
        begin s = x + y; if (s >= DQ) s = s - DQ; dadd = s[31:0]; end
    endfunction
    function [31:0] dsub(input [31:0] x, input [31:0] y);
        longint unsigned s;
        begin s = (x >= y) ? (x - y) : (x + DQ - y); dsub = s[31:0]; end
    endfunction
    function [31:0] dd2(input [31:0] x);
        longint unsigned s;
        begin s = x[0] ? (x + DQ) : x; dd2 = (s >> 1); end
    endfunction

    task tally;
        input [255:0] name;
        input [31:0] got;
        input [31:0] exp;
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                if (errors <= 20) $display("[FAIL] %0s a=%h b=%h opm=%b asb=%b itt=%b got=%h exp=%h",
                                           name, a, b, opm, asb, itt, got, exp);
            end
        end
    endtask

    task run_kem;
        input [15:0] al, ah, bl, bh;
        begin
            a = {ah, al};
            b = {bh, bl};
            dummy_a = {$random, $random};
            dummy_b = {$random, $random};
            opm = 0; asb = 0; itt = 0; #1; tally("kem_c1_add", c1, {kadd(ah,bh), kadd(al,bl)});
            opm = 0; asb = 0; itt = 1; #1; tally("kem_c1_add_d2", c1, {kd2(kadd(ah,bh)), kd2(kadd(al,bl))});
            opm = 0; asb = 0; itt = 0; #1; tally("kem_c2_add", c2, {kadd(ah,bh), kadd(al,bl)});
            opm = 0; asb = 1; itt = 0; #1; tally("kem_c2_sub", c2, {ksub(ah,bh), ksub(al,bl)});
            opm = 0; asb = 0; itt = 1; #1; tally("kem_c2_add_d2", c2, {kd2(kadd(ah,bh)), kd2(kadd(al,bl))});
            opm = 0; asb = 1; itt = 1; #1; tally("kem_c2_sub_d2", c2, {kd2(ksub(ah,bh)), kd2(ksub(al,bl))});
            opm = 0; asb = 0; itt = 0; #1; tally("kem_c4_add", c4, {kadd(ah,bh), kadd(al,bl)});
            opm = 0; asb = 1; itt = 0; #1; tally("kem_c4_sub", c4, {ksub(ah,bh), ksub(al,bl)});
        end
    endtask

    task run_dsa;
        input [31:0] xa, xb;
        begin
            a = xa;
            b = xb;
            dummy_a = {$random, $random};
            dummy_b = {$random, $random};
            opm = 1; asb = 0; itt = 0; #1; tally("dsa_c1_add", c1, dadd(xa,xb));
            opm = 1; asb = 0; itt = 1; #1; tally("dsa_c1_add_d2", c1, dd2(dadd(xa,xb)));
            opm = 1; asb = 0; itt = 0; #1; tally("dsa_c2_add", c2, dadd(xa,xb));
            opm = 1; asb = 1; itt = 0; #1; tally("dsa_c2_sub", c2, dsub(xa,xb));
            opm = 1; asb = 0; itt = 1; #1; tally("dsa_c2_add_d2", c2, dd2(dadd(xa,xb)));
            opm = 1; asb = 1; itt = 1; #1; tally("dsa_c2_sub_d2", c2, dd2(dsub(xa,xb)));
            opm = 1; asb = 0; itt = 0; #1; tally("dsa_c4_add", c4, dadd(xa,xb));
            opm = 1; asb = 1; itt = 0; #1; tally("dsa_c4_sub", c4, dsub(xa,xb));
        end
    endtask

    function [31:0] rq_dsa;
        input integer dummy;
        begin rq_dsa = $urandom % DQ; end
    endfunction

    initial begin
        errors = 0;
        checks = 0;
        dummy_a = 32'b0;
        dummy_b = 32'b0;
        if (!$value$plusargs("NRAND=%d", n)) n = 100000;
        $display("[tb_comp1_comp2_comp4] NRAND=%0d", n);
        run_kem(0,0,0,0);
        run_kem(KQ-1,KQ-1,KQ-1,KQ-1);
        run_dsa(0,0);
        run_dsa(DQ-1,DQ-1);
        run_dsa(1,DQ-1);
        for (k = 0; k < n; k = k + 1) begin
            run_kem(($random & 32'h7fffffff) % KQ, ($random & 32'h7fffffff) % KQ,
                    ($random & 32'h7fffffff) % KQ, ($random & 32'h7fffffff) % KQ);
            run_dsa(rq_dsa(0), rq_dsa(0));
        end
        $display("[tb_comp1_comp2_comp4] checks=%0d errors=%0d %s",
                 checks, errors, (errors == 0) ? "PASS" : "FAIL");
        $finish;
    end
endmodule

`default_nettype wire
