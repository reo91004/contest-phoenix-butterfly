# Stage 1: Stage 4b Control

## 목적

Solinas Stage 7 변경분을 제거하고 Stage 4b restored RTL을 다시 기준점으로 고정한다.
이 control은 이후 inactive dummy matrix의 모든 비교 기준이다.

## 구현 상태

- 기준 RTL: Stage 4b restored RTL.
- Solinas reducer, normal-domain zeta, Stage 7 golden/test 변경은 제거.
- `docs/experiments/stage7_solinas/`는 삭제.
- Stage 7 raw TVLA artifact는 `reports/tvla/stage7_solinas_stage4b_260521/`에
  보존.

## 실행 기록

- diagnostics:
  - `check_phoenix_consistency.py`: PASS
  - `check_bank_conflicts.py`: PASS
- Verilator:
  - `tb_comp3_agile_modmul`: PASS
  - `tb_superbutterfly_all_modes`: PASS
  - `tb_phoenix_core`: PASS
  - `tb_phoenix_host_io`: PASS
  - `tb_phoenix_cw305_wrapper`: PASS
  - `tb_phoenix_mldsa_pwm_io`: PASS, `cycles=140`
- CW305 30ns build:
  - bitstream mtime: `2026-05-21 02:31:11 KST`
  - WNS `0.203 ns`, TNS `0.000 ns`
  - WHS `0.063 ns`, THS `0.000 ns`
  - LUT `9727`, FF `3268`, RAMB36 `8`, DSP `0`
- 보존 artifact:
  - `reports/tvla/inactive_dummy_stage1_stage4b_control_260521/phoenix_stage4b_control.bit`
  - `reports/tvla/inactive_dummy_stage1_stage4b_control_260521/phoenix_stage4b_control_timing.rpt`
  - `reports/tvla/inactive_dummy_stage1_stage4b_control_260521/phoenix_stage4b_control_impl_util.rpt`

TVLA command:

```bash
OUTDIR=reports/tvla/inactive_dummy_stage1_stage4b_control_260521 \
OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' \
TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0x5EED \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```

## TVLA 결과

![Stage 1 control TVLA overview](../../../reports/tvla/inactive_dummy_stage1_stage4b_control_260521/mlkem_mldsa_tvla_overview.png)

Stage 1 vs previous Stage 4b control repeat:

![Stage 1 vs previous Stage 4b control](../../../reports/tvla/inactive_dummy_stage1_stage4b_control_260521/comparison_vs_stage4b_control_repeat.png)

| Operation | Stage 1 control max `|t|` | peak index | cycles | clipping |
|---|---:|---:|---:|---:|
| `mlkem_ntt` | 98.403 | 116 | 248 | 0 |
| `mlkem_intt` | 44.048 | 116 | 248 | 0 |
| `mlkem_pwm` | 104.827 | 63 | 149 | 0 |
| `mldsa_ntt` | 85.319 | 506 | 538 | 0 |
| `mldsa_intt` | 122.083 | 123 | 538 | 0 |
| `mldsa_pwm` | 74.604 | 109 | 140 | 0 |

## 판단

완료. Stage 1은 새 inactive dummy matrix의 control로 사용한다.

`mldsa_intt` peak 123, `mlkem_pwm` peak 63, `mldsa_pwm` peak 109가 기존 Stage 4b
계열과 같은 위치에서 재현됐다. 따라서 이후 Stage 2-5에서 이 peak들이 낮아지는지
확인하면 된다.
