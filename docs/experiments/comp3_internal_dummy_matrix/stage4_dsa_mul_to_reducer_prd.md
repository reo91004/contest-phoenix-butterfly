# Stage 4: DSA Karatsuba PRD Propagated To Reducer

## 목적

ML-KEM mode에서 inactive DSA Karatsuba PRD 결과를 Montgomery reducer까지 전파한다.
이는 이전 COMP3 inactive-cone PRD 중 DSA cone 쪽 동작을 더 가깝게 재현하되, ML-DSA
mode의 inactive KEM dummy는 아직 섞지 않는 분리 실험이다.

## 구현 원칙

- ML-KEM mode:
  - KEM active output path는 real operand 유지.
  - inactive DSA Karatsuba input은 public PRD.
  - DSA Montgomery reducer input은 Karatsuba PRD output.
- ML-DSA mode:
  - DSA active path는 real operand 유지.
  - KEM inactive path는 Stage 4b와 동일하게 둔다.
- output mux는 변경하지 않는다.

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
  - bitstream mtime: `2026-05-21 03:50:59 KST`
  - WNS/TNS: `0.197 ns / 0.000 ns`
  - WHS/THS: `0.077 ns / 0.000 ns`
  - LUT/FF/RAMB36/DSP: `9921 / 3339 / 8 / 0`
- artifact:
  - `../../../reports/tvla/comp3_internal_stage4_dsa_mul_to_reducer_prd_260521/phoenix_comp3_stage4_dsa_mul_to_reducer_prd.bit`
  - `../../../reports/tvla/comp3_internal_stage4_dsa_mul_to_reducer_prd_260521/phoenix_comp3_stage4_dsa_mul_to_reducer_prd_timing.rpt`
  - `../../../reports/tvla/comp3_internal_stage4_dsa_mul_to_reducer_prd_260521/phoenix_comp3_stage4_dsa_mul_to_reducer_prd_impl_util.rpt`
  - `../../../reports/tvla/comp3_internal_stage4_dsa_mul_to_reducer_prd_260521/rtl_stage4_dsa_mul_to_reducer_prd.patch`

## TVLA 결과

명령:

```bash
OUTDIR=reports/tvla/comp3_internal_stage4_dsa_mul_to_reducer_prd_260521 \
OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' \
TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0x5EED \
PYTHON=/home/reo/.pyenv/versions/sca/bin/python \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```

| Operation | max `|t|` | peak index | cycles | clipping |
|---|---:|---:|---:|---:|
| `mlkem_ntt` | 29.206 | 216 | 248 | 0 |
| `mlkem_intt` | 32.115 | 79 | 248 | 0 |
| `mlkem_pwm` | 48.449 | 145 | 149 | 0 |
| `mldsa_ntt` | 83.253 | 186 | 538 | 0 |
| `mldsa_intt` | 128.142 | 123 | 538 | 0 |
| `mldsa_pwm` | 71.907 | 105 | 140 | 0 |

![Stage 4 TVLA overview](../../../reports/tvla/comp3_internal_stage4_dsa_mul_to_reducer_prd_260521/mlkem_mldsa_tvla_overview.png)

비교 artifact:

- `../../../reports/tvla/comp3_internal_stage4_dsa_mul_to_reducer_prd_260521/comparison_vs_stage4b_control.png`
- `../../../reports/tvla/comp3_internal_stage4_dsa_mul_to_reducer_prd_260521/comparison_vs_stage2_dsa_mul_only.png`
- `../../../reports/tvla/comp3_internal_stage4_dsa_mul_to_reducer_prd_260521/comparison_vs_original_baseline.png`

## 판단

Reject / informative.

ML-KEM 세 operation은 Stage 2 Karatsuba-only보다도 크게 좋아졌다. 그러나
`mldsa_intt`가 Stage 4b control `122.083`보다 큰 `128.142`로 악화했고, peak index
123도 유지되었다. 따라서 final 후보로는 올리지 않는다.

이 결과는 Stage 2와 합쳐 해석해야 한다.

- DSA Karatsuba-only PRD: six-op 균형이 좋고 repeat 재현됨.
- DSA Karatsuba PRD를 reducer까지 전파: ML-KEM 개선은 훨씬 크지만 ML-DSA INTT 악화.

따라서 현재 최선의 COMP3 내부 후보는 Stage 2이며, reducer까지 PRD를 전파하는 것은
ML-KEM 전용으로는 매력적이지만 전체 six-op 목표에는 맞지 않는다.
