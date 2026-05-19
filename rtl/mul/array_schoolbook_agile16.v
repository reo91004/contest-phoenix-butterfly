// -----------------------------------------------------------------------------
// array_schoolbook_agile16.v
// 16x16 unsigned integer schoolbook multiplier for ML-KEM lane products.
// The compatibility parameters and carry_en_i input are kept so existing
// instantiations stay stable, but the active design now has integer behavior
// only. No Verilog multiply operator is used in this datapath.
// -----------------------------------------------------------------------------
`default_nettype none

module array_schoolbook_agile16 #(
    parameter integer CARRY_GATED_ARRAY = 0
)(
    input  wire [15:0] a_i,
    input  wire [15:0] b_i,
    input  wire        carry_en_i,
    output wire [31:0] p_o
);
    wire unused_carry_en = carry_en_i;
    wire unused_param = (CARRY_GATED_ARRAY == 0);

    array_schoolbook_unsigned #(.A_W(16), .B_W(16), .P_W(32)) u_mul (
        .a_i(a_i),
        .b_i(b_i),
        .p_o(p_o)
    );
endmodule

`default_nettype wire
