// -----------------------------------------------------------------------------
// coefficient_index_gen.v  (구 coefficient_index.v — 재배치, 로직 보존)
// Coefficient Index unit (paper Fig 9, §4.2.1).
//
// Pipeline:
//   INIT_ADDRESS -> UPDATE_UNIT -> INDEX_SBU0 / INDEX_SBU1 -> BANK_DECODER
//
// Per FFT-like operation, the scheduler emits two butterfly pairs per cycle
// for the two-SBU PE. The pair grouping below is chosen so the MRW+22 bank
// decoder sees four distinct banks for the four coefficient reads.
//
// Conventions:
//   poly_size  = N - 1, where N is the number of 32-bit coefficient words
//   layer      = 0..log2(N) - 1
//   step       = 1 << layer (pair stride within a butterfly group)
//   pointwise  = PWM schedule, where coefficients are consumed by index
//                rather than by FFT-like butterfly pairs.
// -----------------------------------------------------------------------------
`default_nettype none

module coefficient_index_gen #(
    parameter integer INDEX_W   = 12,
    parameter integer LAYER_W   = 4
)(
    input  wire                clk,
    input  wire                rst_n,
    input  wire                start,
    input  wire [INDEX_W-1:0]  init_address,
    input  wire [INDEX_W-1:0]  poly_size,    // N - 1
    input  wire [LAYER_W-1:0]  layer,
    input  wire                pointwise,
    input  wire                pointwise_single,
    output reg  [INDEX_W-1:0]  idx_sbu0_a,
    output reg  [INDEX_W-1:0]  idx_sbu0_b,
    output reg  [INDEX_W-1:0]  idx_sbu1_a,
    output reg  [INDEX_W-1:0]  idx_sbu1_b,
    output reg                 valid_out,
    output reg                 done
);

    reg [INDEX_W-1:0] pair_base;
    reg [INDEX_W-1:0] pair_within;
    reg [INDEX_W-1:0] pair_delta;
    // One extra count bit keeps the comparisons exact for all supported sizes.
    reg [INDEX_W:0]   total_pairs;
    reg               running;
    wire [INDEX_W:0]  poly_words = {1'b0, poly_size} + {{INDEX_W{1'b0}}, 1'b1};

    function [INDEX_W-1:0] pair_a;
        input [INDEX_W-1:0] pair_id;
        input [LAYER_W-1:0] layer_id;
        reg   [INDEX_W-1:0] step_v;
        reg   [INDEX_W-1:0] group_v;
        reg   [INDEX_W-1:0] within_v;
        begin
            step_v   = ({{(INDEX_W-1){1'b0}}, 1'b1} << layer_id);
            group_v  = pair_id >> layer_id;
            within_v = pair_id & (step_v - 1'b1);
            pair_a   = (group_v << (layer_id + 1'b1)) + within_v;
        end
    endfunction

    function [INDEX_W-1:0] pair_b;
        input [INDEX_W-1:0] pair_id;
        input [LAYER_W-1:0] layer_id;
        begin
            pair_b = pair_a(pair_id, layer_id) + ({{(INDEX_W-1){1'b0}}, 1'b1} << layer_id);
        end
    endfunction

    function [INDEX_W:0] add2_ext;
        input [INDEX_W-1:0] x;
        input [INDEX_W-1:0] y;
        begin
            add2_ext = {1'b0, x} + {1'b0, y};
        end
    endfunction

    function [INDEX_W:0] add3_ext;
        input [INDEX_W-1:0] x;
        input [INDEX_W-1:0] y;
        input [INDEX_W-1:0] z;
        begin
            add3_ext = {1'b0, x} + {1'b0, y} + {1'b0, z};
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pair_base  <= 0;
            pair_within <= 0;
            pair_delta <= 1;
            total_pairs <= 0;
            running    <= 1'b0;
            idx_sbu0_a <= 0;
            idx_sbu0_b <= 0;
            idx_sbu1_a <= 0;
            idx_sbu1_b <= 0;
            valid_out  <= 1'b0;
            done       <= 1'b0;
        end else if (start) begin
            pair_base   <= 0;
            pair_within <= 0;
            pair_delta  <= pointwise ? (pointwise_single ? 1 : 2)
                                     : (((layer == 0) || layer[0]) ? 1 : 2);
            total_pairs <= pointwise ? poly_words
                                     : (poly_words >> 1);
            valid_out  <= 1'b0;
            done       <= 1'b0;
            running    <= 1'b1;
        end else if (running) begin
            if (pointwise) begin
                idx_sbu0_a <= init_address + pair_base;
                idx_sbu0_b <= init_address + pair_base;
                idx_sbu1_a <= init_address + pair_base + (pointwise_single ? 0 : 1);
                idx_sbu1_b <= init_address + pair_base + (pointwise_single ? 0 : 1);
                valid_out  <= 1'b1;

                if (add2_ext(pair_base, pair_delta) >= total_pairs) begin
                    done    <= 1'b1;
                    running <= 1'b0;
                end else begin
                    pair_base <= pair_base + pair_delta;
                end
            end else begin
                idx_sbu0_a <= init_address + pair_a(pair_base + pair_within, layer);
                idx_sbu0_b <= init_address + pair_b(pair_base + pair_within, layer);
                idx_sbu1_a <= init_address + pair_a(pair_base + pair_within + pair_delta, layer);
                idx_sbu1_b <= init_address + pair_b(pair_base + pair_within + pair_delta, layer);
                valid_out  <= 1'b1;

                if (add3_ext(pair_base, pair_within, pair_delta) >= total_pairs) begin
                    valid_out <= 1'b0;
                    done      <= 1'b1;
                    running   <= 1'b0;
                end else if (pair_within + 1'b1 >= pair_delta) begin
                    if (add2_ext(pair_base, pair_delta << 1) >= total_pairs) begin
                        done    <= 1'b1;
                        running <= 1'b0;
                    end else begin
                        pair_base   <= pair_base + (pair_delta << 1);
                        pair_within <= 0;
                    end
                end else begin
                    pair_within <= pair_within + 1'b1;
                end
            end
        end else begin
            valid_out <= 1'b0;
            done      <= 1'b0;
        end
    end

endmodule

`default_nettype wire
