// -----------------------------------------------------------------------------
// array_schoolbook_unsigned.v
// Unsigned combinational schoolbook multiplier built from shifted partial rows.
// No Verilog multiply operator is used in this datapath.
// -----------------------------------------------------------------------------
`default_nettype none

module array_schoolbook_unsigned #(
    parameter integer A_W = 16,
    parameter integer B_W = 16,
    parameter integer P_W = A_W + B_W
)(
    input  wire [A_W-1:0] a_i,
    input  wire [B_W-1:0] b_i,
    output wire [P_W-1:0] p_o
);
    wire [P_W-1:0] a_ext = {{(P_W-A_W){1'b0}}, a_i};
    wire [P_W-1:0] acc [0:B_W];
    assign acc[0] = {P_W{1'b0}};

    genvar i;
    generate
        for (i = 0; i < B_W; i = i + 1) begin : g_rows
            wire [P_W-1:0] row_i = b_i[i] ? (a_ext << i) : {P_W{1'b0}};
            assign acc[i+1] = acc[i] + row_i;
        end
    endgenerate

    assign p_o = acc[B_W];
endmodule

`default_nettype wire
