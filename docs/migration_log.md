# 마이그레이션 로그

날짜: 2026-05-19 KST

## 0단계: 복사와 baseline

- `/home/reo/Documents/Repository/phoenix-fpga`의 추적 source material을
  `/home/reo/Documents/Repository/sca-2026-phoenix`로 복사했다.
- 기존 CW305 Vivado project file
  `boards/cw305/vivado_project/phoenix_cw305.xpr`를 보존했다.
- 복사 전에 source repository가 clean 상태임을 확인했다.

## 1단계: RTL 방향 결정

- 활성 설계는 예전 binary-field transform 동작을 제거한다.
- `opmode=0`은 ML-KEM, `opmode=1`은 ML-DSA로 정의한다.
- ML-DSA 계수는 `8380417` modulo의 정규화된 Montgomery residue로 표현한다.
- ML-DSA용 COMP3는 정수 schoolbook piece만 사용한다.

## 2단계: RTL 리팩터

- `rtl/common/phoenix_defs.vh`에 ML-DSA 상수를 추가했다.
- SBU mode bit `sel[8]`을 ML-DSA 선택으로 재정의하고 ML-DSA NTT, INTT,
  PWM SBU mode를 추가했다.
- 예전 binary-field arithmetic path를 다음 ML-DSA path로 교체했다.
  - `rtl/arith/mldsa_modadd32.v`
  - `rtl/arith/mldsa_modsub32.v`
  - `rtl/arith/mldsa_div2_32.v`
  - `rtl/arith/mldsa_modarith32.v`
  - `rtl/mul/mldsa_karatsuba24.v`
  - `rtl/reduce/mldsa_montgomery_reduce.v`
- COMP1/2/3/4는 ML-KEM의 packed 16비트 lane arithmetic을 유지하고,
  ML-DSA에는 32비트 단일 계수 lane을 사용하도록 정리했다.
- SBU routed/reference 동작은 ML-KEM CT/GS/PWM 및 ML-DSA CT/GS/PWM만 다룬다.
- `phoenix_control_unit`, `constant_memory`, `phoenix_top`, writeback,
  CW305 wrapper 문서를 256-word ML-DSA polynomial layout에 맞췄다.

## 3단계: Cleanup

- 퇴역 RTL module, 예전 generated report, 발표/보고서 초안, 비활성 capture 및
  experiment script를 제거했다.
- 모든 활성 `rtl/` source와 CW305 project file
  `boards/cw305/vivado_project/phoenix_cw305.xpr`를 보존했다.
- Top-level README, RTL/testbench/CW305 문서, Python golden helper, diagnostics를
  ML-KEM / ML-DSA 기준으로 다시 작성했다.

## 4단계: 검증 snapshot

2026-05-19 KST에 실행한 command:

```bash
python3 scripts/diagnostics/check_bank_conflicts.py
python3 scripts/diagnostics/check_phoenix_consistency.py
bash sim/run_verilator.sh
verilator --lint-only -sv -Wno-fatal -Irtl/common \
  rtl/common/*.v rtl/arith/*.v rtl/mul/*.v rtl/reduce/*.v \
  rtl/comp/*.v rtl/sbu/*.v rtl/phoenix/*.v --top-module phoenix_top
```

결과:

- Scheduler diagnostics: ML-KEM 128-word 및 ML-DSA 256-word layout 통과.
- Consistency diagnostics: 통과.
- Verilator suite: exit 0. `tb_barrett_reduce`는 standalone harness가
  `checks=0`을 출력하므로 inconclusive로 분류하지만, Barrett 동작은 COMP3와
  SBU test에서 계속 검증된다.
- Top lint: exit 0, nonfatal width warning만 존재.
- Static cleanup: 활성 file에서 퇴역 datapath token이 남지 않음.

당시 `tb_phoenix_core` cycle smoke:

| Operation | Cycles |
|---|---:|
| `mlkem_ntt` | 248 |
| `mlkem_intt` | 248 |
| `mlkem_pwm` | 149 |
| `mldsa_ntt` | 538 |
| `mldsa_intt` | 538 |
| `mldsa_pwm` | 140 |

## 5단계: 문서 및 DSP audit

문서 audit:

- `docs/`에는 활성 planning/progress note와 원 논문 PDF만 남긴다.
  - `docs/phoenix_paper_analysis.md`
  - `docs/mlkem_mldsa_refactor_plan.md`
  - `docs/migration_log.md`
  - `docs/extensions/mldsa_comp3_idea.md`
  - 원 PHOENIX 논문 PDF
- 예전 transfer note, presentation, report, LaTeX, 비활성 capture,
  비활성 experiment file은 제거된 상태다.
- 남은 `docs/` file은 모두 현재 설계 근거 또는 진행 기록으로 필요하다.

정합성 근거:

- `rtl/phoenix/phoenix_control_unit.v`는 `instr[8:7]`를 ML-KEM/ML-DSA scheme
  선택으로 해석하고, NTT/INTT/PWM opcode만 지원한다.
- ML-DSA layout은 같은 control unit에서 `poly_size_minus1=255`,
  `last_layer=7`로 구현되어 있다.
- COMP1/2/3/4에서 `opmode=1`은 ML-DSA를 선택하고, ML-KEM은 packed 16비트
  lane을 유지한다.
- ML-DSA 상수는 `rtl/common/phoenix_defs.vh`에 있다:
  `MLDSA_Q=8380417`, `MLDSA_QINV=58728449`, `MLDSA_R_MOD_Q=4193792`.
- COMP3는 `mldsa_karatsuba24`와 `mldsa_montgomery_reduce`를 사용한다.
- `phoenix_top`은 ML-DSA pointwise multiplication을 256 word에 대한 두 독립
  SBU 처리로 route하고, ML-KEM은 기존 cascaded two-step PWM path를 유지한다.

실행한 command:

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

결과:

- Static cleanup: 활성 file에서 퇴역 datapath token이 남지 않음.
- Scheduler diagnostics: 통과.
- Consistency diagnostics: 통과.
- Verilator suite: exit 0. `tb_barrett_reduce`는 위와 같은 이유로
  inconclusive 유지.
- Verilator top lint: exit 0, nonfatal width warning만 존재.
- Vivado 2025.2 no-DSP synthesis:
  - `superbutterfly_sbu`: `DSP primitive cell count = 0`, utilization report의
    `DSPs = 0`.
  - `phoenix_top`: `DSP primitive cell count = 0`, utilization report의
    `DSPs = 0`, `RAMB36E1 = 8`.

## 6단계: instruction 단순화와 한글 문서화

사용자 검토에 따라 `instr[8:7]`에 ML-DSA 세 파라미터 세트를 각각 넣는
초기 리팩터 결정을 재검토했다.

근거:

- 원 논문 Figure 11은 instruction을 `algo`, `security level`, `u/d`, `addr`,
  `opcode`로 설명한다.
- 원본 RTL은 `00`을 ML-KEM으로, 나머지 값을 보안레벨별 다른 layout으로
  해석했다.
- 원 논문 Remark 2는 ML-KEM의 세 보안레벨이 단일 NTT/INTT/PWM 실행에서는
  같은 polynomial size를 쓰므로 같은 실행이라고 명시한다.
- ML-DSA도 이 RTL이 제공하는 단일 polynomial primitive 기준으로는 세
  파라미터 세트가 같은 `n=256`, `q=8380417` 구조를 공유한다.

결정:

- `instr[8:7] = 00`: ML-KEM.
- `instr[8:7] = 01`: ML-DSA.
- `instr[8:7] = 10`, `11`: 예약, 미지원. Control unit은 빠르게 `done`으로
  종료한다.

수정:

- `rtl/phoenix/phoenix_control_unit.v`의 decode를 `reserved=instr[8]`,
  `scheme=instr[7]`로 단순화했다.
- `tb/tb_phoenix_core.sv`, `tb/tb_phoenix_host_io.sv`,
  `tb/tb_phoenix_cw305_wrapper.sv`의 instruction 생성 helper를 1비트 scheme
  기반으로 바꿨다.
- `tb/tb_phoenix_core.sv`에 `10`, `11` reserved-field smoke를 추가했다.
- `scripts/parse_cycles.py`의 expected cycle key를 `mldsa_ntt`,
  `mldsa_intt`, `mldsa_pwm`로 정리했다.
- 활성 Markdown 문서를 한국어로 갱신했다.

재검증:

```bash
python3 scripts/diagnostics/check_bank_conflicts.py
python3 scripts/diagnostics/check_phoenix_consistency.py
bash sim/run_verilator.sh tb_phoenix_core
bash sim/run_verilator.sh
verilator --lint-only -sv -Wno-fatal -Irtl/common \
  rtl/common/*.v rtl/arith/*.v rtl/mul/*.v rtl/reduce/*.v \
  rtl/comp/*.v rtl/sbu/*.v rtl/phoenix/*.v --top-module phoenix_top
cd synth
bash -ic 'vivado-on; vivado -mode batch -source vivado_synth_no_dsp.tcl -tclargs superbutterfly_sbu xc7a100tftg256-2'
bash -ic 'vivado-on; vivado -mode batch -source vivado_synth_no_dsp.tcl -tclargs phoenix_top xc7a100tftg256-2'
```

결과:

- `tb_phoenix_core`: `checks=8 errors=0 PASS`.
- Cycle smoke: `mlkem_ntt=248`, `mlkem_intt=248`, `mlkem_pwm=149`,
  `mldsa_ntt=538`, `mldsa_intt=538`, `mldsa_pwm=140`.
- 전체 Verilator suite: exit 0. `tb_barrett_reduce`는 기존처럼 standalone
  `checks=0`이라 inconclusive로 표시된다.
- Top lint: exit 0, 기존 width warning만 존재.
- Vivado 2025.2 no-DSP synthesis:
  - `superbutterfly_sbu`: `DSP primitive cell count = 0`, utilization report의
    `DSPs = 0`.
  - `phoenix_top`: `DSP primitive cell count = 0`, utilization report의
    `DSPs = 0`, `RAMB36E1 = 8`.

## 7단계: COMP3와 ML-DSA PWM I/O 재검증

사용자 검토에 따라 ML-KEM/Kyber 및 ML-DSA/Dilithium 명칭과 COMP3 구현을 다시
확인했다.

명칭 결정:

- 원 코드의 `kyber_*` prefix는 ML-KEM arithmetic module명으로 남아 있다.
- 새로 추가한 signature 쪽은 FIPS 204 표준명에 맞춰 `mldsa_*`를 사용한다.
- CRYSTALS-Dilithium이라는 이름으로 맞추는 방법도 가능하지만, 현재 저장소의
  활성 interface와 제출 문서는 ML-KEM/ML-DSA 표준명을 기준으로 한다. 따라서
  지금은 `mldsa_*`를 유지하고, 향후 명칭 정리 phase가 필요하면 `kyber_*`를
  `mlkem_*`로 바꾸는 쪽이 더 일관적이다.

COMP3 확인 및 수정:

- ML-KEM path는 기존처럼 32비트 word 안의 두 16비트 lane을 독립적으로 곱하고
  각 lane을 Barrett reduction한다.
- ML-DSA의 `q - 1 = 0x7fe000`이므로 정상 residue는 23비트이다.
- `rtl/mul/mldsa_karatsuba24.v`를 24비트 container 내부의 `low 12 + high 11`
  split으로 명시 수정했다.
- M0는 `12x12`, M1은 `11x11`, M2는 `(12+11)` sum을 받는 `13x13`
  schoolbook multiplier이다.
- `rtl/reduce/mldsa_montgomery_reduce.v`는 FIPS 204 Appendix A의
  `QINV=58728449`, radix `2^32` MontgomeryReduce 구조와 일치하며 결과를
  `0..q-1`로 normalize한다.

Pointwise multiplication 확인:

- ML-DSA PWM은 complete NTT domain의 coefficient-wise Montgomery
  multiplication으로 구현된다.
- `phoenix_top`은 ML-DSA PWM에서 memory-up을 operand A, memory-down을 operand
  B로 읽고, SBU0/SBU1 두 개로 index `i`, `i+1`을 병렬 처리한다.
- 결과는 memory-up의 같은 index로 writeback되고 memory-down은 보존된다.
- 이를 직접 검증하기 위해 `tb_phoenix_mldsa_pwm_io.sv`를 추가했다. 이 test는
  256개 Montgomery-domain residue를 memory-up/down에 preload하고, PWM 실행 후
  memory-up 256개 출력이 `MontgomeryReduce(up[i] * down[i])`와 모두 같은지
  확인한다. 동시에 memory-down 256개가 덮어써지지 않았는지도 확인한다.

재검증 command:

```bash
bash sim/run_verilator.sh tb_mldsa_karatsuba24
bash sim/run_verilator.sh tb_comp3_agile_modmul
bash sim/run_verilator.sh tb_phoenix_mldsa_pwm_io
bash sim/run_verilator.sh
python3 scripts/diagnostics/check_bank_conflicts.py
python3 scripts/diagnostics/check_phoenix_consistency.py
verilator --lint-only -sv -Wno-fatal -Irtl/common \
  rtl/common/*.v rtl/arith/*.v rtl/mul/*.v rtl/reduce/*.v \
  rtl/comp/*.v rtl/sbu/*.v rtl/phoenix/*.v --top-module phoenix_top
cd synth
bash -ic 'vivado-on; vivado -mode batch -source vivado_synth_no_dsp.tcl -tclargs superbutterfly_sbu xc7a100tftg256-2'
bash -ic 'vivado-on; vivado -mode batch -source vivado_synth_no_dsp.tcl -tclargs phoenix_top xc7a100tftg256-2'
```

결과:

- `tb_mldsa_karatsuba24`: `checks=200004 errors=0 PASS`.
- `tb_comp3_agile_modmul`: `checks=400006 errors=0 PASS`.
- `tb_phoenix_mldsa_pwm_io`: `cycles=140 checks=512 errors=0 PASS`.
- 전체 Verilator suite: exit 0. `tb_barrett_reduce`는 기존처럼 standalone
  `checks=0`이라 inconclusive로 표시된다.
- Scheduler diagnostics: ML-KEM/ML-DSA NTT/PWM bank conflict 및 offset check 통과.
- Consistency diagnostics: ML-KEM schedule/golden 및 ML-DSA zeta/Montgomery check 통과.
- Static cleanup: 퇴역 datapath token 및 오래된 ML-DSA level key가 활성 file에 없음.
- Top lint: exit 0, 기존 width warning만 존재.
- Vivado 2025.2 no-DSP synthesis:
  - `superbutterfly_sbu`: `DSP primitive cell count = 0`, utilization report의
    `DSPs = 0`, `Slice LUTs = 3108`.
  - `phoenix_top`: `DSP primitive cell count = 0`, utilization report의
    `DSPs = 0`, `RAMB36E1 = 8`, `Slice LUTs = 8668`.
