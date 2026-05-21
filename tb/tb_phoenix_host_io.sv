// -----------------------------------------------------------------------------
// tb/tb_phoenix_host_io.sv
// Smoke test for the phoenix_core idle host memory port used by CW305 wrappers.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_phoenix_host_io;
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

    localparam [3:0] OP_FWD = 4'b0100;

    function [8:0] make_instr;
        input       scheme;
        input [3:0] op;
        begin
            make_instr = {1'b0, scheme, 1'b0, op, 2'b00};
        end
    endfunction

    task automatic host_write;
        input       mem;
        input [1:0] bank;
        input [9:0] addr;
        input [31:0] data;
        begin
            if (!host_ready) begin
                $error("host_write while host_ready is low");
            end
            @(negedge clk);
            host_mem   = mem;
            host_bank  = bank;
            host_addr  = addr;
            host_din   = data;
            host_we    = 1'b1;
            host_valid = 1'b1;
            @(posedge clk);
            #1;
            host_valid = 1'b0;
            host_we    = 1'b0;
        end
    endtask

    task automatic host_read_expect;
        input       mem;
        input [1:0] bank;
        input [9:0] addr;
        input [31:0] expected;
        begin
            if (!host_ready) begin
                $error("host_read while host_ready is low");
            end
            @(negedge clk);
            host_mem   = mem;
            host_bank  = bank;
            host_addr  = addr;
            host_din   = 32'b0;
            host_we    = 1'b0;
            host_valid = 1'b1;
            @(posedge clk);
            #1;
            host_valid = 1'b0;
            if (host_dout !== expected) begin
                $error("host read mismatch mem=%0d bank=%0d addr=%0d got=%08x expected=%08x",
                       mem, bank, addr, host_dout, expected);
            end
        end
    endtask

    task automatic run_short_op;
        begin
            @(negedge clk);
            instr = make_instr(1'b0, OP_FWD);
            instr_valid = 1'b1;
            @(posedge clk);
            #1;
            instr_valid = 1'b0;
            wait (busy === 1'b1);
            if (host_ready !== 1'b0) begin
                $error("host_ready stayed high while core busy");
            end
            wait (done === 1'b1);
            @(posedge clk);
            if (host_ready !== 1'b1) begin
                $error("host_ready did not return high after core done");
            end
        end
    endtask

    initial begin
        instr_valid = 1'b0;
        instr = 9'b0;
        host_valid = 1'b0;
        host_we = 1'b0;
        host_mem = 1'b0;
        host_bank = 2'b0;
        host_addr = 10'b0;
        host_din = 32'b0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);

        host_write(1'b0, 2'd0, 10'd3,  32'h11223344);
        host_write(1'b0, 2'd2, 10'd17, 32'h55667788);
        host_write(1'b1, 2'd1, 10'd5,  32'haabbccdd);
        host_write(1'b1, 2'd3, 10'd29, 32'h01020304);

        host_read_expect(1'b0, 2'd0, 10'd3,  32'h11223344);
        host_read_expect(1'b0, 2'd2, 10'd17, 32'h55667788);
        host_read_expect(1'b1, 2'd1, 10'd5,  32'haabbccdd);
        host_read_expect(1'b1, 2'd3, 10'd29, 32'h01020304);

        run_short_op();

        $display("[PHOENIX-HOST-IO] checks=5 errors=0 PASS");
        $finish;
    end
endmodule
