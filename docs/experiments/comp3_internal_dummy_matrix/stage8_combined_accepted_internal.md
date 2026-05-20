# Stage 8: Combined Accepted COMP3 Internal Dummy

## 목적

Stage 2-7 중 Stage 4b control보다 명확히 개선되고 repeat에서도 재현된 COMP3 내부
dummy만 조합한다.

## 조합 규칙

- rejected 단일 실험은 조합하지 않는다.
- ML-KEM만 좋아지고 ML-DSA worst가 악화한 실험은 조합하지 않는다.
- 조합 후보는 먼저 six-op TVLA를 수행하고, 좋아 보일 때만 `ORDER_SEED=0xC0DEC`
  repeat를 수행한다.

## 실행 기록

실행하지 않았다.

Stage 2-7을 모두 본 결과, accepted 후보는 Stage 2 하나뿐이다.

- Stage 2: accepted 후보, key repeat 재현.
- Stage 3: timing reject.
- Stage 4: ML-KEM은 크게 개선됐지만 `mldsa_intt` 악화.
- Stage 5: KEM lo lane PRD, ML-DSA worst와 ML-KEM 악화.
- Stage 6: KEM hi lane PRD, ML-DSA NTT/INTT/PWM 악화.
- Stage 7: KEM reducer PRD, `mldsa_intt` 크게 악화.

따라서 조합할 독립 accepted 후보가 없고, Stage 8은 no-op으로 처리한다.

## TVLA 결과

새 TVLA는 실행하지 않았다. 현재 최선의 COMP3 internal 결과는 Stage 2 결과를
그대로 참조한다.

| Operation | Stage 4b control | Stage 2 DSA mul-only PRD |
|---|---:|---:|
| `mlkem_ntt` | 98.403 | 68.726 |
| `mlkem_intt` | 44.048 | 43.319 |
| `mlkem_pwm` | 104.827 | 96.004 |
| `mldsa_ntt` | 85.319 | 80.229 |
| `mldsa_intt` | 122.083 | 117.028 |
| `mldsa_pwm` | 74.604 | 71.047 |

Key repeat:

| Operation | Stage 4b control | Stage 2 repeat |
|---|---:|---:|
| `mlkem_pwm` | 104.827 | 95.354 |
| `mldsa_intt` | 122.083 | 113.569 |
| `mldsa_pwm` | 74.604 | 72.984 |

## 판단

Skipped / no-op.

조합 실험은 “둘 이상의 독립 accepted 후보”가 있을 때만 의미가 있다. 현재는 Stage 2만
accepted 후보이고 나머지는 timing reject 또는 TVLA reject이므로, Stage 2를 그대로
보존하는 것이 정합하다.

Stage 2도 TVLA pass는 아니며, `mldsa_intt` worst가 여전히 100대에 남는다. 따라서
이 matrix의 결론은 “COMP3 내부 inactive dummy로 전체 pass를 만들 수 있다”가 아니라,
“ML-KEM mode의 inactive DSA Karatsuba-only PRD는 균형 잡힌 개선 후보지만,
ML-DSA worst를 근본적으로 없애지는 못한다”이다.
