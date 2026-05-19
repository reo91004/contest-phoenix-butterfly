// -----------------------------------------------------------------------------
// tb_kyber_modarith.sv
// ML-KEM modular add/sub/div2 + modarith16 exhaustive self-checking TB
// (핸드오버 §13.2: zero mismatch). 조합 DUT — clock 불필요.
//
//   exhaustive a,b in [0,Q)  (STRIDE=1 기본). 빠른 반복용으로
//   +STRIDE=<n> plusarg 로 strided 검사 가능 (정합 검증은 STRIDE=1).
//   div2 는 x in [0,Q) exhaustive.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
`default_nettype none

module tb_kyber_modarith;
    localparam integer Q     = 3329;
    localparam integer WIDTH = 16;

    integer stride;
    integer a, b;
    integer errors;
    integer checks;

    reg  [WIDTH-1:0] a_r, b_r;
    wire [WIDTH-1:0] add_o, sub_o, div2_o;
    wire [WIDTH-1:0] ma_add0, ma_sub0, ma_add1, ma_sub1;

    kyber_modadd16_csa #(.Q(Q), .WIDTH(WIDTH)) u_add (.a_i(a_r), .b_i(b_r), .c_o(add_o));
    kyber_modsub16_csa #(.Q(Q), .WIDTH(WIDTH)) u_sub (.a_i(a_r), .b_i(b_r), .c_o(sub_o));
    kyber_div2_16      #(.Q(Q), .WIDTH(WIDTH)) u_d2  (.a_i(a_r), .c_o(div2_o));

    kyber_modarith16 #(.Q(Q), .WIDTH(WIDTH)) u_ma_a0 (.a_i(a_r), .b_i(b_r), .addsub_i(1'b0), .intt_i(1'b0), .c_o(ma_add0));
    kyber_modarith16 #(.Q(Q), .WIDTH(WIDTH)) u_ma_s0 (.a_i(a_r), .b_i(b_r), .addsub_i(1'b1), .intt_i(1'b0), .c_o(ma_sub0));
    kyber_modarith16 #(.Q(Q), .WIDTH(WIDTH)) u_ma_a1 (.a_i(a_r), .b_i(b_r), .addsub_i(1'b0), .intt_i(1'b1), .c_o(ma_add1));
    kyber_modarith16 #(.Q(Q), .WIDTH(WIDTH)) u_ma_s1 (.a_i(a_r), .b_i(b_r), .addsub_i(1'b1), .intt_i(1'b1), .c_o(ma_sub1));

    function integer ref_add(input integer x, input integer y); ref_add = (x + y) % Q; endfunction
    function integer ref_sub(input integer x, input integer y); ref_sub = ((x - y) % Q + Q) % Q; endfunction
    function integer ref_div2(input integer x); ref_div2 = ((x >> 1) + ((x & 1) ? (Q+1)/2 : 0)) % Q; endfunction

    task check(input [255:0] name, input integer got, input integer exp);
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                if (errors <= 20)
                    $display("[FAIL] %0s a=%0d b=%0d got=%0d exp=%0d", name, a, b, got, exp);
            end
        end
    endtask

    initial begin
        errors = 0; checks = 0;
        if (!$value$plusargs("STRIDE=%d", stride)) stride = 1;
        $display("[tb_kyber_modarith] Q=%0d STRIDE=%0d (exhaustive=STRIDE1)", Q, stride);

        // div2 exhaustive x in [0,Q)
        for (a = 0; a < Q; a = a + 1) begin
            a_r = a[WIDTH-1:0]; b_r = '0; #1;
            check("div2", div2_o, ref_div2(a));
        end

        // add/sub + modarith16 exhaustive a,b in [0,Q)
        for (a = 0; a < Q; a = a + stride) begin
            for (b = 0; b < Q; b = b + stride) begin
                a_r = a[WIDTH-1:0]; b_r = b[WIDTH-1:0]; #1;
                check("add",      add_o,   ref_add(a,b));
                check("sub",      sub_o,   ref_sub(a,b));
                check("ma_add0",  ma_add0, ref_add(a,b));
                check("ma_sub0",  ma_sub0, ref_sub(a,b));
                check("ma_add1",  ma_add1, ref_div2(ref_add(a,b)));
                check("ma_sub1",  ma_sub1, ref_div2(ref_sub(a,b)));
            end
        end

        $display("[tb_kyber_modarith] checks=%0d errors=%0d", checks, errors);
        if (errors == 0) $display("[tb_kyber_modarith] PASS");
        else             $display("[tb_kyber_modarith] FAIL (%0d mismatches)", errors);
        $finish;
    end
endmodule

`default_nettype wire
