// -----------------------------------------------------------------------------
// phoenix_control_unit.v
// Top-level control FSM for the ML-KEM / ML-DSA accelerator.
//
// Decodes the 9-bit instruction word:
//   instr[8:7] = scheme field (00=ML-KEM, 01=ML-DSA, 10/11=reserved)
//   instr[6]   = u/d (memory-up / memory-down / both)
//   instr[5:2] = opcode
//   instr[1:0] = address (precompute starting offset)
//
// Supported opcodes:
//   0100 NTT
//   0001 INTT
//   0010 PWM
// -----------------------------------------------------------------------------
`include "sbu_config.vh"
`default_nettype none

module phoenix_control_unit (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        instr_valid,
    input  wire [8:0]  instr,
    output reg  [8:0]  sel0,
    output reg  [8:0]  sel1,
    output reg         pwm_chain,
    output reg         start_index,
    output reg         pointwise,
    output reg         pointwise_single,
    output reg         mem_down,
    output reg [11:0]  init_address,
    output reg [11:0]  poly_size_minus1,
    output reg [3:0]   layer,
    output reg         busy,
    output reg         done,
    input  wire        index_done
);

    // Decoded fields
    wire       reserved = instr[8];
    wire       scheme   = instr[7];     // 0 = ML-KEM, 1 = ML-DSA
    wire       updown   = instr[6];
    wire [3:0] opcode   = instr[5:2];
    wire [1:0] addr_off = instr[1:0];

    wire is_mldsa = scheme;

    localparam [3:0] OP_FWD       = 4'b0100;
    localparam [3:0] OP_INV       = 4'b0001;
    localparam [3:0] OP_PWM       = 4'b0010;
    // FSM
    localparam [2:0] S_IDLE = 3'd0,
                     S_RUN  = 3'd1,
                     S_DRAIN = 3'd2,
                     S_DONE = 3'd3;
    reg [2:0] state;
    reg [3:0] cur_layer;
    reg [3:0] last_layer;
    reg [4:0] drain_ctr;
    reg [4:0] drain_cycles;
    reg       descending_layers;

    localparam integer DRAIN_SINGLE = `SBU_LATENCY + 1;
    localparam integer DRAIN_CHAIN  = (`SBU_LATENCY * 2) + 2;

    function [4:0] op_drain_cycles;
        input scheme_sel;
        input [3:0] op;
        begin
            if (!scheme_sel && (op == OP_PWM)) begin
                // BRAM read + SBU0 + cascade register + SBU1 + write-back.
                op_drain_cycles = DRAIN_CHAIN;
            end else begin
                op_drain_cycles = DRAIN_SINGLE;
            end
        end
    endfunction

    function [3:0] op_last_layer;
        input scheme_sel;
        input [3:0] op;
        begin
            if (op == OP_PWM) begin
                op_last_layer = 4'd0;
            end else if (!scheme_sel) begin
                op_last_layer = 4'd6;   // ML-KEM incomplete NTT: seven layers
            end else begin
                op_last_layer = 4'd7;   // ML-DSA full 256-word NTT
            end
        end
    endfunction

    function [11:0] op_poly_size_minus1;
        input scheme_sel;
        input [3:0] op;
        begin
            if (!scheme_sel) begin
                op_poly_size_minus1 = 12'd127;   // 256 coefficients packed into 128 words
            end else begin
                op_poly_size_minus1 = 12'd255;   // 256 ML-DSA coefficients
            end
        end
    endfunction

    function op_descending_layers;
        input [3:0] op;
        begin
            op_descending_layers = (op == OP_FWD);
        end
    endfunction

    function op_supported;
        input scheme_sel;
        input [3:0] op;
        begin
            op_supported = (op == OP_FWD) ||
                           (op == OP_INV) ||
                           (op == OP_PWM);
        end
    endfunction

    function op_offset_valid;
        input scheme_sel;
        input [3:0] op;
        input [1:0] addr;
        reg [12:0] start_ext;
        reg [12:0] last_ext;
        begin
            start_ext = {1'b0, addr, 10'b0};
            last_ext = start_ext + {1'b0, op_poly_size_minus1(scheme_sel, op)};
            op_offset_valid = (last_ext <= 13'd4095);
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= S_IDLE;
            sel0             <= 9'b0;
            sel1             <= 9'b0;
            pwm_chain        <= 1'b0;
            start_index      <= 1'b0;
            pointwise        <= 1'b0;
            pointwise_single <= 1'b0;
            mem_down         <= 1'b0;
            init_address     <= 12'b0;
            poly_size_minus1 <= 12'd127;
            layer            <= 4'd0;
            cur_layer        <= 4'd0;
            last_layer       <= 4'd0;
            drain_ctr        <= 5'd0;
            drain_cycles     <= DRAIN_SINGLE;
            descending_layers <= 1'b0;
            busy             <= 1'b0;
            done             <= 1'b0;
        end else begin
            start_index <= 1'b0;
            done        <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (instr_valid) begin
                        if (reserved ||
                            !op_supported(scheme, opcode) ||
                            !op_offset_valid(scheme, opcode, addr_off)) begin
                            sel0 <= `SBU_MOD_ADD;
                            sel1 <= `SBU_MOD_ADD;
                            pwm_chain <= 1'b0;
                            pointwise <= 1'b0;
                            pointwise_single <= 1'b0;
                            mem_down <= 1'b0;
                            start_index <= 1'b0;
                            busy <= 1'b1;
                            state <= S_DONE;
                        end else begin
                            // Default mode codes
                            case (opcode)
                                OP_FWD: begin
                                    sel0 <= is_mldsa ? `SBU_MLDSA_NTT  : `SBU_NTT_CT;
                                    sel1 <= is_mldsa ? `SBU_MLDSA_NTT  : `SBU_NTT_CT;
                                    pwm_chain <= 1'b0;
                                    pointwise <= 1'b0;
                                    pointwise_single <= 1'b0;
                                end
                                OP_INV: begin
                                    sel0 <= is_mldsa ? `SBU_MLDSA_INTT : `SBU_INTT_GS;
                                    sel1 <= is_mldsa ? `SBU_MLDSA_INTT : `SBU_INTT_GS;
                                    pwm_chain <= 1'b0;
                                    pointwise <= 1'b0;
                                    pointwise_single <= 1'b0;
                                end
                                OP_PWM: begin
                                    if (is_mldsa) begin
                                        sel0 <= `SBU_MLDSA_PWM;
                                        sel1 <= `SBU_MLDSA_PWM;
                                        pwm_chain <= 1'b0;
                                        pointwise <= 1'b1;
                                        pointwise_single <= 1'b0;
                                    end else begin
                                        sel0 <= `SBU_PWM0;
                                        sel1 <= `SBU_PWM1;
                                        pwm_chain <= 1'b1;
                                        pointwise <= 1'b1;
                                        pointwise_single <= 1'b1;
                                    end
                                end
                                default: begin
                                    sel0 <= `SBU_MOD_ADD;
                                    sel1 <= `SBU_MOD_ADD;
                                    pwm_chain <= 1'b0;
                                    pointwise <= 1'b0;
                                    pointwise_single <= 1'b0;
                                end
                            endcase

                            poly_size_minus1 <= op_poly_size_minus1(scheme, opcode);
                            last_layer       <= op_last_layer(scheme, opcode);
                            drain_cycles     <= op_drain_cycles(scheme, opcode);
                            descending_layers <= op_descending_layers(opcode);
                            mem_down         <= updown;

                            init_address <= {addr_off, 10'b0};
                            layer        <= op_descending_layers(opcode) ? op_last_layer(scheme, opcode) : 4'd0;
                            cur_layer    <= op_descending_layers(opcode) ? op_last_layer(scheme, opcode) : 4'd0;
                            drain_ctr    <= 5'd0;
                            start_index  <= 1'b1;
                            busy         <= 1'b1;
                            state        <= S_RUN;
                        end
                    end
                end

                S_RUN: begin
                    busy <= 1'b1;

                    if (index_done && descending_layers && (cur_layer > 4'd0)) begin
                        cur_layer   <= cur_layer - 1'b1;
                        layer       <= cur_layer - 1'b1;
                        start_index <= 1'b1;
                    end else if (index_done && !descending_layers && (cur_layer < last_layer)) begin
                        cur_layer   <= cur_layer + 1;
                        layer       <= cur_layer + 1;
                        start_index <= 1'b1;
                    end else if (index_done) begin
                        drain_ctr <= 5'd0;
                        state     <= S_DRAIN;
                    end
                end

                S_DRAIN: begin
                    busy <= 1'b1;
                    if (drain_ctr + 1'b1 >= drain_cycles) begin
                        state <= S_DONE;
                    end else begin
                        drain_ctr <= drain_ctr + 1'b1;
                    end
                end

                S_DONE: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
