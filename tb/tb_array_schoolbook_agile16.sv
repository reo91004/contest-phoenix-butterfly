// -----------------------------------------------------------------------------
// tb_array_schoolbook_agile16.sv
// 16x16 integer schoolbook multiplier regression.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
`default_nettype none

module tb_array_schoolbook_agile16;
    integer limit, nrand, i, j, k, errors, checks;
    reg  [15:0] a, b;
    wire [31:0] p0, p1;

    array_schoolbook_agile16 u0 (.a_i(a), .b_i(b), .carry_en_i(1'b1), .p_o(p0));
    array_schoolbook_agile16 #(.CARRY_GATED_ARRAY(1)) u1 (.a_i(a), .b_i(b), .carry_en_i(1'b1), .p_o(p1));

    task chk;
        input [15:0] xa;
        input [15:0] xb;
        reg [31:0] exp;
        begin
            a = xa;
            b = xb;
            exp = xa * xb;
            #1;
            checks = checks + 2;
            if (p0 !== exp) begin
                errors = errors + 1;
                if (errors <= 20) $display("[FAIL p0] a=%0d b=%0d got=%h exp=%h", xa, xb, p0, exp);
            end
            if (p1 !== exp) begin
                errors = errors + 1;
                if (errors <= 20) $display("[FAIL p1] a=%0d b=%0d got=%h exp=%h", xa, xb, p1, exp);
            end
        end
    endtask

    initial begin
        errors = 0;
        checks = 0;
        if (!$value$plusargs("LIMIT=%d", limit)) limit = 256;
        if (!$value$plusargs("NRAND=%d", nrand)) nrand = 200000;
        $display("[tb_array_schoolbook_agile16] LIMIT=%0d NRAND=%0d", limit, nrand);

        for (i = 0; i < 16; i = i + 1) begin
            for (j = 0; j < 16; j = j + 1) begin
                chk(16'h1 << i, 16'h1 << j);
            end
        end
        chk(16'h0000,16'hffff);
        chk(16'hffff,16'hffff);
        chk(16'haaaa,16'h5555);
        for (i = 0; i < limit; i = i + 1) begin
            for (j = 0; j < limit; j = j + 1) begin
                chk(i[15:0], j[15:0]);
            end
        end
        for (k = 0; k < nrand; k = k + 1) begin
            chk($random, $random);
        end

        $display("[tb_array_schoolbook_agile16] checks=%0d errors=%0d %s",
                 checks, errors, (errors == 0) ? "PASS" : "FAIL");
        $finish;
    end
endmodule

`default_nettype wire
