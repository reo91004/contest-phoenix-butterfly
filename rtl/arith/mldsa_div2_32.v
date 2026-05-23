// -----------------------------------------------------------------------------
// mldsa_div2_32.v
// Modular division by two over q=8380417.
// -----------------------------------------------------------------------------
`include "phoenix_defs.vh"
`default_nettype none

module mldsa_div2_32 (
    input  wire [31:0] a_i,
    output wire [31:0] c_o
);
    localparam [23:0] Q24 = 24'd8380417;

    wire [23:0] a_v = {1'b0, a_i[22:0]};
    wire [23:0] odd_adjusted = a_v + Q24;
    wire [23:0] half = a_i[0] ? {1'b0, odd_adjusted[23:1]}
                              : {1'b0, a_v[23:1]};

    assign c_o = {9'b0, half[22:0]};
endmodule

`default_nettype wire
