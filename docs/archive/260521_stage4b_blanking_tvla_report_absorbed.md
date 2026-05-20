# Stage 4b Datapath Blanking TVLA Report

작성일: 2026-05-21 KST

이 문서는 PHOENIX ML-KEM / ML-DSA 가속기에서 수행한 datapath blanking 실험을
처음 보는 사람이 이해할 수 있도록 정리한 보고서다. 핵심 질문은 하나였다.

> 선택되지 않았거나 invalid인 datapath가 secret-dependent 값을 계속 들고 있거나
> 불필요하게 toggle하면서 fixed-vs-random TVLA peak를 키우고 있는가?

결론부터 말하면, 현재 최종 선택 RTL은 Stage 4b다. Stage 4b는 TVLA pass는
아니지만, baseline 대비 worst max `|t|`를 `144.055 -> 112.877`로 낮춘
가장 균형 잡힌 small-RTL blanking 후보였다. 반면 Stage 6 R2는 ML-KEM 세
operation에서 매우 좋은 결과를 냈지만 ML-DSA INTT/PWM을 악화시켜 최종 RTL에는
넣지 않았다.

## TVLA를 읽는 기준

이번 실험은 모두 fixed-vs-random TVLA다.

- threshold는 `4.5`다.
- 표의 `max |t|`는 한 trace 안에서 가장 큰 absolute t-value다.
- `peak index`는 그 최대값이 나온 sample index다.
- 숫자가 낮을수록 좋지만, `4.5`보다 크면 여전히 leakage candidate다.
- 이 프로젝트의 값은 20대부터 140대까지 나오므로 threshold 근처의 애매한
  통계가 아니라 명확한 first-order leakage 후보로 봐야 한다.

측정 조건은 비교 가능성을 위해 Stage 4b 계열에서 동일하게 유지했다.

```bash
OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm'
TRACES=1000
SECRET_DIST=auto
TRACE_ORDER=shuffle
ORDER_SEED=0x5EED
```

## 한 줄 요약

| 구분 | 무엇을 한 실험인가 | 최종 판단 |
|---|---|---|
| Baseline | blanking 없이 기본 fixed-vs-random leakage 측정 | 모든 op가 크게 실패 |
| Stage 1 | invalid SBU/cascade/output에 `0` 주입 | 일부 개선, 일부 악화 |
| Stage 2 | memory read output과 invalid metadata에 `0` 주입 | `mlkem_intt` 개선, 일부 악화 |
| Stage 3 | ML-DSA invalid SBU cycle에 public PRD dummy 주입 | ML-DSA 개선 신호 확인 |
| Stage 4b | Stage 3 + active COMP1/2/4 unused input zero blanking | 현재 최종 선택 RTL |
| Stage 5 | Stage 4b 이후 작은 zero blanking 후보 B1/B2/B3 | 모두 reject |
| Stage 6 R2 | COMP3 inactive cone에 public PRD dummy 주입 | ML-KEM은 매우 좋지만 ML-DSA 악화, reject |

## Baseline: 아무 blanking도 없는 상태

Baseline은 선택되지 않은 datapath가 이전 값이나 현재 secret operand를 그대로
볼 수 있는 상태다. 예를 들어 output mux가 어떤 COMP 결과를 선택하지 않아도,
그 COMP 내부 multiplier/reducer는 입력을 받아 toggle할 수 있다. 또한 invalid
cycle에서 pipeline register나 memory read output register가 이전 값을 유지하면
이 값도 leakage shape에 섞일 수 있다.

Baseline TVLA overview:

![Baseline TVLA overview](../reports/tvla/mlkem_mldsa_secretdist_20260519_cw305_husky_1000/mlkem_mldsa_tvla_overview.png)

Baseline 결과:

| Operation | Baseline max `|t|` | Peak index | Cycles |
|---|---:|---:|---:|
| `mlkem_ntt` | 84.901 | 219 | 248 |
| `mlkem_intt` | 65.052 | 250 | 248 |
| `mlkem_pwm` | 114.713 | 63 | 149 |
| `mldsa_ntt` | 132.180 | 63 | 538 |
| `mldsa_intt` | 135.012 | 213 | 538 |
| `mldsa_pwm` | 144.055 | 115 | 140 |

여기서 가장 나쁜 것은 `mldsa_pwm=144.055`였다. 하지만 모든 operation이
threshold `4.5`를 매우 크게 넘었기 때문에, 하나의 특정 operation만 문제가
아니라 전체 datapath hygiene이 좋지 않은 상태라고 판단했다.

## Stage 1: invalid SBU/cascade/output zero blanking

Stage 1의 질문은 이것이다.

> SBU pipeline이 valid하지 않은 cycle에서도 이전 secret-dependent operand를
> 계속 들고 있으면 leakage가 생기지 않을까?

여기서 중요한 점은 "미리 선택되지 않을 line을 예측해서 0으로 채운다"가 아니다.
Stage 1은 `valid_i=0`인 cycle, 즉 현재 SBU에 실제 연산이 들어오지 않는 cycle을
보고 그 입력 register를 안전한 값으로 덮어쓴다.

구현 위치는 `rtl/sbu/superbutterfly_sbu_routed.v`와
`rtl/phoenix/sbu_pair_pe.v`다.

SBU 입력 stage에서는 세 가지 경우로 나뉜다.

```verilog
if (valid_i) begin
    sel1 <= sel_i;
    a1   <= a_i;
    b1   <= b_i;
    c1   <= c_i;
    v1   <= 1'b1;
end else begin
    sel1 <= SEL_BLANK;
    a1   <= 32'b0;
    b1   <= 32'b0;
    c1   <= 32'b0;
    v1   <= 1'b0;
end
```

현재 Stage 4b RTL에서는 이 기본 zero path 위에 Stage 3 PRD path가 추가되어
있다. 하지만 Stage 1의 본질은 invalid input을 `0`으로 덮어 이전 operand가
pipeline에 남지 않게 하는 것이다.

ML-KEM PWM cascade path도 같은 철학으로 처리했다. SBU0 output이 valid하지
않으면 SBU1으로 넘어가는 cascade register에 `0`을 넣는다.

```verilog
cascade_a_r     <= sbu0_valid_out ? sbu0_out0 : 32'b0;
cascade_b_r     <= sbu0_valid_out ? sbu0_out1 : 32'b0;
cascade_valid_r <= sbu0_valid_out;
cascade_c_pipe[0] <= valid0_in ? sbu0_c : 32'b0;
```

SBU output register도 invalid이면 `0`을 낸다.

```verilog
else begin
    y0r <= 32'b0;
    y1r <= 32'b0;
    vr  <= 1'b0;
end
```

해석은 반반이었다. `mldsa_intt`, `mldsa_pwm`에는 개선 신호가 있었지만
`mlkem_intt`는 악화했다. 즉 stale-state leakage는 실제로 있었지만, 조용한
zero blanking이 항상 좋은 방향으로만 작동하지는 않았다.

## Stage 2: memory read-output zero blanking

Stage 2의 질문은 이것이다.

> core가 읽지 않는 memory side나 invalid read cycle에서 BRAM output register가
> 이전 secret memory 값을 유지하고 있지 않을까?

구현 위치는 `rtl/phoenix/poly_memory_updown.v`와 `rtl/phoenix/phoenix_top.v`다.

BRAM port-A read output은 read enable이 없으면 `0`을 낸다.

```verilog
a_dout <= a_en ? mem[a_addr] : {DATA_W{1'b0}};
```

Top에서는 operation에 따라 memory-up/down read enable을 만든다.

```verilog
wire core_reads_both_sides = is_mlkem_pwm || is_mldsa_pwm;
wire [3:0] core_mu_read_en =
    (idx_valid && (!ctl_mem_down || core_reads_both_sides)) ? 4'hf : 4'b0;
wire [3:0] core_md_read_en =
    (idx_valid && ( ctl_mem_down || core_reads_both_sides)) ? 4'hf : 4'b0;
```

의미는 다음과 같다.

- NTT/INTT처럼 한쪽 memory side만 읽는 operation은 선택된 side만 enable한다.
- ML-KEM PWM과 ML-DSA PWM은 memory-up/down 양쪽을 모두 쓰므로 양쪽을 enable한다.
- `idx_valid=0`이면 core read enable은 `0`이 되고, BRAM output도 `0`으로 간다.

주의할 점은 Stage 4b가 "정확히 필요한 bank만" 읽는 설계는 아니라는 것이다.
pointwise operation에서 `4'hf`를 더 좁은 mask로 바꾸는 실험은 Stage 5 B1에서
따로 해봤지만 reject되었다.

Stage 2의 핵심 성과는 `mlkem_intt` 개선이었다. 하지만 `mlkem_ntt`와
`mldsa_pwm`은 악화했다. 해석은 간단하다. 안 쓰는 memory switching을 줄이면
실제 leakage source 하나는 줄지만, 동시에 물리적 noise/hiding처럼 작동하던
switching도 사라져 active arithmetic peak가 더 선명해질 수 있다.

## Stage 3: ML-DSA invalid-cycle public PRD flushing

Stage 3의 질문은 이것이다.

> invalid cycle을 전부 `0`으로 조용하게 만들기보다, secret과 무관한 public
> dummy value로 SBU 내부 arithmetic state를 flush하면 더 나을까?

여기서 말하는 random은 masking용 진짜 secret randomness가 아니다. 현재 RTL의
Stage 3/4b에 들어간 것은 deterministic public LFSR 기반 PRD다.

- secret과 독립이다.
- fixed/random class와 직접 연결된 값이 아니다.
- architectural output이나 memory writeback으로 나가지 않는다.
- 목적은 invalid SBU 내부 stage가 이전 functional operand를 오래 들고 있지
  않게 하는 것이다.

구현 위치는 `rtl/sbu/superbutterfly_sbu_routed.v`다.

```verilog
reg [31:0] blank_lfsr;
wire [31:0] blank_a = blank_lfsr;
wire [31:0] blank_b =
    {blank_lfsr[15:0], blank_lfsr[31:16]} ^ 32'hA5A55A5A;
wire [31:0] blank_c =
    {blank_lfsr[7:0], blank_lfsr[31:8]} ^ 32'h3C6EF372;
```

최종 Stage 4b에 남은 정책은 다음이다.

```verilog
wire use_prd_candidate = `SBU_OPMODE(sel_i); // ML-DSA이면 1
wire use_prd_blank =
    USE_PRD_INVALID_BLANKING && !valid_i && use_prd_candidate;
```

즉 invalid cycle에서 ML-KEM과 ML-DSA를 다르게 처리한다.

| 상황 | SBU stage-1 입력 | valid bit |
|---|---|---|
| valid cycle | 실제 `a_i`, `b_i`, `c_i` | `v1=1` |
| invalid ML-KEM cycle | zero operands + safe selector | `v1=0` |
| invalid ML-DSA cycle | public PRD operands + current ML-DSA selector | `v1=0` |

실제 주입 부분은 다음과 같다.

```verilog
else if (use_prd_blank) begin
    sel1 <= sel_i;
    a1   <= blank_a;
    b1   <= blank_b;
    c1   <= blank_c;
    v1   <= 1'b0;
end
```

`v1=0`이므로 이 dummy computation은 valid output으로 인정되지 않는다. 마지막
output register에서도 invalid output은 `0`으로 덮인다.

Stage 3의 중요한 시행착오는 다음과 같다.

- PRD를 너무 넓게 넣으면 ML-KEM 쪽이 악화했다.
- ML-KEM invalid cycle은 zero로 두고, ML-DSA invalid cycle에만 PRD를 넣는
  hybrid가 가장 균형이 좋았다.
- PRD를 끈 control run에서는 ML-DSA PWM/NTT 개선이 거의 사라졌다.

그래서 Stage 4b의 "random"은 모든 곳에 들어간 것이 아니라, ML-DSA invalid
SBU cycle에만 들어간 public PRD flushing이다.

## Stage 4/4b: active COMP1/2/4 zero blanking

Stage 4의 질문은 Stage 1-3과 다르다.

> valid cycle 안에서도 output mux가 선택하지 않는 arithmetic cone이 secret
> operand를 보고 불필요하게 toggle하고 있지 않을까?

Stage 1-3은 invalid/idle/drain 성격의 cycle을 다뤘다. Stage 4는 valid cycle
안의 unused COMP input을 `0`으로 막았다. 구현 위치는
`rtl/sbu/superbutterfly_sbu_routed.v`다.

COMP2는 inverse transform에서만 필요하다. 그래서 NTT/PWM/MOD_ADD에서는
input을 `0`으로 둔다.

```verilog
c2a=32'b0; c2b=32'b0; c2_sub=1'b0; c2_intt=1'b0;
case (sel1)
    `SBU_INTT_GS,
    `SBU_MLDSA_INTT: begin
        c2a=b1; c2b=a1; c2_sub=1'b1; c2_intt=1'b1;
    end
endcase
```

COMP1은 output mux가 `comp1_y`를 쓰는 operation에서만 real operand를 받는다.
예를 들어 ML-DSA PWM은 output mux가 `p6`만 사용하므로 COMP1 input은 zero로
남는다.

```verilog
c1a=32'b0; c1b=32'b0; c1_intt=1'b0;
case (sel6)
    `SBU_NTT_CT,
    `SBU_MLDSA_NTT : begin c1a=a6; c1b=p6; c1_intt=1'b0; end
    `SBU_INTT_GS,
    `SBU_MLDSA_INTT: begin c1a=a6; c1b=b6; c1_intt=1'b1; end
    `SBU_PWM1      : begin c1a={b6[15:0],b6[15:0]};
                           c1b={p6[31:16],b6[31:16]}; end
    `SBU_PWM0,
    `SBU_MOD_ADD   : begin c1a=a6; c1b=b6; c1_intt=1'b0; end
endcase
```

COMP4는 NTT/PWM1에서 output mux가 사용한다. 그래서 기본은 zero이고, 선택된
operation에서만 real operand를 넣는다.

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

Stage 4b의 핵심은 ML-KEM INTT 예외다.

- Stage 4a에서는 ML-KEM INTT에서도 COMP4를 zero로 껐다.
- 그러자 `mlkem_intt`가 reproducibly 악화했다.
- Stage 4b는 `SBU_INTT_GS`, 즉 ML-KEM INTT에서만 COMP4 switching을 다시 살렸다.
- ML-DSA INTT인 `SBU_MLDSA_INTT`는 여전히 COMP4 input을 zero로 둔다.

이 예외 때문에 Stage 4b가 Stage 4a보다 나아졌고, 전체 worst 기준으로 현재
best small-RTL candidate가 되었다.

## Stage 4b TVLA 결과

Stage 4b TVLA overview:

![Stage 4b TVLA overview](../reports/tvla/mlkem_mldsa_blanking_stage4b_kem_intt_comp4_exception_20260520_cw305_husky_1000/mlkem_mldsa_tvla_overview.png)

Stage 4b vs baseline:

![Stage 4b vs baseline](../reports/tvla/mlkem_mldsa_blanking_stage4b_kem_intt_comp4_exception_20260520_cw305_husky_1000/comparison_vs_baseline.png)

수치 비교:

| Operation | Baseline max `|t|` | Stage 4b max `|t|` | Delta | Delta % | Peak movement | Cycles |
|---|---:|---:|---:|---:|---|---:|
| `mlkem_ntt` | 84.901 | 96.516 | +11.616 | +13.68% | 219 -> 116 | 248 |
| `mlkem_intt` | 65.052 | 42.888 | -22.165 | -34.07% | 250 -> 236 | 248 |
| `mlkem_pwm` | 114.713 | 103.869 | -10.843 | -9.45% | 63 -> 63 | 149 |
| `mldsa_ntt` | 132.180 | 85.738 | -46.442 | -35.14% | 63 -> 506 | 538 |
| `mldsa_intt` | 135.012 | 112.877 | -22.135 | -16.39% | 213 -> 123 | 538 |
| `mldsa_pwm` | 144.055 | 78.170 | -65.885 | -45.74% | 115 -> 109 | 140 |

요약하면 Stage 4b는 여섯 operation 중 다섯 개를 baseline보다 낮췄다. 특히
ML-DSA 평균 leakage는 크게 내려갔다.

| Metric | Baseline | Stage 4b | 해석 |
|---|---:|---:|---|
| Worst operation | `mldsa_pwm` | `mldsa_intt` | dominant leakage 위치가 이동함 |
| Worst max `|t|` | 144.055 | 112.877 | 개선됐지만 pass는 아님 |
| ML-KEM 평균 | 88.222 | 81.091 | 완만한 개선 |
| ML-DSA 평균 | 137.082 | 92.262 | 큰 개선 |

`mlkem_ntt`가 오른 것은 이상한 일이 아니다. Stage 4b는 "모든 operation을 각각
최적화한 bitstream"이 아니라 "한 bitstream에서 worst case를 가장 잘 낮춘
후보"다. 어떤 unused switching은 leakage source이면서 동시에 active leakage를
가리는 noise처럼 작동할 수 있다. 그 switching을 blanking하면 한쪽 op에서는
좋아지고 다른 op에서는 peak가 더 선명해질 수 있다.

Stage 4b key repeat에서도 주요 peak는 안정적으로 재현됐다.

| Operation | Stage 4b full | Key repeat | Repeat peak |
|---|---:|---:|---:|
| `mlkem_pwm` | 103.869 | 105.388 | 63 |
| `mldsa_intt` | 112.877 | 114.900 | 123 |
| `mldsa_pwm` | 78.170 | 74.680 | 109 |

따라서 Stage 4b는 우연히 한 번 낮게 나온 결과가 아니라, 재현 가능한 현재
baseline으로 보는 것이 맞다.

## 현재 Stage 4b RTL에 실제로 들어간 값들

아래 표가 "zero/random이 정확히 어디에 들어갔는가"에 대한 최종 답이다.

| 구분 | 위치 | 들어가는 값 | 조건 | 현재 Stage 4b 포함 여부 |
|---|---|---|---|---|
| BRAM read output | `poly_memory_updown.v` | `0` | `a_en=0` | 포함 |
| core memory read enable | `phoenix_top.v` | enable `0` | `idx_valid=0` 또는 선택 안 된 memory side | 포함 |
| SBU invalid ML-KEM input | `superbutterfly_sbu_routed.v` | `0` + safe selector | `valid_i=0`, ML-KEM selector | 포함 |
| SBU invalid ML-DSA input | `superbutterfly_sbu_routed.v` | public PRD `blank_a/b/c` | `valid_i=0`, ML-DSA selector | 포함 |
| SBU invalid output | `superbutterfly_sbu_routed.v` | `0` | delayed valid `v6=0` | 포함 |
| ML-KEM cascade input | `sbu_pair_pe.v` | `0` | SBU0 output invalid | 포함 |
| COMP2 active input | `superbutterfly_sbu_routed.v` | `0` | selected op이 INTT가 아님 | 포함 |
| COMP1 active input | `superbutterfly_sbu_routed.v` | `0` | output mux가 COMP1을 쓰지 않음 | 포함 |
| COMP4 active input | `superbutterfly_sbu_routed.v` | `0` | NTT/PWM1/ML-KEM INTT 외 op | 포함 |
| COMP3 inactive KEM/DSA cone | `comp3_agile_modmul.v` | 없음 | Stage 4b에서는 real input이 양쪽 cone에 그대로 들어감 | 미포함 |

가장 헷갈리기 쉬운 점은 마지막 줄이다. 현재 Stage 4b의
`comp3_agile_modmul.v`에는 R2의 dummy input이 없다. 현재 COMP3는 KEM cone과
DSA cone이 모두 `a_i/b_i`를 보고, 마지막 mux만 `opmode_i`로 output을 고른다.

```verilog
assign c_o = opmode_i ? dsa_out : kem_out;
```

즉 Stage 4b는 COMP3 inactive cone을 blanking하지 않는다. COMP3 inactive cone
blanking은 Stage 5 B3와 Stage 6 R1/R2/R3에서 따로 실험했고, 최종 RTL에는
반영하지 않았다.

## Stage 5: Stage 4b 이후 작은 zero blanking 후보들

Stage 5는 "Stage 4b 위에 더 작은 RTL blanking을 하나씩 추가하면 pass에
가까워지는가"를 본 실험이다. 모두 Stage 4b에서 새 branch로 시작했고, 큰 구조는
바꾸지 않았다.

| 후보 | 바꾼 점 | 결과 |
|---|---|---|
| B1 | PWM/pointwise read enable을 실제 bank mask로 좁힘 | `mldsa_pwm`은 좋아졌지만 worst `mldsa_intt=127.224`, reject |
| B2 | ML-DSA PWM에서 unused `a_i`를 `0`으로 입력 | `mldsa_pwm`은 좋아졌지만 `mlkem_ntt=125.233`, reject |
| B3 | COMP3 inactive KEM/DSA cone을 `0`으로 blanking | `mlkem_pwm`은 좋아졌지만 `mldsa_intt=150.301`, reject |

B3가 특히 중요했다. COMP3에서 선택되지 않은 algorithm cone을 `0`으로 껐더니
일부 ML-KEM PWM peak는 내려갔지만 ML-DSA NTT/INTT가 크게 악화했다. 이는
inactive cone switching이 leakage source이기도 하지만, 어떤 operation에서는
active leakage를 가리는 noise/hiding처럼 작동했을 가능성을 보여준다.

## Stage 6 R2: COMP3 inactive cone public PRD dummy

R2는 Stage 5 B3의 다음 질문이었다.

> COMP3 inactive cone을 완전히 `0`으로 꺼서 문제가 생겼다면, secret과 무관한
> public PRD dummy switching을 넣으면 어떨까?

R2 TVLA overview:

![R2 TVLA overview](../reports/tvla/mlkem_mldsa_stage6_r2_prd_dummy_comp3_20260520_cw305_husky_1000/mlkem_mldsa_tvla_overview.png)

R2 vs Stage 4b:

![R2 vs Stage 4b](../reports/tvla/mlkem_mldsa_stage6_r2_prd_dummy_comp3_20260520_cw305_husky_1000/comparison_vs_stage4b.png)

R2는 `comp3_agile_modmul.v`에 `dummy_a_i`, `dummy_b_i`를 임시로 추가한
실험이었다.

| Mode | selected active cone | inactive cone에 넣은 값 |
|---|---|---|
| ML-KEM mode | KEM cone = real `a_i/b_i` | DSA cone = public PRD dummy `[23:0]` |
| ML-DSA mode | DSA cone = real `a_i[23:0]/b_i[23:0]` | KEM cone = public PRD dummy `[31:0]` |

중요한 제약은 유지했다.

- output mux는 그대로였다.
- active arithmetic cone에는 PRD를 섞지 않았다.
- dummy는 secret, memory contents, fixed/random class와 독립인 public source였다.
- SBU latency, scheduler, memory layout, cycle count는 바꾸지 않았다.

결과는 매우 흥미로웠지만 최종 accept는 아니었다.

| Operation | Stage 4b max `|t|` | R2 max `|t|` | Delta % | Stage 4b peak | R2 peak |
|---|---:|---:|---:|---:|---:|
| `mlkem_ntt` | 96.516 | 29.532 | -69.40% | 116 | 217 |
| `mlkem_intt` | 42.888 | 27.140 | -36.72% | 236 | 149 |
| `mlkem_pwm` | 103.869 | 52.516 | -49.44% | 63 | 156 |
| `mldsa_ntt` | 85.738 | 82.381 | -3.92% | 506 | 63 |
| `mldsa_intt` | 112.877 | 121.557 | +7.69% | 123 | 123 |
| `mldsa_pwm` | 78.170 | 85.713 | +9.65% | 109 | 114 |

R2가 ML-KEM에서 너무 좋은 이유는 ML-KEM active arithmetic을 바꿨기 때문이
아니다. ML-KEM mode에서는 active KEM cone은 그대로였고, 선택되지 않는 DSA cone에
public PRD dummy switching을 넣었다. 즉 ML-KEM의 좋은 결과는 "active KEM
계산이 안전해졌다"라기보다 "주변 inactive DSA cone switching shape가 ML-KEM
peak visibility를 크게 바꿨다"로 해석해야 한다.

반대로 ML-DSA에서는 active DSA Montgomery multiply/reduction cone이 그대로였다.
R2는 inactive KEM cone에 dummy를 넣었지만, `mldsa_intt`의 peak index 123은
Stage 4b와 동일하게 남았고 값은 더 커졌다. 그래서 R2는 최종 RTL로 accept하지
않았다.

## 최종 판단

현재 선택은 Stage 4b다.

- Stage 4b는 TVLA pass가 아니다.
- 그래도 baseline보다 훨씬 정돈된 hygiene baseline이다.
- invalid-cycle stale state, memory read retention, invalid cascade state,
  unused COMP1/2/4 active input leakage를 줄였다.
- Stage 5의 작은 deterministic zero blanking 후보들은 Stage 4b보다 worst가
  좋아지지 않았다.
- Stage 6 R2는 ML-KEM 방향의 강한 힌트를 줬지만 ML-DSA active arithmetic
  leakage를 해결하지 못했다.

따라서 현재 남은 핵심 문제는 선택되지 않은 path만의 문제가 아니다. 특히
`mldsa_intt` peak index 123처럼 안정적으로 남는 peak는 selected active
arithmetic path, 즉 ML-DSA COMP3 Montgomery multiply/reduction window와 더
가깝게 봐야 한다. 다음 실험은 단순히 "더 많이 0으로 끄기"가 아니라, inactive
dummy switching과 active arithmetic protection을 분리해서 설계해야 한다.
