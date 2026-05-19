// -----------------------------------------------------------------------------
// tb_mldsa_karatsuba24.sv
// Raw ML-DSA integer product test. Valid normalized residues fit in 23 bits
// inside the 24-bit interface container.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
`default_nettype none

module tb_mldsa_karatsuba24;
    integer n, k, errors, checks;
    reg  [23:0] a, b;
    wire [47:0] p;

    mldsa_karatsuba24 u_dut (.a_i(a), .b_i(b), .p_o(p));

    task chk;
        input [23:0] xa;
        input [23:0] xb;
        reg [47:0] exp;
        begin
            a = xa;
            b = xb;
            exp = xa * xb;
            #1;
            checks = checks + 1;
            if (p !== exp) begin
                errors = errors + 1;
                if (errors <= 20) $display("[FAIL] a=%h b=%h got=%h exp=%h", xa, xb, p, exp);
            end
        end
    endtask

    initial begin
        errors = 0;
        checks = 0;
        if (!$value$plusargs("NRAND=%d", n)) n = 200000;
        $display("[tb_mldsa_karatsuba24] NRAND=%0d", n);
        chk(24'd0, 24'd0);
        chk(24'h7fffff, 24'h7fffff);
        chk(24'd8380416, 24'd8380416);
        chk(24'h000001, 24'h7fe000);
        for (k = 0; k < n; k = k + 1) begin
            chk($urandom & 24'h7fffff, $urandom & 24'h7fffff);
        end
        $display("[tb_mldsa_karatsuba24] checks=%0d errors=%0d %s",
                 checks, errors, (errors == 0) ? "PASS" : "FAIL");
        $finish;
    end
endmodule

`default_nettype wire
