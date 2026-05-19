// -----------------------------------------------------------------------------
// cycle_counter.v
// Operation cycle counter for PHOENIX evaluation. Reset on `start` pulse,
// counts while `busy` is high and `done` is low. After `done`, the value is
// frozen until the next `start`.
// -----------------------------------------------------------------------------
`default_nettype none

module cycle_counter (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire        busy,
    input  wire        done,
    output reg  [31:0] cycle_count
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count <= 32'd0;
        end else if (start) begin
            cycle_count <= 32'd0;
        end else if (busy && !done) begin
            cycle_count <= cycle_count + 32'd1;
        end
    end

endmodule

`default_nettype wire
