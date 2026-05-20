# Stage 3: DSA Cone Zero In ML-KEM Mode

## 목적

Stage 2의 zero counterpart다. ML-KEM mode에서 inactive DSA COMP2 cone을 public PRD가
아니라 `0`으로 고정한다.

확인하고 싶은 질문은 하나다.

```text
Stage 2의 ML-KEM 악화가 PRD dummy switching 때문인가,
아니면 ML-KEM mode에서 DSA COMP2 cone을 건드리는 것 자체가 민감한가?
```

## 구현 원칙

- ML-KEM mode:
  - KEM COMP2 active output path는 real operand 유지.
  - DSA COMP2 inactive cone의 `a/b` 입력은 `32'b0`.
- ML-DSA mode:
  - DSA COMP2 active output path는 real operand 유지.
  - KEM COMP2 cone은 Stage 4b와 동일하게 둔다.
- COMP2 interface는 바꾸지 않았다. PRD LFSR도 추가하지 않았다.
- output mux, scheduler, SBU latency 8, memory layout, cycle count는 변경하지 않았다.

## 실행 기록

| 항목 | 결과 |
|---|---|
| RTL patch | `reports/tvla/comp2_internal_stage3_dsa_cone_zero_in_kem_260521/rtl_stage3_dsa_cone_zero_in_kem.patch` |
| bitstream mtime | `2026-05-21 05:07:49 KST` |
| WNS/TNS | `0.128 ns / 0.000 ns` |
| WHS/THS | `0.066 ns / 0.000 ns` |
| LUT/FF/RAMB36/DSP | `9852 / 3284 / 8 / 0` |
| diagnostics | `check_phoenix_consistency.py` PASS, `check_bank_conflicts.py` PASS |
| Verilator | `tb_comp1_comp2_comp4`, `tb_superbutterfly_all_modes`, `tb_phoenix_core`, `tb_phoenix_host_io`, `tb_phoenix_cw305_wrapper`, `tb_phoenix_mldsa_pwm_io` PASS |
| TVLA OUTDIR | `reports/tvla/comp2_internal_stage3_dsa_cone_zero_in_kem_260521` |
| TVLA command | `OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0x5EED` |

## TVLA 결과

비교 기준은 `reports/tvla/inactive_dummy_stage1_stage4b_control_260521`이다.

| Operation | Stage 4b control | Stage 3 DSA cone zero | peak index | cycles | clipping | 판단 |
|---|---:|---:|---:|---:|---:|---|
| `mlkem_ntt` | 98.403 | 125.940 | 116 | 248 | 0 | 악화 |
| `mlkem_intt` | 44.048 | 70.275 | 182 | 248 | 0 | 악화 |
| `mlkem_pwm` | 104.827 | 114.347 | 63 | 149 | 0 | 악화 |
| `mldsa_ntt` | 85.319 | 116.623 | 505 | 538 | 0 | 크게 악화 |
| `mldsa_intt` | 122.083 | 117.934 | 123 | 538 | 0 | 소폭 개선 |
| `mldsa_pwm` | 74.604 | 76.777 | 134 | 140 | 0 | 소폭 악화 |

![Stage 3 vs Stage 4b control](../../../reports/tvla/comp2_internal_stage3_dsa_cone_zero_in_kem_260521/overview_vs_stage4b_control.png)

추가 비교 artifact:

- `reports/tvla/comp2_internal_stage3_dsa_cone_zero_in_kem_260521/compare_vs_stage4b_control.csv`
- `reports/tvla/comp2_internal_stage3_dsa_cone_zero_in_kem_260521/compare_vs_stage2_prd.csv`
- `reports/tvla/comp2_internal_stage3_dsa_cone_zero_in_kem_260521/compare_vs_comp3_stage2_best.csv`

## 판단

Reject.

Stage 3은 Stage 2보다 ML-KEM 악화 폭은 줄였지만, Stage 4b control보다 좋은 실험은
아니다. `mlkem_ntt`, `mlkem_intt`, `mlkem_pwm`이 모두 악화했고, ML-DSA에서도
`mldsa_ntt`가 `85.319 -> 116.623`으로 크게 튀었다. `mldsa_intt` peak 123은
`122.083 -> 117.934`로 소폭 낮아졌지만, 이 정도 개선은 전체 worst 악화를 상쇄하지
못한다.

Stage 2와 비교하면 PRD switching이 ML-KEM NTT 악화를 더 키운 것은 맞다. Stage 2의
`mlkem_ntt`는 181.375였고 Stage 3 zero는 125.940이다. 그러나 zero만 넣어도 Stage 4b
control보다 ML-KEM과 `mldsa_ntt`가 나빠졌으므로, ML-KEM mode에서 inactive DSA COMP2
cone을 억지로 PRD/zero 처리하는 방향은 accept 후보에서 제외한다.

다음 실험은 반대 방향이다. ML-DSA mode에서 inactive KEM COMP2 cone만 PRD/zero로
건드려서, ML-DSA active leakage가 낮아지는지와 ML-KEM control이 보존되는지를 확인한다.
