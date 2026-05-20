# 이 리팩터를 위한 PHOENIX 논문 분석

날짜: 2026-05-19 KST

이 문서는 ML-KEM / ML-DSA 리팩터에 필요한 PHOENIX 논문의 근거를 정리한다.
원 논문 PDF는 `docs/reference/[eprint25]_PHOENIX MLKEM and HQC.pdf`에 보관한다.

## 원 PHOENIX의 핵심 구조

PHOENIX는 느슨하게 결합된 polynomial-multiplication accelerator이다. 원
논문의 핵심 아이디어는 하나의 SuperButterfly datapath를 ML-KEM NTT
butterfly over `Z_q`와 HQC additive-FFT butterfly over `F_2^32` 사이에서
공유하는 것이다.

이 리팩터에서 재사용할 수 있는 구조적 아이디어는 다음이다.

- 32비트 SBU datapath와 고정 8-cycle 외부 latency.
- 하나의 processing element 안에 두 개의 SBU 배치.
- memory-up 네 bank와 memory-down 네 bank로 나눈 in-place polynomial memory.
- bank conflict가 없도록 구성된 coefficient scheduler.
- NTT, inverse NTT, pointwise multiply를 고르는 짧은 instruction word.
- DSP를 쓰지 않는 multiplier/reduction 구조.

## 원 instruction field에 대한 근거

원본 RTL의 `/home/reo/Documents/Repository/phoenix-fpga/rtl/phoenix/phoenix_control_unit.v`
주석과 decode logic은 `instr[8:7]`를 다음처럼 사용했다.

| 비트 | 원 PHOENIX RTL 의미 |
|---|---|
| `00` | ML-KEM I/III/V |
| `01` | HQC-128 |
| `10` | HQC-192 |
| `11` | HQC-256 |

즉 원 설계가 단순히 1비트 `0/1`만 둔 것은 아니었다. 다만 그 2비트가
필요했던 이유는 code-based 쪽에서 security level에 따라 polynomial word
수가 달랐기 때문이다. 실제 원 RTL도 `00`일 때는 ML-KEM packed 128-word
layout, `01`일 때는 2048-word layout, `10/11`일 때는 4096-word layout을
선택했다.

논문 Figure 11 설명도 instruction field를 `algo`, `security level`, `u/d`,
`addr`, `opcode`로 나누며, `algo`는 cryptosystem 선택, `security level`은
선택된 cryptosystem의 보안레벨 지정이라고 설명한다.

또한 논문 Remark 2는 ML-KEM의 세 보안레벨이 모두 같은 polynomial size
`n = 256`을 쓰며, 단일 NTT, INTT, PWM 실행은 세 레벨에서 같다고 명시한다.
따라서 원 PHOENIX에서도 ML-KEM 쪽은 `00` 하나로 충분했다.

## 새 설계의 instruction 결정

새 설계는 ML-KEM과 ML-DSA만 지원한다. ML-DSA의 세 파라미터 세트는 전체
알고리즘의 vector/matrix 차원은 다르지만, 이 RTL이 노출하는 단일 polynomial
primitive 관점에서는 `n = 256`, `q = 8380417`, 같은 NTT/INTT/PWM 구조를
공유한다.

그래서 `instr[8:7]`는 다음처럼 줄인다.

| 비트 | 새 설계 의미 |
|---|---|
| `00` | ML-KEM |
| `01` | ML-DSA |
| `10` | 예약, 미지원 |
| `11` | 예약, 미지원 |

이렇게 하면 기존 9비트 명령어 shape는 유지하면서도, 필요 없는 세부
파라미터 분기를 scheduler, testbench, host wrapper, 문서에 퍼뜨리지 않는다.

## 새 설계로 가져오지 않는 부분

현재 활성 가속기는 HQC 지원을 주장하지 않는다. 다음 항목은 논문 이해를 위한
역사적 참고로만 남긴다.

- additive FFT와 inverse additive FFT 지원.
- `F_2^32` XOR arithmetic.
- carryless multiplication과 `x^32+x^22+x^2+x+1` modulo carryless reduction.
- Cantor-basis M4R table 기반 HQC constant generation.
- HQC polynomial size 및 opcode variant.

## 새 설계 방향

새 가속기는 lattice-family arithmetic 공유 구조로 바뀐다.

- ML-KEM은 기존 `q=3329`의 16비트 2-lane modular datapath를 유지한다.
- ML-DSA는 `q=8380417`의 32비트 단일 계수 datapath를 추가한다.
- ML-DSA multiplication은 정수 schoolbook piece만 사용한다.
- ML-DSA product는 FIPS 204 Appendix A의 Montgomery reduction 지침을 따른다.

결론적으로 PHOENIX의 bottom-up datapath 공유 철학은 유지하지만, 수학적
대상은 ML-KEM/HQC에서 ML-KEM/ML-DSA로 바뀐다.
