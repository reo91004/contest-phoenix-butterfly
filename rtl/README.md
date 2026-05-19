# RTL 지도

이 RTL tree는 PHOENIX에서 파생한 CW305 datapath 위에서 ML-KEM과 ML-DSA의
다항식 산술을 수행하도록 정리되어 있다.

## Scheme mode

- `opmode=0`: ML-KEM, 32비트 워드마다 16비트 lane 두 개.
- `opmode=1`: ML-DSA, 32비트 워드마다 정규화된 Montgomery residue 한 개.

## 명칭 정책

- `kyber_*` prefix는 원 코드에서 이어진 ML-KEM arithmetic module 이름이다.
- 새로 추가한 signature 쪽 RTL은 FIPS 204의 공식 이름을 따라 `mldsa_*` prefix를
  사용한다.
- CRYSTALS-Dilithium은 ML-DSA의 전신 이름이지만, 활성 interface와 문서는
  표준명인 ML-DSA를 기준으로 둔다. 명칭만 맞추기 위해 `mldsa_*`를
  `dilithium_*`으로 바꾸지는 않는다.

## 주요 block

| 영역 | 역할 |
|---|---|
| `common/` | 전역 상수, SBU mode code, delay/counter helper |
| `arith/` | ML-KEM lane arithmetic 및 ML-DSA modular arithmetic |
| `mul/` | 정수 schoolbook multiplier와 ML-DSA 12+11 split 곱 조합 |
| `reduce/` | ML-KEM Barrett 및 ML-DSA Montgomery reduction |
| `comp/` | 공유 COMP1/2/3/4 arithmetic block |
| `sbu/` | routed/reference SuperButterfly unit |
| `phoenix/` | scheduler, memory, constant ROM, control FSM, top-level core |

## 지원 SBU 연산

- ML-KEM: `SBU_NTT_CT`, `SBU_INTT_GS`, `SBU_PWM0`, `SBU_PWM1`, `SBU_MOD_ADD`.
- ML-DSA: `SBU_MLDSA_NTT`, `SBU_MLDSA_INTT`, `SBU_MLDSA_PWM`.

Routed SBU의 외부 latency는 8 cycle을 유지한다.
