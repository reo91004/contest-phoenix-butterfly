# Stage 3: ML-DSA invalid-cycle public PRD flushing

## 목적

Stage 3는 invalid SBU cycle을 모두 zero로 조용하게 만들기보다, secret과 무관한
public PRD dummy operand로 SBU 내부 state를 flush하면 TVLA peak가 낮아지는지
확인한 실험이다.

여기서 PRD는 masking randomness가 아니다. deterministic public LFSR이고,
architectural output이나 memory writeback으로 나가지 않는다.

## 기준 RTL

기준은 Stage 2다. Stage 3 계열은 Stage 2 memory read-output blanking을 유지한
채 `rtl/sbu/superbutterfly_sbu_routed.v`의 invalid-cycle SBU input 정책을 바꿨다.

## 공통 RTL 구조

PRD source:

```verilog
reg [31:0] blank_lfsr;
wire [31:0] blank_a = blank_lfsr;
wire [31:0] blank_b =
    {blank_lfsr[15:0], blank_lfsr[31:16]} ^ 32'hA5A55A5A;
wire [31:0] blank_c =
    {blank_lfsr[7:0], blank_lfsr[31:8]} ^ 32'h3C6EF372;
```

최종적으로 살아남은 Stage 3d/3g/4b 계열 정책:

```verilog
wire use_prd_candidate = `SBU_OPMODE(sel_i); // ML-DSA이면 1
wire use_prd_blank =
    USE_PRD_INVALID_BLANKING && !valid_i && use_prd_candidate;
```

즉 valid cycle은 real input, invalid ML-KEM cycle은 zero, invalid ML-DSA cycle은
public PRD를 넣는다. 이때 `v1=0`이므로 dummy computation은 valid output이
아니다.

## Stage 3a: public PRD flush, ML-DSA dummy selector

기존 이름: Stage 3a

초기 실험은 invalid cycle에 public PRD operand를 넣었지만 dummy selector가
ML-DSA PWM 쪽으로 치우쳐 있었다.

| Operation | Baseline | Stage 3a | 변화 |
|---|---:|---:|---:|
| `mlkem_ntt` | 84.901 | 107.246 | 악화 |
| `mlkem_intt` | 65.052 | 102.237 | 악화 |
| `mlkem_pwm` | 114.713 | 129.216 | 악화 |
| `mldsa_ntt` | 132.180 | 96.864 | 개선 |
| `mldsa_intt` | 135.012 | 148.236 | 악화 |
| `mldsa_pwm` | 144.055 | 70.810 | 크게 개선 |

해석: ML-DSA NTT/PWM에는 강한 개선 신호가 있었지만 ML-KEM이 크게 악화했다.
selector/opmode mismatch가 원인 후보였다.

## Stage 3b: operation-matched PRD selector

기존 이름: Stage 3b

Stage 3a의 PRD operand는 유지하되 invalid-cycle selector를 현재 operation과
맞췄다.

| Operation | Baseline | Stage 3b | 변화 |
|---|---:|---:|---:|
| `mlkem_ntt` | 84.901 | 121.281 | 악화 |
| `mlkem_intt` | 65.052 | 67.855 | 거의 동일 |
| `mlkem_pwm` | 114.713 | 123.381 | 악화 |
| `mldsa_ntt` | 132.180 | 87.880 | 개선 |
| `mldsa_intt` | 135.012 | 131.437 | 소폭 개선 |
| `mldsa_pwm` | 144.055 | 72.497 | 크게 개선 |

해석: ML-DSA NTT/PWM 개선은 재현되었고, Stage 3a의 ML-KEM INTT 악화는 일부
완화되었다. 그러나 ML-KEM NTT/PWM은 여전히 나빴다.

## Stage 3c: ML-KEM zero, ML-DSA PRD hybrid

기존 이름: Stage 3c

ML-KEM invalid cycle은 Stage 2처럼 zero로 두고, ML-DSA invalid cycle에만 PRD를
넣었다. 단, 이 버전은 LFSR이 매 cycle free-run했다.

| Operation | Baseline | Stage 3c | 변화 |
|---|---:|---:|---:|
| `mlkem_ntt` | 84.901 | 142.259 | 크게 악화 |
| `mlkem_intt` | 65.052 | 79.685 | 악화 |
| `mlkem_pwm` | 114.713 | 114.232 | 거의 동일 |
| `mldsa_ntt` | 132.180 | 106.959 | 개선 |
| `mldsa_intt` | 135.012 | 114.004 | 개선 |
| `mldsa_pwm` | 144.055 | 68.711 | 크게 개선 |

해석: ML-KEM invalid operand는 zero였는데도 ML-KEM NTT가 크게 악화했다. 따라서
원인은 PRD operand가 ML-KEM arithmetic으로 들어간 것이 아니라, free-running LFSR
자체의 extra switching 또는 placement 영향으로 보았다.

## Stage 3d: gated LFSR

기존 이름: Stage 3d

Stage 3c의 hybrid policy는 유지하되, LFSR은 실제로 ML-DSA invalid-cycle PRD를
emit할 때만 advance하도록 gated 처리했다.

| Operation | Baseline | Stage 3d | 변화 |
|---|---:|---:|---:|
| `mlkem_ntt` | 84.901 | 95.158 | 소폭 악화 |
| `mlkem_intt` | 65.052 | 44.948 | 개선 |
| `mlkem_pwm` | 114.713 | 123.480 | 악화 |
| `mldsa_ntt` | 132.180 | 92.929 | 개선 |
| `mldsa_intt` | 135.012 | 130.465 | 소폭 개선 |
| `mldsa_pwm` | 144.055 | 71.915 | 크게 개선 |

Stage 3d는 Stage 3c의 ML-KEM NTT 악화를 크게 줄였다. 이 결과는 free-running
dummy generator가 실제 문제였다는 해석을 강하게 지지한다.

## Stage 3d methodology check: shuffled order

기존 이름: Stage 3d shuffled

같은 Stage 3d bitstream으로 trace order를 shuffle했다.

| Operation | Baseline | Stage 3d shuffled | 변화 |
|---|---:|---:|---:|
| `mlkem_ntt` | 84.901 | 99.210 | 악화 |
| `mlkem_intt` | 65.052 | 44.315 | 개선 |
| `mlkem_pwm` | 114.713 | 114.901 | 거의 동일 |
| `mldsa_ntt` | 132.180 | 94.490 | 개선 |
| `mldsa_intt` | 135.012 | 127.071 | 개선 |
| `mldsa_pwm` | 144.055 | 71.935 | 크게 개선 |

해석: Stage 3d 결론은 capture order artifact가 아니었다. 특히 `mldsa_pwm`은
71.915 paired vs 71.935 shuffled로 거의 같았다.

## Stage 3e: no-PRD control

기존 이름: Stage 3e

Stage 3d 코드 shape는 유지하되 `USE_PRD_INVALID_BLANKING=0`으로 PRD를 껐다.

| Operation | Stage 3d shuffled | Stage 3e | 변화 |
|---|---:|---:|---:|
| `mlkem_ntt` | 99.210 | 105.942 | 악화 |
| `mlkem_intt` | 44.315 | 35.023 | 개선 |
| `mlkem_pwm` | 114.901 | 114.851 | 거의 동일 |
| `mldsa_ntt` | 94.490 | 146.369 | 크게 악화 |
| `mldsa_intt` | 127.071 | 125.538 | 거의 동일 |
| `mldsa_pwm` | 71.935 | 141.801 | 크게 악화 |

해석: ML-DSA NTT/PWM 개선은 PRD invalid-cycle flushing에 의존했다. PRD를 끄면
개선이 거의 사라졌다.

## Stage 3f: targeted ML-DSA NTT/PWM PRD

기존 이름: Stage 3f

ML-DSA NTT/PWM에만 PRD를 넣고 ML-DSA INTT에는 넣지 않는 targeted policy를
실험했다.

| Operation | Baseline | Stage 3f | 변화 |
|---|---:|---:|---:|
| `mlkem_ntt` | 84.901 | 97.873 | 악화 |
| `mlkem_intt` | 65.052 | 69.397 | 악화 |
| `mlkem_pwm` | 114.713 | 113.071 | 거의 동일 |
| `mldsa_ntt` | 132.180 | 84.613 | 크게 개선 |
| `mldsa_intt` | 135.012 | 147.020 | 악화 |
| `mldsa_pwm` | 144.055 | 69.409 | 크게 개선 |

INTT repeat에서도 `mlkem_intt=71.813`, `mldsa_intt=151.225`로 악화가 재현됐다.
따라서 targeted policy는 NTT/PWM에는 좋지만 all-operation 후보로는 reject했다.

## Stage 3g: balanced PRD repeat

기존 이름: Stage 3g

Stage 3d의 balanced policy를 재확인했다.

| Operation | Stage 3d shuffled | Stage 3g | 변화 |
|---|---:|---:|---:|
| `mlkem_ntt` | 99.210 | 98.885 | 거의 동일 |
| `mlkem_intt` | 44.315 | 48.363 | 소폭 악화 |
| `mlkem_pwm` | 114.901 | 120.513 | 소폭 악화 |
| `mldsa_ntt` | 94.490 | 93.214 | 거의 동일 |
| `mldsa_intt` | 127.071 | 121.693 | 개선 |
| `mldsa_pwm` | 71.935 | 74.868 | 소폭 악화 |

Stage 3g는 Stage 3d policy가 재현 가능함을 확인했다. 이후 Stage 4는 Stage 3g의
balanced ML-DSA PRD invalid-cycle flushing을 유지하고 active COMP blanking을
추가했다.

## 복구 방법

Stage 3 계열을 Stage 2로 되돌리려면 다음을 제거한다.

- `blank_lfsr`, `blank_a/b/c`, `use_prd_candidate`, `use_prd_blank`.
- invalid ML-DSA cycle에서 PRD를 넣는 branch.
- LFSR advance 조건.

Stage 3d/3g/4b policy에서 PRD만 끄려면 `USE_PRD_INVALID_BLANKING=1'b0`으로
두는 Stage 3e 형태가 control이다.

## 판단

Stage 3의 핵심 발견은 두 가지다.

- ML-DSA NTT/PWM 개선에는 public PRD invalid-cycle flushing이 실제로 필요하다.
- PRD generator는 free-run하면 ML-KEM에 악영향을 줄 수 있으므로 gated되어야 한다.

하지만 Stage 3만으로는 TVLA pass가 아니며, 이후 Stage 4에서 active valid-cycle
unused COMP input blanking을 추가했다.
