# Datapath Blanking TVLA 실험 요약

작성일: 2026-05-21 KST

이 폴더는 PHOENIX ML-KEM / ML-DSA 가속기에서 수행한 datapath blanking TVLA
실험을 Stage 단위로 정리한다. 각 Stage 문서는 “무엇을 바꿨는지, 왜 바꿨는지,
TVLA가 어떻게 변했는지, 다시 이전 기준으로 어떻게 복구할 수 있는지”를 남긴다.

## 현재 RTL

현재 working tree의 active RTL은 **Stage 6c candidate**다. 다만 이 폴더의 Stage 1-6
역사적 datapath blanking 결론에서 최종 선택됐던 기준점은 **Stage 4b restored RTL**이다.

- original baseline이 아니다.
- Stage 6b public PRD inactive-cone dummy가 아니다.
- 현재 source에는 Stage 4b 위에 COMP3 internal Stage 2와 COMP2 internal Stage 4 PRD
  조합이 적용돼 있다.
- Stage 4b에 남아 있는 핵심은 memory read-output zero blanking, ML-DSA invalid-cycle PRD flushing, COMP1/2/4 active unused-input zero blanking, ML-KEM INTT COMP4 exception이다.

## Stage별 결론

| 문서 | 핵심 실험 | 결론 |
|---|---|---|
| `00_baseline.md` | blanking 없는 기준 TVLA | 모든 op가 크게 실패 |
| `01_stage1.md` | invalid SBU/cascade/output zero blanking | 일부 개선, `mlkem_intt` 악화 |
| `02_stage2.md` | memory read-output zero blanking, Stage 2b ablation | `mlkem_intt` 안정 개선, pass는 아님 |
| `03_stage3.md` | ML-DSA invalid-cycle public PRD flushing 계열 | PRD가 ML-DSA NTT/PWM 개선에 필요함 |
| `04_stage4.md` | active COMP1/2/4 blanking, Stage 4b exception | 현재 최종 선택 RTL |
| `05_stage5.md` | Stage 4b 이후 small zero blanking 후보 | 모두 rejected |
| `06_stage6.md` | COMP3 inactive-cone dummy 후보 | Stage 6b는 ML-KEM 힌트가 크지만 rejected |
| `07_next_experiments.md` | Solinas/random dummy 후속 계획 | Solinas rejected, inactive dummy rejected, COMP2/COMP3 조합 Stage 6c candidate |

후속 실행 원장은 `docs/experiments/inactive_dummy_matrix/README.md`,
`docs/experiments/comp3_internal_dummy_matrix/README.md`,
`docs/experiments/comp2_internal_dummy_matrix/README.md`에 둔다.

## 주요 TVLA 수치

| Operation | Baseline | Stage 4b | Stage 6b |
|---|---:|---:|---:|
| `mlkem_ntt` | 84.901 | 96.516 | 29.532 |
| `mlkem_intt` | 65.052 | 42.888 | 27.140 |
| `mlkem_pwm` | 114.713 | 103.869 | 52.516 |
| `mldsa_ntt` | 132.180 | 85.738 | 82.381 |
| `mldsa_intt` | 135.012 | 112.877 | 121.557 |
| `mldsa_pwm` | 144.055 | 78.170 | 85.713 |

Stage 6b는 ML-KEM 세 operation을 크게 낮췄지만 `mldsa_intt`와 `mldsa_pwm`을
Stage 4b보다 악화시켰다. 따라서 이 폴더의 원래 datapath blanking 흐름에서는 Stage 4b가
최종 선택이었다. 이후 COMP3/COMP2 internal dummy matrix에서 Stage 6c candidate가 새
best-so-far로 올라왔다.

## 그림

Baseline:

![Baseline TVLA overview](../../../reports/tvla/mlkem_mldsa_secretdist_20260519_cw305_husky_1000/mlkem_mldsa_tvla_overview.png)

Stage 4b:

![Stage 4b TVLA overview](../../../reports/tvla/mlkem_mldsa_blanking_stage4b_kem_intt_comp4_exception_20260520_cw305_husky_1000/mlkem_mldsa_tvla_overview.png)

Stage 6b:

![Stage 6b TVLA overview](../../../reports/tvla/mlkem_mldsa_stage6_r2_prd_dummy_comp3_20260520_cw305_husky_1000/mlkem_mldsa_tvla_overview.png)

## 원본 Raw Ledger

분할 전 전체 raw ledger는 아래에 보존했다.

`docs/archive/260521_datapath_blanking_experiment_full_ledger.md`
