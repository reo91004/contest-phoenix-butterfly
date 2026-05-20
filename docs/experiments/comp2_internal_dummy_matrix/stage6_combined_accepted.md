# Stage 6: Op-Selective / Combined COMP2 Internal Dummy

## 목적

Stage 2-5에서 단독 accept 후보는 나오지 않았다. 다만 Stage 5의
`mldsa_intt 122.083 -> 103.804` 개선은 매우 강했다. 문제는 Stage 5가 모든 ML-DSA
cycle에서 inactive KEM COMP2 cone을 zero로 묶어 `mldsa_ntt`와 ML-KEM까지 악화했다는
점이다.

따라서 Stage 6은 단순 조합이 아니라 먼저 op-selective 추출을 수행한다.

- Stage 6a: `opmode_i && intt_i`일 때만 inactive KEM COMP2 cone zero.
- Stage 6b: `opmode_i && intt_i`일 때만 inactive KEM COMP2 cone public PRD.
- 이후 두 후보 중 Stage 4b control보다 명확히 좋은 것만 combination 후보로 본다.

## Stage 6a: ML-DSA INTT KEM Cone Zero

### 구현 원칙

- 기준은 Stage 4b restored RTL이다.
- `comp2_agile_modarith_div2.v`에서 KEM two-lane input만 조건부 zero 처리했다.
- 조건은 `opmode_i && intt_i`다.
  - ML-DSA INTT pre-sub/div2 path에서는 inactive KEM cone이 `0`을 받는다.
  - ML-DSA NTT/PWM에서는 `intt_i=0`이므로 Stage 4b와 동일하다.
  - ML-KEM mode에서는 `opmode_i=0`이므로 Stage 4b와 동일하다.
- output mux, scheduler, latency, memory layout은 변경하지 않았다.

## 실행 기록

| 항목 | 결과 |
|---|---|
| RTL patch | `reports/tvla/comp2_internal_stage6a_mldsa_intt_kem_cone_zero_260521/rtl_stage6a_mldsa_intt_kem_cone_zero.patch` |
| bitstream mtime | `2026-05-21 05:39:28 KST` |
| WNS/TNS | `0.195 ns / 0.000 ns` |
| WHS/THS | `0.068 ns / 0.000 ns` |
| LUT/FF/RAMB36/DSP | `9843 / 3285 / 8 / 0` |
| diagnostics | `check_phoenix_consistency.py` PASS, `check_bank_conflicts.py` PASS |
| Verilator | `tb_comp1_comp2_comp4`, `tb_superbutterfly_all_modes`, `tb_phoenix_core`, `tb_phoenix_host_io`, `tb_phoenix_cw305_wrapper`, `tb_phoenix_mldsa_pwm_io` PASS |
| TVLA OUTDIR | `reports/tvla/comp2_internal_stage6a_mldsa_intt_kem_cone_zero_260521` |
| TVLA command | `OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0x5EED` |

## TVLA 결과

비교 기준은 `reports/tvla/inactive_dummy_stage1_stage4b_control_260521`이다.

| Operation | Stage 4b control | Stage 6a op-selective zero | peak index | cycles | clipping | 판단 |
|---|---:|---:|---:|---:|---:|---|
| `mlkem_ntt` | 98.403 | 113.723 | 116 | 248 | 0 | 악화 |
| `mlkem_intt` | 44.048 | 55.402 | 116 | 248 | 0 | 악화 |
| `mlkem_pwm` | 104.827 | 93.055 | 63 | 149 | 0 | 개선 |
| `mldsa_ntt` | 85.319 | 82.762 | 506 | 538 | 0 | 개선 |
| `mldsa_intt` | 122.083 | 118.254 | 123 | 538 | 0 | 소폭 개선 |
| `mldsa_pwm` | 74.604 | 73.875 | 113 | 140 | 0 | 거의 동일/소폭 개선 |

![Stage 6a vs Stage 4b control](../../../reports/tvla/comp2_internal_stage6a_mldsa_intt_kem_cone_zero_260521/overview_vs_stage4b_control.png)

추가 비교 artifact:

- `reports/tvla/comp2_internal_stage6a_mldsa_intt_kem_cone_zero_260521/compare_vs_stage4b_control.csv`
- `reports/tvla/comp2_internal_stage6a_mldsa_intt_kem_cone_zero_260521/compare_vs_stage5_all_dsa_zero.csv`
- `reports/tvla/comp2_internal_stage6a_mldsa_intt_kem_cone_zero_260521/compare_vs_stage4_prd.csv`

## 판단

Stage 6a는 reject / informative다.

Op-selective로 좁히자 Stage 5의 `mldsa_ntt` 대악화는 사라졌고, 오히려
`85.319 -> 82.762`로 약간 좋아졌다. `mlkem_pwm`도 `104.827 -> 93.055`로 개선됐다.
하지만 기대했던 `mldsa_intt` 개선은 Stage 5의 `103.804`에서 `118.254`로 거의 사라졌다.
또한 `mlkem_ntt`, `mlkem_intt`가 control보다 올라갔다.

따라서 “ML-KEM, ML-DSA 모두 유의미하게 감소” 조건에는 맞지 않는다. 다만 Stage 5의
악화 원인이 모든 ML-DSA cycle에 blanking을 걸었던 것이라는 점은 확인했다. 다음 Stage
6b에서는 같은 op-selective 조건으로 zero가 아니라 public PRD dummy를 넣어본다.

## Stage 6b: ML-DSA INTT KEM Cone PRD

### 구현 원칙

- 기준은 Stage 4b restored RTL이다.
- Stage 6a와 같은 `opmode_i && intt_i` 조건을 사용한다.
- inactive KEM COMP2 cone의 low/high lane에 public PRD `dummy_a_i/dummy_b_i`를 넣는다.
- active DSA COMP2 output path는 real operand를 유지한다.
- `superbutterfly_sbu_routed.v`에 COMP2 dummy용 32-bit LFSR을 추가했다.

### 실행 기록

| 항목 | 결과 |
|---|---|
| RTL patch | `reports/tvla/comp2_internal_stage6b_mldsa_intt_kem_cone_prd_260521/rtl_stage6b_mldsa_intt_kem_cone_prd.patch` |
| bitstream mtime | `2026-05-21 05:50:15 KST` |
| WNS/TNS | `-0.805 ns / -20.641 ns` |
| WHS/THS | `0.057 ns / 0.000 ns` |
| LUT/FF/RAMB36/DSP | `9900 / 3344 / 8 / 0` |
| diagnostics | `check_phoenix_consistency.py` PASS, `check_bank_conflicts.py` PASS |
| Verilator | `tb_comp1_comp2_comp4`, `tb_superbutterfly_all_modes`, `tb_phoenix_core`, `tb_phoenix_host_io`, `tb_phoenix_cw305_wrapper`, `tb_phoenix_mldsa_pwm_io` PASS |
| TVLA | timing fail 때문에 미실행 |

### 판단

Timing reject.

Stage 6b는 기능적으로는 clean이지만, 30ns timing을 만족하지 못했다. 따라서 Stage 4b
control과 정합 비교 가능한 CW305 TVLA는 수행하지 않았다. PRD LFSR, dummy mux, 그리고
`opmode_i && intt_i` 조건이 COMP2 주변 timing path를 너무 무겁게 만든 것으로 본다.

Stage 6b는 결과가 없어서 combination 후보에 넣지 않는다. COMP2 단독 실험군에서
현재까지 의미 있는 관찰은 다음과 같다.

- 가장 큰 `mldsa_intt` 감소: Stage 5 all-DSA KEM cone zero, 하지만 ML-KEM/NTT 악화.
- 가장 균형 있는 COMP2 단독 trade-off: Stage 4 KEM cone PRD, 하지만 `mldsa_ntt`와
  ML-KEM NTT/PWM 소폭 악화.
- op-selective zero는 NTT 악화를 줄였지만 `mldsa_intt` 개선을 거의 잃었다.

따라서 COMP2 단독으로는 아직 final candidate가 없다. 다음 방향은 이미 all-op 개선을 보인
COMP3 Stage 2 후보 위에 COMP2 Stage 4 또는 Stage 6a를 조합해, COMP3의 ML-KEM 개선
여유가 COMP2 trade-off를 흡수할 수 있는지 확인하는 것이다.

## Stage 6c: COMP3 Stage 2 + COMP2 Stage 4 PRD

### 목적

COMP3 internal Stage 2는 Stage 4b control 대비 six-op을 모두 낮춘 가장 균형 좋은 후보였다.
COMP2 Stage 4는 단독으로는 `mlkem_ntt`, `mlkem_pwm`, `mldsa_ntt`를 조금 악화했지만,
`mldsa_intt`와 `mldsa_pwm`을 낮췄다.

Stage 6c는 이 둘을 조합해서, COMP3 Stage 2의 ML-KEM 개선 여유가 COMP2 Stage 4의
trade-off를 흡수하면서 `mldsa_intt`를 더 낮출 수 있는지 확인한다.

### 구현 요약

- COMP3:
  - ML-KEM mode에서 inactive DSA Karatsuba 입력에 public PRD dummy를 넣는다.
  - DSA reducer 입력은 inactive ML-KEM mode에서 `0`으로 둔다.
  - active KEM/DSA output path에는 dummy를 섞지 않는다.
- COMP2:
  - ML-DSA mode에서 inactive KEM COMP2 low/high lane에 public PRD dummy를 넣는다.
  - active DSA COMP2 output path에는 dummy를 섞지 않는다.
- output mux, scheduler, latency, memory layout은 변경하지 않았다.

### 실행 기록

| 항목 | 결과 |
|---|---|
| RTL patch | `reports/tvla/combined_comp3s2_comp2s4_prd_260521/rtl_combined_comp3s2_comp2s4_prd.patch` |
| bitstream mtime | `2026-05-21 05:55:23 KST` |
| WNS/TNS | `0.139 ns / 0.000 ns` |
| WHS/THS | `0.096 ns / 0.000 ns` |
| LUT/FF/RAMB36/DSP | `10194 / 3424 / 8 / 0` |
| diagnostics | `check_phoenix_consistency.py` PASS, `check_bank_conflicts.py` PASS |
| Verilator | `tb_comp1_comp2_comp4`, `tb_comp3_agile_modmul`, `tb_superbutterfly_all_modes`, `tb_phoenix_core`, `tb_phoenix_host_io`, `tb_phoenix_cw305_wrapper`, `tb_phoenix_mldsa_pwm_io` PASS |
| TVLA OUTDIR | `reports/tvla/combined_comp3s2_comp2s4_prd_260521` |
| repeat OUTDIR | `reports/tvla/combined_comp3s2_comp2s4_prd_repeat_0xC0DEC_260521` |

### TVLA 결과

비교 기준은 `reports/tvla/inactive_dummy_stage1_stage4b_control_260521`이다.

| Operation | Stage 4b control | COMP3 Stage 2 | Stage 6c first | Stage 6c repeat | 판단 |
|---|---:|---:|---:|---:|---|
| `mlkem_ntt` | 98.403 | 68.726 | 57.912 | 58.849 | 큰 개선, 재현 |
| `mlkem_intt` | 44.048 | 43.319 | 59.519 | 58.341 | 악화, 재현 |
| `mlkem_pwm` | 104.827 | 96.004 | 94.381 | 96.317 | 개선, 재현 |
| `mldsa_ntt` | 85.319 | 80.229 | 75.660 | 77.052 | 개선, 재현 |
| `mldsa_intt` | 122.083 | 117.028 | 99.696 | 102.864 | 큰 개선, 재현 |
| `mldsa_pwm` | 74.604 | 71.047 | 72.538 | 75.171 | first 개선, repeat는 control과 유사/소폭 악화 |

Stage 6c TVLA overview:

![Stage 6c TVLA overview](../../../reports/tvla/combined_comp3s2_comp2s4_prd_260521/mlkem_mldsa_tvla_overview.png)

Stage 6c 개별 operation t-value:

| ML-KEM NTT | ML-KEM INTT | ML-KEM PWM |
|---|---|---|
| ![Stage 6c ML-KEM NTT t-values](../../../reports/tvla/combined_comp3s2_comp2s4_prd_260521/phoenix_mlkem_ntt_full_1000_db10_tvalues.png) | ![Stage 6c ML-KEM INTT t-values](../../../reports/tvla/combined_comp3s2_comp2s4_prd_260521/phoenix_mlkem_intt_full_1000_db10_tvalues.png) | ![Stage 6c ML-KEM PWM t-values](../../../reports/tvla/combined_comp3s2_comp2s4_prd_260521/phoenix_mlkem_pwm_full_1000_db10_tvalues.png) |

| ML-DSA NTT | ML-DSA INTT | ML-DSA PWM |
|---|---|---|
| ![Stage 6c ML-DSA NTT t-values](../../../reports/tvla/combined_comp3s2_comp2s4_prd_260521/phoenix_mldsa_ntt_full_1000_db10_tvalues.png) | ![Stage 6c ML-DSA INTT t-values](../../../reports/tvla/combined_comp3s2_comp2s4_prd_260521/phoenix_mldsa_intt_full_1000_db10_tvalues.png) | ![Stage 6c ML-DSA PWM t-values](../../../reports/tvla/combined_comp3s2_comp2s4_prd_260521/phoenix_mldsa_pwm_full_1000_db10_tvalues.png) |

Stage 6c 비교 그래프:

![Stage 6c vs Stage 4b control](../../../reports/tvla/combined_comp3s2_comp2s4_prd_260521/comparison_vs_stage4b_control.png)

![Stage 6c vs original baseline](../../../reports/tvla/combined_comp3s2_comp2s4_prd_260521/comparison_vs_original_baseline.png)

![Stage 6c vs COMP3 Stage 2](../../../reports/tvla/combined_comp3s2_comp2s4_prd_260521/comparison_vs_comp3_stage2_best.png)

![Stage 6c vs COMP2 Stage 4](../../../reports/tvla/combined_comp3s2_comp2s4_prd_260521/comparison_vs_comp2_stage4.png)

Repeat 비교:

![Stage 6c repeat overview](../../../reports/tvla/combined_comp3s2_comp2s4_prd_repeat_0xC0DEC_260521/mlkem_mldsa_tvla_overview.png)

![Stage 6c repeat vs first seed](../../../reports/tvla/combined_comp3s2_comp2s4_prd_repeat_0xC0DEC_260521/comparison_vs_first_seed.png)

![Stage 6c repeat vs Stage 4b control](../../../reports/tvla/combined_comp3s2_comp2s4_prd_repeat_0xC0DEC_260521/comparison_vs_stage4b_control.png)

추가 artifact:

- `reports/tvla/combined_comp3s2_comp2s4_prd_260521/comparison_vs_stage4b_control.csv`
- `reports/tvla/combined_comp3s2_comp2s4_prd_260521/comparison_vs_original_baseline.csv`
- `reports/tvla/combined_comp3s2_comp2s4_prd_260521/comparison_vs_comp3_stage2_best.csv`
- `reports/tvla/combined_comp3s2_comp2s4_prd_260521/comparison_vs_comp2_stage4.csv`
- `reports/tvla/combined_comp3s2_comp2s4_prd_repeat_0xC0DEC_260521/comparison_vs_stage4b_control.csv`
- `reports/tvla/combined_comp3s2_comp2s4_prd_repeat_0xC0DEC_260521/comparison_vs_first_seed.csv`

### 판단

Stage 6c는 현재까지 worst를 가장 낮춘 candidate다.

- Stage 4b control worst: `mldsa_intt 122.083`
- COMP3 Stage 2 worst: `mldsa_intt 117.028`
- Stage 6c first worst: `mldsa_intt 99.696`
- Stage 6c repeat worst: `mldsa_intt 102.864`

즉 worst 기준으로는 현재까지 가장 좋고, 핵심이던 `mldsa_intt` peak 123 감소도 repeat에서
재현됐다. 다만 완전 accepted RTL이라고 부르기에는 아직 문제가 있다. `mlkem_intt`가
control의 44.048에서 약 58-60으로 안정적으로 악화했고, `mldsa_pwm`도 repeat에서
control보다 약간 높아졌다.

따라서 Stage 6c는 "best-so-far / candidate"로 두되, 최종 accept 전에는 다음 follow-up을
봐야 한다.

- COMP2 Stage 4 PRD가 `mlkem_intt`를 올리는지, COMP3와의 조합 placement가 올리는지 분리.
- COMP2 dummy LFSR seed/placement를 바꿔 `mlkem_intt` 악화를 완화할 수 있는지 확인.
- 또는 COMP2 Stage 4 대신 Stage 6a zero를 COMP3 Stage 2와 조합해 ML-KEM INTT 악화가
  줄어드는지 확인.

## Stage 6d: COMP3 Stage 2 + COMP2 Stage 6a Zero

### 목적

Stage 6c의 가장 큰 약점은 `mlkem_intt`가 Stage 4b control `44.048`에서
`59.519 / 58.341`로 안정적으로 악화한다는 점이다. Stage 6d는 COMP2 쪽을 public
PRD가 아니라 Stage 6a의 op-selective zero로 바꾸면 이 악화가 줄어드는지 확인했다.

### 구현 요약

- COMP3는 Stage 6c와 동일하다.
  - ML-KEM mode에서 inactive DSA Karatsuba 입력에 public PRD dummy를 넣는다.
  - inactive DSA reducer 입력은 `0`으로 둔다.
- COMP2는 Stage 4 PRD 대신 Stage 6a zero를 사용한다.
  - 조건은 `opmode_i && intt_i`다.
  - ML-DSA INTT에서 inactive KEM COMP2 cone만 `0`을 받는다.
- active output path, scheduler, latency, memory layout은 변경하지 않았다.

### 실행 기록

| 항목 | 결과 |
|---|---|
| RTL patch | `reports/tvla/combined_comp3s2_comp2s6a_zero_260521/rtl_combined_comp3s2_comp2s6a_zero.patch` |
| bitstream mtime | `2026-05-21 06:15:18 KST` |
| WNS/TNS | `0.114 ns / 0.000 ns` |
| WHS/THS | `0.083 ns / 0.000 ns` |
| LUT/FF/RAMB36/DSP | `10096 / 3356 / 8 / 0` |
| diagnostics | `check_phoenix_consistency.py` PASS, `check_bank_conflicts.py` PASS |
| Verilator | `tb_comp1_comp2_comp4`, `tb_comp3_agile_modmul`, `tb_superbutterfly_all_modes`, `tb_phoenix_core`, `tb_phoenix_host_io`, `tb_phoenix_cw305_wrapper`, `tb_phoenix_mldsa_pwm_io` PASS |
| TVLA OUTDIR | `reports/tvla/combined_comp3s2_comp2s6a_zero_260521` |

### TVLA 결과

| Operation | Stage 4b control | Stage 6c first | Stage 6d | peak index | cycles | clipping |
|---|---:|---:|---:|---:|---:|---:|
| `mlkem_ntt` | 98.403 | 57.912 | 56.696 | 114 | 248 | 0 |
| `mlkem_intt` | 44.048 | 59.519 | 54.461 | 149 | 248 | 0 |
| `mlkem_pwm` | 104.827 | 94.381 | 95.750 | 56 | 149 | 0 |
| `mldsa_ntt` | 85.319 | 75.660 | 79.649 | 151 | 538 | 0 |
| `mldsa_intt` | 122.083 | 99.696 | 108.582 | 123 | 538 | 0 |
| `mldsa_pwm` | 74.604 | 72.538 | 73.378 | 106 | 140 | 0 |

![Stage 6d vs Stage 4b control](../../../reports/tvla/combined_comp3s2_comp2s6a_zero_260521/compare_vs_stage4b_control.png)

추가 artifact:

- `reports/tvla/combined_comp3s2_comp2s6a_zero_260521/compare_vs_stage4b_control.csv`
- `reports/tvla/combined_comp3s2_comp2s6a_zero_260521/compare_vs_stage6c_comp3s2_comp2s4.csv`
- `reports/tvla/combined_comp3s2_comp2s6a_zero_260521/compare_vs_comp3_stage2_best.csv`

### 판단

Stage 6d는 rejected / informative다.

Stage 6c 대비 `mlkem_intt`는 `59.519 -> 54.461`로 조금 낮아졌다. 하지만 핵심 worst인
`mldsa_intt`가 `99.696 -> 108.582`로 다시 올라갔다. Stage 4b control보다는 여전히
좋지만, 현재 best-so-far인 Stage 6c보다 six-op worst가 나쁘다. 따라서 repeat seed는
실행하지 않았다.

해석은 명확하다. COMP2 op-selective zero는 ML-KEM INTT 악화를 일부 줄일 수 있지만,
Stage 6c에서 얻었던 `mldsa_intt` peak 123 감소를 상당 부분 잃는다. 따라서 Stage 6c의
COMP2 Stage 4 PRD가 아직 더 나은 균형점이다.

## Stage 6e: COMP3 Stage 2 + COMP2 Stage 5 All-DSA Zero

### 목적

Stage 5 단독 실험은 `mldsa_intt`를 `122.083 -> 103.804`로 크게 낮췄지만,
`mldsa_ntt`와 ML-KEM 쪽을 악화했다. Stage 6e는 COMP3 Stage 2의 ML-KEM 개선 여유와
조합하면 all-DSA zero의 악화를 흡수할 수 있는지 확인하려 했다.

### 구현 요약

- COMP3는 Stage 6c/6d와 동일하다.
- COMP2는 ML-DSA mode 전체에서 inactive KEM COMP2 cone을 `0`으로 묶었다.
  - 조건은 `opmode_i`다.
  - Stage 6d의 `opmode_i && intt_i`보다 더 넓다.
- active DSA COMP2 output path에는 dummy를 섞지 않는다.

### 실행 기록

| 항목 | 결과 |
|---|---|
| RTL patch | `reports/tvla/combined_comp3s2_comp2s5_zero_260521/rtl_combined_comp3s2_comp2s5_zero.patch` |
| WNS/TNS | `-0.436 ns / -7.474 ns` |
| WHS/THS | `0.081 ns / 0.000 ns` |
| LUT/FF/RAMB36/DSP | `10126 / 3351 / 8 / 0` |
| diagnostics | `check_phoenix_consistency.py` PASS, `check_bank_conflicts.py` PASS |
| Verilator | `tb_comp1_comp2_comp4`, `tb_comp3_agile_modmul`, `tb_superbutterfly_all_modes`, `tb_phoenix_core`, `tb_phoenix_host_io`, `tb_phoenix_cw305_wrapper`, `tb_phoenix_mldsa_pwm_io` PASS |
| TVLA | 30ns timing fail 때문에 미실행 |

### 판단

Stage 6e는 timing reject다.

기능적으로는 clean하지만 30ns constraint에서 setup timing을 만족하지 못했다. 따라서
fixed-vs-random TVLA는 실행하지 않았다. all-DSA zero는 Stage 5 단독에서도 TVLA trade-off가
컸고, COMP3 Stage 2와 조합했을 때는 timing까지 깨진다. 현재 흐름에서 final candidate로
볼 이유가 없다.

## Stage 6 현재 결론

Stage 6c가 여전히 best-so-far다.

| 후보 | 핵심 변경 | 판단 |
|---|---|---|
| Stage 6c | COMP3 Stage 2 PRD + COMP2 Stage 4 PRD | best-so-far / candidate |
| Stage 6d | COMP3 Stage 2 PRD + COMP2 Stage 6a zero | Stage 6c보다 `mldsa_intt` 악화, reject |
| Stage 6e | COMP3 Stage 2 PRD + COMP2 Stage 5 all-DSA zero | timing reject |

따라서 “ML-KEM, ML-DSA 모두 유의미하게 감소”라는 기준에서 현재 가장 좋은 후보는
Stage 6c다. 다만 Stage 6c도 TVLA pass가 아니며, `mlkem_intt` 악화가 남는다. 다음 후보는
COMP1/COMP4를 얹는 것보다 Stage 6c의 COMP2 PRD selector/LFSR placement를 더 보수적으로
다듬는 방향이 낫다. COMP1/COMP4 단독 실험은 이미 Stage 4b control 대비 worst를 낮추지
못했고, 특히 COMP4는 `mldsa_intt` peak 123에 거의 영향이 없었다.
