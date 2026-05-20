# Stage 7 ML-DSA Solinas Arithmetic Baseline 계획

작성일: 2026-05-21 KST

## 결론

Stage 7은 **Stage 4b blanking을 유지한 채 ML-DSA arithmetic representation만
normal-domain Solinas-style reduction으로 바꾼 새 arithmetic baseline**이다.
이 실험은 masking/shuffling이 아니며, Stage 6b의 inactive dummy 결과를 버리지 않고
다음 질문으로 넘기기 위한 분리 실험이다.

핵심 주의점은 하나다.

```text
Montgomery reducer만 Solinas reducer로 단순 교체하면 안 된다.
ML-DSA zeta ROM, operand generation, golden model을 같은 normal-domain으로 맞춰야 한다.
```

기존 Stage 4b RTL은 `constant_memory.v`에서 ML-DSA zeta를 Montgomery form으로
저장하고, `comp3_agile_modmul.v`에서 `mldsa_montgomery_reduce`를 사용했다. FIPS
204의 MontgomeryReduce는 `a * 2^-32 mod q`를 계산하며 `QINV=58728449`를 사용한다.
Dilithium reference도 같은 구조다.

따라서 기존 Montgomery zeta/input에 normal-domain Solinas reducer만 꽂으면 곱셈
결과에 Montgomery factor가 남아 기능이 틀어진다.

## 왜 실험할 가치가 있는가

Stage 4b는 baseline 대비 worst를 낮췄지만 TVLA pass는 아니다.

```text
baseline worst: mldsa_pwm 144.055
Stage 4b worst: mldsa_intt 112.877
```

Stage 6b는 COMP3 inactive cone에 public PRD dummy를 넣었을 때 ML-KEM을 크게
개선했지만, ML-DSA는 악화 또는 정체했다.

```text
mlkem_ntt:   96.516 -> 29.532
mlkem_intt:  42.888 -> 27.140
mlkem_pwm:  103.869 -> 52.516

mldsa_intt: 112.877 -> 121.557
mldsa_pwm:   78.170 -> 85.713
```

즉 남은 큰 peak는 선택되지 않은 cone보다 **선택된 ML-DSA active arithmetic path**와
더 관련 있어 보인다. 특히 `mldsa_intt` peak index 123이 Stage 4b와 Stage 6b에서
계속 남았다는 점이 중요하다.

ML-DSA modulus는 다음 pseudo-Mersenne 형태다.

```text
q = 8380417 = 2^23 - 2^13 + 1
2^23 == 2^13 - 1 (mod q)
```

그래서 `mldsa_karatsuba24`의 48-bit product를 radix `2^23` 기준으로 접는
Solinas-style reduction을 만들 수 있다. 이 branch가 좋아지면 Montgomery
reduction/correction cone이 주요 원인이었을 가능성이 커지고, 좋아지지 않아도
active arithmetic leakage가 더 깊은 문제라는 근거가 된다.

## 구현 정의

Stage 7 current implementation:

- 기준: Stage 4b restored RTL.
- 유지: 9-bit instruction, SBU latency 8, two-SBU PE, scheduler, memory layout,
  cycle count, Stage 4b blanking.
- 변경: ML-DSA COMP3 path만 `mldsa_karatsuba24 -> mldsa_solinas_reduce_48`.
- 변경: ML-DSA zeta ROM을 Montgomery form이 아니라 normal-domain `zeta`,
  inverse는 `-zeta mod q`로 저장.
- 변경: Python golden, diagnostics, Verilator golden, TVLA operand generation을
  ML-DSA normal-domain 기준으로 맞춤.
- 유지: ML-KEM path.
- 유지: legacy `mldsa_montgomery_reduce` module/test는 비교와 회귀용으로 남김.

## 실행 순서

1. Stage 4b control bitstream은 `MLDSA_DOMAIN=montgomery`로 TVLA를 다시 찍는다.
2. Stage 7 Solinas RTL은 diagnostics, Verilator, CW305 30ns bitstream build를 통과해야 한다.
3. Stage 7 six-op TVLA는 `MLDSA_DOMAIN=normal`로 찍는다.
4. 개선 후보면 `mldsa_intt`, `mldsa_pwm`, `mlkem_pwm`을 `ORDER_SEED=0xC0DEC`로 repeat한다.
5. 기능/timing clean이고 ML-DSA가 크게 악화되지 않으면 Stage 7 위에서 COMP3 inactive
   PRD dummy를 다시 적용한다.
6. Stage 7이 유효하면 historical baseline, Stage 1, Stage 2, Stage 3g, Stage 4a,
   Stage 4b 대표 지점에 Solinas patch를 적용해 ladder를 재측정한다.

## 판단 기준

- Accept 후보: Stage 4b worst `mldsa_intt ~= 112.877`보다 낮아야 한다.
- Reject: 기능 불일치, timing fail, ML-DSA worst 악화, peak index 123이 유지되며
  값만 커지는 경우.
- ML-KEM이 크게 변하면 ML-KEM RTL은 바뀌지 않았으므로 placement/routing artifact
  가능성을 별도 표기한다.

## 2026-05-21 실행 결과

Stage 7 Solinas baseline은 구현, diagnostics, Verilator, 30ns bitstream build는
통과했지만 TVLA는 rejected/informative로 판정했다.

검증:

- `check_phoenix_consistency.py`: PASS
- `check_bank_conflicts.py`: PASS
- 핵심 Verilator regression: PASS
- CW305 30ns timing: WNS 0.942 ns, TNS 0, WHS 0.068 ns, THS 0
- Utilization: LUT 9016, FF 3233, RAMB36 8, DSP 0

TVLA:

| Operation | Stage 4b | Stage 7 Solinas | 판단 |
|---|---:|---:|---|
| `mlkem_ntt` | 96.516 | 96.944 | 거의 동일 |
| `mlkem_intt` | 42.888 | 153.768 | 크게 악화 |
| `mlkem_pwm` | 103.869 | 96.676 | 소폭 개선 |
| `mldsa_ntt` | 85.738 | 103.679 | 악화 |
| `mldsa_intt` | 112.877 | 151.292 | worst 악화, peak 123 유지 |
| `mldsa_pwm` | 78.170 | 71.399 | 개선 |

결론:

```text
Stage 7 Solinas baseline = rejected / informative
```

이 결과는 “ML-DSA Montgomery reduction을 normal-domain Solinas로 바꾸면 자동으로
좋아질 것”이라는 가설을 기각한다. 특히 `mldsa_intt` peak 123이 유지되면서 값이
커졌으므로, 남은 문제는 단순 reduction 알고리즘보다 active INTT arithmetic/window,
placement/routing coupling, 또는 더 큰 masking/shuffling 설계와 관련될 가능성이 크다.

주의: 2026-05-21 후속 작업에서 source는 Stage 4b restored RTL로 복구했다. Solinas
전용 문서 폴더는 삭제했고, raw TVLA artifact는
`reports/tvla/stage7_solinas_stage4b_260521/`에 보존한다.

## 참고

- FIPS 204: <https://nvlpubs.nist.gov/nistpubs/fips/nist.fips.204.pdf>
- Dilithium reference `reduce.c`: <https://github.com/pq-crystals/dilithium/blob/master/ref/reduce.c>
