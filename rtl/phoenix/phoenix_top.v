// -----------------------------------------------------------------------------
// phoenix_top.v
// Top-level wrapper for ML-KEM / ML-DSA operation-level evaluation.
//
// Combines: Processing Element (2x SBU), Polynomial Memory, Constant Memory,
//           Coefficient Index, Bank Decoder, Phoenix Control, Cycle Counter.
//
// The core exposes an operation-level PHOENIX datapath suitable for RTL
// simulation and Vivado area/cycle evaluation. A narrow host memory port is
// provided for board wrappers to preload/read polynomial banks while idle.
//
// Interface (loosely-coupled, paper §5.1):
//   instr_valid + instr[8:0]   - one-shot command (Fig 11)
//   busy / done                - status
//   cycle_count                - operation cycle telemetry
//
// Bus / DMA shim (AXI4-Lite or CW305 USB register protocol) remains outside
// this module and should only drive the host port when host_ready is high.
// -----------------------------------------------------------------------------
`include "sbu_config.vh"
`default_nettype none

module phoenix_top #(
    parameter integer INDEX_W = 12,
    parameter integer ADDR_W  = 10,
    parameter integer DATA_W  = 32
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         instr_valid,
    input  wire [8:0]   instr,
    output wire         busy,
    output wire         done,
    output wire [31:0]  cycle_count,
    // Host memory access, valid only while host_ready is high.
    input  wire         host_valid,
    input  wire         host_we,
    input  wire         host_mem,       // 0 = memory-up, 1 = memory-down
    input  wire [1:0]   host_bank,
    input  wire [ADDR_W-1:0] host_addr,
    input  wire [DATA_W-1:0] host_din,
    output wire [DATA_W-1:0] host_dout,
    output wire         host_ready,
    // Debug taps expose PE outputs for simulation and waveform inspection.
    output wire [31:0]  dbg_pe_o00,
    output wire [31:0]  dbg_pe_o01,
    output wire [31:0]  dbg_pe_o10,
    output wire [31:0]  dbg_pe_o11,
    output wire         dbg_pe_v0,
    output wire         dbg_pe_v1
);

    localparam integer WB_LAT  = 9;  // BRAM read latency + SBU pipeline

    // ---- Control ----
    wire [8:0]  ctl_sel0, ctl_sel1;
    wire        ctl_pwm_chain;
    wire        ctl_start_index;
    wire        ctl_pointwise;
    wire        ctl_pointwise_single;
    wire        ctl_mem_down;
    wire [INDEX_W-1:0] ctl_init_address;
    wire [INDEX_W-1:0] ctl_poly_size_minus1;
    wire [3:0]  ctl_layer;
    wire        ctl_busy;
    wire        ctl_done;
    wire        idx_done;

    phoenix_control_unit u_ctl (
        .clk              (clk),
        .rst_n            (rst_n),
        .instr_valid      (instr_valid),
        .instr            (instr),
        .sel0             (ctl_sel0),
        .sel1             (ctl_sel1),
        .pwm_chain        (ctl_pwm_chain),
        .start_index      (ctl_start_index),
        .pointwise        (ctl_pointwise),
        .pointwise_single (ctl_pointwise_single),
        .mem_down         (ctl_mem_down),
        .init_address     (ctl_init_address),
        .poly_size_minus1 (ctl_poly_size_minus1),
        .layer            (ctl_layer),
        .busy             (ctl_busy),
        .done             (ctl_done),
        .index_done       (idx_done)
    );

    // ---- Coefficient Index + Bank Decoders ----
    wire [INDEX_W-1:0] idx0_a, idx0_b, idx1_a, idx1_b;
    wire        idx_valid;

    coefficient_index_gen u_idx (
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (ctl_start_index),
        .init_address(ctl_init_address),
        .poly_size   (ctl_poly_size_minus1),
        .layer       (ctl_layer),
        .pointwise   (ctl_pointwise),
        .pointwise_single(ctl_pointwise_single),
        .idx_sbu0_a  (idx0_a),
        .idx_sbu0_b  (idx0_b),
        .idx_sbu1_a  (idx1_a),
        .idx_sbu1_b  (idx1_b),
        .valid_out   (idx_valid),
        .done        (idx_done)
    );

    wire [1:0] bk0a, bk0b, bk1a, bk1b;
    wire [ADDR_W-1:0] ad0a, ad0b, ad1a, ad1b;
    bank_decoder_4way u_bd0a (.index(idx0_a), .bank(bk0a), .address(ad0a));
    bank_decoder_4way u_bd0b (.index(idx0_b), .bank(bk0b), .address(ad0b));
    bank_decoder_4way u_bd1a (.index(idx1_a), .bank(bk1a), .address(ad1a));
    bank_decoder_4way u_bd1b (.index(idx1_b), .bank(bk1b), .address(ad1b));

    // ---- Polynomial Memory wiring ----
    function [4*ADDR_W-1:0] pack_addr4;
        input [1:0]        b0;
        input [ADDR_W-1:0] a0;
        input [1:0]        b1;
        input [ADDR_W-1:0] a1;
        input [1:0]        b2;
        input [ADDR_W-1:0] a2;
        input [1:0]        b3;
        input [ADDR_W-1:0] a3;
        integer b;
        begin
            pack_addr4 = {(4*ADDR_W){1'b0}};
            for (b = 0; b < 4; b = b + 1) begin
                if (b == b0) pack_addr4[(b+1)*ADDR_W-1 -: ADDR_W] = a0;
                if (b == b1) pack_addr4[(b+1)*ADDR_W-1 -: ADDR_W] = a1;
                if (b == b2) pack_addr4[(b+1)*ADDR_W-1 -: ADDR_W] = a2;
                if (b == b3) pack_addr4[(b+1)*ADDR_W-1 -: ADDR_W] = a3;
            end
        end
    endfunction

    function [4*DATA_W-1:0] pack_data4;
        input [1:0]         b0;
        input [DATA_W-1:0]  d0;
        input [1:0]         b1;
        input [DATA_W-1:0]  d1;
        input [1:0]         b2;
        input [DATA_W-1:0]  d2;
        input [1:0]         b3;
        input [DATA_W-1:0]  d3;
        integer b;
        begin
            pack_data4 = {(4*DATA_W){1'b0}};
            for (b = 0; b < 4; b = b + 1) begin
                if (b == b0) pack_data4[(b+1)*DATA_W-1 -: DATA_W] = d0;
                if (b == b1) pack_data4[(b+1)*DATA_W-1 -: DATA_W] = d1;
                if (b == b2) pack_data4[(b+1)*DATA_W-1 -: DATA_W] = d2;
                if (b == b3) pack_data4[(b+1)*DATA_W-1 -: DATA_W] = d3;
            end
        end
    endfunction

    function [3:0] pack_we4;
        input       valid;
        input [1:0] b0;
        input [1:0] b1;
        input [1:0] b2;
        input [1:0] b3;
        begin
            pack_we4 = 4'b0;
            if (valid) begin
                pack_we4[b0] = 1'b1;
                pack_we4[b1] = 1'b1;
                pack_we4[b2] = 1'b1;
                pack_we4[b3] = 1'b1;
            end
        end
    endfunction

    function [3:0] pack_we2;
        input       valid;
        input [1:0] b0;
        input [1:0] b1;
        begin
            pack_we2 = 4'b0;
            if (valid) begin
                pack_we2[b0] = 1'b1;
                pack_we2[b1] = 1'b1;
            end
        end
    endfunction

    function [3:0] pack_we1;
        input       valid;
        input [1:0] b0;
        begin
            pack_we1 = 4'b0;
            if (valid) begin
                pack_we1[b0] = 1'b1;
            end
        end
    endfunction

    wire [4*ADDR_W-1:0] read_addr = pack_addr4(bk0a, ad0a, bk0b, ad0b, bk1a, ad1a, bk1b, ad1b);
    wire host_active = host_valid && host_ready;
    wire host_mu = host_active && !host_mem;
    wire host_md = host_active &&  host_mem;
    wire [4*ADDR_W-1:0] host_addr4 = pack_addr4(host_bank, host_addr,
                                                host_bank, host_addr,
                                                host_bank, host_addr,
                                                host_bank, host_addr);
    wire [4*DATA_W-1:0] host_din4 = pack_data4(host_bank, host_din,
                                               host_bank, host_din,
                                               host_bank, host_din,
                                               host_bank, host_din);
    wire [3:0] host_we4 = pack_we1(host_active && host_we, host_bank);

    wire [4*DATA_W-1:0] mu_a_dout, md_a_dout;
    wire [DATA_W-1:0] sbu0_o0, sbu0_o1, sbu1_o0, sbu1_o1;
    wire              sbu0_vo, sbu1_vo;

    (* shreg_extract = "no" *) reg [1:0]        wb_b0 [0:WB_LAT-1];
    (* shreg_extract = "no" *) reg [1:0]        wb_b1 [0:WB_LAT-1];
    (* shreg_extract = "no" *) reg [1:0]        wb_b2 [0:WB_LAT-1];
    (* shreg_extract = "no" *) reg [1:0]        wb_b3 [0:WB_LAT-1];
    (* shreg_extract = "no" *) reg [ADDR_W-1:0] wb_a0 [0:WB_LAT-1];
    (* shreg_extract = "no" *) reg [ADDR_W-1:0] wb_a1 [0:WB_LAT-1];
    (* shreg_extract = "no" *) reg [ADDR_W-1:0] wb_a2 [0:WB_LAT-1];
    (* shreg_extract = "no" *) reg [ADDR_W-1:0] wb_a3 [0:WB_LAT-1];
    integer wi;

    localparam integer PWM_WB_LAT = 18;
    (* shreg_extract = "no" *) reg [1:0]        pwm_wb_b0 [0:PWM_WB_LAT-1];
    (* shreg_extract = "no" *) reg [ADDR_W-1:0] pwm_wb_a0 [0:PWM_WB_LAT-1];
    integer pwi;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (wi = 0; wi < WB_LAT; wi = wi + 1) begin
                wb_b0[wi] <= 2'b0; wb_b1[wi] <= 2'b0; wb_b2[wi] <= 2'b0; wb_b3[wi] <= 2'b0;
                wb_a0[wi] <= {ADDR_W{1'b0}}; wb_a1[wi] <= {ADDR_W{1'b0}};
                wb_a2[wi] <= {ADDR_W{1'b0}}; wb_a3[wi] <= {ADDR_W{1'b0}};
            end
            for (pwi = 0; pwi < PWM_WB_LAT; pwi = pwi + 1) begin
                pwm_wb_b0[pwi] <= 2'b0;
                pwm_wb_a0[pwi] <= {ADDR_W{1'b0}};
            end
        end else begin
            if (idx_valid) begin
                wb_b0[0] <= bk0a; wb_a0[0] <= ad0a;
                wb_b1[0] <= bk0b; wb_a1[0] <= ad0b;
                wb_b2[0] <= bk1a; wb_a2[0] <= ad1a;
                wb_b3[0] <= bk1b; wb_a3[0] <= ad1b;
                pwm_wb_b0[0] <= bk0a;
                pwm_wb_a0[0] <= ad0a;
            end else begin
                wb_b0[0] <= 2'b0; wb_a0[0] <= {ADDR_W{1'b0}};
                wb_b1[0] <= 2'b0; wb_a1[0] <= {ADDR_W{1'b0}};
                wb_b2[0] <= 2'b0; wb_a2[0] <= {ADDR_W{1'b0}};
                wb_b3[0] <= 2'b0; wb_a3[0] <= {ADDR_W{1'b0}};
                pwm_wb_b0[0] <= 2'b0;
                pwm_wb_a0[0] <= {ADDR_W{1'b0}};
            end
            for (wi = 1; wi < WB_LAT; wi = wi + 1) begin
                wb_b0[wi] <= wb_b0[wi-1]; wb_a0[wi] <= wb_a0[wi-1];
                wb_b1[wi] <= wb_b1[wi-1]; wb_a1[wi] <= wb_a1[wi-1];
                wb_b2[wi] <= wb_b2[wi-1]; wb_a2[wi] <= wb_a2[wi-1];
                wb_b3[wi] <= wb_b3[wi-1]; wb_a3[wi] <= wb_a3[wi-1];
            end
            for (pwi = 1; pwi < PWM_WB_LAT; pwi = pwi + 1) begin
                pwm_wb_b0[pwi] <= pwm_wb_b0[pwi-1];
                pwm_wb_a0[pwi] <= pwm_wb_a0[pwi-1];
            end
        end
    end

    wire is_mldsa_pwm = (ctl_sel0 == `SBU_MLDSA_PWM);
    wire is_mlkem_pwm = ctl_pwm_chain;
    wire independent_wb = (!ctl_pwm_chain) && (sbu0_vo | sbu1_vo);
    wire pwm_chain_wb   = ctl_pwm_chain && sbu1_vo;

    wire fftlike_wb = independent_wb && !is_mldsa_pwm;
    wire [3:0] wb_we_fft = pack_we4(fftlike_wb,
                                    wb_b0[WB_LAT-1], wb_b1[WB_LAT-1],
                                    wb_b2[WB_LAT-1], wb_b3[WB_LAT-1]);
    wire [4*ADDR_W-1:0] wb_addr_fft = pack_addr4(wb_b0[WB_LAT-1], wb_a0[WB_LAT-1],
                                                 wb_b1[WB_LAT-1], wb_a1[WB_LAT-1],
                                                 wb_b2[WB_LAT-1], wb_a2[WB_LAT-1],
                                                 wb_b3[WB_LAT-1], wb_a3[WB_LAT-1]);
    wire [4*DATA_W-1:0] wb_din_fft = pack_data4(wb_b0[WB_LAT-1], sbu0_o0,
                                                wb_b1[WB_LAT-1], sbu0_o1,
                                                wb_b2[WB_LAT-1], sbu1_o0,
                                                wb_b3[WB_LAT-1], sbu1_o1);

    wire [3:0] wb_we_mldsa_pwm = pack_we2(independent_wb && is_mldsa_pwm,
                                        wb_b0[WB_LAT-1], wb_b2[WB_LAT-1]);
    wire [4*ADDR_W-1:0] wb_addr_mldsa_pwm = pack_addr4(wb_b0[WB_LAT-1], wb_a0[WB_LAT-1],
                                                     wb_b2[WB_LAT-1], wb_a2[WB_LAT-1],
                                                     wb_b0[WB_LAT-1], wb_a0[WB_LAT-1],
                                                     wb_b2[WB_LAT-1], wb_a2[WB_LAT-1]);
    wire [4*DATA_W-1:0] wb_din_mldsa_pwm = pack_data4(wb_b0[WB_LAT-1], sbu0_o0,
                                                    wb_b2[WB_LAT-1], sbu1_o0,
                                                    wb_b0[WB_LAT-1], sbu0_o0,
                                                    wb_b2[WB_LAT-1], sbu1_o0);

    wire [3:0] mu_b_we_ind = is_mldsa_pwm ? wb_we_mldsa_pwm :
                              ctl_mem_down ? 4'b0 : wb_we_fft;
    wire [4*ADDR_W-1:0] mu_b_addr_ind = is_mldsa_pwm ? wb_addr_mldsa_pwm : wb_addr_fft;
    wire [4*DATA_W-1:0] mu_b_din_ind = is_mldsa_pwm ? wb_din_mldsa_pwm : wb_din_fft;

    wire [3:0] mu_b_we_pwm = pack_we1(pwm_chain_wb, pwm_wb_b0[PWM_WB_LAT-1]);
    wire [4*ADDR_W-1:0] mu_b_addr_pwm = pack_addr4(pwm_wb_b0[PWM_WB_LAT-1], pwm_wb_a0[PWM_WB_LAT-1],
                                                   pwm_wb_b0[PWM_WB_LAT-1], pwm_wb_a0[PWM_WB_LAT-1],
                                                   pwm_wb_b0[PWM_WB_LAT-1], pwm_wb_a0[PWM_WB_LAT-1],
                                                   pwm_wb_b0[PWM_WB_LAT-1], pwm_wb_a0[PWM_WB_LAT-1]);
    wire [4*DATA_W-1:0] mu_b_din_pwm = pack_data4(pwm_wb_b0[PWM_WB_LAT-1], sbu1_o0,
                                                  pwm_wb_b0[PWM_WB_LAT-1], sbu1_o0,
                                                  pwm_wb_b0[PWM_WB_LAT-1], sbu1_o0,
                                                  pwm_wb_b0[PWM_WB_LAT-1], sbu1_o0);

    wire [3:0] mu_b_we_w = pwm_chain_wb ? mu_b_we_pwm : mu_b_we_ind;
    wire [4*ADDR_W-1:0] mu_b_addr_w = pwm_chain_wb ? mu_b_addr_pwm : mu_b_addr_ind;
    wire [4*DATA_W-1:0] mu_b_din_w = pwm_chain_wb ? mu_b_din_pwm : mu_b_din_ind;

    wire [3:0] md_b_we_w = (fftlike_wb && ctl_mem_down) ? wb_we_fft : 4'b0;
    wire [4*ADDR_W-1:0] md_b_addr_w = wb_addr_fft;
    wire [4*DATA_W-1:0] md_b_din_w = wb_din_fft;

    wire [3:0] host_read_en = pack_we1(host_active, host_bank);
    wire       core_reads_both_sides = is_mlkem_pwm || is_mldsa_pwm;
    wire [3:0] core_mu_read_en = (idx_valid && (!ctl_mem_down || core_reads_both_sides)) ? 4'hf : 4'b0;
    wire [3:0] core_md_read_en = (idx_valid && ( ctl_mem_down || core_reads_both_sides)) ? 4'hf : 4'b0;
    wire [3:0] mu_a_en_w = host_mu ? host_read_en : core_mu_read_en;
    wire [3:0] md_a_en_w = host_md ? host_read_en : core_md_read_en;
    wire [3:0] mu_a_we_w = host_mu ? host_we4 : 4'b0;
    wire [4*ADDR_W-1:0] mu_a_addr_w = host_mu ? host_addr4 : read_addr;
    wire [4*DATA_W-1:0] mu_a_din_w = host_mu ? host_din4 : {4*DATA_W{1'b0}};
    wire [3:0] md_a_we_w = host_md ? host_we4 : 4'b0;
    wire [4*ADDR_W-1:0] md_a_addr_w = host_md ? host_addr4 : read_addr;
    wire [4*DATA_W-1:0] md_a_din_w = host_md ? host_din4 : {4*DATA_W{1'b0}};

    poly_memory_updown #(.DEPTH(1024), .DATA_W(DATA_W), .ADDR_W(ADDR_W)) u_pm (
        .clk      (clk),
        .mu_a_en   (mu_a_en_w),
        .mu_a_we  (mu_a_we_w),
        .mu_a_addr(mu_a_addr_w),
        .mu_a_din (mu_a_din_w),
        .mu_a_dout(mu_a_dout),
        .mu_b_we  (mu_b_we_w),
        .mu_b_addr(mu_b_addr_w),
        .mu_b_din (mu_b_din_w),
        .md_a_en   (md_a_en_w),
        .md_a_we  (md_a_we_w),
        .md_a_addr(md_a_addr_w),
        .md_a_din (md_a_din_w),
        .md_a_dout(md_a_dout),
        .md_b_we  (md_b_we_w),
        .md_b_addr(md_b_addr_w),
        .md_b_din (md_b_din_w)
    );

    // Select read data per SBU per side
    function [DATA_W-1:0] sel_dout;
        input [4*DATA_W-1:0] bus;
        input [1:0]          which;
        begin
            sel_dout = bus[(which+1)*DATA_W-1 -: DATA_W];
        end
    endfunction

    reg       host_mem_d;
    reg [1:0] host_bank_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            host_mem_d  <= 1'b0;
            host_bank_d <= 2'b0;
        end else if (host_active) begin
            host_mem_d  <= host_mem;
            host_bank_d <= host_bank;
        end
    end
    assign host_dout = host_mem_d ? sel_dout(md_a_dout, host_bank_d)
                                  : sel_dout(mu_a_dout, host_bank_d);

    reg [1:0] bk0a_d, bk0b_d, bk1a_d, bk1b_d;
    reg       pe_valid_in;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bk0a_d <= 2'b0; bk0b_d <= 2'b0; bk1a_d <= 2'b0; bk1b_d <= 2'b0;
            pe_valid_in <= 1'b0;
        end else begin
            bk0a_d <= bk0a; bk0b_d <= bk0b; bk1a_d <= bk1a; bk1b_d <= bk1b;
            pe_valid_in <= idx_valid;
        end
    end

    wire [DATA_W-1:0] mu0a = sel_dout(mu_a_dout, bk0a_d);
    wire [DATA_W-1:0] mu0b = sel_dout(mu_a_dout, bk0b_d);
    wire [DATA_W-1:0] mu1a = sel_dout(mu_a_dout, bk1a_d);
    wire [DATA_W-1:0] mu1b = sel_dout(mu_a_dout, bk1b_d);
    wire [DATA_W-1:0] md0a = sel_dout(md_a_dout, bk0a_d);
    wire [DATA_W-1:0] md0b = sel_dout(md_a_dout, bk0b_d);
    wire [DATA_W-1:0] md1a = sel_dout(md_a_dout, bk1a_d);
    wire [DATA_W-1:0] md1b = sel_dout(md_a_dout, bk1b_d);

    wire [DATA_W-1:0] side0a = ctl_mem_down ? md0a : mu0a;
    wire [DATA_W-1:0] side0b = ctl_mem_down ? md0b : mu0b;
    wire [DATA_W-1:0] side1a = ctl_mem_down ? md1a : mu1a;
    wire [DATA_W-1:0] side1b = ctl_mem_down ? md1b : mu1b;
    wire [11:0] pwm_f0 = mu0a[11:0];
    wire [11:0] pwm_f1 = mu0a[16 +: 12];
    wire [11:0] pwm_g0 = md0a[11:0];
    wire [11:0] pwm_g1 = md0a[16 +: 12];
    wire [DATA_W-1:0] pwm0_a = {4'b0, pwm_g0, 4'b0, pwm_f0};
    wire [DATA_W-1:0] pwm0_b = {4'b0, pwm_g1, 4'b0, pwm_f1};

    wire [DATA_W-1:0] sbu0_a = is_mlkem_pwm ? pwm0_a :
                                is_mldsa_pwm ? mu0a  : side0a;
    wire [DATA_W-1:0] sbu0_b = is_mlkem_pwm ? pwm0_b :
                                is_mldsa_pwm ? md0a  : side0b;
    wire [DATA_W-1:0] sbu1_a = is_mldsa_pwm ? mu1a : side1a;
    wire [DATA_W-1:0] sbu1_b = is_mldsa_pwm ? md1a : side1b;

    function [7:0] ntt_ct_addr;
        input [INDEX_W-1:0] index;
        input [3:0]         layer_id;
        reg   [7:0]         group_id;
        reg   [7:0]         layer_base;
        begin
            group_id   = index >> (layer_id + 1'b1);
            layer_base = 8'd1 << (4'd6 - layer_id);
            ntt_ct_addr = layer_base + group_id;
        end
    endfunction

    function [7:0] ntt_gs_addr;
        input [INDEX_W-1:0] index;
        input [3:0]         layer_id;
        reg   [7:0]         group_id;
        reg   [7:0]         layer_base;
        begin
            group_id  = index >> (layer_id + 1'b1);
            layer_base = 8'd128 - (8'd1 << (4'd7 - layer_id));
            ntt_gs_addr = 8'd128 + layer_base + group_id;
        end
    endfunction

    function [7:0] mldsa_ntt_addr;
        input [INDEX_W-1:0] index;
        input [3:0]         layer_id;
        reg   [7:0]         group_id;
        reg   [8:0]         layer_base;
        begin
            group_id = index >> (layer_id + 1'b1);
            layer_base = 9'd1 << (4'd7 - layer_id);
            mldsa_ntt_addr = layer_base[7:0] + group_id;
        end
    endfunction

    function [7:0] mldsa_intt_addr;
        input [INDEX_W-1:0] index;
        input [3:0]         layer_id;
        reg   [7:0]         group_id;
        reg   [8:0]         layer_top;
        reg   [8:0]         addr_ext;
        begin
            group_id = index >> (layer_id + 1'b1);
            layer_top = 9'd1 << (4'd8 - layer_id);
            addr_ext = layer_top - 9'd1 - {1'b0, group_id};
            mldsa_intt_addr = addr_ext[7:0];
        end
    endfunction

    wire [INDEX_W-1:0] idx0_a_local = idx0_a - ctl_init_address;
    wire [INDEX_W-1:0] idx1_a_local = idx1_a - ctl_init_address;

    wire is_intt_gs = (ctl_sel0 == `SBU_INTT_GS);
    wire is_mldsa_now = ctl_sel0[8];
    wire is_mldsa_intt = (ctl_sel0 == `SBU_MLDSA_INTT);
    wire [7:0] kem_addr0 = is_intt_gs ? ntt_gs_addr(idx0_a_local, ctl_layer)
                                      : ntt_ct_addr(idx0_a_local, ctl_layer);
    wire [7:0] kem_addr1 = is_intt_gs ? ntt_gs_addr(idx1_a_local, ctl_layer)
                                      : ntt_ct_addr(idx1_a_local, ctl_layer);
    wire [7:0] dsa_addr0 = is_mldsa_intt ? mldsa_intt_addr(idx0_a_local, ctl_layer)
                                         : mldsa_ntt_addr(idx0_a_local, ctl_layer);
    wire [7:0] dsa_addr1 = is_mldsa_intt ? mldsa_intt_addr(idx1_a_local, ctl_layer)
                                         : mldsa_ntt_addr(idx1_a_local, ctl_layer);
    wire [7:0] ntt_addr0 = is_mldsa_now ? dsa_addr0 : kem_addr0;
    wire [7:0] ntt_addr1 = is_mldsa_now ? dsa_addr1 : kem_addr1;

    // ---- Constant Memory ----
    wire [31:0] cm_q0, cm_q1, cm_pwm;
    constant_memory u_cm (
        .clk       (clk),
        .scheme_i  (is_mldsa_now),
        .inverse_i (is_intt_gs | is_mldsa_intt),
        .ntt_addr0 (ntt_addr0),
        .ntt_addr1 (ntt_addr1),
        .ntt_q0    (cm_q0),
        .ntt_q1    (cm_q1),
        .pwm_addr  (idx0_a_local[6:0]),
        .pwm_q     (cm_pwm)
    );

    // SBU constant input mux. ML-DSA pointwise multiplication uses c_i as the
    // memory-up operand and b_i as the memory-down operand.
    wire [DATA_W-1:0] sbu0_c = is_mlkem_pwm ? cm_pwm :
                                is_mldsa_pwm ? mu0a : cm_q0;
    wire [DATA_W-1:0] sbu1_c = is_mlkem_pwm ? cm_pwm :
                                is_mldsa_pwm ? mu1a : cm_q1;

    // ---- Processing Element ----
    sbu_pair_pe u_pe (
        .clk            (clk),
        .rst_n          (rst_n),
        .sel0           (ctl_sel0),
        .valid0_in      (pe_valid_in),
        .sbu0_a         (sbu0_a),
        .sbu0_b         (sbu0_b),
        .sbu0_c         (sbu0_c),
        .sel1           (ctl_sel1),
        .valid1_in      (pe_valid_in),
        .sbu1_a         (sbu1_a),
        .sbu1_b         (sbu1_b),
        .sbu1_c         (sbu1_c),
        .pwm_chain      (ctl_pwm_chain),
        .sbu0_out0      (sbu0_o0),
        .sbu0_out1      (sbu0_o1),
        .sbu0_valid_out (sbu0_vo),
        .sbu1_out0      (sbu1_o0),
        .sbu1_out1      (sbu1_o1),
        .sbu1_valid_out (sbu1_vo)
    );

    // ---- Cycle counter ----
    cycle_counter u_cc (
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (instr_valid),
        .busy        (ctl_busy),
        .done        (ctl_done),
        .cycle_count (cycle_count)
    );

    assign busy        = ctl_busy;
    assign done        = ctl_done;
    assign host_ready  = rst_n && !ctl_busy;
    assign dbg_pe_o00  = sbu0_o0;
    assign dbg_pe_o01  = sbu0_o1;
    assign dbg_pe_o10  = sbu1_o0;
    assign dbg_pe_o11  = sbu1_o1;
    assign dbg_pe_v0   = sbu0_vo;
    assign dbg_pe_v1   = sbu1_vo;

endmodule

`default_nettype wire
