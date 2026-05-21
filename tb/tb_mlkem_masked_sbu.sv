// -----------------------------------------------------------------------------
// tb_mlkem_masked_sbu.sv
// Verifies ML-KEM two-share SBU arithmetic by recombining routed outputs.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
`include "sbu_config.vh"
`default_nettype none

module tb_mlkem_masked_sbu;
    localparam integer KQ = 3329;

    reg clk = 0, rst_ni = 0, vin = 0;
    reg [8:0] sel;
    reg [31:0] a0, b0, c0, a1, b1, c1, rnd;
    wire vout;
    wire [31:0] y0, y1, y0m, y1m;

    superbutterfly_sbu #(.USE_REF(0)) dut (
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
        .valid_o(vout),
        .y0_o(y0),
        .y1_o(y1),
        .y0_mask_o(y0m),
        .y1_mask_o(y1m)
    );

    always #5 clk = ~clk;

    function [15:0] kadd(input integer x, input integer y);
        begin kadd = (x + y) % KQ; end
    endfunction
    function [15:0] ksub(input integer x, input integer y);
        begin ksub = ((x - y) % KQ + KQ) % KQ; end
    endfunction
    function [15:0] kmul(input integer x, input integer y);
        begin kmul = (x * y) % KQ; end
    endfunction
    function [15:0] kd2(input integer x);
        begin kd2 = ((x >> 1) + ((x & 1) ? ((KQ + 1) / 2) : 0)) % KQ; end
    endfunction
    function [15:0] rq(input integer dummy);
        begin rq = ($random & 32'h7fffffff) % KQ; end
    endfunction
    function [31:0] pack(input [15:0] lo, input [15:0] hi);
        begin pack = {hi, lo}; end
    endfunction
    function [31:0] split0(input [31:0] x, input [31:0] m);
        begin
            split0 = {
                ksub(x[31:16], m[31:16]),
                ksub(x[15:0],  m[15:0])
            };
        end
    endfunction
    function [31:0] recombine(input [31:0] x0, input [31:0] x1);
        begin
            recombine = {
                kadd(x0[31:16], x1[31:16]),
                kadd(x0[15:0],  x1[15:0])
            };
        end
    endfunction

    task golden;
        input [8:0] s;
        input [31:0] a;
        input [31:0] b;
        input [31:0] c;
        output [31:0] g0;
        output [31:0] g1;
        reg [15:0] al, ah, bl, bh, cl, ch;
        reg [15:0] t_lo, t_hi, d_lo, d_hi, m2, m3, s2;
        begin
            al = a[15:0]; ah = a[31:16];
            bl = b[15:0]; bh = b[31:16];
            cl = c[15:0]; ch = c[31:16];
            g0 = 32'b0;
            g1 = 32'b0;
            case (s)
                `SBU_NTT_CT: begin
                    t_lo = kmul(cl, bl); t_hi = kmul(ch, bh);
                    g0 = pack(kadd(al,t_lo), kadd(ah,t_hi));
                    g1 = pack(ksub(al,t_lo), ksub(ah,t_hi));
                end
                `SBU_INTT_GS: begin
                    d_lo = kd2(ksub(bl, al)); d_hi = kd2(ksub(bh, ah));
                    g0 = pack(kd2(kadd(al,bl)), kd2(kadd(ah,bh)));
                    g1 = pack(kmul(cl,d_lo), kmul(ch,d_hi));
                end
                `SBU_MOD_ADD: begin
                    g0 = pack(kadd(al,bl), kadd(ah,bh));
                    g1 = 32'b0;
                end
                `SBU_PWM0: begin
                    g0 = pack(kadd(al,bl), kadd(ah,bh));
                    g1 = pack(kmul(al,ah), kmul(bl,bh));
                end
                `SBU_PWM1: begin
                    m2 = kmul(al,ah);
                    m3 = kmul(bh,cl);
                    s2 = kadd(bl,bh);
                    g0 = pack(kadd(bl,m3), ksub(m2,s2));
                    g1 = 32'b0;
                end
                default: begin
                    g0 = 32'b0;
                    g1 = 32'b0;
                end
            endcase
        end
    endtask

    function [8:0] mode_at(input integer i);
        case (i % 5)
            0: mode_at = `SBU_NTT_CT;
            1: mode_at = `SBU_INTT_GS;
            2: mode_at = `SBU_PWM0;
            3: mode_at = `SBU_PWM1;
            default: mode_at = `SBU_MOD_ADD;
        endcase
    endfunction

    reg [8:0]  h_sel [0:1023];
    reg [31:0] h_a   [0:1023];
    reg [31:0] h_b   [0:1023];
    reg [31:0] h_c   [0:1023];
    reg        h_v   [0:1023];
    integer i, cyc, errors, checks;
    reg [31:0] a_full, b_full, c_full, am, bm;
    reg [31:0] exp0, exp1, got0, got1;

    initial begin
        errors = 0;
        checks = 0;
        cyc = 0;
        for (i = 0; i < 1024; i = i + 1) h_v[i] = 1'b0;
        sel = 9'b0; a0 = 0; b0 = 0; c0 = 0; a1 = 0; b1 = 0; c1 = 0; rnd = 0;
        repeat (4) @(posedge clk);
        rst_ni = 1'b1;
        repeat (4) @(posedge clk);

        for (i = 0; i < 1200; i = i + 1) begin
            @(negedge clk);
            sel = mode_at(i);
            a_full = pack(rq(0), rq(0));
            b_full = pack(rq(0), rq(0));
            c_full = pack(rq(0), rq(0));
            am = pack(rq(0), rq(0));
            bm = pack(rq(0), rq(0));
            a1 = am;
            b1 = bm;
            c1 = 32'b0;
            a0 = split0(a_full, am);
            b0 = split0(b_full, bm);
            c0 = c_full;
            rnd = pack(rq(0), rq(0));
            vin = 1'b1;

            h_sel[cyc % 1024] = sel;
            h_a[cyc % 1024] = a_full;
            h_b[cyc % 1024] = b_full;
            h_c[cyc % 1024] = c_full;
            h_v[cyc % 1024] = 1'b1;

            if (cyc >= 8 && h_v[(cyc-8) % 1024] && vout) begin
                golden(h_sel[(cyc-8) % 1024], h_a[(cyc-8) % 1024],
                       h_b[(cyc-8) % 1024], h_c[(cyc-8) % 1024], exp0, exp1);
                got0 = recombine(y0, y0m);
                got1 = recombine(y1, y1m);
                checks = checks + 1;
                if (got0 !== exp0 || got1 !== exp1) begin
                    errors = errors + 1;
                    if (errors <= 20) begin
                        $display("[FAIL] cyc=%0d sel=%b got=(%h,%h) exp=(%h,%h) raw=(%h,%h) mask=(%h,%h)",
                                 cyc, h_sel[(cyc-8) % 1024], got0, got1, exp0, exp1, y0, y1, y0m, y1m);
                    end
                end
            end
            cyc = cyc + 1;
        end

        for (i = 0; i < 12; i = i + 1) begin
            @(negedge clk);
            vin = 1'b0;
            h_v[cyc % 1024] = 1'b0;
            if (cyc >= 8 && h_v[(cyc-8) % 1024] && vout) begin
                golden(h_sel[(cyc-8) % 1024], h_a[(cyc-8) % 1024],
                       h_b[(cyc-8) % 1024], h_c[(cyc-8) % 1024], exp0, exp1);
                got0 = recombine(y0, y0m);
                got1 = recombine(y1, y1m);
                checks = checks + 1;
                if (got0 !== exp0 || got1 !== exp1) errors = errors + 1;
            end
            cyc = cyc + 1;
        end

        if (errors == 0) begin
            $display("[tb_mlkem_masked_sbu] checks=%0d errors=0 PASS", checks);
            $finish;
        end else begin
            $display("[tb_mlkem_masked_sbu] checks=%0d errors=%0d FAIL", checks, errors);
            $finish;
        end
    end
endmodule

`default_nettype wire
