# ML-KEM / ML-DSA 리팩터 계획

날짜: 2026-05-19 KST

## 목표

복사한 PHOENIX FPGA 프로젝트를 ML-KEM과 ML-DSA의 NTT 계열 다항식 연산을
위한 RTL 우선 가속기로 전환한다. 첫 번째 milestone은 RTL과 시뮬레이션
정합성이다. CW305 bitstream 및 부채널 capture 전환은 이후 단계에서 다룬다.

## 인터페이스 결정

- 9비트 instruction word는 유지한다.
- `instr[8:7]`는 scheme field로만 사용한다.
  - `00`: ML-KEM
  - `01`: ML-DSA
  - `10`, `11`: 예약, 미지원
- 지원 opcode:
  - `0100`: forward NTT
  - `0001`: inverse NTT
  - `0010`: pointwise multiply
- ML-KEM 메모리는 32비트 워드당 16비트 계수 2개를 유지한다.
- ML-DSA 메모리는 32비트 워드당 정규화된 Montgomery residue 1개를 사용한다.

원 PHOENIX에서는 상위 2비트가 알고리즘과 보안레벨을 함께 담았다. 그러나
원 논문 Remark 2는 ML-KEM의 세 보안레벨이 단일 NTT/INTT/PWM 실행에서는
같은 polynomial size를 쓰므로 같은 실행으로 처리된다고 설명한다. ML-DSA도
이 리팩터가 다루는 primitive NTT/PWM 관점에서는 세 파라미터 세트가 같은
`n=256`, `q=8380417` 구조를 공유하므로, 보안레벨을 명령어에 중복 인코딩하지
않는다.

## Bottom-Up 작업 순서

1. 복사 상태를 문서화하고 불필요한 퇴역 산출물을 제거한다.
2. 예전 binary-field 경로를 ML-DSA modular arithmetic으로 교체한다.
3. COMP3를 ML-DSA 정수 schoolbook piece와 Montgomery reduction으로 재구성한다.
4. SBU mode를 ML-KEM 및 ML-DSA CT/GS/PWM 동작만 포함하도록 정리한다.
5. 최상위 control, constant memory, writeback, CW305 문서를 갱신한다.
6. Golden model과 testbench를 새 scheme 인코딩에 맞춘다.
7. 정적 cleanup check, Verilator simulation, Vivado no-DSP synthesis를 수행한다.

## 수용 기준

- 활성 RTL에 퇴역 datapath가 남지 않는다.
- ML-KEM regression test가 계속 통과한다.
- ML-DSA add/sub/div2, Montgomery reduction, COMP3, SBU test가 통과한다.
- Simulation runner는 ML-KEM 및 ML-DSA test만 실행한다.
- Vivado no-DSP synthesis에서 `superbutterfly_sbu`와 `phoenix_top` 모두
  `DSPs = 0`이어야 한다.
- 구현 진행 상황과 검증 결과는 `docs/migration_log.md`에 계속 기록한다.
