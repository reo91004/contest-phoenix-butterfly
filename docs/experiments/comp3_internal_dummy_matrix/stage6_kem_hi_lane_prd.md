# Stage 6: KEM Hi-Lane PRD In ML-DSA Mode

## 목적

ML-DSA mode에서 inactive KEM hi lane만 public PRD로 흔들어 lo lane과 비교한다.

## 구현 원칙

- ML-DSA mode:
  - DSA active output path는 real operand 유지.
  - inactive KEM hi multiplier/reducer lane만 public PRD.
  - inactive KEM lo lane은 Stage 4b와 동일하게 둔다.
- ML-KEM mode:
  - KEM active path는 real operand 유지.
- output mux는 변경하지 않는다.

## 실행 기록

| 항목 | 결과 |
|---|---|
| RTL patch | `reports/tvla/comp3_internal_stage6_kem_hi_lane_prd_260521/rtl_stage6_kem_hi_lane_prd.patch` |
| bitstream mtime | `2026-05-21 04:12:08 KST` |
| WNS/TNS | `0.279 ns / 0.000 ns` |
| WHS/THS | `0.083 ns / 0.000 ns` |
| LUT/FF/RAMB36/DSP | `9722 / 3351 / 8 / 0` |
| diagnostics | `check_phoenix_consistency.py` PASS, `check_bank_conflicts.py` PASS |
| Verilator | `tb_comp3_agile_modmul`, `tb_superbutterfly_all_modes`, `tb_phoenix_core`, `tb_phoenix_host_io`, `tb_phoenix_cw305_wrapper`, `tb_phoenix_mldsa_pwm_io` PASS |
| TVLA OUTDIR | `reports/tvla/comp3_internal_stage6_kem_hi_lane_prd_260521` |
| TVLA command | `OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0x5EED` |

## TVLA 결과

비교 기준은 `reports/tvla/inactive_dummy_stage1_stage4b_control_260521`이다.

| Operation | Stage 4b control | Stage 6 KEM hi-lane PRD | peak index | cycles | clipping | 판단 |
|---|---:|---:|---:|---:|---:|---|
| `mlkem_ntt` | 98.403 | 69.258 | 158 | 248 | 0 | 개선 |
| `mlkem_intt` | 44.048 | 48.601 | 169 | 248 | 0 | 악화 |
| `mlkem_pwm` | 104.827 | 106.615 | 63 | 149 | 0 | 거의 동일/악화 |
| `mldsa_ntt` | 85.319 | 106.009 | 506 | 538 | 0 | 악화 |
| `mldsa_intt` | 122.083 | 132.490 | 123 | 538 | 0 | 악화 |
| `mldsa_pwm` | 74.604 | 88.216 | 105 | 140 | 0 | 악화 |

![Stage 6 vs Stage 4b control](../../../reports/tvla/comp3_internal_stage6_kem_hi_lane_prd_260521/overview_vs_inactive_stage1_control.png)

추가 비교 artifact:

- `reports/tvla/comp3_internal_stage6_kem_hi_lane_prd_260521/compare_vs_inactive_stage1_control.csv`
- `reports/tvla/comp3_internal_stage6_kem_hi_lane_prd_260521/compare_vs_stage4b_control.csv`
- `reports/tvla/comp3_internal_stage6_kem_hi_lane_prd_260521/compare_vs_stage5_kem_lo_lane_prd.csv`

## 판단

Reject.

Stage 5의 lo-lane PRD처럼 ML-KEM 전체가 무너지는 패턴은 아니지만, ML-DSA 세
operation이 모두 악화했다. 특히 핵심 worst인 `mldsa_intt` peak 123이
`122.083 -> 132.490`으로 커졌고, `mldsa_ntt`도 peak 506 위치에서
`85.319 -> 106.009`로 커졌다.

따라서 inactive KEM hi lane에 dummy switching을 넣는 것은 ML-DSA leakage를
낮추는 방향이 아니다. lo/high lane 둘 다 ML-DSA mode에서 active-window peak를
키웠으므로, 다음 실험은 multiplier lane이 아니라 inactive KEM Barrett reducer
입력만 분리해서 확인한다.
