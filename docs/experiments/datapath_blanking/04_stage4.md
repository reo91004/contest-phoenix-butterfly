# Stage 4: active COMP blanking과 Stage 4b 최종 후보

## 목적

Stage 4는 invalid-cycle 문제가 아니라 valid active cycle 안의 unused arithmetic
cone을 다룬다. 질문은 다음이었다.

> output mux가 선택하지 않는 COMP1/2/4가 secret operand를 보고 toggle하면서
> leakage를 키우는가?

## 기준 RTL

기준은 Stage 3g다. Stage 4는 Stage 3g의 balanced ML-DSA PRD invalid-cycle
flushing을 유지하고, COMP1/2/4 input mux에 active-cycle zero blanking을 추가했다.

## Stage 4a: active COMP blanking

기존 이름: Stage 4a

변경 위치: `rtl/sbu/superbutterfly_sbu_routed.v`

COMP2는 INTT에서만 real input을 받는다.

```verilog
c2a=32'b0; c2b=32'b0; c2_sub=1'b0; c2_intt=1'b0;
case (sel1)
    `SBU_INTT_GS,
    `SBU_MLDSA_INTT: begin
        c2a=b1; c2b=a1; c2_sub=1'b1; c2_intt=1'b1;
    end
endcase
```

COMP1은 output mux가 `comp1_y`를 쓰는 operation에서만 real input을 받는다.
ML-DSA PWM은 output mux가 `p6`만 쓰므로 COMP1은 zero 상태로 남는다.

COMP4는 NTT/PWM1에서만 real input을 받도록 했다. Stage 4a에서는 ML-KEM INTT도
unused로 보고 COMP4를 zero로 두었다.

| Operation | Stage 3g | Stage 4a | 변화 |
|---|---:|---:|---:|
| `mlkem_ntt` | 98.885 | 88.877 | 개선 |
| `mlkem_intt` | 48.363 | 69.162 | 악화 |
| `mlkem_pwm` | 120.513 | 112.912 | 개선 |
| `mldsa_ntt` | 93.214 | 93.286 | 거의 동일 |
| `mldsa_intt` | 121.693 | 116.608 | 개선 |
| `mldsa_pwm` | 74.868 | 69.567 | 개선 |

Stage 4a는 worst를 낮췄지만 `mlkem_intt`가 reproducibly 악화했다.

## Stage 4b: ML-KEM INTT COMP4 exception

기존 이름: Stage 4b

Stage 4b는 Stage 4a에서 악화된 `mlkem_intt`를 회복하기 위해 ML-KEM INTT
selector인 `SBU_INTT_GS`에서만 COMP4 switching을 다시 살렸다. ML-DSA INTT인
`SBU_MLDSA_INTT`는 여전히 COMP4 input이 zero다.

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

Stage 4b TVLA overview:

![Stage 4b TVLA overview](../../../reports/tvla/mlkem_mldsa_blanking_stage4b_kem_intt_comp4_exception_20260520_cw305_husky_1000/mlkem_mldsa_tvla_overview.png)

Stage 4b vs baseline:

![Stage 4b vs baseline](../../../reports/tvla/mlkem_mldsa_blanking_stage4b_kem_intt_comp4_exception_20260520_cw305_husky_1000/comparison_vs_baseline.png)

| Operation | Baseline | Stage 4b | 변화 |
|---|---:|---:|---:|
| `mlkem_ntt` | 84.901 | 96.516 | 악화 |
| `mlkem_intt` | 65.052 | 42.888 | 개선 |
| `mlkem_pwm` | 114.713 | 103.869 | 개선 |
| `mldsa_ntt` | 132.180 | 85.738 | 개선 |
| `mldsa_intt` | 135.012 | 112.877 | 개선 |
| `mldsa_pwm` | 144.055 | 78.170 | 개선 |

Key repeat:

| Operation | Stage 4b full | Repeat | Repeat peak |
|---|---:|---:|---:|
| `mlkem_pwm` | 103.869 | 105.388 | 63 |
| `mldsa_intt` | 112.877 | 114.900 | 123 |
| `mldsa_pwm` | 78.170 | 74.680 | 109 |

## 현재 Stage 4b RTL에 들어간 blanking

| 경로 | 파일 | 값 | 조건 |
|---|---|---|---|
| BRAM read output | `poly_memory_updown.v` | `0` | `a_en=0` |
| SBU invalid ML-KEM input | `superbutterfly_sbu_routed.v` | `0` | `valid_i=0`, ML-KEM selector |
| SBU invalid ML-DSA input | `superbutterfly_sbu_routed.v` | public PRD | `valid_i=0`, ML-DSA selector |
| SBU invalid output | `superbutterfly_sbu_routed.v` | `0` | delayed valid false |
| ML-KEM cascade | `sbu_pair_pe.v` | `0` | SBU0 output invalid |
| COMP2 active input | `superbutterfly_sbu_routed.v` | `0` | INTT가 아님 |
| COMP1 active input | `superbutterfly_sbu_routed.v` | `0` | output mux가 COMP1을 쓰지 않음 |
| COMP4 active input | `superbutterfly_sbu_routed.v` | `0` | NTT/PWM1/ML-KEM INTT 외 |

중요: Stage 4b의 `comp3_agile_modmul.v`에는 COMP3 inactive-cone dummy가 없다.
KEM cone과 DSA cone은 모두 real `a_i/b_i`를 보고, output mux만 `opmode_i`로
선택한다.

## 검증

- diagnostics 통과.
- Verilator regression 통과.
- Stage 4b post-route timing: WNS `0.203 ns`, TNS `0.000 ns`, WHS `0.063 ns`, THS `0.000 ns`.
- utilization: 9727 LUTs, 3268 registers, 8 RAMB36-equivalent, 0 DSP.
- cycle count 유지.

## 판단

Stage 4b는 현재 best all-operation small-RTL blanking candidate다. TVLA pass는
아니지만, baseline worst `144.055`를 `112.877`로 낮췄고 key repeat도 안정적이다.

## 복구 방법

Stage 4b에서 Stage 3g로 되돌리려면 COMP1/2/4 active input zero blanking을 제거하고
Stage 3g처럼 real operands가 각 COMP에 들어가도록 복구한다. Stage 4b에서 Stage 4a로
되돌리려면 `SBU_INTT_GS` COMP4 exception만 제거해 ML-KEM INTT에서도 COMP4 input을
zero로 둔다.
