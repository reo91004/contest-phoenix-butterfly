# Stage 2: DSA Cone PRD In ML-KEM Mode

## 목적

ML-KEM mode에서 COMP2의 active output은 KEM two-lane 결과다. 이때 DSA 32-bit
add/sub/div2 cone은 output mux가 선택하지 않는 inactive cone이다.

Stage 2는 inactive DSA COMP2 cone에 public PRD operand를 넣어, COMP3 internal Stage 2와
비슷한 balanced dummy switching 효과가 COMP2에도 있는지 확인한다.

## 구현 원칙

- ML-KEM mode:
  - KEM COMP2 active output path는 real operand 유지.
  - DSA COMP2 inactive cone은 public PRD `dummy_a_i/dummy_b_i`를 입력으로 받는다.
- ML-DSA mode:
  - DSA COMP2 active output path는 real operand 유지.
  - KEM COMP2 cone은 Stage 4b와 동일하게 둔다.
- output mux, scheduler, latency는 변경하지 않는다.

## 실행 기록

| 항목 | 결과 |
|---|---|
| RTL patch | `reports/tvla/comp2_internal_stage2_dsa_cone_prd_in_kem_260521/rtl_stage2_dsa_cone_prd_in_kem.patch` |
| bitstream mtime | `2026-05-21 04:56:28 KST` |
| WNS/TNS | `0.054 ns / 0.000 ns` |
| WHS/THS | `0.069 ns / 0.000 ns` |
| LUT/FF/RAMB36/DSP | `9974 / 3336 / 8 / 0` |
| diagnostics | `check_phoenix_consistency.py` PASS, `check_bank_conflicts.py` PASS |
| Verilator | `tb_comp1_comp2_comp4`, `tb_superbutterfly_all_modes`, `tb_phoenix_core`, `tb_phoenix_host_io`, `tb_phoenix_cw305_wrapper`, `tb_phoenix_mldsa_pwm_io` PASS |
| TVLA OUTDIR | `reports/tvla/comp2_internal_stage2_dsa_cone_prd_in_kem_260521` |
| TVLA command | `OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0x5EED` |

## TVLA 결과

비교 기준은 `reports/tvla/inactive_dummy_stage1_stage4b_control_260521`이다.

| Operation | Stage 4b control | Stage 2 DSA cone PRD | peak index | cycles | clipping | 판단 |
|---|---:|---:|---:|---:|---:|---|
| `mlkem_ntt` | 98.403 | 181.375 | 116 | 248 | 0 | 크게 악화 |
| `mlkem_intt` | 44.048 | 58.136 | 182 | 248 | 0 | 악화 |
| `mlkem_pwm` | 104.827 | 118.629 | 63 | 149 | 0 | 악화 |
| `mldsa_ntt` | 85.319 | 79.568 | 352 | 538 | 0 | 개선 |
| `mldsa_intt` | 122.083 | 114.601 | 123 | 538 | 0 | 개선 |
| `mldsa_pwm` | 74.604 | 70.903 | 114 | 140 | 0 | 개선 |

![Stage 2 vs Stage 4b control](../../../reports/tvla/comp2_internal_stage2_dsa_cone_prd_in_kem_260521/overview_vs_inactive_stage1_control.png)

추가 비교 artifact:

- `reports/tvla/comp2_internal_stage2_dsa_cone_prd_in_kem_260521/compare_vs_inactive_stage1_control.csv`
- `reports/tvla/comp2_internal_stage2_dsa_cone_prd_in_kem_260521/compare_vs_comp2_unused_prd.csv`
- `reports/tvla/comp2_internal_stage2_dsa_cone_prd_in_kem_260521/compare_vs_comp3_best_stage2.csv`

## 판단

Reject / informative.

ML-DSA 세 operation은 모두 낮아졌다. 특히 `mldsa_intt` peak 123은
`122.083 -> 114.601`로 낮아졌고, `mldsa_ntt`, `mldsa_pwm`도 개선됐다. 따라서 COMP2의
inactive DSA cone switching은 ML-DSA TVLA shape에 유의미한 영향을 준다.

하지만 ML-KEM 세 operation은 모두 악화했고, 특히 `mlkem_ntt`가
`98.403 -> 181.375`로 크게 튀었다. active KEM output path는 논리적으로 바꾸지
않았는데도 ML-KEM active window가 크게 악화했으므로, 이 PRD cone은 placement/routing
또는 shared COMP2 주변 switching을 과하게 바꾼 것으로 본다.

따라서 Stage 2는 단독 accept 후보가 아니다. 다음 Stage 3에서는 같은 위치를 PRD가
아니라 deterministic zero로 묶어, ML-DSA 개선이 dummy switching 때문인지 DSA cone
quieting 때문인지 분리한다.
