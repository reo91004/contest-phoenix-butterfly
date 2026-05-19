// -----------------------------------------------------------------------------
// tb_barrett_reduce.sv
// kyber_barrett_reduce_24: exhaustive product a,b<q (핸드오버 §9.7,§13.2).
//   for a,b in [0,Q): dut(a*b) == (a*b) % Q.  +STRIDE=<n> (정합검증 STRIDE=1)
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
`default_nettype none

module tb_barrett_reduce;
    localparam integer Q = 3329;
    integer stride, a, b, errors, checks;
    reg  [23:0] prod;
    wire [15:0] r;

    kyber_barrett_reduce_24 #(.Q(Q)) u_dut (.a_i(prod), .r_o(r));

    initial begin
        errors=0; checks=0;
        if (!$value$plusargs("STRIDE=%d", stride)) stride = 1;
        $display("[tb_barrett_reduce] Q=%0d STRIDE=%0d", Q, stride);
        for (a=0;a<Q;a=a+stride) begin
            for (b=0;b<Q;b=b+stride) begin
                prod = (a*b); #1; checks=checks+1;
                if (r !== ((a*b) % Q)) begin
                    errors=errors+1;
                    if (errors<=20) $display("[FAIL] a=%0d b=%0d prod=%0d got=%0d exp=%0d",
                                             a,b,a*b,r,(a*b)%Q);
                end
            end
        end
        $display("[tb_barrett_reduce] checks=%0d errors=%0d %s",
                 checks, errors, (errors==0)?"PASS":"FAIL");
        $finish;
    end
endmodule

`default_nettype wire
