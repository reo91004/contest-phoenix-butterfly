# SCA 2026 PHOENIX 리팩터

이 저장소는 PHOENIX SuperButterfly RTL을 기반으로 한 ML-KEM / ML-DSA
가속기 리팩터의 활성 작업본이다. 원 논문은 설계 배경과 비교 기준으로만
`docs/`에 보관하고, 현재 구현 목표는 다음으로 바뀌었다.

- ML-KEM NTT, INTT, PWM: 기존과 같은 32비트 워드 안의 16비트 2-lane 형식.
- ML-DSA NTT, INTT, PWM: 32비트 워드당 계수 1개, `q = 8380417`의 정규화된
  Montgomery residue 형식.
- CW305와 맞는 9비트 명령어 형식 및 메모리 래퍼 유지.

1차 성공 기준은 RTL 및 시뮬레이션 정합성이다. CW305 bitstream closure와
부채널 계측 스크립트 전환은 이후 단계로 둔다.

## 명령어 워드

9비트 명령어 형식은 유지한다.

| 필드 | 의미 |
|---|---|
| `instr[8:7]` | scheme 선택 |
| `instr[6]` | memory-up / memory-down 선택 |
| `instr[5:2]` | opcode |
| `instr[1:0]` | 사전계산 시작 주소 offset |

`instr[8:7]`는 현재 다음처럼 해석한다.

| 비트 | 의미 |
|---|---|
| `00` | ML-KEM |
| `01` | ML-DSA |
| `10` | 예약, 미지원 |
| `11` | 예약, 미지원 |

ML-DSA의 세 파라미터 세트는 이 연산기에서 사용하는 primitive NTT/PWM의
`n`, `q`, zeta 체계가 같으므로 명령어에 따로 인코딩하지 않는다.

지원 opcode는 다음 세 개뿐이다.

| Opcode | 연산 |
|---|---|
| `0100` | NTT |
| `0001` | INTT |
| `0010` | PWM |

## 현재 구조

```text
sca-2026-phoenix/
├── docs/
│   ├── README.md
│   ├── handover/                  인수인계 및 실행 계획
│   ├── experiments/datapath_blanking/
│   │   ├── README.md              SCA 실험 요약
│   │   ├── 00_baseline.md
│   │   ├── 01_stage1.md
│   │   ├── 02_stage2.md
│   │   ├── 03_stage3.md
│   │   ├── 04_stage4.md           현재 RTL 기준 Stage 4b 설명
│   │   ├── 05_stage5.md
│   │   ├── 06_stage6.md
│   │   └── 07_next_experiments.md
│   ├── implementation/            RTL migration 및 구현 배경
│   ├── reference/                 논문 분석과 원 PHOENIX PDF
│   └── archive/                   흡수된 초안과 full raw ledger
├── rtl/
│   ├── common/   공통 상수, 카운터, 설정
│   ├── arith/    ML-KEM 및 ML-DSA modular add/sub/div2
│   ├── mul/      LUT 기반 정수 곱셈기
│   ├── reduce/   ML-KEM Barrett 및 ML-DSA Montgomery reduction
│   ├── comp/     COMP1/2/3/4 블록
│   ├── sbu/      routed/reference SuperButterfly unit
│   └── phoenix/  메모리, 스케줄러, 제어기, 최상위 코어
├── tb/           SystemVerilog testbench
├── model/        Python golden/reference helper
├── sim/          Verilator 실행 스크립트
├── boards/cw305/ CW305 wrapper 및 Vivado project flow
└── scripts/      진단 및 report parser
```

## 빠른 검증

```bash
python3 scripts/diagnostics/check_bank_conflicts.py
python3 scripts/diagnostics/check_phoenix_consistency.py
bash sim/run_verilator.sh
verilator --lint-only -sv -Wno-fatal -Irtl/common \
  rtl/common/*.v rtl/arith/*.v rtl/mul/*.v rtl/reduce/*.v \
  rtl/comp/*.v rtl/sbu/*.v rtl/phoenix/*.v --top-module phoenix_top

cd synth
bash -ic 'vivado-on; vivado -mode batch -source vivado_synth_no_dsp.tcl -tclargs superbutterfly_sbu xc7a100tftg256-2'
bash -ic 'vivado-on; vivado -mode batch -source vivado_synth_no_dsp.tcl -tclargs phoenix_top xc7a100tftg256-2'
```

CW305 project file은
`boards/cw305/vivado_project/phoenix_cw305.xpr`에 보존되어 있다.
`.runs`, `.cache`, `.sim`, log, bitstream 등 재생성 산출물은 보관 대상이 아니다.

## Vivado 2024.2 사용 메모

`boards/cw305/vivado_project/phoenix_cw305.xpr`는 특정 Vivado 버전과 project
경로 정보가 함께 저장되는 파일이다. 2025.2에서 저장된 `.xpr`를 2024.2용으로
맞출 때는 XML을 직접 고치기보다, 2024.2 환경에서 project를 재생성하는 방식이
안전하다.

```bash
cd boards/cw305
source <Vivado-2024.2>/Vivado/settings64.sh
vivado -mode batch -source create_phoenix_project.tcl
vivado vivado_project/phoenix_cw305.xpr
```

이 저장소는 IP/BD/XCI 없이 RTL과 Tcl flow로 구성되어 있으므로 2024.2에서
재생성하기 쉽다. 단, 다른 Vivado 버전에서 만든 `.runs`, `.cache`, `.sim`,
DCP, bitstream, report는 재사용하지 말고 같은 버전에서 다시 생성한다.
