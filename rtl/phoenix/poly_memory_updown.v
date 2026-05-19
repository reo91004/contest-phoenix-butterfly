// -----------------------------------------------------------------------------
// poly_memory_updown.v  (구 polynomial_memory.v — 재배치, 로직 보존)
// 8 dual-port BRAMs grouped as memory-up (4 banks) and memory-down (4 banks).
// Each BRAM is 1024 x 32-bit (paper §4.2.2).
//
// Two read/write port groups feed the Processing Element (SBU0 + SBU1). The
// PE consumes a coefficient PAIR per cycle, so per cycle we read four
// coefficients across the two memory sides.
//
// Ports use 4xW packed buses (Verilog-2001 portable) where the 4 banks live
// in 4 stacked stripes:
//
//   bus[4*W-1 : 3*W] = bank3
//   bus[3*W-1 : 2*W] = bank2
//   bus[2*W-1 : 1*W] = bank1
//   bus[1*W-1 : 0  ] = bank0
//
// The bank_decoder selects which stripe each access targets.
// -----------------------------------------------------------------------------
`default_nettype none

module poly_memory_updown #(
    parameter integer DEPTH      = 1024,
    parameter integer DATA_W     = 32,
    parameter integer ADDR_W     = 10
)(
    input  wire                clk,

    // memory-up: 4 banks, port-a (read) + port-b (write)
    input  wire [3:0]              mu_a_we,
    input  wire [4*ADDR_W-1:0]     mu_a_addr,
    input  wire [4*DATA_W-1:0]     mu_a_din,
    output wire [4*DATA_W-1:0]     mu_a_dout,

    input  wire [3:0]              mu_b_we,
    input  wire [4*ADDR_W-1:0]     mu_b_addr,
    input  wire [4*DATA_W-1:0]     mu_b_din,

    // memory-down: 4 banks, port-a (read) + port-b (write)
    input  wire [3:0]              md_a_we,
    input  wire [4*ADDR_W-1:0]     md_a_addr,
    input  wire [4*DATA_W-1:0]     md_a_din,
    output wire [4*DATA_W-1:0]     md_a_dout,

    input  wire [3:0]              md_b_we,
    input  wire [4*ADDR_W-1:0]     md_b_addr,
    input  wire [4*DATA_W-1:0]     md_b_din
);

    genvar gi;
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : g_mu
            bram_dp #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) u_mu (
                .clk    (clk),
                .a_we   (mu_a_we[gi]),
                .a_addr (mu_a_addr[(gi+1)*ADDR_W-1 -: ADDR_W]),
                .a_din  (mu_a_din [(gi+1)*DATA_W-1 -: DATA_W]),
                .a_dout (mu_a_dout[(gi+1)*DATA_W-1 -: DATA_W]),
                .b_we   (mu_b_we[gi]),
                .b_addr (mu_b_addr[(gi+1)*ADDR_W-1 -: ADDR_W]),
                .b_din  (mu_b_din [(gi+1)*DATA_W-1 -: DATA_W])
            );
        end
        for (gi = 0; gi < 4; gi = gi + 1) begin : g_md
            bram_dp #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) u_md (
                .clk    (clk),
                .a_we   (md_a_we[gi]),
                .a_addr (md_a_addr[(gi+1)*ADDR_W-1 -: ADDR_W]),
                .a_din  (md_a_din [(gi+1)*DATA_W-1 -: DATA_W]),
                .a_dout (md_a_dout[(gi+1)*DATA_W-1 -: DATA_W]),
                .b_we   (md_b_we[gi]),
                .b_addr (md_b_addr[(gi+1)*ADDR_W-1 -: ADDR_W]),
                .b_din  (md_b_din [(gi+1)*DATA_W-1 -: DATA_W])
            );
        end
    endgenerate

endmodule


// -----------------------------------------------------------------------------
// True dual-port BRAM (synchronous read, single clock domain).
//
// PHOENIX's conflict-free scheduler and delayed write-back avoid read-after-write
// hazards at the algorithm level, so same-cycle write-through is not required.
// Keeping the BRAM ports as plain synchronous reads avoids per-bit bypass muxes
// and matches the paper Table 7 accounting where Polynomial Memories are BRAMs,
// not LUT datapath.
// Vivado infers BRAM when DEPTH * DATA_W is large enough.
// -----------------------------------------------------------------------------
module bram_dp #(
    parameter integer DATA_W = 32,
    parameter integer ADDR_W = 10
)(
    input  wire                clk,
    input  wire                a_we,
    input  wire [ADDR_W-1:0]   a_addr,
    input  wire [DATA_W-1:0]   a_din,
    output reg  [DATA_W-1:0]   a_dout,
    input  wire                b_we,
    input  wire [ADDR_W-1:0]   b_addr,
    input  wire [DATA_W-1:0]   b_din
);
    (* ram_style = "block" *) reg [DATA_W-1:0] mem [0:(1<<ADDR_W)-1];
    integer mi;
    initial begin
        for (mi = 0; mi < (1 << ADDR_W); mi = mi + 1) begin
            mem[mi] = {DATA_W{1'b0}};
        end
    end

    always @(posedge clk) begin
        if (a_we) mem[a_addr] <= a_din;
        a_dout <= mem[a_addr];
    end
    always @(posedge clk) begin
        if (b_we) mem[b_addr] <= b_din;
    end
endmodule

`default_nettype wire
