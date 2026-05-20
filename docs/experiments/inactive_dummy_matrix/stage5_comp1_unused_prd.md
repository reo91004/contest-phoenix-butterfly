# Stage 5: COMP1 Unused-Cycle PRD

## 목적

COMP1은 대부분의 operation에서 output에 직접 관여한다. 따라서 이 Stage는 매우
보수적으로, COMP1 output이 architectural output에 쓰이지 않는 cycle에만 PRD input을
적용한다.

## 구현 원칙

- NTT/INTT/PWM0/PWM1/MOD_ADD는 COMP1 output을 사용하므로 real input 유지.
- `SBU_MLDSA_PWM`처럼 output mux가 `p6`만 사용하는 cycle에 한해 COMP1 input PRD 적용.
- 기능 결과와 cycle count는 Stage 4b와 동일해야 한다.
- active output mux는 변경하지 않는다.

## 코드 차이

기준 RTL은 Stage 4b restored RTL이다. 변경은
`rtl/sbu/superbutterfly_sbu_routed.v`에만 넣었다.

- `USE_PRD_COMP1_UNUSED_DUMMY` localparam을 추가했다.
- `sel6 == SBU_MLDSA_PWM`이고 `v6=1`인 cycle에만 32-bit public LFSR
  `comp1_dummy_lfsr`를 advance한다.
- COMP1 operand mux에 `SBU_MLDSA_PWM` branch를 추가해 `comp1_dummy_a/b`를 넣었다.
- NTT/INTT/PWM0/PWM1/MOD_ADD의 COMP1 real operand는 그대로 유지했다.

복구 방법은 위 localparam/LFSR와 `SBU_MLDSA_PWM` branch를 제거하고, Stage 4b처럼
해당 selector가 COMP1 default zero branch로 떨어지게 두는 것이다.

## 실행 기록

- diagnostics:
  - `check_phoenix_consistency.py`: PASS
  - `check_bank_conflicts.py`: PASS
- Verilator:
  - `tb_comp3_agile_modmul`
  - `tb_superbutterfly_all_modes`
  - `tb_phoenix_core`
  - `tb_phoenix_host_io`
  - `tb_phoenix_cw305_wrapper`
  - `tb_phoenix_mldsa_pwm_io`
  - 결과: PASS, `tb_phoenix_mldsa_pwm_io cycles=140`
- Vivado 30ns build:
  - bitstream mtime: `2026-05-21 03:14:20 KST`
  - WNS/TNS: `0.209 ns / 0.000 ns`
  - WHS/THS: `0.064 ns / 0.000 ns`
  - LUT/FF/RAMB36/DSP: `9660 / 3338 / 8 / 0`
- artifact:
  - `../../../reports/tvla/inactive_dummy_stage5_comp1_prd_260521/phoenix_stage5_comp1_prd.bit`
  - `../../../reports/tvla/inactive_dummy_stage5_comp1_prd_260521/phoenix_stage5_comp1_prd_timing.rpt`
  - `../../../reports/tvla/inactive_dummy_stage5_comp1_prd_260521/phoenix_stage5_comp1_prd_impl_util.rpt`

## TVLA 결과

명령:

```bash
OUTDIR=reports/tvla/inactive_dummy_stage5_comp1_prd_260521 \
OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' \
TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0x5EED \
PYTHON=/home/reo/.pyenv/versions/sca/bin/python \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```

| Operation | max `|t|` | peak index | cycles | clipping |
|---|---:|---:|---:|---:|
| `mlkem_ntt` | 131.925 | 116 | 248 | 0 |
| `mlkem_intt` | 41.747 | 100 | 248 | 0 |
| `mlkem_pwm` | 115.442 | 63 | 149 | 0 |
| `mldsa_ntt` | 108.988 | 389 | 538 | 0 |
| `mldsa_intt` | 115.536 | 123 | 538 | 0 |
| `mldsa_pwm` | 72.259 | 114 | 140 | 0 |

![Stage 5 TVLA overview](../../../reports/tvla/inactive_dummy_stage5_comp1_prd_260521/mlkem_mldsa_tvla_overview.png)

비교 artifact:

- `../../../reports/tvla/inactive_dummy_stage5_comp1_prd_260521/comparison_vs_stage1_control.png`
- `../../../reports/tvla/inactive_dummy_stage5_comp1_prd_260521/comparison_vs_original_baseline.png`
- `../../../reports/tvla/inactive_dummy_stage5_comp1_prd_260521/comparison_vs_stage4_comp4_prd.png`

## 판단

Reject.

`mldsa_intt`는 Stage 1 control `122.083`에서 `115.536`으로 낮아졌고 `mldsa_pwm`도
조금 낮아졌다. 하지만 `mlkem_ntt`가 `98.403`에서 `131.925`로, `mlkem_pwm`이
`104.827`에서 `115.442`로, `mldsa_ntt`가 `85.319`에서 `108.988`로 악화했다.

따라서 COMP1 unused-cycle PRD는 전체 TVLA를 함께 낮추는 후보가 아니다. 특히
`mlkem_pwm` peak 63이 더 커졌으므로 repeat나 Stage 6 조합 후보로 올리지 않는다.
