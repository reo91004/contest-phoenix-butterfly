// -----------------------------------------------------------------------------
// superbutterfly_sbu.v
// SBU public wrapper (핸드오버 §5.6,§12). USE_REF=0 → routed (합성 기본),
// USE_REF=1 → reference. 외부 latency = 8 cycle, 두 구현 equivalence 보장.
// -----------------------------------------------------------------------------
`default_nettype none

module superbutterfly_sbu #(
    parameter integer USE_REF = 0   // 0: routed (Figure 3), 1: reference
)(
    input  wire        clk_i,
    input  wire        rst_ni,
    input  wire        valid_i,
    input  wire [8:0]  sel_i,
    input  wire [31:0] a_i,
    input  wire [31:0] b_i,
    input  wire [31:0] c_i,
    input  wire [31:0] a_mask_i,
    input  wire [31:0] b_mask_i,
    input  wire [31:0] c_mask_i,
    input  wire [31:0] rand_i,
    output wire        valid_o,
    output wire [31:0] y0_o,
    output wire [31:0] y1_o,
    output wire [31:0] y0_mask_o,
    output wire [31:0] y1_mask_o
);
    generate
        if (USE_REF != 0) begin : g_ref
            superbutterfly_sbu_ref u_sbu (
                .clk_i(clk_i), .rst_ni(rst_ni), .valid_i(valid_i), .sel_i(sel_i),
                .a_i(a_i), .b_i(b_i), .c_i(c_i),
                .a_mask_i(a_mask_i), .b_mask_i(b_mask_i), .c_mask_i(c_mask_i),
                .rand_i(rand_i),
                .valid_o(valid_o), .y0_o(y0_o), .y1_o(y1_o),
                .y0_mask_o(y0_mask_o), .y1_mask_o(y1_mask_o)
            );
        end else begin : g_routed
            superbutterfly_sbu_routed u_sbu (
                .clk_i(clk_i), .rst_ni(rst_ni), .valid_i(valid_i), .sel_i(sel_i),
                .a_i(a_i), .b_i(b_i), .c_i(c_i),
                .a_mask_i(a_mask_i), .b_mask_i(b_mask_i), .c_mask_i(c_mask_i),
                .rand_i(rand_i),
                .valid_o(valid_o), .y0_o(y0_o), .y1_o(y1_o),
                .y0_mask_o(y0_mask_o), .y1_mask_o(y1_mask_o)
            );
        end
    endgenerate
endmodule

`default_nettype wire
