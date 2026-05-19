// -----------------------------------------------------------------------------
// tb/tb_phoenix_core.sv
// Operation-level cycle smoke test for the ML-KEM / ML-DSA core.
//
// This testbench drives the 9-bit instruction interface and emits parseable
// cycle lines:
//   [PHOENIX-CYCLES] op=<name> cycles=<n>
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_phoenix_core;
    logic clk = 0;
    logic rst_n = 0;
    always #5 clk = ~clk;

    logic        instr_valid;
    logic [8:0]  instr;
    wire         busy;
    wire         done;
    wire [31:0] cycle_count;
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
        .host_valid(1'b0),
        .host_we(1'b0),
        .host_mem(1'b0),
        .host_bank(2'b0),
        .host_addr(10'b0),
        .host_din(32'b0),
        .host_dout(),
        .host_ready(),
        .dbg_pe_o00(dbg_pe_o00),
        .dbg_pe_o01(dbg_pe_o01),
        .dbg_pe_o10(dbg_pe_o10),
        .dbg_pe_o11(dbg_pe_o11),
        .dbg_pe_v0(dbg_pe_v0),
        .dbg_pe_v1(dbg_pe_v1)
    );

    localparam [3:0] OP_FWD = 4'b0100;
    localparam [3:0] OP_INV = 4'b0001;
    localparam [3:0] OP_PWM = 4'b0010;

    integer checks;
    integer errors;

    function [8:0] make_instr;
        input       scheme;
        input [3:0] op;
        begin
            make_instr = {1'b0, scheme, 1'b0, op, 2'b00};
        end
    endfunction

    function [8:0] make_instr_raw_scheme_field;
        input [1:0] scheme_field;
        input [3:0] op;
        begin
            make_instr_raw_scheme_field = {scheme_field, 1'b0, op, 2'b00};
        end
    endfunction

    task automatic run_op;
        input [8:0] cmd;
        input string name;
        input integer scale;
        integer scaled_cycles;
        begin
            @(posedge clk);
            instr <= cmd;
            instr_valid <= 1'b1;
            @(posedge clk);
            instr_valid <= 1'b0;
            wait (done === 1'b1);
            scaled_cycles = cycle_count * scale;
            $display("[PHOENIX-CYCLES] op=%s cycles=%0d", name, scaled_cycles);
            checks = checks + 1;
            repeat (4) @(posedge clk);
        end
    endtask

    task automatic run_reserved_expect_done;
        input [8:0] cmd;
        input string name;
        begin
            @(posedge clk);
            instr <= cmd;
            instr_valid <= 1'b1;
            @(posedge clk);
            instr_valid <= 1'b0;
            wait (done === 1'b1);
            checks = checks + 1;
            if (cycle_count > 32'd4) begin
                errors = errors + 1;
                $error("reserved scheme field did not terminate quickly: %s cycles=%0d",
                       name, cycle_count);
            end
            repeat (4) @(posedge clk);
        end
    endtask

    initial begin
        checks = 0;
        errors = 0;
        instr_valid = 1'b0;
        instr = 9'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);

        run_op(make_instr(1'b0, OP_FWD), "mlkem_ntt", 1);
        run_op(make_instr(1'b0, OP_INV), "mlkem_intt", 1);
        run_op(make_instr(1'b0, OP_PWM), "mlkem_pwm", 1);

        run_op(make_instr(1'b1, OP_FWD), "mldsa_ntt", 1);
        run_op(make_instr(1'b1, OP_INV), "mldsa_intt", 1);
        run_op(make_instr(1'b1, OP_PWM), "mldsa_pwm", 1);

        run_reserved_expect_done(make_instr_raw_scheme_field(2'b10, OP_FWD), "reserved10");
        run_reserved_expect_done(make_instr_raw_scheme_field(2'b11, OP_FWD), "reserved11");

        $display("[PHOENIX-CORE] checks=%0d errors=%0d %s",
                 checks, errors, (errors == 0) ? "PASS" : "FAIL");
        $finish;
    end
endmodule
