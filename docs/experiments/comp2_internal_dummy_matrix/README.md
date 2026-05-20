# COMP2 Internal Dummy Matrix

작성일: 2026-05-21 KST

## 목적

이 실험 묶음은 Stage 4b restored RTL을 기준으로, COMP2 내부의 KEM/DSA
add/sub/div2 sub-cone에 zero 또는 public PRD dummy를 넣었을 때 TVLA가 어떻게 바뀌는지
분해한다.

이전 `inactive_dummy_matrix`의 COMP2 unused-cycle PRD는 `mldsa_intt` peak 123을
크게 낮췄지만 `mlkem_pwm`과 `mldsa_ntt`를 악화했다. 이번에는 COMP2 전체 unused-cycle이
아니라 COMP2 내부 inactive algorithm cone을 더 좁게 본다.

```text
COMP2 output mux가 선택하지 않는 KEM/DSA arithmetic cone에만
zero 또는 public PRD를 넣으면, mldsa_intt 개선을 유지하면서
ML-KEM/ML-DSA 전체 worst를 낮출 수 있는가?
```

## 기준 RTL

- Stage 2-6b의 단독 COMP2 실험 기준은 Stage 4b restored RTL이다.
- Stage 6c 이후 조합 실험은 COMP3 internal Stage 2 candidate 위에서 수행했다.
- 현재 working tree에는 Stage 6c candidate가 적용돼 있다.
- active architectural output으로 선택되는 계산값에는 dummy를 섞지 않는다.
- SBU latency 8, scheduler, memory layout, cycle count, DSP 0 목표는 유지한다.

## Stage 구성

| 문서 | 실험 | 상태 |
|---|---|---|
| `stage1_control.md` | Stage 4b control alias | 기존 control 재사용 |
| `stage2_dsa_cone_prd_in_kem.md` | ML-KEM mode에서 inactive DSA COMP2 cone만 PRD | rejected, ML-DSA 개선 / ML-KEM NTT 크게 악화 |
| `stage3_dsa_cone_zero_in_kem.md` | Stage 2의 zero counterpart | rejected, ML-KEM 전반 및 ML-DSA NTT 악화 |
| `stage4_kem_cone_prd_in_dsa.md` | ML-DSA mode에서 inactive KEM COMP2 cone만 PRD | rejected/informative, worst 개선이나 NTT/PWM 일부 악화 |
| `stage5_kem_cone_zero_in_dsa.md` | Stage 4의 zero counterpart | rejected, `mldsa_intt` 크게 개선 / NTT와 ML-KEM 악화 |
| `stage6_combined_accepted.md` | op-selective zero/PRD와 개선 후보 조합 | Stage 6c best-so-far / Stage 6d reject / Stage 6e timing reject |

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
- `mldsa_intt` peak 123을 낮추더라도 `mlkem_pwm` peak 63 또는 `mldsa_ntt` peak 506이
  크게 악화하면 reject한다.
- 개선 후보만 `ORDER_SEED=0xC0DEC` repeat를 수행한다.
- rejected 실험도 문서와 patch artifact를 보존한다.

## Stage 2 중간 결론

ML-KEM mode에서 inactive DSA COMP2 cone에 public PRD를 넣으면 ML-DSA 세 operation은
모두 낮아졌다. 그러나 ML-KEM 세 operation이 모두 악화했고, 특히 `mlkem_ntt`가
`98.403 -> 181.375`로 크게 튀어 reject다.

| Operation | Stage 4b control | Stage 2 DSA cone PRD | 판단 |
|---|---:|---:|---|
| `mlkem_ntt` | 98.403 | 181.375 | 크게 악화 |
| `mlkem_intt` | 44.048 | 58.136 | 악화 |
| `mlkem_pwm` | 104.827 | 118.629 | 악화 |
| `mldsa_ntt` | 85.319 | 79.568 | 개선 |
| `mldsa_intt` | 122.083 | 114.601 | 개선 |
| `mldsa_pwm` | 74.604 | 70.903 | 개선 |

해석상 COMP2 inactive DSA cone은 ML-DSA TVLA shape를 낮출 수 있지만, PRD switching을
넣는 방식은 ML-KEM active window를 크게 악화한다. 다음 Stage 3은 같은 위치의
deterministic zero counterpart다.

## Stage 3 중간 결론

ML-KEM mode에서 inactive DSA COMP2 cone을 `0`으로 고정해도 accept 후보가 되지 못했다.
PRD보다 ML-KEM NTT 악화 폭은 작았지만, Stage 4b control 대비 ML-KEM 세 operation이
모두 나빠졌고 `mldsa_ntt`도 크게 악화했다.

| Operation | Stage 4b control | Stage 2 DSA cone PRD | Stage 3 DSA cone zero | 판단 |
|---|---:|---:|---:|---|
| `mlkem_ntt` | 98.403 | 181.375 | 125.940 | zero도 악화 |
| `mlkem_intt` | 44.048 | 58.136 | 70.275 | zero가 더 악화 |
| `mlkem_pwm` | 104.827 | 118.629 | 114.347 | 악화 |
| `mldsa_ntt` | 85.319 | 79.568 | 116.623 | zero에서 크게 악화 |
| `mldsa_intt` | 122.083 | 114.601 | 117.934 | 소폭 개선 |
| `mldsa_pwm` | 74.604 | 70.903 | 76.777 | 소폭 악화 |

해석상 Stage 2의 ML-KEM NTT 대악화에는 PRD switching 성분이 있었지만, inactive DSA
COMP2 cone을 ML-KEM mode에서 PRD/zero로 처리하는 방향 자체가 안전하지 않다. 따라서
Stage 4부터는 반대 방향, 즉 ML-DSA mode에서 inactive KEM COMP2 cone만 건드리는
실험으로 넘어간다.

## Stage 4 중간 결론

ML-DSA mode에서 inactive KEM COMP2 cone에 public PRD를 넣는 방향은 Stage 2/3보다
훨씬 안정적이었다. six-op worst는 `122.083 -> 115.792`로 낮아졌고, `mldsa_intt`,
`mldsa_pwm`, `mlkem_intt`가 개선됐다.

| Operation | Stage 4b control | Stage 4 KEM cone PRD | 판단 |
|---|---:|---:|---|
| `mlkem_ntt` | 98.403 | 101.770 | 소폭 악화 |
| `mlkem_intt` | 44.048 | 31.868 | 개선 |
| `mlkem_pwm` | 104.827 | 108.888 | 소폭 악화 |
| `mldsa_ntt` | 85.319 | 95.607 | 악화 |
| `mldsa_intt` | 122.083 | 115.792 | 개선 |
| `mldsa_pwm` | 74.604 | 70.864 | 개선 |

하지만 `mlkem_ntt`, `mlkem_pwm`, `mldsa_ntt`가 모두 control보다 올라갔기 때문에
“ML-KEM, ML-DSA 모두 유의미한 동반 감소”에는 아직 맞지 않는다. 단독 final candidate가
아니라 informative trade-off로 남기고, 같은 위치의 zero counterpart를 Stage 5에서 본다.

## Stage 5 중간 결론

ML-DSA mode에서 inactive KEM COMP2 cone을 `0`으로 고정하면 `mldsa_intt` peak 123은
가장 크게 내려갔다. 그러나 ML-KEM 세 operation과 `mldsa_ntt`가 같이 악화되어 단독
accept는 아니다.

| Operation | Stage 4b control | Stage 4 KEM cone PRD | Stage 5 KEM cone zero | 판단 |
|---|---:|---:|---:|---|
| `mlkem_ntt` | 98.403 | 101.770 | 121.412 | zero에서 악화 |
| `mlkem_intt` | 44.048 | 31.868 | 53.754 | PRD만 개선 |
| `mlkem_pwm` | 104.827 | 108.888 | 113.692 | 악화 |
| `mldsa_ntt` | 85.319 | 95.607 | 116.949 | zero에서 크게 악화 |
| `mldsa_intt` | 122.083 | 115.792 | 103.804 | zero가 가장 개선 |
| `mldsa_pwm` | 74.604 | 70.864 | 75.799 | PRD만 개선 |

Stage 5의 핵심 교훈은 “COMP2 KEM cone zero가 `mldsa_intt`에는 강하게 먹히지만, 모든
ML-DSA cycle에 적용하면 NTT/PWM switching balance를 깨뜨린다”는 것이다. 다음은
`SBU_MLDSA_INTT`에만 적용하는 op-selective zero/PRD를 본다.

## Stage 6a 중간 결론

`opmode_i && intt_i`일 때만 inactive KEM COMP2 cone을 zero로 묶으면 Stage 5의
`mldsa_ntt` 대악화는 사라졌다. `mldsa_ntt`와 `mlkem_pwm`은 control보다 좋아졌다.
하지만 핵심이던 `mldsa_intt` 개선은 크게 약해졌고, `mlkem_ntt`, `mlkem_intt`가
control보다 올라갔다.

| Operation | Stage 4b control | Stage 5 all-DSA zero | Stage 6a INTT-only zero | 판단 |
|---|---:|---:|---:|---|
| `mlkem_ntt` | 98.403 | 121.412 | 113.723 | 여전히 악화 |
| `mlkem_intt` | 44.048 | 53.754 | 55.402 | 악화 |
| `mlkem_pwm` | 104.827 | 113.692 | 93.055 | 개선 |
| `mldsa_ntt` | 85.319 | 116.949 | 82.762 | op-selective에서 회복/개선 |
| `mldsa_intt` | 122.083 | 103.804 | 118.254 | 개선 약화 |
| `mldsa_pwm` | 74.604 | 75.799 | 73.875 | 소폭 개선 |

다음은 Stage 6b로 같은 op-selective 조건에 public PRD dummy를 넣는다. 목표는 Stage 4의
PRD 안정성과 Stage 5의 INTT 개선 사이에서 더 좋은 균형점을 찾는 것이다.

## Stage 6b 중간 결론

Stage 6b op-selective PRD는 기능 검증은 통과했지만 30ns timing을 만족하지 못했다.

| 항목 | 결과 |
|---|---:|
| WNS | -0.805 ns |
| TNS | -20.641 ns |
| WHS | 0.057 ns |
| THS | 0.000 ns |
| LUT/FF/RAMB36/DSP | 9900 / 3344 / 8 / 0 |

따라서 TVLA는 실행하지 않았다. COMP2 단독 실험에서는 최종 accept 후보가 나오지 않았고,
다음은 이미 all-op 개선을 보인 COMP3 Stage 2 후보와 COMP2 trade-off 후보를 조합해 본다.

## Stage 6c 중간 결론

COMP3 Stage 2와 COMP2 Stage 4 PRD를 조합한 Stage 6c는 현재까지 worst를 가장 낮춘
candidate다. First seed와 repeat seed 모두에서 `mldsa_intt` peak가 약 100 근처로 낮아졌다.

| Operation | Stage 4b control | COMP3 Stage 2 | Stage 6c first | Stage 6c repeat |
|---|---:|---:|---:|---:|
| `mlkem_ntt` | 98.403 | 68.726 | 57.912 | 58.849 |
| `mlkem_intt` | 44.048 | 43.319 | 59.519 | 58.341 |
| `mlkem_pwm` | 104.827 | 96.004 | 94.381 | 96.317 |
| `mldsa_ntt` | 85.319 | 80.229 | 75.660 | 77.052 |
| `mldsa_intt` | 122.083 | 117.028 | 99.696 | 102.864 |
| `mldsa_pwm` | 74.604 | 71.047 | 72.538 | 75.171 |

판단은 best-so-far / candidate다. Worst는 가장 낮지만, `mlkem_intt`가 control보다 안정적으로
악화하므로 최종 accept 전에는 follow-up이 필요하다.

## Stage 6d 중간 결론

Stage 6c의 COMP2 Stage 4 PRD를 Stage 6a op-selective zero로 바꿔 조합했다. 목적은
Stage 6c에서 남은 `mlkem_intt` 악화를 줄이는 것이었다.

| Operation | Stage 4b control | Stage 6c first | Stage 6d | 판단 |
|---|---:|---:|---:|---|
| `mlkem_ntt` | 98.403 | 57.912 | 56.696 | 개선 유지 |
| `mlkem_intt` | 44.048 | 59.519 | 54.461 | Stage 6c보다 완화, control보다는 악화 |
| `mlkem_pwm` | 104.827 | 94.381 | 95.750 | 개선 유지 |
| `mldsa_ntt` | 85.319 | 75.660 | 79.649 | 개선 유지하나 Stage 6c보다 약함 |
| `mldsa_intt` | 122.083 | 99.696 | 108.582 | Stage 6c보다 악화 |
| `mldsa_pwm` | 74.604 | 72.538 | 73.378 | 거의 동일 |

결론은 reject / informative다. `mlkem_intt`는 약간 나아졌지만, 핵심 worst인
`mldsa_intt`가 다시 108대로 올라가 Stage 6c보다 나쁘다. repeat는 실행하지 않았다.

## Stage 6e 중간 결론

Stage 6e는 COMP3 Stage 2 위에 COMP2 Stage 5 all-DSA zero를 얹었다. 기능 검증은
통과했지만 30ns timing을 만족하지 못했다.

| 항목 | 결과 |
|---|---:|
| WNS | -0.436 ns |
| TNS | -7.474 ns |
| WHS | 0.081 ns |
| THS | 0.000 ns |
| LUT/FF/RAMB36/DSP | 10126 / 3351 / 8 / 0 |

따라서 TVLA는 실행하지 않았다. all-DSA zero는 Stage 5 단독 결과에서도 TVLA trade-off가
컸고, COMP3 Stage 2와 조합하면 timing까지 깨진다.

## 현재 best-so-far

현재까지의 best-so-far는 Stage 6c다. Stage 4b control 대비 six-op worst를
`122.083 -> 99.696`, repeat에서 `102.864`까지 낮췄다. 하지만 `mlkem_intt` 악화가
남아 final accepted RTL보다는 candidate로 둔다.

## 공통 실행 명령

```bash
python3 scripts/diagnostics/check_phoenix_consistency.py
python3 scripts/diagnostics/check_bank_conflicts.py
bash sim/run_verilator.sh 'tb_comp1_comp2_comp4 tb_superbutterfly_all_modes tb_phoenix_core tb_phoenix_host_io tb_phoenix_cw305_wrapper tb_phoenix_mldsa_pwm_io'
```

```bash
OUTDIR=reports/tvla/<comp2_internal_stage_name> \
OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' \
TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0x5EED \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```
