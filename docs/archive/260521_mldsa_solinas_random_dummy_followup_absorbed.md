# ML-DSA Solinas Reduction과 COMP1/2/3/4 Random Dummy 후속 계획

작성일: 2026-05-21 KST

이 문서는 Stage 6 R2 결과를 보고 생긴 두 질문에 답한다.

1. R2가 ML-KEM에서 너무 좋았으니, ML-DSA Montgomery reduction을 Solinas-style
   reduction으로 바꾸면 ML-DSA도 좋아질까?
2. COMP1/2/3/4 모두에 random dummy를 넣어보는 실험은 의미가 있을까?

결론은 다음과 같다.

- Solinas-style reduction은 실험 가치는 있지만, R2 결과만으로 좋아질 것이라고
  결론낼 수 없다.
- 먼저 COMP1/2/3/4의 unused input 또는 inactive cone에 public PRD dummy를 넣는
  Stage 7 matrix 실험을 하는 것이 더 직접적이다.
- Solinas-style reduction은 Stage 7 이후 별도 branch에서 다루는 것이 맞다.

## R2 결과가 실제로 말해주는 것

R2는 COMP3 inactive cone 실험이었다. active arithmetic을 바꾼 실험이 아니다.

| Mode | active cone | R2가 건드린 cone |
|---|---|---|
| ML-KEM | KEM modular multiply/reduce | inactive DSA cone에 public PRD dummy |
| ML-DSA | DSA Montgomery multiply/reduce | inactive KEM cone에 public PRD dummy |

결과는 비대칭이었다.

| Operation | Stage 4b | R2 | 해석 |
|---|---:|---:|---|
| `mlkem_ntt` | 96.516 | 29.532 | 매우 큰 개선 |
| `mlkem_intt` | 42.888 | 27.140 | 큰 개선 |
| `mlkem_pwm` | 103.869 | 52.516 | 큰 개선 |
| `mldsa_ntt` | 85.738 | 82.381 | 거의 비슷 |
| `mldsa_intt` | 112.877 | 121.557 | 악화, peak 123 유지 |
| `mldsa_pwm` | 78.170 | 85.713 | 악화 |

따라서 R2의 메시지는 "ML-KEM arithmetic 자체가 고쳐졌다"가 아니다. 더 정확한
해석은 다음이다.

> ML-KEM active KEM cone 주변에서 inactive DSA cone의 public PRD switching이
> ML-KEM peak visibility를 크게 낮췄다. 그러나 ML-DSA active DSA cone,
> 특히 INTT의 stable peak는 그대로 남았다.

그래서 R2 결과는 버리기 아깝다. 하지만 accepted RTL로 바로 넣기에는
ML-DSA worst가 Stage 4b보다 나쁘다.

## Montgomery를 Solinas-style로 바꾸면 좋아질까?

가능성은 있다. 하지만 R2 결과만으로는 "좋아질 것"이라고 말할 수 없다.

ML-DSA modulus는 다음 형태다.

```text
q = 8380417 = 0x7fe001 = 2^23 - 2^13 + 1
```

이 형태 때문에 Solinas-style folding reduction은 수학적으로 생각해볼 수 있다.
예를 들어 modulo `q`에서는 다음 관계를 사용할 수 있다.

```text
2^23 == 2^13 - 1 mod q
```

즉 46-48비트 product의 high part를 `2^13` shift와 subtract/add 형태로 접어
내리는 reducer를 만들 수 있다. Montgomery reduction처럼 `QINV=58728449`와
`2^32` radix를 쓰는 구조와는 다른 switching shape가 나올 가능성이 있다.

하지만 side-channel 관점에서는 세 가지 이유로 조심해야 한다.

첫째, R2가 개선한 것은 inactive cone switching이다. Solinas-style reducer는
ML-DSA selected active DSA cone 자체를 바꾸는 일이다. 실험 범주가 다르다.

둘째, 더 작거나 더 조용한 회로가 TVLA에서 항상 좋아지는 것은 아니다. Stage 5
B3에서 inactive COMP3 cone을 `0`으로 껐더니 ML-KEM PWM은 좋아졌지만
ML-DSA INTT/NTT가 크게 악화했다. switching을 줄이면 leakage도 줄 수 있지만,
물리적 noise가 줄어 active leakage가 더 선명해질 수도 있다.

셋째, active multiplier input은 여전히 secret-dependent다. Reducer만 바꾼다고
first-order leakage가 사라진다는 보장은 없다. 특히 `mldsa_intt` peak index
123이 Stage 4b와 R2에서 동일하게 남았다는 점은 active arithmetic window가
강하게 의심된다는 뜻이다.

따라서 현재 판단은 이렇다.

> Solinas-style ML-DSA reducer는 별도 실험 가치는 있지만, R2 다음의 1순위는
> 아니다. 먼저 R2가 보여준 "inactive public dummy switching" 효과를
> COMP1/2/3/4 전체로 체계적으로 분해해야 한다.

## COMP1/2/3/4 random dummy 실험은 의미가 있나?

의미가 있다. 다만 여기서 random dummy는 masking이 아니라 public dummy
switching이다. secret share를 만들거나 arithmetic masking을 하는 것이 아니다.

목표는 다음 질문을 분해하는 것이다.

> Stage 4b에서 unused COMP input을 `0`으로 조용히 만드는 대신, secret과 무관한
> public PRD dummy를 넣어 switching shape를 유지하면 TVLA peak visibility가
> 낮아지는가?

이 실험은 R2와 논리적으로 이어진다.

- R2는 COMP3 inactive algorithm cone에 public PRD dummy를 넣었다.
- ML-KEM에서는 아주 좋았다.
- ML-DSA에서는 active DSA cone peak가 남았다.
- 그러면 COMP1/2/4에서도 "zero blanking이 너무 조용해서 active peak가
  선명해진 것인지"를 볼 가치가 있다.

## Stage 7 제안: COMP1/2/3/4 public PRD dummy matrix

기준은 반드시 Stage 4b다. R2 위에 쌓지 않는다.

공통 invariant:

- 9-bit instruction 유지.
- SBU latency 8 유지.
- two-SBU PE 유지.
- memory layout, scheduler, cycle count 유지.
- active output mux 의미 유지.
- active arithmetic cone에는 dummy를 섞지 않음.
- dummy는 secret, fixed/random class, memory contents와 독립.

공통 TVLA command:

```bash
OUTDIR=reports/tvla/<stage7_branch_name> \
OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' \
TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0x5EED \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```

공통 verification:

```bash
python3 scripts/diagnostics/check_phoenix_consistency.py
python3 scripts/diagnostics/check_bank_conflicts.py
bash sim/run_verilator.sh 'tb_comp3_agile_modmul tb_superbutterfly_all_modes tb_phoenix_core tb_phoenix_host_io tb_phoenix_cw305_wrapper tb_phoenix_mldsa_pwm_io'
```

### Stage 7A: peak-to-cycle mapping

RTL 변경 없이 먼저 한다.

- Stage 4b `mldsa_intt` peak index 123이 어느 SBU pipeline stage와 맞는지 매핑한다.
- Stage 4b `mlkem_pwm` peak index 63도 같이 매핑한다.
- COMP1/2/3/4 중 어떤 block이 해당 window에 있는지 VCD/SAIF 또는 debug trace로 본다.

이 작업은 dummy를 어디에 넣을지 줄여준다. max `|t|`만 보고 RTL을 계속 바꾸면
placement artifact와 실제 leakage를 구분하기 어렵다.

### Stage 7B1: COMP2 unused-input PRD dummy

Stage 4b에서 COMP2는 INTT가 아닐 때 input을 `0`으로 둔다.

실험:

- `sel1`이 `SBU_INTT_GS` 또는 `SBU_MLDSA_INTT`이면 기존처럼 real input.
- 그 외 valid cycle에서 COMP2 input에 public PRD dummy를 넣는다.
- invalid-cycle behavior는 Stage 4b 그대로 둔다.

목적:

- Stage 4b의 COMP2 zero blanking이 너무 조용해서 NTT/PWM active peak를
  선명하게 만든 것인지 확인한다.

### Stage 7B2: COMP4 unused-input PRD dummy

Stage 4b에서 COMP4는 NTT, ML-KEM INTT 예외, PWM1에서만 real input을 받는다.

실험:

- `SBU_NTT_CT`, `SBU_MLDSA_NTT`, `SBU_INTT_GS`, `SBU_PWM1`은 기존 real input 유지.
- 그 외 valid cycle에서 COMP4 input에 public PRD dummy를 넣는다.
- ML-KEM INTT COMP4 exception은 반드시 유지한다.

목적:

- Stage 4b가 COMP4를 zero로 끈 operation에서 dummy switching이 ML-DSA 또는
  ML-KEM peak를 낮추는지 확인한다.

### Stage 7B3: COMP1 unused-input PRD dummy

Stage 4b에서 COMP1은 대부분의 operation에서 쓰이지만 ML-DSA PWM에서는 output
mux가 `p6`만 사용한다.

실험:

- output mux가 COMP1을 사용하는 operation은 real input 유지.
- output mux가 COMP1을 사용하지 않는 valid cycle에는 COMP1 input에 public PRD
  dummy를 넣는다.

목적:

- Stage 5 B2에서 ML-DSA PWM unused `a_i=0`가 local PWM에는 좋았지만 global
  worst를 악화시킨 이유를 더 세밀하게 본다.

### Stage 7B4: COMP3 inactive-cone PRD dummy v2

R2를 다시 하되, control을 더 명확히 둔다.

실험:

- ML-KEM mode: active KEM cone real, inactive DSA cone PRD dummy.
- ML-DSA mode: active DSA cone real, inactive KEM cone PRD dummy.
- PRD LFSR advance 조건을 valid COMP3 transaction에만 제한한다.
- 동일 branch에서 replay control을 섞지 않는다.

목적:

- R2의 ML-KEM 개선을 재현하고, implementation/control을 더 명확히 한다.

### Stage 7C: accepted-only combination

B1/B2/B3/B4 중 개별 branch에서 Stage 4b worst를 악화시키지 않고 의미 있게 좋아진
것만 조합한다.

조합 규칙:

- 개별 reject된 branch는 조합하지 않는다.
- 한 operation만 좋아지고 `mldsa_intt` peak 123이 악화되면 reject한다.
- 조합 branch도 Stage 4b와 full A/B 비교하고, 개선되면 key repeat를 한다.

## Solinas-style reducer는 언제 할까?

Solinas-style reducer는 Stage 7 이후 별도 Stage 8로 다룬다.

Stage 8의 최소 조건:

- `comp3_agile_modmul.v`의 ML-DSA reducer만 바꾼다.
- external COMP3 interface는 유지한다.
- SBU latency 8 유지.
- DSP 0 유지.
- cycle count 유지.
- ML-DSA modular product가 기존 Montgomery-domain convention과 정확히 맞아야 한다.
- `tb_mldsa_montgomery_reduce`에 해당하는 새 equivalence test를 먼저 만든다.

주의할 점:

- Montgomery-domain 전체 convention을 바꾸면 constant memory, host encoding,
  golden model, TVLA vector 생성까지 다 바뀐다.
- 그래서 첫 실험은 "interface-equivalent reducer replacement"여야 한다.
- 만약 Montgomery-domain을 버리고 Solinas canonical domain으로 옮기려면, 그것은
  blanking 실험이 아니라 arithmetic representation migration이다.

## Decision rule

Stage 7/8 모두 다음 기준으로 판단한다.

- Stage 4b worst `mldsa_intt ~= 112.877`보다 worst가 낮아야 accept 후보.
- `mldsa_intt` peak index 123이 커지면 reject에 가깝게 본다.
- ML-KEM만 좋아지고 ML-DSA가 악화하면 accepted RTL이 아니라 informative result로 보존한다.
- 좋은 branch는 `ORDER_SEED=0xC0DEC` key repeat를 한다.
- 모든 결과는 `docs/datapath_blanking_experiment.md`에 즉시 기록한다.

## 최종 권고

R2 결과는 버리기 아깝다. 하지만 그것은 "ML-KEM 주변 inactive cone dummy
switching이 TVLA shape를 크게 바꿀 수 있다"는 강한 신호이지, "ML-DSA reducer를
바꾸면 해결된다"는 증거는 아니다.

따라서 다음 순서는 다음이 가장 합리적이다.

1. Stage 7A로 peak-to-cycle mapping을 한다.
2. COMP1/2/3/4 public PRD dummy matrix를 Stage 4b 기준으로 하나씩 실행한다.
3. ML-KEM 개선과 ML-DSA 악화를 분리해서 accept/reject한다.
4. 그래도 `mldsa_intt` peak 123이 남으면, Stage 8에서 ML-DSA active reducer
   자체를 Solinas-style 후보로 바꿔 본다.

이 순서가 R2의 좋은 신호를 살리면서도, active arithmetic leakage와 inactive
dummy hiding을 섞어 해석하는 위험을 가장 줄인다.
