# Stage 3: DSA Reducer-Only PRD In ML-KEM Mode

## 목적

ML-KEM mode에서 inactive DSA Montgomery reducer switching만 따로 만든다. Stage 2와
비교해 DSA Karatsuba와 Montgomery reducer 중 어느 쪽이 ML-KEM TVLA shape를 더 크게
바꾸는지 본다.

## 구현 원칙

- ML-KEM mode:
  - KEM active output path는 real operand 유지.
  - inactive DSA Karatsuba input은 `0`.
  - DSA Montgomery reducer input에는 public PRD 기반 64-bit dummy를 넣는다.
- ML-DSA mode:
  - DSA active path는 real operand 유지.
  - KEM inactive path는 Stage 4b와 동일하게 둔다.
- output mux는 변경하지 않는다.

## 실행 기록

- diagnostics:
  - `check_phoenix_consistency.py`: PASS
  - `check_bank_conflicts.py`: PASS
- Verilator:
  - `tb_comp3_agile_modmul`
  - `tb_superbutterfly_all_modes`
  - `tb_phoenix_core`
  - `tb_phoenix_host_io`
  - `tb_phoenix_cw305_wrapper`
  - `tb_phoenix_mldsa_pwm_io`
  - 결과: PASS, `tb_phoenix_mldsa_pwm_io cycles=140`
- Vivado 30ns build:
  - WNS/TNS: `-0.466 ns / -6.323 ns`
  - WHS/THS: `0.102 ns / 0.000 ns`
  - LUT/FF/RAMB36/DSP: `10098 / 3343 / 8 / 0`
- artifact:
  - `../../../reports/tvla/comp3_internal_stage3_dsa_reducer_only_prd_260521/phoenix_comp3_stage3_dsa_reducer_only_prd_timing_fail.bit`
  - `../../../reports/tvla/comp3_internal_stage3_dsa_reducer_only_prd_260521/phoenix_comp3_stage3_dsa_reducer_only_prd_timing_fail.rpt`
  - `../../../reports/tvla/comp3_internal_stage3_dsa_reducer_only_prd_260521/phoenix_comp3_stage3_dsa_reducer_only_prd_impl_util.rpt`
  - `../../../reports/tvla/comp3_internal_stage3_dsa_reducer_only_prd_260521/rtl_stage3_dsa_reducer_only_prd_timing_fail.patch`

## TVLA 결과

실행하지 않았다. 30ns timing fail이므로 Stage 4b control과 공정하게 비교할 수 있는
CW305 TVLA 후보가 아니다.

## 판단

Reject on timing.

이 실험은 inactive DSA Montgomery reducer input 앞에 64-bit PRD mux를 추가한다.
기능은 깨지지 않았지만 WNS `-0.466 ns`로 timing을 만족하지 못했다. 따라서 이 방향은
그 자체로는 사용할 수 없고, reducer-only dummy를 다시 보려면 mux를 reducer 내부의 더
늦은/작은 cone으로 쪼개거나 registered/predecoded dummy selector를 따로 설계해야 한다.
