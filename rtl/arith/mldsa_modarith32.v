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
    wire [31:0] add_r;
    wire [31:0] sub_r;
    mldsa_modadd32 u_add (.a_i(a_i), .b_i(b_i), .c_o(add_r));
    mldsa_modsub32 u_sub (.a_i(a_i), .b_i(b_i), .c_o(sub_r));

    wire [31:0] as_r = addsub_i ? sub_r : add_r;
    wire [31:0] div_r;
    mldsa_div2_32 u_div (.a_i(as_r), .c_o(div_r));
    assign c_o = intt_i ? div_r : as_r;
endmodule

`default_nettype wire
