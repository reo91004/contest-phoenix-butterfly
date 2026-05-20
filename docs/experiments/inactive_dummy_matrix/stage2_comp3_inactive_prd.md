# Stage 2: COMP3 Inactive Algorithm-Cone PRD

## 목적

Stage 6b에서 관찰된 ML-KEM 개선을 Stage 4b 복구 상태에서 다시 검증한다. COMP3는
ML-KEM cone과 ML-DSA cone을 동시에 계산하고 output mux로 하나만 선택한다. 이때
선택되지 않은 algorithm cone에만 public PRD dummy를 넣는다.

## 구현 원칙

- ML-KEM mode: KEM cone은 real operand, inactive DSA cone은 public PRD.
- ML-DSA mode: DSA cone은 real operand, inactive KEM cone은 public PRD.
- output mux와 latency는 유지.
- active arithmetic cone에는 dummy를 섞지 않는다.

## 실행 기록

- RTL 변경:
  - `comp3_agile_modmul.v`에 `dummy_a_i`, `dummy_b_i` port 추가.
  - ML-KEM mode에서는 KEM cone에 real `a_i/b_i`, inactive DSA cone에 dummy.
  - ML-DSA mode에서는 DSA cone에 real `a_i/b_i[23:0]`, inactive KEM cone에 dummy.
  - `superbutterfly_sbu_routed.v`에 active valid cycle에서 advance하는 public LFSR
    dummy source 추가.
  - `superbutterfly_sbu_ref.v`, `tb_comp3_agile_modmul.sv`의 COMP3 instantiation 갱신.
- diagnostics:
  - `check_phoenix_consistency.py`: PASS
  - `check_bank_conflicts.py`: PASS
- Verilator:
  - 핵심 regression PASS
  - `tb_phoenix_mldsa_pwm_io`: `cycles=140`
- CW305 30ns build:
  - bitstream mtime: `2026-05-21 02:42:02 KST`
  - WNS `0.139 ns`, TNS `0.000 ns`
  - WHS `0.059 ns`, THS `0.000 ns`
  - LUT `9877`, FF `3345`, RAMB36 `8`, DSP `0`

TVLA command:

```bash
OUTDIR=reports/tvla/inactive_dummy_stage2_comp3_prd_260521 \
OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' \
TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0x5EED \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```

## TVLA 결과

![Stage 2 TVLA overview](../../../reports/tvla/inactive_dummy_stage2_comp3_prd_260521/mlkem_mldsa_tvla_overview.png)

Stage 2 vs Stage 1 control:

![Stage 2 vs Stage 1 control](../../../reports/tvla/inactive_dummy_stage2_comp3_prd_260521/comparison_vs_stage1_control.png)

| Operation | Stage 1 control | Stage 2 COMP3 PRD | peak index | cycles | clipping |
|---|---:|---:|---:|---:|---:|
| `mlkem_ntt` | 98.403 | 25.908 | 114 | 248 | 0 |
| `mlkem_intt` | 44.048 | 29.160 | 45 | 248 | 0 |
| `mlkem_pwm` | 104.827 | 53.688 | 145 | 149 | 0 |
| `mldsa_ntt` | 85.319 | 87.421 | 63 | 538 | 0 |
| `mldsa_intt` | 122.083 | 165.043 | 123 | 538 | 0 |
| `mldsa_pwm` | 74.604 | 93.703 | 105 | 140 | 0 |

## 판단

Rejected / informative.

ML-KEM은 Stage 6b와 같은 방향으로 크게 좋아졌다. 이는 inactive DSA cone에 public
dummy switching을 넣는 것이 ML-KEM peak visibility를 강하게 바꿀 수 있음을 다시
확인한다.

하지만 `mldsa_intt` peak 123이 유지된 채 `122.083 -> 165.043`으로 크게 악화했고,
`mldsa_pwm`도 `74.604 -> 93.703`으로 악화했다. 따라서 Stage 2는 accepted
combination 후보에 넣지 않는다.
