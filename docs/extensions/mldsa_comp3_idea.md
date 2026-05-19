# ML-DSA COMP3 구현 메모

날짜: 2026-05-19 KST

이 문서는 활성 리팩터에 반영된 COMP3 아이디어를 기록한다.

## 산술 형태

ML-DSA는 `q = 8380417 = 0x7fe001`을 사용하므로 정규화된 residue는
23비트에 들어간다. RTL interface는 정렬을 위해 24비트 container를 쓰지만,
실제 multiplier split은 low 12비트와 high 11비트이다. 계수 곱의 raw product는
최대 46비트 범위에 있고 48비트 wire로 보관한다. 이는 32비트 워드 안에 16비트
곱 두 개를 독립적으로 담는 ML-KEM COMP3와 맞지 않는다.

구현 방향은 다음이다.

- ML-KEM COMP3는 16비트 lane 두 개의 독립 곱과 Barrett reduction을 유지한다.
- ML-DSA에는 12+11 split의 정수 Karatsuba 곱 경로를 추가한다.
- ML-DSA product는 `QINV = 58728449`를 사용하는 Montgomery reduction으로 줄인다.
- 외부 SBU latency는 8 cycle로 유지한다.

근거:

- FIPS 204 Table 1은 세 ML-DSA parameter set 모두에서 같은 `q = 8380417`과
  `zeta = 1753`을 사용한다.
- FIPS 204 Appendix A의 MontgomeryReduce는 `QINV = 58728449`와 `2^32`
  radix를 사용한다.
- `q - 1 = 0x7fe000`이므로 정상 입력의 bit 23은 항상 0이다. 따라서
  Karatsuba split은 `a = a0 + 2^12 * a1`, `a0` 12비트, `a1` 11비트가 된다.

## 검증 hook

활성 check는 다음과 같다.

- `tb_mldsa_karatsuba24.sv`: raw 23비트 product 구조 확인.
- `tb_mldsa_montgomery_reduce.sv`: FIPS 방식 reduction 확인.
- `tb_comp3_agile_modmul.sv`: ML-KEM 및 ML-DSA COMP3 동작 확인.
- `tb_superbutterfly_all_modes.sv`: routed/reference SBU 일치 확인.
- `tb_phoenix_mldsa_pwm_io.sv`: `phoenix_top` memory-up/down을 통한 256-word
  ML-DSA pointwise multiplication 입출력 확인.
