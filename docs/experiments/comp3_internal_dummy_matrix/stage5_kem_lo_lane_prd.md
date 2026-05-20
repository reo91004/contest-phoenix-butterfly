# Stage 5: KEM Lo-Lane PRD In ML-DSA Mode

## 목적

ML-DSA mode에서 inactive KEM cone이 ML-DSA TVLA 악화에 어떤 영향을 주는지 lo lane부터
분해한다.

## 구현 원칙

- ML-DSA mode:
  - DSA active output path는 real operand 유지.
  - inactive KEM lo multiplier/reducer lane만 public PRD.
  - inactive KEM hi lane은 Stage 4b와 동일하게 둔다.
- ML-KEM mode:
  - KEM active path는 real operand 유지.
- output mux는 변경하지 않는다.

## 실행 기록

| 항목 | 결과 |
|---|---|
| RTL patch | `reports/tvla/comp3_internal_stage5_kem_lo_lane_prd_260521/rtl_stage5_kem_lo_lane_prd.patch` |
| bitstream mtime | `2026-05-21 04:01:17 KST` |
| WNS/TNS | `0.069 ns / 0.000 ns` |
| WHS/THS | `0.066 ns / 0.000 ns` |
| LUT/FF/RAMB36/DSP | `9913 / 3342 / 8 / 0` |
| diagnostics | `check_phoenix_consistency.py` PASS, `check_bank_conflicts.py` PASS |
| Verilator | `tb_comp3_agile_modmul`, `tb_superbutterfly_all_modes`, `tb_phoenix_core`, `tb_phoenix_host_io`, `tb_phoenix_cw305_wrapper`, `tb_phoenix_mldsa_pwm_io` PASS |
| TVLA OUTDIR | `reports/tvla/comp3_internal_stage5_kem_lo_lane_prd_260521` |
| TVLA command | `OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0x5EED` |

## TVLA 결과

비교 기준은 `reports/tvla/inactive_dummy_stage1_stage4b_control_260521`이다.

| Operation | Stage 4b control | Stage 5 KEM lo-lane PRD | peak index | cycles | clipping | 판단 |
|---|---:|---:|---:|---:|---:|---|
| `mlkem_ntt` | 98.403 | 114.410 | 124 | 248 | 0 | 악화 |
| `mlkem_intt` | 44.048 | 51.082 | 100 | 248 | 0 | 악화 |
| `mlkem_pwm` | 104.827 | 115.727 | 63 | 149 | 0 | 악화 |
| `mldsa_ntt` | 85.319 | 74.872 | 63 | 538 | 0 | 개선 |
| `mldsa_intt` | 122.083 | 136.095 | 123 | 538 | 0 | 악화 |
| `mldsa_pwm` | 74.604 | 91.089 | 106 | 140 | 0 | 악화 |

![Stage 5 vs Stage 4b control](../../../reports/tvla/comp3_internal_stage5_kem_lo_lane_prd_260521/overview_vs_inactive_stage1_control.png)

추가 비교 artifact:

- `reports/tvla/comp3_internal_stage5_kem_lo_lane_prd_260521/compare_vs_inactive_stage1_control.csv`
- `reports/tvla/comp3_internal_stage5_kem_lo_lane_prd_260521/compare_vs_stage4b_control.csv`
- `reports/tvla/comp3_internal_stage5_kem_lo_lane_prd_260521/compare_vs_original_baseline.csv`
- `reports/tvla/comp3_internal_stage5_kem_lo_lane_prd_260521/compare_vs_stage2_dsa_mul_only_prd.csv`

## 판단

Reject.

이 실험은 ML-DSA mode에서 inactive KEM lo lane만 public PRD로 흔드는 것이므로,
직접적인 기대 효과는 ML-DSA operation 쪽이었다. 실제로 `mldsa_ntt`는 낮아졌지만,
가장 중요한 worst인 `mldsa_intt` peak 123이 `122.083 -> 136.095`로 커졌다.
또한 ML-KEM active datapath는 논리적으로 바꾸지 않았는데도 `mlkem_ntt`,
`mlkem_pwm`이 크게 악화했다.

따라서 이 결과는 KEM lo-lane dummy가 안정적인 개선 기법이라는 근거가 아니라,
inactive multiplier lane의 PRD switching이 placement/routing 및 주변 active-window
leakage shape를 크게 바꿀 수 있다는 근거로 보존한다. 다음 실험은 같은 기준에서
KEM hi lane을 분리해 lo lane과 같은 현상이 반복되는지 확인한다.
