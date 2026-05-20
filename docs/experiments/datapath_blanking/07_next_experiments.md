# Stage 7 이후 후속 실험 계획

## 질문

Stage 6b가 ML-KEM에서 매우 좋은 결과를 냈기 때문에 두 질문이 생겼다.

1. ML-DSA Montgomery reduction을 Solinas-style reduction으로 바꾸면 ML-DSA도 좋아질까?
2. COMP1/2/3/4 모두에 public random dummy를 넣어보는 실험은 의미가 있을까?

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

## Stage 7 제안: COMP1/2/3/4 public dummy matrix

기준은 반드시 Stage 4b다. Stage 6b 위에 쌓지 않는다.

공통 invariant:

- 9-bit instruction 유지.
- SBU latency 8 유지.
- two-SBU PE 유지.
- memory layout, scheduler, cycle count 유지.
- active output mux 의미 유지.
- active arithmetic cone에는 dummy를 섞지 않음.
- dummy는 secret, fixed/random class, memory contents와 독립.

### Stage 7a: peak-to-cycle mapping

RTL 변경 없이 먼저 한다.

- Stage 4b `mldsa_intt` peak index 123이 어느 SBU pipeline stage와 맞는지 매핑.
- Stage 4b `mlkem_pwm` peak index 63도 함께 매핑.
- COMP1/2/3/4 중 어느 block이 해당 window에 있는지 VCD/SAIF 또는 debug trace로 확인.

### Stage 7b: COMP2 unused-input PRD dummy

Stage 4b에서 COMP2는 INTT가 아닐 때 input이 zero다. 이 zero 대신 valid-cycle
public PRD dummy를 넣어 NTT/PWM active peak가 낮아지는지 본다.

### Stage 7c: COMP4 unused-input PRD dummy

Stage 4b에서 COMP4는 NTT, ML-KEM INTT exception, PWM1에서만 real input을 받는다.
나머지 valid cycle에 public PRD dummy를 넣는다. ML-KEM INTT exception은 유지한다.

### Stage 7d: COMP1 unused-input PRD dummy

output mux가 COMP1을 쓰지 않는 valid cycle에만 COMP1 input을 public PRD dummy로
바꾼다. 특히 ML-DSA PWM 주변 leakage shape를 본다.

### Stage 7e: COMP3 inactive-cone PRD dummy v2

Stage 6b를 다시 하되 control을 더 명확히 둔다.

- ML-KEM mode: active KEM cone real, inactive DSA cone PRD dummy.
- ML-DSA mode: active DSA cone real, inactive KEM cone PRD dummy.
- PRD LFSR advance는 valid COMP3 transaction에만 제한.

## Stage 8 제안: ML-DSA Solinas-style reducer

Stage 7 이후에도 `mldsa_intt` peak 123이 남으면 Stage 8에서 ML-DSA active reducer를
바꿔 본다.

조건:

- `comp3_agile_modmul.v`의 ML-DSA reducer만 바꾼다.
- external COMP3 interface 유지.
- SBU latency 8 유지.
- DSP 0 유지.
- cycle count 유지.
- Montgomery-domain convention과 golden model equivalence를 먼저 확인.

만약 Montgomery-domain 자체를 버리고 canonical/Solinas domain으로 옮긴다면, 그것은
blanking 실험이 아니라 arithmetic representation migration이다.

## Decision rule

- Stage 4b worst `mldsa_intt ~= 112.877`보다 낮아야 accept 후보.
- `mldsa_intt` peak index 123이 커지면 reject에 가깝게 본다.
- ML-KEM만 좋아지고 ML-DSA가 악화하면 informative result로 보존한다.
- 좋은 branch는 `ORDER_SEED=0xC0DEC` key repeat를 한다.

## 최종 권고

Stage 6b 결과는 버리기 아깝다. 하지만 그 결과는 Solinas-style reducer의 성공
증거가 아니라 inactive public dummy switching이 TVLA shape를 크게 바꿀 수 있다는
증거다. 따라서 다음 순서는 `peak mapping -> COMP1/2/3/4 public dummy matrix ->
Solinas-style reducer`가 가장 안전하다.
