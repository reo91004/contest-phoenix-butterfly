# Stage 5: KEM Cone Zero In ML-DSA Mode

## 목적

Stage 4의 zero counterpart다. ML-DSA mode에서 inactive KEM COMP2 cone을 public PRD가
아니라 `0`으로 고정한다.

확인 질문은 Stage 4의 개선이 public PRD dummy switching 때문인지, 아니면 inactive KEM
COMP2 cone을 조용히 만든 효과인지 분리하는 것이다.

## 구현 원칙

- ML-KEM mode:
  - KEM COMP2 active output path는 real operand 유지.
- ML-DSA mode:
  - DSA COMP2 active output path는 real operand 유지.
  - KEM COMP2 inactive low/high lane 입력은 `32'b0`.
- COMP2 interface는 바꾸지 않았다. PRD LFSR도 추가하지 않았다.
- output mux, scheduler, SBU latency 8, memory layout, cycle count는 변경하지 않았다.

## 실행 기록

| 항목 | 결과 |
|---|---|
| RTL patch | `reports/tvla/comp2_internal_stage5_kem_cone_zero_in_dsa_260521/rtl_stage5_kem_cone_zero_in_dsa.patch` |
| bitstream mtime | `2026-05-21 05:29:05 KST` |
| WNS/TNS | `0.126 ns / 0.000 ns` |
| WHS/THS | `0.066 ns / 0.000 ns` |
| LUT/FF/RAMB36/DSP | `9749 / 3288 / 8 / 0` |
| diagnostics | `check_phoenix_consistency.py` PASS, `check_bank_conflicts.py` PASS |
| Verilator | `tb_comp1_comp2_comp4`, `tb_superbutterfly_all_modes`, `tb_phoenix_core`, `tb_phoenix_host_io`, `tb_phoenix_cw305_wrapper`, `tb_phoenix_mldsa_pwm_io` PASS |
| TVLA OUTDIR | `reports/tvla/comp2_internal_stage5_kem_cone_zero_in_dsa_260521` |
| TVLA command | `OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0x5EED` |

## TVLA 결과

비교 기준은 `reports/tvla/inactive_dummy_stage1_stage4b_control_260521`이다.

| Operation | Stage 4b control | Stage 5 KEM cone zero | peak index | cycles | clipping | 판단 |
|---|---:|---:|---:|---:|---:|---|
| `mlkem_ntt` | 98.403 | 121.412 | 116 | 248 | 0 | 악화 |
| `mlkem_intt` | 44.048 | 53.754 | 116 | 248 | 0 | 악화 |
| `mlkem_pwm` | 104.827 | 113.692 | 63 | 149 | 0 | 악화 |
| `mldsa_ntt` | 85.319 | 116.949 | 506 | 538 | 0 | 크게 악화 |
| `mldsa_intt` | 122.083 | 103.804 | 123 | 538 | 0 | 크게 개선 |
| `mldsa_pwm` | 74.604 | 75.799 | 115 | 140 | 0 | 거의 동일/소폭 악화 |

![Stage 5 vs Stage 4b control](../../../reports/tvla/comp2_internal_stage5_kem_cone_zero_in_dsa_260521/overview_vs_stage4b_control.png)

추가 비교 artifact:

- `reports/tvla/comp2_internal_stage5_kem_cone_zero_in_dsa_260521/compare_vs_stage4b_control.csv`
- `reports/tvla/comp2_internal_stage5_kem_cone_zero_in_dsa_260521/compare_vs_stage4_prd.csv`
- `reports/tvla/comp2_internal_stage5_kem_cone_zero_in_dsa_260521/compare_vs_comp3_stage2_best.csv`

## 판단

Reject / strong follow-up signal.

Stage 5는 단독 final candidate가 아니다. `mldsa_intt` peak 123이 `122.083 -> 103.804`로
가장 크게 내려간 것은 매우 의미 있지만, 그 대가로 `mlkem_ntt`, `mlkem_intt`,
`mlkem_pwm`이 모두 악화했고 `mldsa_ntt`도 `85.319 -> 116.949`로 크게 튀었다.

이 결과는 중요한 힌트를 준다. Stage 5는 `opmode_i=ML-DSA`인 모든 cycle에서 KEM COMP2
inactive cone을 0으로 묶었다. 하지만 실제 COMP2 결과가 architectural하게 중요해지는
곳은 주로 `SBU_MLDSA_INTT`의 pre-sub/div2 경로다. `mldsa_ntt`와 `mldsa_pwm`까지 같은
blanking을 강제로 적용했기 때문에, NTT/PWM의 switching balance를 깨뜨렸을 가능성이
높다.

따라서 다음 실험은 Stage 6 조합이 아니라 op-selective Stage 6a/6b로 잡는다.

- Stage 6a: `SBU_MLDSA_INTT`일 때만 inactive KEM COMP2 cone zero.
- Stage 6b: `SBU_MLDSA_INTT`일 때만 inactive KEM COMP2 cone public PRD.

이 두 실험이 `mldsa_intt` 개선을 유지하면서 `mldsa_ntt`, `mldsa_pwm`, ML-KEM을 되돌릴
수 있는지 확인한다.
