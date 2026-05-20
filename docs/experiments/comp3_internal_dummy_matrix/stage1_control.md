# Stage 1: Stage 4b Control

## 목적

새 COMP3 internal dummy matrix의 기준점을 고정한다. 새 TVLA를 다시 찍지 않고,
직전 `inactive_dummy_matrix`에서 복구 후 측정한 Stage 4b control을 재사용한다.

## 기준 artifact

- OUTDIR: `../../../reports/tvla/inactive_dummy_stage1_stage4b_control_260521`
- bitstream: `../../../reports/tvla/inactive_dummy_stage1_stage4b_control_260521/phoenix_stage4b_control.bit`
- timing: WNS/TNS `0.203 ns / 0.000 ns`, WHS/THS `0.063 ns / 0.000 ns`
- utilization: LUT/FF/RAMB36/DSP `9727 / 3268 / 8 / 0`

## TVLA 결과

| Operation | max `|t|` | peak index | cycles | clipping |
|---|---:|---:|---:|---:|
| `mlkem_ntt` | 98.403 | 116 | 248 | 0 |
| `mlkem_intt` | 44.048 | 116 | 248 | 0 |
| `mlkem_pwm` | 104.827 | 63 | 149 | 0 |
| `mldsa_ntt` | 85.319 | 506 | 538 | 0 |
| `mldsa_intt` | 122.083 | 123 | 538 | 0 |
| `mldsa_pwm` | 74.604 | 109 | 140 | 0 |

![Stage 4b control TVLA overview](../../../reports/tvla/inactive_dummy_stage1_stage4b_control_260521/mlkem_mldsa_tvla_overview.png)

## 판단

이 값을 모든 COMP3 internal dummy stage의 기준으로 사용한다.
