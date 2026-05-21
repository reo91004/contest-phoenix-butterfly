// -----------------------------------------------------------------------------
// phoenix_cw305_wrapper.v
// CW305 register-protocol bridge for phoenix_top.
//
// Command mapping through cw305_reg_aes:
//   key_i[127]     = 1 -> start PHOENIX operation
//   key_i[126:118] = instr[8:0] for start commands
//
//   key_i[127]     = 0 -> idle memory access
//   key_i[126:123] = slot: 0..3 memory-up banks, 4..7 memory-down banks
//   key_i[122]     = bulk write, four 32-bit words to addr..addr+3
//   key_i[121]     = read single 32-bit word
//   key_i[120:119] = region: 0=share0 data, 1=share1 mask, 2=random tape
//   key_i[9:0]     = word address inside the selected bank
//   data_i[31:0]   = single write payload
//   data_i[127:0]  = bulk write payload, four little-endian 32-bit words
//
// Read/status responses are returned in data_o and latched by cw305_reg_aes
// when busy_o falls.
// -----------------------------------------------------------------------------
`default_nettype none

module phoenix_cw305_wrapper (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         load_i,
    input  wire [127:0] key_i,
    input  wire [127:0] data_i,
    output wire [127:0] data_o,
    output wire         busy_o,
    output wire         trigger_o
);

    localparam [31:0] MAGIC = 32'h50485831; // "PHX1"

    localparam [3:0] S_IDLE            = 4'd0,
                     S_START_ISSUE     = 4'd1,
                     S_WAIT_BUSY       = 4'd2,
                     S_WAIT_DONE       = 4'd3,
                     S_MEM_WRITE_ISSUE = 4'd4,
                     S_MEM_WRITE_DONE  = 4'd5,
                     S_MEM_READ_ISSUE  = 4'd6,
                     S_MEM_READ_WAIT   = 4'd7,
                     S_MEM_READ_DONE   = 4'd8,
                     S_BULK_ISSUE      = 4'd9,
                     S_BULK_STEP       = 4'd10,
                     S_DONE            = 4'd11;

    reg [3:0] state;
    reg       busy_r;
    reg [127:0] data_o_r;

    reg        instr_valid_r;
    reg [8:0]  instr_r;
    wire       core_busy;
    wire       core_done;
    wire [31:0] core_cycle_count;

    reg        host_valid_r;
    reg        host_we_r;
    reg        host_mem_r;
    reg [1:0]  host_region_r;
    reg [1:0]  host_bank_r;
    reg [9:0]  host_addr_r;
    reg [31:0] host_din_r;
    wire [31:0] host_dout;
    wire        host_ready;

    reg [3:0]   slot_r;
    reg [1:0]   region_r;
    reg [9:0]   addr_r;
    reg [127:0] payload_r;
    reg [1:0]   bulk_idx_r;
    reg [3:0]   error_code_r;

    wire cmd_start = key_i[127];
    wire cmd_bulk  = key_i[122];
    wire cmd_read  = key_i[121];
    wire slot_valid = (key_i[126:123] < 4'd8);
    wire region_valid = (key_i[120:119] < 2'd3);

    wire [31:0] dbg_pe_o00, dbg_pe_o01, dbg_pe_o10, dbg_pe_o11;
    wire        dbg_pe_v0, dbg_pe_v1;

    phoenix_top u_core (
        .clk(clk),
        .rst_n(rst_n),
        .instr_valid(instr_valid_r),
        .instr(instr_r),
        .busy(core_busy),
        .done(core_done),
        .cycle_count(core_cycle_count),
        .host_valid(host_valid_r),
        .host_we(host_we_r),
        .host_mem(host_mem_r),
        .host_region(host_region_r),
        .host_bank(host_bank_r),
        .host_addr(host_addr_r),
        .host_din(host_din_r),
        .host_dout(host_dout),
        .host_ready(host_ready),
        .dbg_pe_o00(dbg_pe_o00),
        .dbg_pe_o01(dbg_pe_o01),
        .dbg_pe_o10(dbg_pe_o10),
        .dbg_pe_o11(dbg_pe_o11),
        .dbg_pe_v0(dbg_pe_v0),
        .dbg_pe_v1(dbg_pe_v1)
    );

    function [31:0] bulk_word;
        input [127:0] payload;
        input [1:0]   idx;
        begin
            bulk_word = payload[idx*32 +: 32];
        end
    endfunction

    function [127:0] status_word;
        input [31:0] field1;
        input [31:0] field2;
        input [31:0] field3;
        begin
            status_word = {MAGIC, field1, field2, field3};
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            busy_r        <= 1'b0;
            data_o_r      <= {128{1'b0}};
            instr_valid_r <= 1'b0;
            instr_r       <= 9'b0;
            host_valid_r  <= 1'b0;
            host_we_r     <= 1'b0;
            host_mem_r    <= 1'b0;
            host_region_r <= 2'b0;
            host_bank_r   <= 2'b0;
            host_addr_r   <= 10'b0;
            host_din_r    <= 32'b0;
            slot_r        <= 4'b0;
            region_r      <= 2'b0;
            addr_r        <= 10'b0;
            payload_r     <= 128'b0;
            bulk_idx_r    <= 2'b0;
            error_code_r  <= 4'b0;
        end else begin
            instr_valid_r <= 1'b0;
            host_valid_r  <= 1'b0;
            host_we_r     <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy_r <= 1'b0;
                    error_code_r <= 4'b0;

                    if (load_i) begin
                        busy_r    <= 1'b1;
                        payload_r <= data_i;
                        addr_r    <= key_i[9:0];
                        slot_r    <= key_i[126:123];
                        region_r  <= key_i[120:119];

                        if (cmd_start) begin
                            if (!host_ready) begin
                                error_code_r <= 4'd1;
                                data_o_r <= status_word(32'hffff0001, 32'b0, 32'b0);
                                state <= S_DONE;
                            end else begin
                                instr_r <= key_i[126:118];
                                state <= S_START_ISSUE;
                            end
                        end else if (!slot_valid || !region_valid) begin
                            error_code_r <= 4'd2;
                            data_o_r <= status_word(32'hffff0002, {26'b0, key_i[120:119], key_i[126:123]}, 32'b0);
                            state <= S_DONE;
                        end else if (!host_ready) begin
                            error_code_r <= 4'd3;
                            data_o_r <= status_word(32'hffff0003, 32'b0, 32'b0);
                            state <= S_DONE;
                        end else if (cmd_read) begin
                            state <= S_MEM_READ_ISSUE;
                        end else if (cmd_bulk) begin
                            bulk_idx_r <= 2'b0;
                            state <= S_BULK_ISSUE;
                        end else begin
                            state <= S_MEM_WRITE_ISSUE;
                        end
                    end
                end

                S_START_ISSUE: begin
                    instr_valid_r <= 1'b1;
                    state <= S_WAIT_BUSY;
                end

                S_WAIT_BUSY: begin
                    if (core_busy) begin
                        state <= S_WAIT_DONE;
                    end
                end

                S_WAIT_DONE: begin
                    if (core_done) begin
                        data_o_r <= status_word(core_cycle_count, 32'b0, {30'b0, core_done, core_busy});
                        state <= S_DONE;
                    end
                end

                S_MEM_WRITE_ISSUE: begin
                    host_valid_r <= 1'b1;
                    host_we_r    <= 1'b1;
                    host_mem_r   <= slot_r[2];
                    host_region_r <= region_r;
                    host_bank_r  <= slot_r[1:0];
                    host_addr_r  <= addr_r;
                    host_din_r   <= payload_r[31:0];
                    state <= S_MEM_WRITE_DONE;
                end

                S_MEM_WRITE_DONE: begin
                    data_o_r <= status_word(32'b0, {16'b0, region_r, slot_r, addr_r}, payload_r[31:0]);
                    state <= S_DONE;
                end

                S_MEM_READ_ISSUE: begin
                    host_valid_r <= 1'b1;
                    host_we_r    <= 1'b0;
                    host_mem_r   <= slot_r[2];
                    host_region_r <= region_r;
                    host_bank_r  <= slot_r[1:0];
                    host_addr_r  <= addr_r;
                    state <= S_MEM_READ_WAIT;
                end

                S_MEM_READ_WAIT: begin
                    state <= S_MEM_READ_DONE;
                end

                S_MEM_READ_DONE: begin
                    data_o_r <= status_word(32'b0, {16'b0, region_r, slot_r, addr_r}, host_dout);
                    state <= S_DONE;
                end

                S_BULK_ISSUE: begin
                    host_valid_r <= 1'b1;
                    host_we_r    <= 1'b1;
                    host_mem_r   <= slot_r[2];
                    host_region_r <= region_r;
                    host_bank_r  <= slot_r[1:0];
                    host_addr_r  <= addr_r + {8'b0, bulk_idx_r};
                    host_din_r   <= bulk_word(payload_r, bulk_idx_r);
                    state <= S_BULK_STEP;
                end

                S_BULK_STEP: begin
                    if (bulk_idx_r == 2'd3) begin
                        data_o_r <= status_word(32'b0, {16'b0, region_r, slot_r, addr_r}, 32'h00000004);
                        state <= S_DONE;
                    end else begin
                        bulk_idx_r <= bulk_idx_r + 1'b1;
                        state <= S_BULK_ISSUE;
                    end
                end

                S_DONE: begin
                    busy_r <= 1'b0;
                    state <= S_IDLE;
                end

                default: begin
                    data_o_r <= status_word(32'hffff000f, {28'b0, error_code_r}, 32'b0);
                    state <= S_DONE;
                end
            endcase
        end
    end

    assign data_o = data_o_r;
    assign busy_o = busy_r || core_busy;
    assign trigger_o = core_busy;

endmodule

`default_nettype wire
