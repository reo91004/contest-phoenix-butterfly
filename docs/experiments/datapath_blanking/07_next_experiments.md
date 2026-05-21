# Stage 7 이후 후속 실험 계획

## 질문

Stage 6b가 ML-KEM에서 매우 좋은 결과를 냈기 때문에 두 질문이 생겼다.

1. ML-DSA Montgomery reduction을 Solinas-style reduction으로 바꾸면 ML-DSA도 좋아질까?
2. COMP1/2/3/4 모두에 public random dummy를 넣어보는 실험은 의미가 있을까?

## 2026-05-21 업데이트

두 질문 모두 실제로 분리 실험했다.

- Solinas-style ML-DSA arithmetic baseline은 기능/timing은 통과했지만 TVLA worst를
  악화시켜 rejected/informative로 보존했다. 상세는
  `docs/handover/260521_mldsa_solinas_stage7_plan.md`에 둔다.
- COMP1/2/3/4 inactive/unused public PRD dummy matrix는 Stage 4b restored RTL에서
  다시 실행했다. 상세는 `docs/experiments/inactive_dummy_matrix/README.md`에 둔다.
- matrix 결론은 "일부 operation은 낮아지지만 six-op worst가 함께 내려가는 accepted
  후보는 없음"이다.
- 이후 COMP3/COMP2 내부 inactive cone을 더 좁게 쪼갠 matrix를 추가로 실행했다. 상세는
  `docs/experiments/comp3_internal_dummy_matrix/README.md`와
  `docs/experiments/comp2_internal_dummy_matrix/README.md`에 둔다.
- 논문 후보 RTL은 COMP3 internal Stage 2 `DSA Karatsuba-only PRD in ML-KEM mode`로
  정했다. Original baseline 대비 six-op max `|t|`가 모두 낮아졌기 때문이다.
- Stage 6c candidate는 Stage 4b control 대비 worst를 `mldsa_intt 122.083 -> 99.696`,
  repeat에서 `102.864`까지 낮췄지만, `mlkem_intt` 악화가 남아 final RTL에는 적용하지 않는다.

## 현재 해석

Stage 6b는 active arithmetic을 바꾼 실험이 아니다. ML-KEM mode에서는 active KEM
cone은 그대로 두고 inactive DSA cone에 public PRD dummy를 넣었다. 따라서 ML-KEM
개선은 “KEM arithmetic 자체가 안전해졌다”가 아니라 “주변 inactive dummy switching이
ML-KEM peak visibility를 크게 바꿨다”로 해석해야 한다.

반대로 ML-DSA mode에서는 active DSA Montgomery multiply/reduction cone이 그대로였고,
inactive KEM cone만 dummy를 받았다. `mldsa_intt` peak 123은 그대로 남고 값은 더
커졌다. 그래서 Solinas-style reducer가 자동으로 좋아질 것이라고 말할 수 없다.

## Solinas-style ML-DSA reduction 가능성

ML-DSA modulus:

```text
q = 8380417 = 0x7fe001 = 2^23 - 2^13 + 1
```

따라서 다음 관계를 이용한 folding reduction은 수학적으로 가능하다.

```text
2^23 == 2^13 - 1 mod q
```

하지만 이것은 active DSA arithmetic cone을 바꾸는 일이다. Stage 6b가 건드린
inactive cone과는 실험 범주가 다르다. 더 작은 reducer가 TVLA를 낮춘다는 보장도
없다. 회로가 조용해지면서 active leakage가 더 선명해질 수도 있다.

결론:

- Solinas-style reducer는 별도 실험 가치는 있다.
- 그러나 Stage 6b 다음의 1순위는 아니다.
- 먼저 inactive/unused public dummy switching 효과를 COMP1/2/3/4 전체에서
  체계적으로 분해해야 한다.

## 실행된 matrix: COMP1/2/3/4 public dummy

기준은 반드시 Stage 4b다. Stage 6b 위에 쌓지 않는다.

공통 invariant:

- 9-bit instruction 유지.
- SBU latency 8 유지.
- two-SBU PE 유지.
- memory layout, scheduler, cycle count 유지.
- active output mux 의미 유지.
- active arithmetic cone에는 dummy를 섞지 않음.
- dummy는 secret, fixed/random class, memory contents와 독립.

### Peak-to-cycle mapping

RTL 변경 없이 먼저 한다.

- Stage 4b `mldsa_intt` peak index 123이 어느 SBU pipeline stage와 맞는지 매핑.
- Stage 4b `mlkem_pwm` peak index 63도 함께 매핑.
- COMP1/2/3/4 중 어느 block이 해당 window에 있는지 VCD/SAIF 또는 debug trace로 확인.

### COMP2 unused-input PRD dummy

Stage 4b에서 COMP2는 INTT가 아닐 때 input이 zero다. 이 zero 대신 valid-cycle
public PRD dummy를 넣어 NTT/PWM active peak가 낮아지는지 본다.

### COMP4 unused-input PRD dummy

Stage 4b에서 COMP4는 NTT, ML-KEM INTT exception, PWM1에서만 real input을 받는다.
나머지 valid cycle에 public PRD dummy를 넣는다. ML-KEM INTT exception은 유지한다.

### COMP1 unused-input PRD dummy

output mux가 COMP1을 쓰지 않는 valid cycle에만 COMP1 input을 public PRD dummy로
바꾼다. 특히 ML-DSA PWM 주변 leakage shape를 본다.

### COMP3 inactive-cone PRD dummy v2

Stage 6b를 다시 하되 control을 더 명확히 둔다.

- ML-KEM mode: active KEM cone real, inactive DSA cone PRD dummy.
- ML-DSA mode: active DSA cone real, inactive KEM cone PRD dummy.
- PRD LFSR advance는 valid COMP3 transaction에만 제한.

## Solinas-style reducer 결과

ML-DSA active reducer 변경은 별도 Solinas baseline으로 실제 구현해 측정했다. 결과는
rejected/informative다.

조건:

- `comp3_agile_modmul.v`의 ML-DSA reducer만 바꾼다.
- external COMP3 interface 유지.
- SBU latency 8 유지.
- DSP 0 유지.
- cycle count 유지.
- Montgomery-domain convention과 golden model equivalence를 먼저 확인.

Montgomery-domain 자체를 버리고 canonical/Solinas domain으로 옮기는 것은 blanking
실험이 아니라 arithmetic representation migration이며, 이번 결과는 그 migration만으로
TVLA pass 방향이 자동으로 열리지 않음을 보여준다.

## Decision rule

- Stage 4b worst `mldsa_intt ~= 112.877`보다 낮아야 accept 후보.
- `mldsa_intt` peak index 123이 커지면 reject에 가깝게 본다.
- ML-KEM만 좋아지고 ML-DSA가 악화하면 informative result로 보존한다.
- 좋은 branch는 `ORDER_SEED=0xC0DEC` key repeat를 한다.

## 최종 권고

Stage 6b 결과는 여전히 중요한 관찰이다. 하지만 후속 matrix와 Solinas branch까지 보면,
현재 범위의 inactive public dummy switching이나 arithmetic baseline 교체만으로
six-op TVLA pass 후보가 나오지는 않았다. 다음 큰 방향은 `mldsa_intt` peak 123과
`mlkem_pwm` peak 63을 cycle/net 단위로 더 좁히거나, 더 큰 범주의 masking/shuffling
설계를 별도 계획으로 분리하는 것이다.
