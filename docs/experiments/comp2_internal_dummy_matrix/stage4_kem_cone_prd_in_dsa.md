# Stage 4: KEM Cone PRD In ML-DSA Mode

## 목적

ML-DSA mode에서 COMP2의 active output은 DSA 32-bit 결과다. 이때 KEM two-lane cone은
output mux가 선택하지 않는 inactive cone이다.

Stage 4는 inactive KEM COMP2 cone에 public PRD operand를 넣어, `mldsa_intt` peak 123에
직접 영향을 줄 수 있는지 확인한다.

Stage 2/3과 반대 방향이다. ML-KEM mode에서는 KEM cone이 active이므로 real operand를
그대로 유지하고, ML-DSA mode에서만 KEM two-lane add/sub/div2 cone에 public PRD를 넣는다.

## 구현 원칙

- ML-KEM mode:
  - KEM COMP2 active output path는 real operand 유지.
  - DSA COMP2 cone은 Stage 4b와 동일하게 real operand를 받는다.
- ML-DSA mode:
  - DSA COMP2 active output path는 real operand 유지.
  - KEM COMP2 inactive cone의 low/high 16-bit lane은 public PRD `dummy_a_i/dummy_b_i`를 받는다.
- `superbutterfly_sbu_routed.v`에 COMP2 dummy용 32-bit LFSR을 추가했다.
- `superbutterfly_sbu_ref.v`는 functional reference라 dummy를 `0`으로 tie-off했다.
- output mux, scheduler, SBU latency 8, memory layout, cycle count는 변경하지 않았다.

## 실행 기록

| 항목 | 결과 |
|---|---|
| RTL patch | `reports/tvla/comp2_internal_stage4_kem_cone_prd_in_dsa_260521/rtl_stage4_kem_cone_prd_in_dsa.patch` |
| bitstream mtime | `2026-05-21 05:19:03 KST` |
| WNS/TNS | `0.114 ns / 0.000 ns` |
| WHS/THS | `0.082 ns / 0.000 ns` |
| LUT/FF/RAMB36/DSP | `9831 / 3343 / 8 / 0` |
| diagnostics | `check_phoenix_consistency.py` PASS, `check_bank_conflicts.py` PASS |
| Verilator | `tb_comp1_comp2_comp4`, `tb_superbutterfly_all_modes`, `tb_phoenix_core`, `tb_phoenix_host_io`, `tb_phoenix_cw305_wrapper`, `tb_phoenix_mldsa_pwm_io` PASS |
| TVLA OUTDIR | `reports/tvla/comp2_internal_stage4_kem_cone_prd_in_dsa_260521` |
| TVLA command | `OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0x5EED` |

## TVLA 결과

비교 기준은 `reports/tvla/inactive_dummy_stage1_stage4b_control_260521`이다.

| Operation | Stage 4b control | Stage 4 KEM cone PRD | peak index | cycles | clipping | 판단 |
|---|---:|---:|---:|---:|---:|---|
| `mlkem_ntt` | 98.403 | 101.770 | 116 | 248 | 0 | 소폭 악화 |
| `mlkem_intt` | 44.048 | 31.868 | 116 | 248 | 0 | 개선 |
| `mlkem_pwm` | 104.827 | 108.888 | 63 | 149 | 0 | 소폭 악화 |
| `mldsa_ntt` | 85.319 | 95.607 | 506 | 538 | 0 | 악화 |
| `mldsa_intt` | 122.083 | 115.792 | 123 | 538 | 0 | 개선 |
| `mldsa_pwm` | 74.604 | 70.864 | 113 | 140 | 0 | 개선 |

![Stage 4 vs Stage 4b control](../../../reports/tvla/comp2_internal_stage4_kem_cone_prd_in_dsa_260521/overview_vs_stage4b_control.png)

추가 비교 artifact:

- `reports/tvla/comp2_internal_stage4_kem_cone_prd_in_dsa_260521/compare_vs_stage4b_control.csv`
- `reports/tvla/comp2_internal_stage4_kem_cone_prd_in_dsa_260521/compare_vs_stage3_dsa_zero.csv`
- `reports/tvla/comp2_internal_stage4_kem_cone_prd_in_dsa_260521/compare_vs_comp3_stage2_best.csv`

## 판단

Reject for final / informative for COMP2 direction.

Stage 4는 Stage 2/3보다 훨씬 안정적이다. six-op worst는 Stage 4b control의
`mldsa_intt 122.083`에서 `115.792`로 내려갔고, `mldsa_pwm`도 `74.604 -> 70.864`로
낮아졌다. ML-KEM INTT 역시 `44.048 -> 31.868`로 좋아졌다.

하지만 “ML-KEM, ML-DSA 모두 유의미하게 감소”라는 목표에는 아직 부족하다. `mlkem_ntt`,
`mlkem_pwm`, `mldsa_ntt`가 모두 control보다 올라갔고, 특히 `mldsa_ntt`는
`85.319 -> 95.607`로 악화했다. 따라서 단독 final candidate로는 reject한다.

다만 방향성은 의미가 있다. ML-DSA mode에서 inactive KEM COMP2 cone을 건드리는 방식은
Stage 2/3의 반대 방향보다 훨씬 덜 위험하고, `mldsa_intt` peak 123을 낮추는 효과도
있다. 다음 Stage 5에서는 같은 위치를 public PRD가 아니라 deterministic zero로 고정해,
개선이 random dummy switching 때문인지 KEM cone quieting 때문인지 분리한다.
