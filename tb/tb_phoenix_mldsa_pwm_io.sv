// -----------------------------------------------------------------------------
// tb_phoenix_mldsa_pwm_io.sv
// Top-level ML-DSA pointwise-multiplication I/O test.
//
// The test preloads 256 Montgomery-domain residues into memory-up and
// memory-down, runs the ML-DSA PWM command, and reads memory-up back. Expected
// output is coefficient-wise MontgomeryReduce(up[i] * down[i]). Memory-down is
// also checked to remain unchanged.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_phoenix_mldsa_pwm_io;
    localparam longint unsigned Q    = 64'd8380417;
    localparam longint unsigned R    = 64'd4193792;
    localparam longint unsigned RINV = 64'd8265825;
    localparam [3:0] OP_PWM = 4'b0010;

    logic clk = 0;
    logic rst_n = 0;
    always #5 clk = ~clk;

    logic        instr_valid;
    logic [8:0]  instr;
    wire         busy;
    wire         done;
    wire [31:0] cycle_count;

    logic        host_valid;
    logic        host_we;
    logic        host_mem;
    logic [1:0]  host_region;
    logic [1:0]  host_bank;
    logic [9:0]  host_addr;
    logic [31:0] host_din;
    wire [31:0]  host_dout;
    wire         host_ready;

    wire [31:0] dbg_pe_o00, dbg_pe_o01, dbg_pe_o10, dbg_pe_o11;
    wire        dbg_pe_v0, dbg_pe_v1;

    phoenix_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .instr_valid(instr_valid),
        .instr(instr),
        .busy(busy),
        .done(done),
        .cycle_count(cycle_count),
        .host_valid(host_valid),
        .host_we(host_we),
        .host_mem(host_mem),
        .host_region(host_region),
        .host_bank(host_bank),
        .host_addr(host_addr),
        .host_din(host_din),
        .host_dout(host_dout),
        .host_ready(host_ready),
        .dbg_pe_o00(dbg_pe_o00),
        .dbg_pe_o01(dbg_pe_o01),
        .dbg_pe_o10(dbg_pe_o10),
        .dbg_pe_o11(dbg_pe_o11),
        .dbg_pe_v0(dbg_pe_v0),
        .dbg_pe_v1(dbg_pe_v1)
    );

    integer i;
    integer errors;
    integer checks;
    reg [31:0] up_in [0:255];
    reg [31:0] down_in [0:255];
    reg [31:0] exp_out [0:255];
    reg [31:0] got;

    function [8:0] make_instr;
        input       scheme;
        input [3:0] op;
        begin
            make_instr = {1'b0, scheme, 1'b0, op, 2'b00};
        end
    endfunction

    function [31:0] to_mont;
        input [31:0] x;
        longint unsigned y;
        begin
            y = (({32'b0, x} % Q) * R) % Q;
            to_mont = y[31:0];
        end
    endfunction

    function [31:0] mont_mul;
        input [31:0] x;
        input [31:0] y;
        longint unsigned raw;
        longint unsigned red;
        begin
            raw = ({32'b0, x} * {32'b0, y}) % Q;
            red = (raw * RINV) % Q;
            mont_mul = red[31:0];
        end
    endfunction

    function [1:0] bank_of;
        input [11:0] index;
        integer k;
        reg [1:0] sum;
        begin
            sum = 2'b0;
            for (k = 0; k < 6; k = k + 1) begin
                sum = sum + ((index >> (2*k)) & 2'b11);
            end
            bank_of = sum;
        end
    endfunction

    function [9:0] addr_of;
        input [11:0] index;
        begin
            addr_of = index[11:2];
        end
    endfunction

    task automatic host_write_index;
        input       mem;
        input [11:0] index;
        input [31:0] data;
        begin
            if (!host_ready) begin
                errors = errors + 1;
                $error("host_write while host_ready is low");
            end
            @(negedge clk);
            host_mem   = mem;
            host_region = 2'b0;
            host_bank  = bank_of(index);
            host_addr  = addr_of(index);
            host_din   = data;
            host_we    = 1'b1;
            host_valid = 1'b1;
            @(posedge clk);
            #1;
            host_valid = 1'b0;
            host_we    = 1'b0;
        end
    endtask

    task automatic host_read_index;
        input       mem;
        input [11:0] index;
        output [31:0] data;
        begin
            if (!host_ready) begin
                errors = errors + 1;
                $error("host_read while host_ready is low");
            end
            @(negedge clk);
            host_mem   = mem;
            host_region = 2'b0;
            host_bank  = bank_of(index);
            host_addr  = addr_of(index);
            host_din   = 32'b0;
            host_we    = 1'b0;
            host_valid = 1'b1;
            @(posedge clk);
            #1;
            host_valid = 1'b0;
            data = host_dout;
        end
    endtask

    task automatic run_mldsa_pwm;
        begin
            @(negedge clk);
            instr = make_instr(1'b1, OP_PWM);
            instr_valid = 1'b1;
            @(posedge clk);
            #1;
            instr_valid = 1'b0;
            wait (busy === 1'b1);
            wait (done === 1'b1);
            repeat (4) @(posedge clk);
        end
    endtask

    initial begin
        errors = 0;
        checks = 0;
        instr_valid = 1'b0;
        instr = 9'b0;
        host_valid = 1'b0;
        host_we = 1'b0;
        host_mem = 1'b0;
        host_region = 2'b0;
        host_bank = 2'b0;
        host_addr = 10'b0;
        host_din = 32'b0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);

        for (i = 0; i < 256; i = i + 1) begin
            up_in[i] = to_mont((i == 0) ? 32'd0 :
                               (i == 1) ? 32'd1 :
                               (i == 2) ? 32'd8380416 :
                               ((i * i + 17 * i + 5) % Q));
            down_in[i] = to_mont((i == 3) ? 32'd0 :
                                 (i == 4) ? 32'd1 :
                                 (i == 5) ? 32'd8380416 :
                                 ((7 * i * i + 31337 * i + 9) % Q));
            exp_out[i] = mont_mul(up_in[i], down_in[i]);
            host_write_index(1'b0, i[11:0], up_in[i]);
            host_write_index(1'b1, i[11:0], down_in[i]);
        end

        run_mldsa_pwm();

        for (i = 0; i < 256; i = i + 1) begin
            host_read_index(1'b0, i[11:0], got);
            checks = checks + 1;
            if (got !== exp_out[i]) begin
                errors = errors + 1;
                if (errors <= 20) begin
                    $display("[FAIL MLDSA PWM UP] i=%0d got=%08x expected=%08x up=%08x down=%08x",
                             i, got, exp_out[i], up_in[i], down_in[i]);
                end
            end

            host_read_index(1'b1, i[11:0], got);
            checks = checks + 1;
            if (got !== down_in[i]) begin
                errors = errors + 1;
                if (errors <= 20) begin
                    $display("[FAIL MLDSA PWM DOWN] i=%0d got=%08x expected=%08x",
                             i, got, down_in[i]);
                end
            end
        end

        $display("[PHOENIX-MLDSA-PWM-IO] cycles=%0d checks=%0d errors=%0d %s",
                 cycle_count, checks, errors, (errors == 0) ? "PASS" : "FAIL");
        $finish;
    end
endmodule
