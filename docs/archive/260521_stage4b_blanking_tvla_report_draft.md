# PHOENIX Datapath Blanking TVLA Report

Date: 2026-05-20 KST

## Executive Summary

이 보고서는 PHOENIX ML-KEM / ML-DSA accelerator에서 fixed-vs-random TVLA
leakage가 어디서 나오는지 확인하기 위해 수행한 datapath blanking 실험을
정리한다.

핵심 결론은 다음과 같다.

- 기본 baseline은 여섯 operation 모두 TVLA threshold 4.5를 크게 넘었다.
- Stage 1-4는 accelerator 큰 구조를 바꾸지 않고, invalid/unused datapath가
  이전 secret-dependent 값을 유지하거나 불필요하게 토글하는지를 단계적으로
  줄인 실험이다.
- 최종 채택 후보는 Stage 4b이다. Stage 4b는 memory read-output blanking,
  SBU invalid-cycle PRD/zero blanking, cascade invalid blanking, active
  COMP input blanking을 조합한다.
- Stage 4b는 baseline 대비 `mldsa_pwm`, `mldsa_ntt`, `mlkem_intt`,
  `mldsa_intt`, `mlkem_pwm`을 유의미하게 낮췄다. 다만 `mlkem_ntt`는
  악화했고, 전체는 아직 TVLA pass가 아니다.
- 남은 dominant peak는 active modular multiplication/reduction window에
  있다. 따라서 Stage 4b는 좋은 hygiene baseline이지, 완전한 SCA
  countermeasure는 아니다.

## Baseline TVLA

Baseline command:

```sh
OUTDIR=reports/tvla/mlkem_mldsa_secretdist_20260519_cw305_husky_1000 \
OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' \
TRACES=1000 SECRET_DIST=auto \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```

Baseline TVLA overview:

![Baseline TVLA overview](../reports/tvla/mlkem_mldsa_secretdist_20260519_cw305_husky_1000/mlkem_mldsa_tvla_overview.png)

Baseline result:

| Operation | Baseline max abs t | Peak | Cycles | Result |
|---|---:|---:|---:|---|
| `mlkem_ntt` | 84.901 | 219 | 248 | `LEAKAGE_CANDIDATE` |
| `mlkem_intt` | 65.052 | 250 | 248 | `LEAKAGE_CANDIDATE` |
| `mlkem_pwm` | 114.713 | 63 | 149 | `LEAKAGE_CANDIDATE` |
| `mldsa_ntt` | 132.180 | 63 | 538 | `LEAKAGE_CANDIDATE` |
| `mldsa_intt` | 135.012 | 213 | 538 | `LEAKAGE_CANDIDATE` |
| `mldsa_pwm` | 144.055 | 115 | 140 | `LEAKAGE_CANDIDATE` |

이 값들은 threshold 4.5 근처의 애매한 통계가 아니다. 수십에서 140대까지
올라가므로 명백한 first-order leakage 후보로 보아야 한다.

## What We Tried

### Stage 1: SBU Invalid-Cycle Zero Blanking

질문:

> SBU pipeline이 invalid/drain cycle에서 이전 secret-dependent operand를
> 계속 들고 있어서 leakage가 생기는가?

구현:

- `rtl/sbu/superbutterfly_sbu_routed.v`
  - `valid_i=0`일 때 SBU 입력 register를 zero와 safe selector로 강제.
  - `valid_o=0`일 때 output register를 zero로 강제.
- `rtl/phoenix/sbu_pair_pe.v`
  - ML-KEM cascade PWM path에서 SBU0 output이 invalid이면 cascade register를
    zero로 강제.
  - delayed `c` pipe도 invalid transaction에서는 zero를 넣음.

핵심 RTL shape:

```verilog
else begin
    sel1 <= SEL_BLANK;
    a1   <= 32'b0;
    b1   <= 32'b0;
    c1   <= 32'b0;
    v1   <= 1'b0;
end
```

결과:

- `mldsa_intt`, `mldsa_pwm`은 개선됐다.
- `mlkem_intt`는 크게 악화했다.
- 해석: stale-state leakage는 일부 존재하지만, zero blanking만으로는 active
  arithmetic leakage를 없애지 못한다.

### Stage 2: Memory Read-Output Blanking

질문:

> core read가 없거나 선택되지 않은 memory side에서 BRAM output register가
> 이전 secret memory 값을 유지하는가?

구현:

- `rtl/phoenix/poly_memory_updown.v`
  - BRAM port-A read output register에 enable을 적용.
  - read enable이 없으면 output을 zero로 냄.

```verilog
a_dout <= a_en ? mem[a_addr] : {DATA_W{1'b0}};
```

- `rtl/phoenix/phoenix_top.v`
  - FFT-like operation에서는 현재 selected memory side만 read enable.
  - PWM/pointwise operation에서는 memory-up/down 양쪽을 read enable.
  - invalid writeback metadata pipe stage 0을 zero로 blanking.

```verilog
wire [3:0] core_mu_read_en =
    (idx_valid && (!ctl_mem_down || core_reads_both_sides)) ? 4'hf : 4'b0;

wire [3:0] core_md_read_en =
    (idx_valid && ( ctl_mem_down || core_reads_both_sides)) ? 4'hf : 4'b0;
```

결과:

- `mlkem_intt`가 baseline 대비 크게 개선됐고 repeat에서도 재현됐다.
- 하지만 `mlkem_ntt`, `mldsa_pwm`은 악화했다.
- 해석: BRAM read/output retention은 실제 leakage source 중 하나지만, unused
  switching을 줄이면 일부 active peak가 더 선명해질 수 있다.

### Stage 3: Invalid-Cycle PRD Flushing

질문:

> invalid cycle을 zero로 조용히 만드는 대신, public dummy value로 SBU 내부
> multiplier/reducer state를 flush하면 residual-state leakage가 줄어드는가?

중요한 점:

- 여기서 PRD는 진짜 secret randomness나 masking share가 아니다.
- deterministic public LFSR이다.
- architectural output이나 memory writeback으로 나가지 않는다.
- 목적은 invalid SBU pipeline 내부에 이전 secret-dependent 값이 남지 않게
  밀어내는 것이다.

구현 위치: `rtl/sbu/superbutterfly_sbu_routed.v`

```verilog
reg [31:0] blank_lfsr;
wire blank_lfsr_fb =
    blank_lfsr[31] ^ blank_lfsr[21] ^ blank_lfsr[1] ^ blank_lfsr[0];
wire [31:0] blank_lfsr_next = {blank_lfsr[30:0], blank_lfsr_fb};

wire [31:0] blank_a = blank_lfsr;
wire [31:0] blank_b = {blank_lfsr[15:0], blank_lfsr[31:16]} ^ 32'hA5A55A5A;
wire [31:0] blank_c = {blank_lfsr[7:0], blank_lfsr[31:8]} ^ 32'h3C6EF372;
```

최종적으로 살아남은 정책:

```verilog
wire use_prd_candidate = `SBU_OPMODE(sel_i); // sel[8], ML-DSA이면 1
wire use_prd_blank = USE_PRD_INVALID_BLANKING && !valid_i && use_prd_candidate;
```

즉:

| Situation | Input to SBU stage 1 |
|---|---|
| valid cycle | real `a_i`, `b_i`, `c_i` |
| invalid ML-KEM cycle | zero operands, safe selector |
| invalid ML-DSA cycle | public LFSR PRD operands, current selector |

실제 주입:

```verilog
else if (use_prd_blank) begin
    sel1 <= sel_i;
    a1   <= blank_a;
    b1   <= blank_b;
    c1   <= blank_c;
    v1   <= 1'b0;
end
```

`v1=0`이므로 dummy computation은 valid result로 취급되지 않는다. 마지막
output register에서도 invalid이면 zero를 낸다.

```verilog
else begin
    y0r <= 32'b0;
    y1r <= 32'b0;
    vr  <= 1'b0;
end
```

실험으로 확인한 점:

- PRD를 모든 scheme에 넓게 넣으면 ML-KEM 쪽이 악화했다.
- ML-KEM invalid cycle은 zero로 두고, ML-DSA invalid cycle에만 PRD를 넣는
  policy가 가장 균형이 좋았다.
- PRD를 끄는 control run에서는 ML-DSA PWM 개선이 거의 사라졌다. 따라서
  ML-DSA PWM/NTT 개선은 PRD invalid-cycle flushing 효과로 해석할 수 있다.

### Stage 4: Active COMP Blanking

질문:

> valid active cycle 안에서도, output mux가 선택하지 않는 arithmetic cone이
> secret operand를 보고 불필요하게 토글하는가?

Stage 1-3은 주로 invalid/drain/idle cycle을 다뤘다. Stage 4는 valid cycle
안에서 unused arithmetic input을 zero로 막았다.

구현 위치: `rtl/sbu/superbutterfly_sbu_routed.v`

COMP2:

- INTT에서만 functionally 필요하다.
- NTT/PWM/MOD_ADD에서는 input을 zero로 둔다.

```verilog
c2a=32'b0; c2b=32'b0; c2_sub=1'b0; c2_intt=1'b0;
case (sel1)
    `SBU_INTT_GS,
    `SBU_MLDSA_INTT: begin
        c2a=b1; c2b=a1; c2_sub=1'b1; c2_intt=1'b1;
    end
endcase
```

COMP1:

- output mux가 `comp1_y`를 쓰는 operation에서만 input을 넣는다.
- ML-DSA PWM은 output mux에서 `p6`만 쓰므로 COMP1 input은 zero로 남는다.

COMP4:

- NTT와 ML-KEM PWM1에서는 output mux가 `comp4_y`를 쓰므로 input을 넣는다.
- 대부분의 다른 operation에서는 input을 zero로 둔다.

```verilog
c4a=32'b0; c4b=32'b0;
case (sel6)
    `SBU_NTT_CT,
    `SBU_MLDSA_NTT : begin c4a=a6; c4b=p6; end
    `SBU_INTT_GS   : begin c4a=a6; c4b=p6; end
    `SBU_PWM1      : begin
        c4a={16'b0,p6[15:0]};
        c4b={16'b0,comp1_y[15:0]};
    end
endcase
```

Stage 4b의 핵심 예외:

- Stage 4a에서는 ML-KEM INTT에서도 COMP4를 zero로 blanking했다.
- 그 결과 `mlkem_intt`가 reproducibly 악화했다.
- Stage 4b는 ML-KEM INTT인 `SBU_INTT_GS`에서만 COMP4 switching을 다시
  유지한다.
- ML-DSA INTT인 `SBU_MLDSA_INTT`에서는 COMP4가 계속 zero다.

이 예외가 Stage 4a 대비 `mlkem_intt`를 크게 회복시켰고, Stage 4b가 최종
best candidate가 됐다.

## Final Stage 4b Implementation Map

Stage 4b에 실제로 남아 있는 blanking은 다음 경로들이다.

| Path | File | How it is blanked |
|---|---|---|
| BRAM read output | `rtl/phoenix/poly_memory_updown.v` | `a_en=0`이면 `a_dout=0` |
| Core memory read enable | `rtl/phoenix/phoenix_top.v` | invalid read이면 read enable `0` |
| Writeback metadata pipe | `rtl/phoenix/phoenix_top.v` | `idx_valid=0`이면 bank/address metadata `0` |
| SBU invalid ML-KEM input | `rtl/sbu/superbutterfly_sbu_routed.v` | zero operands + safe selector |
| SBU invalid ML-DSA input | `rtl/sbu/superbutterfly_sbu_routed.v` | public LFSR PRD operands, valid remains `0` |
| SBU invalid output | `rtl/sbu/superbutterfly_sbu_routed.v` | output register forced to `0` |
| ML-KEM cascade path | `rtl/phoenix/sbu_pair_pe.v` | invalid SBU0 output/cascade input forced to `0` |
| COMP2 active input | `rtl/sbu/superbutterfly_sbu_routed.v` | only INTT gets real operands |
| COMP1 active input | `rtl/sbu/superbutterfly_sbu_routed.v` | only operations using `comp1_y` get real operands |
| COMP4 active input | `rtl/sbu/superbutterfly_sbu_routed.v` | NTT/PWM1 get real operands; ML-KEM INTT is kept as exception |

Stage 4b에 포함되지 않은 later rejected ideas:

- exact PWM bank read mask in `rtl/phoenix/phoenix_top.v`
- ML-DSA PWM top-level `a_i=0`
- COMP3 internal KEM/DSA cone blanking in `rtl/comp/comp3_agile_modmul.v`

이 세 가지는 Stage 5에서 따로 실험했지만 Stage 4b보다 worst TVLA가 나빠져
최종 active candidate에는 넣지 않았다.

## TVLA Improvement

Stage 4b command:

```sh
OUTDIR=reports/tvla/mlkem_mldsa_blanking_stage4b_kem_intt_comp4_exception_20260520_cw305_husky_1000 \
OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' \
TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0x5EED \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```

Stage 4b TVLA overview:

![Stage 4b TVLA overview](../reports/tvla/mlkem_mldsa_blanking_stage4b_kem_intt_comp4_exception_20260520_cw305_husky_1000/mlkem_mldsa_tvla_overview.png)

Baseline vs Stage 4b comparison:

![Stage 4b vs baseline](../reports/tvla/mlkem_mldsa_blanking_stage4b_kem_intt_comp4_exception_20260520_cw305_husky_1000/comparison_vs_baseline.png)

Numerical comparison:

| Operation | Baseline max abs t | Stage 4b max abs t | Delta | Delta % | Peak movement | Cycles |
|---|---:|---:|---:|---:|---|---:|
| `mlkem_ntt` | 84.901 | 96.516 | +11.616 | +13.68% | 219 -> 116 | 248 |
| `mlkem_intt` | 65.052 | 42.888 | -22.165 | -34.07% | 250 -> 236 | 248 |
| `mlkem_pwm` | 114.713 | 103.869 | -10.843 | -9.45% | 63 -> 63 | 149 |
| `mldsa_ntt` | 132.180 | 85.738 | -46.442 | -35.14% | 63 -> 506 | 538 |
| `mldsa_intt` | 135.012 | 112.877 | -22.135 | -16.39% | 213 -> 123 | 538 |
| `mldsa_pwm` | 144.055 | 78.170 | -65.885 | -45.74% | 115 -> 109 | 140 |

Summary metrics:

| Metric | Baseline | Stage 4b | Interpretation |
|---|---:|---:|---|
| Worst operation | `mldsa_pwm` | `mldsa_intt` | dominant leakage source moved |
| Worst max abs t | 144.055 | 112.877 | improved, but still far above 4.5 |
| ML-KEM average | 88.222 | 81.091 | modest improvement |
| ML-DSA average | 137.082 | 92.262 | large improvement |

## Interpretation

Stage 4b did not make the design TVLA-safe. It did, however, establish a much
cleaner baseline:

- invalid-cycle stale SBU state is no longer simply retained;
- ML-DSA invalid cycles actively flush SBU internals with public PRD operands;
- invalid outputs and cascade registers are forced to zero;
- selected active operations no longer feed secret operands into every unused
  COMP1/COMP2/COMP4 path;
- the ML-KEM INTT COMP4 exception preserves a switching pattern that empirically
  avoids a large `mlkem_intt` regression.

The remaining large peaks, especially `mldsa_intt` and `mlkem_pwm`, are still
active arithmetic leakage. This is why further small deterministic blanking
experiments in Stage 5 did not beat Stage 4b. A future TVLA-pass attempt should
target active modular multiplication/reduction directly, for example with
coefficient shuffling, operation-order hiding, or partial masking.

## One-Slide Explanation

> We first measured a plain baseline and saw large TVLA failures across all
> ML-KEM/ML-DSA operations. We then added datapath hygiene in stages: zeroing
> invalid SBU and memory outputs, flushing ML-DSA invalid cycles with public
> LFSR dummy operands, clearing invalid cascade state, and finally zeroing
> active COMP inputs whose outputs are not used. The best variant, Stage 4b,
> reduced the worst leakage from 144.1 to 112.9 and cut ML-DSA average leakage
> by about one third, but it remains far above the 4.5 TVLA threshold. This
> shows blanking removes residual/unused-path leakage, while the remaining
> signal is active arithmetic leakage requiring shuffling or masking.
