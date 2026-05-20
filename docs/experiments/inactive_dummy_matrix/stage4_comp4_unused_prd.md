# Stage 4: COMP4 Unused-Cycle PRD

## 목적

Stage 4b는 COMP4 unused input을 대체로 zero로 막고, ML-KEM INTT만 예외로 살렸다.
이번 Stage는 COMP4 output이 선택되지 않는 valid cycle에 public PRD dummy switching을
넣어 zero blanking보다 나은지 확인한다.

## 구현 원칙

- NTT, ML-KEM INTT exception, PWM1처럼 COMP4 output이 쓰이는 cycle은 real input 유지.
- ML-DSA INTT, PWM0, ML-DSA PWM, MOD_ADD 등 COMP4 output이 선택되지 않는 cycle에만
  PRD input 적용.
- ML-KEM INTT COMP4 exception은 유지한다.
- active output mux는 변경하지 않는다.

## 코드 차이

기준 RTL은 Stage 4b restored RTL이다. 변경은
`rtl/sbu/superbutterfly_sbu_routed.v`에만 넣었다.

- `USE_PRD_COMP4_UNUSED_DUMMY` localparam을 추가했다.
- `v6` 기준으로 동작하는 32-bit public LFSR `comp4_dummy_lfsr`를 추가했다.
- COMP4 operand mux에서 실제 COMP4 결과를 쓰는 selector는 real operand를 유지했다.
  - `SBU_NTT_CT`
  - `SBU_MLDSA_NTT`
  - `SBU_INTT_GS`
  - `SBU_PWM1`
- 그 외 valid cycle에서는 COMP4 입력을 `comp4_dummy_a/b`로 바꿨다.

복구 방법은 위 localparam/LFSR와 COMP4 default branch의 PRD 대입을 제거하고, Stage 4b처럼
default를 `32'b0`으로 되돌리는 것이다.

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
  - bitstream mtime: `2026-05-21 03:02:41 KST`
  - WNS/TNS: `0.099 ns / 0.000 ns`
  - WHS/THS: `0.066 ns / 0.000 ns`
  - LUT/FF/RAMB36/DSP: `9791 / 3339 / 8 / 0`
- artifact:
  - `../../../reports/tvla/inactive_dummy_stage4_comp4_prd_260521/phoenix_stage4_comp4_prd.bit`
  - `../../../reports/tvla/inactive_dummy_stage4_comp4_prd_260521/phoenix_stage4_comp4_prd_timing.rpt`
  - `../../../reports/tvla/inactive_dummy_stage4_comp4_prd_260521/phoenix_stage4_comp4_prd_impl_util.rpt`

## TVLA 결과

명령:

```bash
OUTDIR=reports/tvla/inactive_dummy_stage4_comp4_prd_260521 \
OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' \
TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0x5EED \
PYTHON=/home/reo/.pyenv/versions/sca/bin/python \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```

| Operation | max `|t|` | peak index | cycles | clipping |
|---|---:|---:|---:|---:|
| `mlkem_ntt` | 165.103 | 116 | 248 | 0 |
| `mlkem_intt` | 43.126 | 116 | 248 | 0 |
| `mlkem_pwm` | 105.432 | 63 | 149 | 0 |
| `mldsa_ntt` | 103.791 | 506 | 538 | 0 |
| `mldsa_intt` | 121.648 | 93 | 538 | 0 |
| `mldsa_pwm` | 73.588 | 134 | 140 | 0 |

![Stage 4 TVLA overview](../../../reports/tvla/inactive_dummy_stage4_comp4_prd_260521/mlkem_mldsa_tvla_overview.png)

비교 artifact:

- `../../../reports/tvla/inactive_dummy_stage4_comp4_prd_260521/comparison_vs_stage1_control.png`
- `../../../reports/tvla/inactive_dummy_stage4_comp4_prd_260521/comparison_vs_original_baseline.png`
- `../../../reports/tvla/inactive_dummy_stage4_comp4_prd_260521/comparison_vs_stage3_comp2_prd.png`

## 판단

Reject.

`mlkem_intt`, `mldsa_intt`, `mldsa_pwm`은 거의 변하지 않았지만, `mlkem_ntt`가
Stage 1 control `98.403`에서 `165.103`으로 크게 악화했다. `mldsa_ntt`도
`85.319`에서 `103.791`로 악화했다. 따라서 COMP4 unused-cycle PRD는 "전체 TVLA가
함께 내려가는" 방향이 아니며, repeat 후보나 Stage 6 조합 후보로 올리지 않는다.

중요한 관찰은 `mlkem_pwm` peak 63이 그대로 남았고, `mldsa_intt` worst가 낮아지지
않았다는 점이다. 이는 COMP4 unused switching만으로는 현재 주요 active leakage를
가리기 어렵고, PRD source 추가가 오히려 일부 transform의 physical noise shape를
나쁘게 만들 수 있음을 보여준다.
