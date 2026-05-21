// -----------------------------------------------------------------------------
// tb_mldsa_masked_sbu.sv
// Verifies ML-DSA two-share SBU arithmetic by recombining routed outputs and
// comparing them against the unmasked reference SBU.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
`include "sbu_config.vh"
`default_nettype none

module tb_mldsa_masked_sbu;
    localparam longint unsigned DQ = 64'd8380417;
    localparam longint unsigned DR = 64'd4193792;

    reg clk = 0, rst_ni = 0, vin = 0;
    reg [8:0] sel;
    reg [31:0] a0, b0, c0, a1, b1, c1, rnd;
    reg [31:0] af, bf, cf;
    wire vref, vrt;
    wire [31:0] y0ref, y1ref, y0rt, y1rt, y0m, y1m;
    wire [31:0] unused_m0, unused_m1;

    superbutterfly_sbu #(.USE_REF(1)) u_ref (
        .clk_i(clk),
        .rst_ni(rst_ni),
        .valid_i(vin),
        .sel_i(sel),
        .a_i(af),
        .b_i(bf),
        .c_i(cf),
        .a_mask_i(32'b0),
        .b_mask_i(32'b0),
        .c_mask_i(32'b0),
        .rand_i(32'b0),
        .valid_o(vref),
        .y0_o(y0ref),
        .y1_o(y1ref),
        .y0_mask_o(unused_m0),
        .y1_mask_o(unused_m1)
    );

    superbutterfly_sbu #(.USE_REF(0)) u_dut (
        .clk_i(clk),
        .rst_ni(rst_ni),
        .valid_i(vin),
        .sel_i(sel),
        .a_i(a0),
        .b_i(b0),
        .c_i(c0),
        .a_mask_i(a1),
        .b_mask_i(b1),
        .c_mask_i(c1),
        .rand_i(rnd),
        .valid_o(vrt),
        .y0_o(y0rt),
        .y1_o(y1rt),
        .y0_mask_o(y0m),
        .y1_mask_o(y1m)
    );

    always #5 clk = ~clk;

    function [31:0] dadd(input [31:0] x, input [31:0] y);
        longint unsigned s;
        begin
            s = x + y;
            if (s >= DQ) s = s - DQ;
            dadd = s[31:0];
        end
    endfunction

    function [31:0] dsub(input [31:0] x, input [31:0] y);
        longint unsigned s;
        begin
            s = (x >= y) ? (x - y) : (x + DQ - y);
            dsub = s[31:0];
        end
    endfunction

    function [31:0] to_mont(input [31:0] x);
        longint unsigned y;
        begin
            y = (x * DR) % DQ;
            to_mont = y[31:0];
        end
    endfunction

    function [31:0] rq_dsa(input integer dummy);
        begin
            rq_dsa = to_mont($urandom % DQ);
        end
    endfunction

    function [31:0] split0(input [31:0] x, input [31:0] m);
        begin
            split0 = dsub(x, m);
        end
    endfunction

    function [31:0] recombine(input [31:0] x0, input [31:0] x1);
        begin
            recombine = dadd(x0, x1);
        end
    endfunction

    function [8:0] mode_at(input integer i);
        case (i % 3)
            0: mode_at = `SBU_MLDSA_NTT;
            1: mode_at = `SBU_MLDSA_INTT;
            default: mode_at = `SBU_MLDSA_PWM;
        endcase
    endfunction

    reg [8:0]  h_sel [0:1023];
    reg        h_v   [0:1023];
    integer i, cyc, errors, checks;
    reg [31:0] am, bm, cm;
    reg [31:0] got0, got1;

    initial begin
        errors = 0;
        checks = 0;
        cyc = 0;
        for (i = 0; i < 1024; i = i + 1) h_v[i] = 1'b0;
        sel = 9'b0; af = 0; bf = 0; cf = 0; a0 = 0; b0 = 0; c0 = 0; a1 = 0; b1 = 0; c1 = 0; rnd = 0;
        repeat (4) @(posedge clk);
        rst_ni = 1'b1;
        repeat (4) @(posedge clk);

        for (i = 0; i < 1200; i = i + 1) begin
            @(negedge clk);
            sel = mode_at(i);
            af = rq_dsa(0);
            bf = rq_dsa(0);
            cf = rq_dsa(0);
            if (sel == `SBU_MLDSA_PWM) begin
                af = cf;
            end
            am = rq_dsa(0);
            bm = rq_dsa(0);
            cm = (sel == `SBU_MLDSA_PWM) ? rq_dsa(0) : 32'b0;
            a1 = am;
            b1 = bm;
            c1 = cm;
            a0 = split0(af, am);
            b0 = split0(bf, bm);
            c0 = split0(cf, cm);
            rnd = rq_dsa(0);
            vin = 1'b1;

            h_sel[cyc % 1024] = sel;
            h_v[cyc % 1024] = 1'b1;

            if (cyc >= 8 && h_v[(cyc-8) % 1024] && vref && vrt) begin
                got0 = recombine(y0rt, y0m);
                got1 = recombine(y1rt, y1m);
                checks = checks + 1;
                if (got0 !== y0ref || got1 !== y1ref) begin
                    errors = errors + 1;
                    if (errors <= 20) begin
                        $display("[FAIL] cyc=%0d sel=%b got=(%h,%h) exp=(%h,%h) raw=(%h,%h) mask=(%h,%h)",
                                 cyc, h_sel[(cyc-8) % 1024], got0, got1, y0ref, y1ref, y0rt, y1rt, y0m, y1m);
                    end
                end
            end
            cyc = cyc + 1;
        end

        for (i = 0; i < 12; i = i + 1) begin
            @(negedge clk);
            vin = 1'b0;
            h_v[cyc % 1024] = 1'b0;
            if (cyc >= 8 && h_v[(cyc-8) % 1024] && vref && vrt) begin
                got0 = recombine(y0rt, y0m);
                got1 = recombine(y1rt, y1m);
                checks = checks + 1;
                if (got0 !== y0ref || got1 !== y1ref) errors = errors + 1;
            end
            cyc = cyc + 1;
        end

        if (errors == 0) begin
            $display("[tb_mldsa_masked_sbu] checks=%0d errors=0 PASS", checks);
            $finish;
        end else begin
            $display("[tb_mldsa_masked_sbu] checks=%0d errors=%0d FAIL", checks, errors);
            $finish;
        end
    end
endmodule

`default_nettype wire
