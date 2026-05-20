# Stage 7: KEM Barrett Reducer PRD In ML-DSA Mode

## 목적

ML-DSA mode에서 inactive KEM multiplier와 Barrett reducer를 분리한다. KEM multiplier는
Stage 4b처럼 real operand로 계속 계산하게 두고, Barrett reducer input 쪽만 public
PRD로 바꿨을 때 ML-DSA TVLA가 어떻게 바뀌는지 본다.

## 구현 원칙

- ML-DSA mode:
  - DSA active output path는 real operand 유지.
  - inactive KEM multiplier input은 Stage 4b처럼 real operand 유지.
  - inactive KEM Barrett reducer input은 public PRD.
- ML-KEM mode:
  - KEM active path는 real operand 유지.
- output mux는 변경하지 않는다.

## 실행 기록

| 항목 | 결과 |
|---|---|
| RTL patch | `reports/tvla/comp3_internal_stage7_kem_reducer_prd_260521/rtl_stage7_kem_reducer_prd.patch` |
| bitstream mtime | `2026-05-21 04:22:27 KST` |
| WNS/TNS | `0.336 ns / 0.000 ns` |
| WHS/THS | `0.090 ns / 0.000 ns` |
| LUT/FF/RAMB36/DSP | `9870 / 3341 / 8 / 0` |
| diagnostics | `check_phoenix_consistency.py` PASS, `check_bank_conflicts.py` PASS |
| Verilator | `tb_comp3_agile_modmul`, `tb_superbutterfly_all_modes`, `tb_phoenix_core`, `tb_phoenix_host_io`, `tb_phoenix_cw305_wrapper`, `tb_phoenix_mldsa_pwm_io` PASS |
| TVLA OUTDIR | `reports/tvla/comp3_internal_stage7_kem_reducer_prd_260521` |
| TVLA command | `OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0x5EED` |

## TVLA 결과

비교 기준은 `reports/tvla/inactive_dummy_stage1_stage4b_control_260521`이다.

| Operation | Stage 4b control | Stage 7 KEM reducer PRD | peak index | cycles | clipping | 판단 |
|---|---:|---:|---:|---:|---:|---|
| `mlkem_ntt` | 98.403 | 116.556 | 116 | 248 | 0 | 악화 |
| `mlkem_intt` | 44.048 | 34.713 | 81 | 248 | 0 | 개선 |
| `mlkem_pwm` | 104.827 | 107.651 | 63 | 149 | 0 | 악화 |
| `mldsa_ntt` | 85.319 | 93.508 | 380 | 538 | 0 | 악화 |
| `mldsa_intt` | 122.083 | 160.762 | 123 | 538 | 0 | 크게 악화 |
| `mldsa_pwm` | 74.604 | 79.059 | 105 | 140 | 0 | 악화 |

![Stage 7 vs Stage 4b control](../../../reports/tvla/comp3_internal_stage7_kem_reducer_prd_260521/overview_vs_inactive_stage1_control.png)

추가 비교 artifact:

- `reports/tvla/comp3_internal_stage7_kem_reducer_prd_260521/compare_vs_inactive_stage1_control.csv`
- `reports/tvla/comp3_internal_stage7_kem_reducer_prd_260521/compare_vs_stage4b_control.csv`
- `reports/tvla/comp3_internal_stage7_kem_reducer_prd_260521/compare_vs_stage6_kem_hi_lane_prd.csv`

## 판단

Reject.

Barrett reducer input만 PRD로 바꿔도 `mldsa_intt` peak 123이
`122.083 -> 160.762`로 크게 악화했다. `mlkem_intt`는 좋아졌지만, six-op worst와
ML-DSA active-window peak를 동시에 망가뜨리므로 채택할 수 없다.

이 결과는 ML-DSA mode에서 inactive KEM reducer 쪽 switching을 무작정 키우는 것이
ML-DSA leakage를 숨기기보다 오히려 active arithmetic peak를 더 선명하게 만들 수
있다는 근거다. Stage 5/6/7 모두 KEM-side dummy가 ML-DSA worst를 악화했기 때문에,
이번 matrix의 유일한 조합 후보는 Stage 2의 DSA Karatsuba-only PRD뿐이다.
