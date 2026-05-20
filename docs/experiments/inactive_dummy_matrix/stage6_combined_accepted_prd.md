# Stage 6: Combined Accepted PRD

## 목적

Stage 2-5 중 Stage 4b control보다 명확히 개선되고 repeat에서도 재현된 dummy만 조합해
상호작용을 확인한다.

## 조합 규칙

- 단일 Stage에서 rejected된 dummy는 조합하지 않는다.
- 조합 결과가 단일 Stage보다 worst를 키우면 조합은 reject하고 단일 결과를 보존한다.
- 조합이 좋아 보이면 `mlkem_pwm`, `mldsa_intt`, `mldsa_pwm` repeat를 수행한다.

## 실행 기록

실행하지 않았다.

Stage 2-5 중 Stage 4b control보다 전체 worst를 낮추고 핵심 peak를 악화시키지 않는
accepted 단일 후보가 없었다.

## TVLA 결과

해당 없음.

## 판단

Stage 6 combined PRD는 보류가 아니라 명시적으로 skip한다.

- Stage 2 COMP3 PRD: ML-KEM은 크게 좋아졌지만 `mldsa_intt`, `mldsa_pwm` 악화.
- Stage 3 COMP2 PRD: `mldsa_intt`는 좋아졌지만 `mlkem_pwm`이 worst로 악화.
- Stage 4 COMP4 PRD: `mlkem_ntt`, `mldsa_ntt` 악화.
- Stage 5 COMP1 PRD: `mldsa_intt`는 조금 좋아졌지만 `mlkem_ntt`, `mlkem_pwm`,
  `mldsa_ntt` 악화.

따라서 조합하면 각 단일 실험의 악화 요인이 누적될 가능성이 높고, 사용자의 원칙인
"좋은 후보만 조합" 조건을 만족하지 않는다. 현재 RTL은 Stage 4b restored 상태로
되돌려 유지한다.
