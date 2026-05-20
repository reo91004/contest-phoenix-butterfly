# Stage 1: Stage 4b Control

## 목적

COMP2 internal dummy matrix의 control은 이미 측정한 Stage 4b restored RTL 결과를
재사용한다.

## 기준 artifact

- TVLA OUTDIR: `reports/tvla/inactive_dummy_stage1_stage4b_control_260521`
- bitstream: `reports/tvla/inactive_dummy_stage1_stage4b_control_260521/phoenix_stage4b_control.bit`

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

이 matrix의 baseline/control로 사용한다.
