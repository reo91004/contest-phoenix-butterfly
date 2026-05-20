# Inactive Calculation Dummy Matrix

작성일: 2026-05-21 KST

## 목적

이 실험 묶음은 Stage 4b restored RTL을 기준으로, 출력에 선택되지 않지만 내부에서
계속 계산되는 COMP1/2/3/4 경로에 public dummy switching을 넣었을 때 TVLA peak가
함께 내려가는지 확인한다.

핵심 질문은 다음이다.

```text
active architectural output은 그대로 두고,
inactive calculation cone/input에만 zero 또는 public PRD dummy를 넣으면
전체 fixed-vs-random TVLA가 개선되는가?
```

## 기준 RTL

기준은 Stage 4b restored RTL이다.

- ML-DSA Solinas Stage 7은 rejected/informative로 보존하고, 이 실험에는 사용하지
  않는다.
- Stage 6b COMP3 PRD dummy도 최종 RTL에는 들어 있지 않으므로, 필요한 경우 Stage 4b
  위에서 다시 구현해 측정한다.
- 9-bit instruction, SBU latency 8, two-SBU PE, scheduler, memory layout, cycle
  count는 유지한다.

## Stage 구성

| 문서 | 실험 | 상태 |
|---|---|---|
| `stage1_stage4b_control.md` | Stage 4b control 재측정 | 완료, control로 사용 |
| `stage2_comp3_inactive_prd.md` | COMP3 inactive algorithm cone public PRD | rejected, ML-KEM만 개선 |
| `stage3_comp2_unused_prd.md` | COMP2 unused-cycle public PRD | rejected, ML-DSA INTT만 개선 |
| `stage4_comp4_unused_prd.md` | COMP4 unused-cycle public PRD | rejected, ML-KEM NTT 크게 악화 |
| `stage5_comp1_unused_prd.md` | COMP1 unused-cycle public PRD | rejected, ML-KEM NTT/PWM 악화 |
| `stage6_combined_accepted_prd.md` | 개선 후보만 조합 | 실행 안 함, accepted 단일 후보 없음 |

## 공통 불변식

- dummy는 secret, fixed/random class, memory contents와 독립이다.
- active output으로 실제 사용되는 계산값에는 dummy를 섞지 않는다.
- public PRD는 hiding/noise 효과를 낼 수 있으므로, 개선 후보는 repeat seed로 재현성을
  확인한다.
- TVLA는 fixed-vs-random만 사용한다.

## 공통 실행 명령

```bash
python3 scripts/diagnostics/check_phoenix_consistency.py
python3 scripts/diagnostics/check_bank_conflicts.py
bash sim/run_verilator.sh 'tb_comp3_agile_modmul tb_superbutterfly_all_modes tb_phoenix_core tb_phoenix_host_io tb_phoenix_cw305_wrapper tb_phoenix_mldsa_pwm_io'
```

```bash
OUTDIR=reports/tvla/<inactive_dummy_stage_name> \
OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' \
TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0x5EED \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```

## 판단 규칙

- Stage 4b control보다 worst max `|t|`가 낮아야 accept 후보로 본다.
- `mldsa_intt` peak 123 또는 `mlkem_pwm` peak 63이 커지면 reject 쪽으로 본다.
- 한 operation만 좋아지고 worst가 악화되면 reject한다.
- 개선 후보만 `ORDER_SEED=0xC0DEC` repeat를 수행한다.

## 현재 Control

현재 matrix의 비교 기준은 `reports/tvla/inactive_dummy_stage1_stage4b_control_260521`이다.

| Operation | max `|t|` | peak index |
|---|---:|---:|
| `mlkem_ntt` | 98.403 | 116 |
| `mlkem_intt` | 44.048 | 116 |
| `mlkem_pwm` | 104.827 | 63 |
| `mldsa_ntt` | 85.319 | 506 |
| `mldsa_intt` | 122.083 | 123 |
| `mldsa_pwm` | 74.604 | 109 |

![Stage 1 control TVLA overview](../../../reports/tvla/inactive_dummy_stage1_stage4b_control_260521/mlkem_mldsa_tvla_overview.png)

## Stage 2 중간 결론

COMP3 inactive algorithm cone PRD는 ML-KEM 세 operation을 크게 낮췄지만,
`mldsa_intt`와 `mldsa_pwm`을 악화시켜 reject했다.

| Operation | Stage 1 control | Stage 2 COMP3 PRD | 판단 |
|---|---:|---:|---|
| `mlkem_ntt` | 98.403 | 25.908 | 개선 |
| `mlkem_intt` | 44.048 | 29.160 | 개선 |
| `mlkem_pwm` | 104.827 | 53.688 | 개선 |
| `mldsa_ntt` | 85.319 | 87.421 | 거의 동일 |
| `mldsa_intt` | 122.083 | 165.043 | 크게 악화 |
| `mldsa_pwm` | 74.604 | 93.703 | 악화 |

## Stage 3 중간 결론

COMP2 unused-cycle PRD는 `mldsa_intt` peak 123을 크게 낮췄지만, `mlkem_pwm`이
더 큰 worst가 되어 reject했다.

| Operation | Stage 1 control | Stage 3 COMP2 PRD | 판단 |
|---|---:|---:|---|
| `mlkem_ntt` | 98.403 | 76.959 | 개선 |
| `mlkem_intt` | 44.048 | 54.099 | 악화 |
| `mlkem_pwm` | 104.827 | 128.534 | 크게 악화 |
| `mldsa_ntt` | 85.319 | 93.961 | 악화 |
| `mldsa_intt` | 122.083 | 93.900 | 개선 |
| `mldsa_pwm` | 74.604 | 76.621 | 거의 동일 |

## Stage 4 중간 결론

COMP4 unused-cycle PRD는 timing은 통과했지만, `mlkem_ntt`가 크게 악화되어 reject했다.
특히 Stage 4b에서 의도적으로 살려 둔 ML-KEM INTT COMP4 exception만으로는 충분하지
않았고, COMP4 dummy LFSR 자체가 placement/routing 또는 공유 주변 cone의 전력 패턴을
키운 것으로 해석한다.

| Operation | Stage 1 control | Stage 4 COMP4 PRD | 판단 |
|---|---:|---:|---|
| `mlkem_ntt` | 98.403 | 165.103 | 크게 악화 |
| `mlkem_intt` | 44.048 | 43.126 | 거의 동일 |
| `mlkem_pwm` | 104.827 | 105.432 | 거의 동일 |
| `mldsa_ntt` | 85.319 | 103.791 | 악화 |
| `mldsa_intt` | 122.083 | 121.648 | 거의 동일 |
| `mldsa_pwm` | 74.604 | 73.588 | 거의 동일 |

## Stage 5 중간 결론

COMP1 unused-cycle PRD는 `SBU_MLDSA_PWM`에서만 COMP1 dummy를 넣도록 제한했지만,
`mlkem_ntt`, `mlkem_pwm`, `mldsa_ntt`가 control보다 악화되어 reject했다. `mldsa_intt`와
`mldsa_pwm`은 조금 낮아졌지만, 전체 worst와 핵심 ML-KEM peak가 악화되므로 조합 후보가
아니다.

| Operation | Stage 1 control | Stage 5 COMP1 PRD | 판단 |
|---|---:|---:|---|
| `mlkem_ntt` | 98.403 | 131.925 | 악화 |
| `mlkem_intt` | 44.048 | 41.747 | 거의 동일 |
| `mlkem_pwm` | 104.827 | 115.442 | 악화 |
| `mldsa_ntt` | 85.319 | 108.988 | 악화 |
| `mldsa_intt` | 122.083 | 115.536 | 개선이지만 worst 아님 |
| `mldsa_pwm` | 74.604 | 72.259 | 거의 동일 |

## Matrix 결론

이번 matrix에서 Stage 2-5는 모두 informative/rejected다. inactive 계산부에 public PRD
switching을 넣으면 일부 operation은 낮아질 수 있지만, 전체 six-op worst가 함께 내려가는
일관된 후보는 없었다. 따라서 이 matrix에서는 Stage 6 combined PRD를 실행하지 않았고,
다음 COMP3/COMP2 internal matrix의 기준을 Stage 4b restored RTL로 다시 잡았다.
