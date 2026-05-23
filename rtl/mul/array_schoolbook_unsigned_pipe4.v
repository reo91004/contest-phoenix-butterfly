// -----------------------------------------------------------------------------
// array_schoolbook_unsigned_pipe4.v
// Four-cycle unsigned schoolbook multiplier using a carry-save reduction tree
// followed by one final carry-propagate adder. The multiplier rows are explicit
// partial products; no Verilog multiply operator or DSP inference is used.
// -----------------------------------------------------------------------------
`default_nettype none

module csa_reduce_level #(
    parameter integer W = 33,
    parameter integer N_IN = 16,
    parameter integer N_GROUPS = N_IN / 3,
    parameter integer N_REM = N_IN - (N_GROUPS * 3),
    parameter integer N_OUT = (N_GROUPS * 2) + N_REM
)(
    input  wire [N_IN*W-1:0]  rows_i,
    output wire [N_OUT*W-1:0] rows_o
);
    genvar g;
    generate
        for (g = 0; g < N_GROUPS; g = g + 1) begin : g_csa
            wire [W-1:0] x = rows_i[(3*g + 0)*W +: W];
            wire [W-1:0] y = rows_i[(3*g + 1)*W +: W];
            wire [W-1:0] z = rows_i[(3*g + 2)*W +: W];
            wire [W-1:0] carry_bits = (x & y) | (x & z) | (y & z);

            assign rows_o[(2*g + 0)*W +: W] = x ^ y ^ z;
            assign rows_o[(2*g + 1)*W +: W] = {carry_bits[W-2:0], 1'b0};
        end

        if (N_REM >= 1) begin : g_rem0
            assign rows_o[(2*N_GROUPS + 0)*W +: W] =
                rows_i[(3*N_GROUPS + 0)*W +: W];
        end

        if (N_REM >= 2) begin : g_rem1
            assign rows_o[(2*N_GROUPS + 1)*W +: W] =
                rows_i[(3*N_GROUPS + 1)*W +: W];
        end
    endgenerate
endmodule

module array_schoolbook_unsigned_pipe4 #(
    parameter integer A_W = 16,
    parameter integer B_W = 16,
    parameter integer P_W = A_W + B_W
)(
    input  wire             clk_i,
    input  wire [A_W-1:0]   a_i,
    input  wire [B_W-1:0]   b_i,
    output wire [P_W-1:0]   p_o
);
    localparam integer R_W = P_W + 1;
    localparam integer N0 = B_W;
    localparam integer N1 = ((N0 / 3) * 2) + (N0 - ((N0 / 3) * 3));
    localparam integer N2 = ((N1 / 3) * 2) + (N1 - ((N1 / 3) * 3));
    localparam integer N3 = ((N2 / 3) * 2) + (N2 - ((N2 / 3) * 3));
    localparam integer N4 = ((N3 / 3) * 2) + (N3 - ((N3 / 3) * 3));
    localparam integer N5 = ((N4 / 3) * 2) + (N4 - ((N4 / 3) * 3));
    localparam integer N6 = ((N5 / 3) * 2) + (N5 - ((N5 / 3) * 3));

    wire [R_W-1:0] a_ext = {{(R_W-A_W){1'b0}}, a_i};
    wire [N0*R_W-1:0] pp_rows;

    genvar i;
    generate
        for (i = 0; i < B_W; i = i + 1) begin : g_pp
            assign pp_rows[i*R_W +: R_W] = b_i[i] ? (a_ext << i) : {R_W{1'b0}};
        end
    endgenerate

    wire [N1*R_W-1:0] level1_rows;
    wire [N2*R_W-1:0] level2_rows;
    wire [N3*R_W-1:0] level3_rows;
    wire [N4*R_W-1:0] level4_rows;
    wire [N5*R_W-1:0] level5_rows;
    wire [N6*R_W-1:0] level6_rows;

    csa_reduce_level #(.W(R_W), .N_IN(N0)) u_level1 (
        .rows_i(pp_rows),
        .rows_o(level1_rows)
    );
    csa_reduce_level #(.W(R_W), .N_IN(N1)) u_level2 (
        .rows_i(level1_rows),
        .rows_o(level2_rows)
    );
    csa_reduce_level #(.W(R_W), .N_IN(N2)) u_level3 (
        .rows_i(level2_rows),
        .rows_o(level3_rows)
    );
    csa_reduce_level #(.W(R_W), .N_IN(N3)) u_level4 (
        .rows_i(level3_rows),
        .rows_o(level4_rows)
    );
    csa_reduce_level #(.W(R_W), .N_IN(N4)) u_level5 (
        .rows_i(level4_rows),
        .rows_o(level5_rows)
    );
    csa_reduce_level #(.W(R_W), .N_IN(N5)) u_level6 (
        .rows_i(level5_rows),
        .rows_o(level6_rows)
    );

    wire [R_W-1:0] reduced_sum = level6_rows[0 +: R_W];
    wire [R_W-1:0] reduced_carry = level6_rows[R_W +: R_W];

    reg [R_W-1:0] sum1;
    reg [R_W-1:0] carry1;
    reg [P_W-1:0] prod2;
    reg [P_W-1:0] prod3;
    reg [P_W-1:0] prod4;

    wire [R_W:0] final_product = {1'b0, sum1} + {1'b0, carry1};

    always @(posedge clk_i) begin
        sum1   <= reduced_sum;
        carry1 <= reduced_carry;
        prod2  <= final_product[P_W-1:0];
        prod3  <= prod2;
        prod4  <= prod3;
    end

    assign p_o = prod4;
endmodule

`default_nettype wire
