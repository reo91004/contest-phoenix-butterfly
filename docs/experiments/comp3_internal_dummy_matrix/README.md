# COMP3 Internal Dummy Matrix

작성일: 2026-05-21 KST

## 목적

이 실험 묶음은 Stage 4b restored RTL을 기준으로, COMP3 내부의 multiplier/reducer
sub-cone에 public dummy switching을 넣었을 때 TVLA가 어떻게 바뀌는지 분해한다.

이전 `inactive_dummy_matrix`의 Stage 2는 COMP3를 KEM cone / DSA cone 단위로만
나눴다. 이번에는 그보다 더 안쪽을 본다.

```text
COMP3 전체 inactive cone dummy가 아니라,
DSA Karatsuba, DSA Montgomery reducer, KEM lo/hi multiplier, KEM Barrett reducer를
따로 분해하면 어느 내부 cone이 TVLA shape를 바꾸는가?
```

## 기준 RTL

- 기준은 Stage 4b restored RTL이다.
- Solinas Stage 7 branch는 사용하지 않는다.
- `inactive_dummy_matrix`의 rejected RTL도 사용하지 않는다.
- active architectural output으로 선택되는 계산값에는 dummy를 섞지 않는다.
- SBU latency 8, scheduler, memory layout, cycle count, DSP 0 목표는 유지한다.

## Stage 구성

| 문서 | 실험 | 상태 |
|---|---|---|
| `stage1_control.md` | Stage 4b control alias | 기존 control 재사용 |
| `stage2_dsa_mul_only_prd.md` | ML-KEM mode에서 inactive DSA Karatsuba만 PRD, DSA reducer는 zero | accepted 후보, repeat 재현 |
| `stage3_dsa_reducer_only_prd.md` | ML-KEM mode에서 inactive DSA reducer만 PRD, DSA Karatsuba는 zero | timing reject |
| `stage4_dsa_mul_to_reducer_prd.md` | ML-KEM mode에서 inactive DSA Karatsuba PRD 결과를 reducer까지 전파 | rejected, ML-KEM 매우 개선 / ML-DSA INTT 악화 |
| `stage5_kem_lo_lane_prd.md` | ML-DSA mode에서 inactive KEM lo lane만 PRD | rejected, ML-DSA INTT 및 ML-KEM 악화 |
| `stage6_kem_hi_lane_prd.md` | ML-DSA mode에서 inactive KEM hi lane만 PRD | rejected, ML-DSA NTT/INTT/PWM 악화 |
| `stage7_kem_reducer_prd.md` | ML-DSA mode에서 inactive KEM Barrett reducer 쪽 PRD | rejected, ML-DSA INTT 크게 악화 |
| `stage8_combined_accepted_internal.md` | 개선 후보만 조합 | skipped, 조합 후보가 Stage 2 하나뿐 |
| `stage9_dsa_mul_only_zero.md` | Stage 2의 zero counterpart: ML-KEM mode inactive DSA Karatsuba와 reducer를 zero | informative trade-off, not final accepted |

## 현재 Control

현재 비교 기준은 `reports/tvla/inactive_dummy_stage1_stage4b_control_260521`이다.

| Operation | max `|t|` | peak index |
|---|---:|---:|
| `mlkem_ntt` | 98.403 | 116 |
| `mlkem_intt` | 44.048 | 116 |
| `mlkem_pwm` | 104.827 | 63 |
| `mldsa_ntt` | 85.319 | 506 |
| `mldsa_intt` | 122.083 | 123 |
| `mldsa_pwm` | 74.604 | 109 |

![Stage 4b control TVLA overview](../../../reports/tvla/inactive_dummy_stage1_stage4b_control_260521/mlkem_mldsa_tvla_overview.png)

## 판단 규칙

- Stage 4b control보다 six-op worst가 낮아야 accept 후보로 본다.
- `mlkem_pwm` peak 63 또는 `mldsa_intt` peak 123이 커지면 reject 쪽으로 본다.
- ML-KEM만 좋아지고 ML-DSA가 크게 악화하면 informative/rejected로 보존한다.
- 개선 후보만 `ORDER_SEED=0xC0DEC` repeat를 수행한다.

## Stage 2 중간 결론

ML-KEM mode에서 inactive DSA Karatsuba만 PRD로 흔들고 DSA Montgomery reducer는
zero로 고정했을 때, six-op 모두 Stage 4b control보다 낮거나 거의 같았다. 특히
이전 whole COMP3 inactive-cone PRD와 달리 ML-DSA가 크게 악화하지 않았다.

| Operation | Stage 4b control | Stage 2 DSA mul-only PRD | 판단 |
|---|---:|---:|---|
| `mlkem_ntt` | 98.403 | 68.726 | 개선 |
| `mlkem_intt` | 44.048 | 43.319 | 거의 동일 |
| `mlkem_pwm` | 104.827 | 96.004 | 개선 |
| `mldsa_ntt` | 85.319 | 80.229 | 개선 |
| `mldsa_intt` | 122.083 | 117.028 | 개선 |
| `mldsa_pwm` | 74.604 | 71.047 | 개선 |

Key repeat에서도 핵심 op 개선이 재현되었다.

| Operation | Stage 4b control | Stage 2 repeat | 판단 |
|---|---:|---:|---|
| `mlkem_pwm` | 104.827 | 95.354 | 재현 |
| `mldsa_intt` | 122.083 | 113.569 | 재현 |
| `mldsa_pwm` | 74.604 | 72.984 | 재현 |

따라서 Stage 2는 TVLA pass는 아니지만 accepted 후보로 보존한다. 다음 실험은 같은 기준
Stage 4b에서 DSA Montgomery reducer-only PRD를 분리해, 개선 원인이 Karatsuba
switching인지 reducer switching인지 더 좁힌다.

## Stage 3 중간 결론

ML-KEM mode에서 inactive DSA Karatsuba를 zero로 두고 DSA Montgomery reducer input만
public PRD로 흔든 실험은 기능 검증은 통과했지만 30ns timing을 만족하지 못했다.

| 항목 | 결과 |
|---|---:|
| WNS/TNS | `-0.466 ns / -6.323 ns` |
| WHS/THS | `0.102 ns / 0.000 ns` |
| LUT/FF/RAMB36/DSP | `10098 / 3343 / 8 / 0` |

따라서 TVLA를 실행하지 않고 timing reject로 남긴다. 원인상 64-bit PRD mux가
Montgomery reducer 입력 앞에 들어가며 critical path를 키운 것으로 본다.

## Stage 4 중간 결론

ML-KEM mode에서 inactive DSA Karatsuba PRD 결과를 Montgomery reducer까지 전파하면
ML-KEM 세 operation은 매우 크게 좋아졌다. 그러나 `mldsa_intt` peak 123이
`122.083 -> 128.142`로 악화해 accepted 후보는 아니다.

| Operation | Stage 4b control | Stage 4 DSA mul-to-reducer PRD | 판단 |
|---|---:|---:|---|
| `mlkem_ntt` | 98.403 | 29.206 | 크게 개선 |
| `mlkem_intt` | 44.048 | 32.115 | 개선 |
| `mlkem_pwm` | 104.827 | 48.449 | 크게 개선 |
| `mldsa_ntt` | 85.319 | 83.253 | 거의 동일 |
| `mldsa_intt` | 122.083 | 128.142 | 악화 |
| `mldsa_pwm` | 74.604 | 71.907 | 개선 |

해석상 ML-KEM 개선에는 inactive DSA reducer까지 포함한 switching shape가 강하게
작용한다. 하지만 이 전파가 ML-DSA INTT의 active-window peak를 다시 키우므로, 최종
후보로는 Stage 2의 Karatsuba-only PRD가 더 균형 잡혀 있다.

## Stage 5 중간 결론

ML-DSA mode에서 inactive KEM lo lane만 public PRD로 흔든 실험은 timing과 기능은
통과했지만 TVLA에서는 reject다. 직접 기대했던 ML-DSA 개선은 `mldsa_ntt`에서만
나타났고, worst인 `mldsa_intt` peak 123은 `122.083 -> 136.095`로 악화했다.
논리적으로 ML-KEM active datapath는 바꾸지 않았지만 ML-KEM 세 op도 함께 악화했다.

| Operation | Stage 4b control | Stage 5 KEM lo-lane PRD | 판단 |
|---|---:|---:|---|
| `mlkem_ntt` | 98.403 | 114.410 | 악화 |
| `mlkem_intt` | 44.048 | 51.082 | 악화 |
| `mlkem_pwm` | 104.827 | 115.727 | 악화 |
| `mldsa_ntt` | 85.319 | 74.872 | 개선 |
| `mldsa_intt` | 122.083 | 136.095 | 악화 |
| `mldsa_pwm` | 74.604 | 91.089 | 악화 |

이 결과는 inactive KEM lo-lane switching이 전체 배치/라우팅 및 active-window leakage
shape를 크게 흔들 수 있음을 보여준다. 다음 실험에서는 KEM hi lane을 분리해 같은
현상이 lane-specific인지 확인한다.

## Stage 6 중간 결론

ML-DSA mode에서 inactive KEM hi lane만 public PRD로 흔든 실험은 Stage 5보다
ML-KEM 쪽 영향은 덜했지만, ML-DSA 세 operation이 모두 악화했다.

| Operation | Stage 4b control | Stage 6 KEM hi-lane PRD | 판단 |
|---|---:|---:|---|
| `mlkem_ntt` | 98.403 | 69.258 | 개선 |
| `mlkem_intt` | 44.048 | 48.601 | 악화 |
| `mlkem_pwm` | 104.827 | 106.615 | 거의 동일/악화 |
| `mldsa_ntt` | 85.319 | 106.009 | 악화 |
| `mldsa_intt` | 122.083 | 132.490 | 악화 |
| `mldsa_pwm` | 74.604 | 88.216 | 악화 |

따라서 KEM lo/high multiplier lane dummy는 둘 다 ML-DSA active-window peak를
키우는 방향이다. 남은 KEM 내부 분해 실험은 multiplier가 아니라 Barrett reducer
입력만 dummy로 흔드는 Stage 7이다.

## Stage 7 중간 결론

ML-DSA mode에서 inactive KEM Barrett reducer input만 public PRD로 바꾼 실험은
`mldsa_intt`를 가장 크게 악화했다. `mlkem_intt`는 좋아졌지만, 전체 worst와
ML-DSA active-window peak를 망가뜨려 reject다.

| Operation | Stage 4b control | Stage 7 KEM reducer PRD | 판단 |
|---|---:|---:|---|
| `mlkem_ntt` | 98.403 | 116.556 | 악화 |
| `mlkem_intt` | 44.048 | 34.713 | 개선 |
| `mlkem_pwm` | 104.827 | 107.651 | 악화 |
| `mldsa_ntt` | 85.319 | 93.508 | 악화 |
| `mldsa_intt` | 122.083 | 160.762 | 크게 악화 |
| `mldsa_pwm` | 74.604 | 79.059 | 악화 |

Stage 5/6/7을 합쳐 보면 ML-DSA mode에서 inactive KEM side에 PRD switching을
넣는 것은 안정적인 개선이 아니며, 특히 `mldsa_intt` peak 123을 계속 키운다.
따라서 이번 COMP3 internal matrix에서 accepted 후보는 Stage 2 하나뿐이다.

## Stage 9 질문

Stage 2의 개선이 random dummy 때문인지 zero blanking 때문인지 아직 분리되지 않았다.
따라서 Stage 9에서는 Stage 2와 같은 위치에서 PRD 대신 `0`을 넣는다.

해석 기준:

- Stage 9가 Stage 2와 비슷하면 random성이 아니라 DSA reducer zero/DSA cone quieting이 핵심이다.
- Stage 9가 Stage 2보다 나쁘면 inactive DSA Karatsuba의 public switching이 TVLA shape를 낮춘 것이다.
- Stage 9가 Stage 4b보다 나쁘면 deterministic zero가 Stage 5 B3처럼 hiding noise를 제거한 것이다.

## Stage 9 결론

Stage 9 zero counterpart는 `mldsa_intt` peak 123을 가장 잘 낮췄지만, `mlkem_intt`와
`mldsa_ntt`를 크게 악화했다. repeat에서도 같은 trade-off가 재현되었다.

| Operation | Stage 4b control | Stage 2 PRD | Stage 9 zero | Stage 9 repeat | 판단 |
|---|---:|---:|---:|---:|---|
| `mlkem_ntt` | 98.403 | 68.726 | 89.643 | - | PRD가 더 좋음 |
| `mlkem_intt` | 44.048 | 43.319 | 79.737 | 78.473 | zero 악화 |
| `mlkem_pwm` | 104.827 | 96.004 | 101.765 | 103.608 | PRD가 더 좋음 |
| `mldsa_ntt` | 85.319 | 80.229 | 108.494 | 114.252 | zero 악화 |
| `mldsa_intt` | 122.083 | 117.028 | 108.032 | 110.611 | zero가 더 좋음 |
| `mldsa_pwm` | 74.604 | 71.047 | 71.612 | 71.780 | 유사 |

따라서 Stage 9는 final accepted가 아니라 informative trade-off다. Stage 2의 효과는
단순한 zero quieting이 아니라, inactive DSA Karatsuba에 public switching을 남기는
쪽이 전체 six-op shape를 더 균형 있게 만든다는 해석을 뒷받침한다.

## 공통 실행 명령

```bash
python3 scripts/diagnostics/check_phoenix_consistency.py
python3 scripts/diagnostics/check_bank_conflicts.py
bash sim/run_verilator.sh 'tb_comp3_agile_modmul tb_superbutterfly_all_modes tb_phoenix_core tb_phoenix_host_io tb_phoenix_cw305_wrapper tb_phoenix_mldsa_pwm_io'
```

```bash
OUTDIR=reports/tvla/<comp3_internal_stage_name> \
OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' \
TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0x5EED \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```
