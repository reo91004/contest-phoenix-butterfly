// -----------------------------------------------------------------------------
// tb/tb_phoenix_cw305_wrapper.sv
// Direct command-protocol smoke test for phoenix_cw305_wrapper.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_phoenix_cw305_wrapper;
    logic clk = 0;
    logic rst_n = 0;
    always #5 clk = ~clk;

    logic         load_i;
    logic [127:0] key_i;
    logic [127:0] data_i;
    wire [127:0]  data_o;
    wire          busy_o;
    wire          trigger_o;

    phoenix_cw305_wrapper dut (
        .clk(clk),
        .rst_n(rst_n),
        .load_i(load_i),
        .key_i(key_i),
        .data_i(data_i),
        .data_o(data_o),
        .busy_o(busy_o),
        .trigger_o(trigger_o)
    );

    localparam [31:0] MAGIC = 32'h50485831;
    localparam [3:0] OP_FWD = 4'b0100;
    localparam [3:0] OP_PWM = 4'b0010;

    function [8:0] make_instr;
        input       scheme;
        input [3:0] op;
        begin
            make_instr = {1'b0, scheme, 1'b0, op, 2'b00};
        end
    endfunction

    function [127:0] mem_key;
        input [1:0] region;
        input [3:0] slot;
        input       bulk;
        input       rd;
        input [9:0] addr;
        begin
            mem_key = 128'b0;
            mem_key[126:123] = slot;
            mem_key[122] = bulk;
            mem_key[121] = rd;
            mem_key[120:119] = region;
            mem_key[9:0] = addr;
        end
    endfunction

    function [127:0] start_key;
        input [8:0] instr;
        begin
            start_key = 128'b0;
            start_key[127] = 1'b1;
            start_key[126:118] = instr;
        end
    endfunction

    task automatic issue;
        input [127:0] key;
        input [127:0] data;
        begin
            @(negedge clk);
            key_i = key;
            data_i = data;
            load_i = 1'b1;
            @(posedge clk);
            #1;
            load_i = 1'b0;
            wait (busy_o === 1'b1);
            wait (busy_o === 1'b0);
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic read_expect;
        input [3:0] slot;
        input [9:0] addr;
        input [31:0] expected;
        begin
            issue(mem_key(2'd0, slot, 1'b0, 1'b1, addr), 128'b0);
            if (data_o[127:96] !== MAGIC || data_o[31:0] !== expected) begin
                $error("wrapper read mismatch slot=%0d addr=%0d got=%08x expected=%08x magic=%08x",
                       slot, addr, data_o[31:0], expected, data_o[127:96]);
            end
        end
    endtask

    task automatic read_region_expect;
        input [1:0] region;
        input [3:0] slot;
        input [9:0] addr;
        input [31:0] expected;
        begin
            issue(mem_key(region, slot, 1'b0, 1'b1, addr), 128'b0);
            if (data_o[127:96] !== MAGIC || data_o[31:0] !== expected) begin
                $error("wrapper region read mismatch region=%0d slot=%0d addr=%0d got=%08x expected=%08x magic=%08x",
                       region, slot, addr, data_o[31:0], expected, data_o[127:96]);
            end
        end
    endtask

    initial begin
        load_i = 1'b0;
        key_i = 128'b0;
        data_i = 128'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);

        issue(mem_key(2'd0, 4'd0, 1'b0, 1'b0, 10'd3), {96'b0, 32'h11223344});
        read_expect(4'd0, 10'd3, 32'h11223344);

        issue(mem_key(2'd0, 4'd5, 1'b1, 1'b0, 10'd20),
              {32'h44444444, 32'h33333333, 32'h22222222, 32'h11111111});
        read_expect(4'd5, 10'd20, 32'h11111111);
        read_expect(4'd5, 10'd21, 32'h22222222);
        read_expect(4'd5, 10'd22, 32'h33333333);
        read_expect(4'd5, 10'd23, 32'h44444444);

        issue(mem_key(2'd1, 4'd0, 1'b0, 1'b0, 10'd7), {96'b0, 32'hdeadbeef});
        issue(mem_key(2'd2, 4'd4, 1'b0, 1'b0, 10'd7), {96'b0, 32'hcafef00d});
        read_region_expect(2'd1, 4'd0, 10'd7, 32'hdeadbeef);
        read_region_expect(2'd2, 4'd4, 10'd7, 32'hcafef00d);

        issue(start_key(make_instr(1'b0, OP_FWD)), 128'b0);
        if (data_o[127:96] !== MAGIC || data_o[95:64] == 32'd0) begin
            $error("wrapper ML-KEM start status mismatch magic=%08x cycles=%0d", data_o[127:96], data_o[95:64]);
        end

        issue(start_key(make_instr(1'b1, OP_PWM)), 128'b0);
        if (data_o[127:96] !== MAGIC || data_o[95:64] == 32'd0) begin
            $error("wrapper ML-DSA start status mismatch magic=%08x cycles=%0d", data_o[127:96], data_o[95:64]);
        end

        $display("[PHOENIX-CW305-WRAPPER] checks=10 errors=0 PASS");
        $finish;
    end
endmodule
