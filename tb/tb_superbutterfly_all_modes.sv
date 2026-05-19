// -----------------------------------------------------------------------------
// tb_superbutterfly_all_modes.sv
// Streaming SBU test for ML-KEM and ML-DSA modes.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
`include "sbu_config.vh"
`default_nettype none

module tb_superbutterfly_all_modes;
    localparam integer KQ = 3329;
    localparam longint unsigned DQ = 64'd8380417;
    localparam longint unsigned DR = 64'd4193792;
    localparam longint unsigned RINV = 64'd8265825;

    reg clk = 0, rst_ni = 0, vin = 0;
    reg [8:0] sel;
    reg [31:0] a, b, c;
    wire vrf, vrt;
    wire [31:0] y0rf, y1rf, y0rt, y1rt;

    superbutterfly_sbu #(.USE_REF(1)) u_ref (
        .clk_i(clk), .rst_ni(rst_ni), .valid_i(vin),
        .sel_i(sel), .a_i(a), .b_i(b), .c_i(c),
        .valid_o(vrf), .y0_o(y0rf), .y1_o(y1rf)
    );
    superbutterfly_sbu #(.USE_REF(0)) u_rt (
        .clk_i(clk), .rst_ni(rst_ni), .valid_i(vin),
        .sel_i(sel), .a_i(a), .b_i(b), .c_i(c),
        .valid_o(vrt), .y0_o(y0rt), .y1_o(y1rt)
    );

    always #5 clk = ~clk;

    function [15:0] kadd(input integer x,y); kadd = (x + y) % KQ; endfunction
    function [15:0] ksub(input integer x,y); ksub = ((x - y) % KQ + KQ) % KQ; endfunction
    function [15:0] kmul(input integer x,y); kmul = (x * y) % KQ; endfunction
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
    function [31:0] dmul(input [31:0] x, input [31:0] y);
        longint unsigned raw;
        longint unsigned red;
        begin raw = x * y; red = ((raw % DQ) * RINV) % DQ; dmul = red[31:0]; end
    endfunction
    function [31:0] to_mont(input [31:0] x);
        longint unsigned y;
        begin y = (x * DR) % DQ; to_mont = y[31:0]; end
    endfunction

    task golden;
        input [8:0] s;
        input [31:0] xa, xb, xc;
        output [31:0] g0;
        output [31:0] g1;
        reg [15:0] al, ah, bl, bh, cl, ch;
        reg [15:0] t_lo, t_hi, d_lo, d_hi, m2, m3, s2;
        reg [31:0] dt;
        begin
            al = xa[15:0]; ah = xa[31:16];
            bl = xb[15:0]; bh = xb[31:16];
            cl = xc[15:0]; ch = xc[31:16];
            g0 = 32'b0;
            g1 = 32'b0;
            case (s)
                `SBU_NTT_CT: begin
                    t_lo = kmul(cl, bl); t_hi = kmul(ch, bh);
                    g0 = {kadd(ah,t_hi), kadd(al,t_lo)};
                    g1 = {ksub(ah,t_hi), ksub(al,t_lo)};
                end
                `SBU_INTT_GS: begin
                    d_lo = kd2(ksub(bl, al)); d_hi = kd2(ksub(bh, ah));
                    g0 = {kd2(kadd(ah,bh)), kd2(kadd(al,bl))};
                    g1 = {kmul(ch,d_hi), kmul(cl,d_lo)};
                end
                `SBU_MOD_ADD: begin
                    g0 = {kadd(ah,bh), kadd(al,bl)};
                    g1 = 32'b0;
                end
                `SBU_PWM0: begin
                    g0 = {kadd(ah,bh), kadd(al,bl)};
                    g1 = {kmul(bl,bh), kmul(al,ah)};
                end
                `SBU_PWM1: begin
                    m2 = kmul(al,ah);
                    m3 = kmul(bh,cl);
                    s2 = kadd(bl,bh);
                    g0 = {ksub(m2,s2), kadd(bl,m3)};
                    g1 = 32'b0;
                end
                `SBU_MLDSA_NTT: begin
                    dt = dmul(xc, xb);
                    g0 = dadd(xa, dt);
                    g1 = dsub(xa, dt);
                end
                `SBU_MLDSA_INTT: begin
                    dt = dd2(dsub(xb, xa));
                    g0 = dd2(dadd(xa, xb));
                    g1 = dmul(xc, dt);
                end
                `SBU_MLDSA_PWM: begin
                    g0 = dmul(xc, xb);
                    g1 = 32'b0;
                end
                default: begin
                    g0 = 32'b0;
                    g1 = 32'b0;
                end
            endcase
        end
    endtask

    integer cyc, errors, checks, latency_meas;
    reg [8:0] h_sel[0:1023];
    reg [31:0] h_a[0:1023], h_b[0:1023], h_c[0:1023];
    reg h_v[0:1023];

    function [8:0] pick_mode(input integer r);
        case (r % 8)
            0: pick_mode = `SBU_NTT_CT;
            1: pick_mode = `SBU_INTT_GS;
            2: pick_mode = `SBU_PWM0;
            3: pick_mode = `SBU_PWM1;
            4: pick_mode = `SBU_MOD_ADD;
            5: pick_mode = `SBU_MLDSA_NTT;
            6: pick_mode = `SBU_MLDSA_INTT;
            default: pick_mode = `SBU_MLDSA_PWM;
        endcase
    endfunction

    function [15:0] rq_kem(input integer dummy);
        begin rq_kem = ($random & 32'h7fffffff) % KQ; end
    endfunction
    function [31:0] rq_dsa(input integer dummy);
        begin rq_dsa = to_mont($urandom % DQ); end
    endfunction

    integer i, NSTREAM;
    reg [31:0] g0e, g1e;
    initial begin
        errors = 0;
        checks = 0;
        cyc = 0;
        NSTREAM = 4000;
        for (i = 0; i < 1024; i = i + 1) h_v[i] = 0;
        rst_ni = 0; vin = 0; sel = 0; a = 0; b = 0; c = 0;
        repeat (4) @(posedge clk);
        rst_ni = 1;

        @(negedge clk); sel = `SBU_MOD_ADD; a = {16'd7,16'd5}; b = {16'd9,16'd3}; c = 0; vin = 1;
        @(negedge clk); vin = 0; sel = 0; a = 0; b = 0; c = 0;
        latency_meas = 0;
        while (!vrf && latency_meas < 32) begin @(posedge clk); latency_meas = latency_meas + 1; end
        if (latency_meas !== 8) begin errors = errors + 1; $display("[FAIL] ref latency=%0d", latency_meas); end
        else $display("[tb_sbu] ref latency = 8 OK");

        repeat (12) @(posedge clk);
        @(negedge clk); sel = `SBU_MOD_ADD; a = {16'd7,16'd5}; b = {16'd9,16'd3}; c = 0; vin = 1;
        @(negedge clk); vin = 0;
        latency_meas = 0;
        while (!vrt && latency_meas < 32) begin @(posedge clk); latency_meas = latency_meas + 1; end
        if (latency_meas !== 8) begin errors = errors + 1; $display("[FAIL] routed latency=%0d", latency_meas); end
        else $display("[tb_sbu] routed latency = 8 OK");

        repeat (12) @(posedge clk);
        cyc = 0;
        for (i = 0; i < NSTREAM; i = i + 1) begin
            @(negedge clk);
            sel = pick_mode(i);
            if (sel[8] == 1'b0) begin
                a = {rq_kem(0), rq_kem(0)};
                b = {rq_kem(0), rq_kem(0)};
                c = {rq_kem(0), rq_kem(0)};
            end else begin
                a = rq_dsa(0);
                b = rq_dsa(0);
                c = rq_dsa(0);
            end
            vin = 1;
            h_sel[cyc % 1024] = sel;
            h_a[cyc % 1024] = a;
            h_b[cyc % 1024] = b;
            h_c[cyc % 1024] = c;
            h_v[cyc % 1024] = 1;
            if (cyc >= 8 && vrf) begin
                golden(h_sel[(cyc-8) % 1024], h_a[(cyc-8) % 1024],
                       h_b[(cyc-8) % 1024], h_c[(cyc-8) % 1024], g0e, g1e);
                checks = checks + 1;
                if (y0rf !== y0rt || y1rf !== y1rt || y0rf !== g0e || y1rf !== g1e) begin
                    errors = errors + 1;
                    if (errors <= 20) $display("[FAIL] cyc=%0d sel=%b ref=(%h,%h) rt=(%h,%h) exp=(%h,%h)",
                                               cyc, h_sel[(cyc-8) % 1024], y0rf, y1rf, y0rt, y1rt, g0e, g1e);
                end
            end
            cyc = cyc + 1;
        end
        for (i = 0; i < 12; i = i + 1) begin
            @(negedge clk);
            vin = 0;
            h_v[cyc % 1024] = 0;
            if (cyc >= 8 && h_v[(cyc-8) % 1024] && vrf) begin
                golden(h_sel[(cyc-8) % 1024], h_a[(cyc-8) % 1024],
                       h_b[(cyc-8) % 1024], h_c[(cyc-8) % 1024], g0e, g1e);
                checks = checks + 1;
                if (y0rf !== y0rt || y1rf !== y1rt || y0rf !== g0e || y1rf !== g1e) begin
                    errors = errors + 1;
                    if (errors <= 20) $display("[FAIL drain] cyc=%0d", cyc);
                end
            end
            cyc = cyc + 1;
        end

        $display("[tb_superbutterfly_all_modes] checks=%0d errors=%0d %s",
                 checks, errors, (errors == 0) ? "PASS" : "FAIL");
        $finish;
    end
endmodule

`default_nettype wire
