// -----------------------------------------------------------------------------
// delay_line.v
// 파라미터화 파이프라인 지연 (SBU latency 정렬용, 핸드오버 §5.1).
// 본질적으로 pass-through 인 모듈 — REQ-RTL-015 예외로 companion .md 에 명시한다.
//
//   DEPTH = 0 : 조합 통과 (d_o = d_i)
//   DEPTH > 0 : DEPTH 단 레지스터 시프트 지연
//
// 비활성 datapath 도 이 모듈로 cycle alignment 를 맞춰 SBU 외부 latency 를
// 전 모드 8-cycle 로 고정한다 (REQ-RTL-011).
// -----------------------------------------------------------------------------
`default_nettype none

module delay_line #(
    parameter integer WIDTH = 32,
    parameter integer DEPTH = 1
)(
    input  wire                 clk_i,
    input  wire                 rst_ni,
    input  wire [WIDTH-1:0]     d_i,
    output wire [WIDTH-1:0]     d_o
);

    generate
        if (DEPTH == 0) begin : g_passthrough
            // 지연 0 — 조합 통과
            assign d_o = d_i;
        end else begin : g_shift
            integer i;
            reg [WIDTH-1:0] pipe [0:DEPTH-1];
            always @(posedge clk_i or negedge rst_ni) begin
                if (!rst_ni) begin
                    for (i = 0; i < DEPTH; i = i + 1)
                        pipe[i] <= {WIDTH{1'b0}};
                end else begin
                    pipe[0] <= d_i;
                    for (i = 1; i < DEPTH; i = i + 1)
                        pipe[i] <= pipe[i-1];
                end
            end
            assign d_o = pipe[DEPTH-1];
        end
    endgenerate

endmodule

`default_nettype wire
