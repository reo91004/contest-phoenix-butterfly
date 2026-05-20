# Stage 9: DSA Mul-Only Zero In ML-KEM Mode

## 목적

Stage 2의 zero counterpart다. Stage 2는 ML-KEM mode에서 inactive DSA Karatsuba만
public PRD로 흔들고 DSA Montgomery reducer input은 `0`으로 고정했다. 이 실험은 같은
위치에 PRD가 아니라 `0`을 넣어, Stage 2 개선이 dummy switching 때문인지 deterministic
zero blanking 때문인지 분리한다.

## 구현 원칙

- ML-KEM mode:
  - KEM active output path는 real operand 유지.
  - inactive DSA Karatsuba input은 `0`.
  - inactive DSA Montgomery reducer input은 `0`.
- ML-DSA mode:
  - DSA active output path는 real operand 유지.
- output mux는 변경하지 않는다.
- `comp3_agile_modmul` port는 Stage 4b와 동일하게 유지한다.

## 실행 기록

| 항목 | 결과 |
|---|---|
| RTL patch | `reports/tvla/comp3_internal_stage9_dsa_mul_only_zero_260521/rtl_stage9_dsa_mul_only_zero.patch` |
| bitstream mtime | `2026-05-21 04:33:53 KST` |
| WNS/TNS | `0.254 ns / 0.000 ns` |
| WHS/THS | `0.066 ns / 0.000 ns` |
| LUT/FF/RAMB36/DSP | `9975 / 3287 / 8 / 0` |
| diagnostics | `check_phoenix_consistency.py` PASS, `check_bank_conflicts.py` PASS |
| Verilator | `tb_comp3_agile_modmul`, `tb_superbutterfly_all_modes`, `tb_phoenix_core`, `tb_phoenix_host_io`, `tb_phoenix_cw305_wrapper`, `tb_phoenix_mldsa_pwm_io` PASS |
| TVLA OUTDIR | `reports/tvla/comp3_internal_stage9_dsa_mul_only_zero_260521` |
| TVLA command | `OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0x5EED` |
| repeat OUTDIR | `reports/tvla/comp3_internal_stage9_dsa_mul_only_zero_key_repeat_260521` |
| repeat command | `OPS='mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0xC0DEC` |

## TVLA 결과

비교 기준은 `reports/tvla/inactive_dummy_stage1_stage4b_control_260521`이다.

| Operation | Stage 4b control | Stage 9 zero | peak index | cycles | clipping | 판단 |
|---|---:|---:|---:|---:|---:|---|
| `mlkem_ntt` | 98.403 | 89.643 | 217 | 248 | 0 | 개선 |
| `mlkem_intt` | 44.048 | 79.737 | 196 | 248 | 0 | 악화 |
| `mlkem_pwm` | 104.827 | 101.765 | 56 | 149 | 0 | 소폭 개선 |
| `mldsa_ntt` | 85.319 | 108.494 | 506 | 538 | 0 | 악화 |
| `mldsa_intt` | 122.083 | 108.032 | 123 | 538 | 0 | 개선 |
| `mldsa_pwm` | 74.604 | 71.612 | 114 | 140 | 0 | 개선 |

![Stage 9 vs Stage 4b control](../../../reports/tvla/comp3_internal_stage9_dsa_mul_only_zero_260521/overview_vs_inactive_stage1_control.png)

Stage 2 PRD counterpart와 비교하면 차이가 더 선명하다.

| Operation | Stage 2 PRD | Stage 9 zero | 판단 |
|---|---:|---:|---|
| `mlkem_ntt` | 68.726 | 89.643 | PRD가 더 좋음 |
| `mlkem_intt` | 43.319 | 79.737 | PRD가 훨씬 좋음 |
| `mlkem_pwm` | 96.004 | 101.765 | PRD가 더 좋음 |
| `mldsa_ntt` | 80.229 | 108.494 | PRD가 훨씬 좋음 |
| `mldsa_intt` | 117.028 | 108.032 | zero가 더 좋음 |
| `mldsa_pwm` | 71.047 | 71.612 | 거의 동일 |

Repeat 결과:

| Operation | Stage 9 zero repeat | peak index | 판단 |
|---|---:|---:|---|
| `mlkem_intt` | 78.473 | 196 | 악화 재현 |
| `mlkem_pwm` | 103.608 | 56 | control 근처, Stage 2보다 악화 |
| `mldsa_ntt` | 114.252 | 506 | 악화 재현 |
| `mldsa_intt` | 110.611 | 123 | 개선 재현 |
| `mldsa_pwm` | 71.780 | 115 | 개선/동등 |

![Stage 9 repeat vs Stage 4b control](../../../reports/tvla/comp3_internal_stage9_dsa_mul_only_zero_key_repeat_260521/overview_vs_inactive_stage1_control.png)

## 판단

Informative / not final accepted.

Stage 9는 중요한 단서를 줬다. DSA Karatsuba와 DSA reducer를 ML-KEM mode에서 완전히
zero로 묶으면 `mldsa_intt` peak 123이 `122.083 -> 108.032`, repeat에서
`110.611`로 내려간다. 즉 zero blanking이 ML-DSA INTT worst를 낮출 여지는 실제로
있다.

하지만 동시에 `mlkem_intt`가 `44.048 -> 79.737`, repeat `78.473`으로 크게
악화했고, `mldsa_ntt`도 `85.319 -> 108.494`, repeat `114.252`로 악화했다.
따라서 Stage 9는 전체 six-op 균형 후보가 아니라 “mldsa_intt peak를 낮추는 trade-off”
실험으로 보존한다.

Stage 2와 비교한 결론은 다음과 같다.

- Stage 2 PRD는 모든 op가 대체로 control보다 낮아지는 균형형 후보였다.
- Stage 9 zero는 `mldsa_intt`는 더 잘 낮추지만 `mlkem_intt`, `mldsa_ntt`를 크게
  악화한다.
- 따라서 Stage 2의 개선은 단순히 DSA cone을 조용히 0으로 만든 효과가 아니다.
  inactive DSA Karatsuba에 public switching을 남긴 것이 전체 TVLA shape를 더 균형 있게
  만든 것으로 해석한다.
