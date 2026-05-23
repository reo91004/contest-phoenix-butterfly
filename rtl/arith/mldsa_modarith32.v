// -----------------------------------------------------------------------------
// mldsa_modarith32.v
// Shared ML-DSA modular add/subtract with optional division by two.
// -----------------------------------------------------------------------------
`default_nettype none

module mldsa_modarith32 (
    input  wire [31:0] a_i,
    input  wire [31:0] b_i,
    input  wire        addsub_i,
    input  wire        intt_i,
    output wire [31:0] c_o
);
    localparam [23:0] Q24 = 24'd8380417;

    wire [23:0] a_v = {1'b0, a_i[22:0]};
    wire [23:0] b_v = {1'b0, b_i[22:0]};
    wire [23:0] raw_add = a_v + b_v;
    wire [23:0] raw_sub = a_v + Q24 - b_v;
    wire [23:0] raw = addsub_i ? raw_sub : raw_add;
    wire [23:0] raw_minus_q = raw - Q24;
    wire [23:0] red = (raw >= Q24) ? raw_minus_q : raw;

    wire [23:0] odd_adjusted = red + Q24;
    wire [23:0] div_r = red[0] ? {1'b0, odd_adjusted[23:1]}
                               : {1'b0, red[23:1]};
    wire [23:0] out_v = intt_i ? div_r : red;

    assign c_o = {9'b0, out_v[22:0]};
endmodule

`default_nettype wire
