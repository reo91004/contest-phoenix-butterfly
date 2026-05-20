# Stage 3: COMP2 Unused-Cycle PRD

## 목적

COMP2 output이 architectural output에 영향을 주지 않는 valid cycle에서 COMP2 input만
public PRD로 흔들어, unused calculation switching이 TVLA peak visibility를 낮추는지
확인한다.

## 구현 원칙

- `SBU_INTT_GS`, `SBU_MLDSA_INTT`에서는 COMP2가 실제 `comp2_y`를 만들므로 real input
  유지.
- NTT/PWM/MOD_ADD 등 COMP2 output이 선택되지 않는 valid cycle에만 PRD input 적용.
- output mux, scheduler, latency는 유지.

## 실행 기록

- RTL 변경:
  - `superbutterfly_sbu_routed.v`에 COMP2 unused-cycle용 public LFSR source 추가.
  - `SBU_INTT_GS`, `SBU_MLDSA_INTT`는 real `b1/a1` subtraction 유지.
  - 그 외 valid cycle에서는 `comp2_y`가 COMP3 operand로 쓰이지 않으므로 COMP2 input을
    public PRD로 대체.
- diagnostics:
  - `check_phoenix_consistency.py`: PASS
  - `check_bank_conflicts.py`: PASS
- Verilator:
  - 핵심 regression PASS
  - `tb_phoenix_mldsa_pwm_io`: `cycles=140`
- CW305 30ns build:
  - bitstream mtime: `2026-05-21 02:52:41 KST`
  - WNS `0.028 ns`, TNS `0.000 ns`
  - WHS `0.050 ns`, THS `0.000 ns`
  - LUT `10024`, FF `3340`, RAMB36 `8`, DSP `0`

TVLA command:

```bash
OUTDIR=reports/tvla/inactive_dummy_stage3_comp2_prd_260521 \
OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' \
TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0x5EED \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```

## TVLA 결과

![Stage 3 TVLA overview](../../../reports/tvla/inactive_dummy_stage3_comp2_prd_260521/mlkem_mldsa_tvla_overview.png)

Stage 3 vs Stage 1 control:

![Stage 3 vs Stage 1 control](../../../reports/tvla/inactive_dummy_stage3_comp2_prd_260521/comparison_vs_stage1_control.png)

| Operation | Stage 1 control | Stage 3 COMP2 PRD | peak index | cycles | clipping |
|---|---:|---:|---:|---:|---:|
| `mlkem_ntt` | 98.403 | 76.959 | 117 | 248 | 0 |
| `mlkem_intt` | 44.048 | 54.099 | 235 | 248 | 0 |
| `mlkem_pwm` | 104.827 | 128.534 | 63 | 149 | 0 |
| `mldsa_ntt` | 85.319 | 93.961 | 424 | 538 | 0 |
| `mldsa_intt` | 122.083 | 93.900 | 123 | 538 | 0 |
| `mldsa_pwm` | 74.604 | 76.621 | 105 | 140 | 0 |

## 판단

Rejected / informative.

COMP2 unused dummy는 `mldsa_intt` peak 123을 낮추는 데 효과가 있었다. 이 점은
ML-DSA INTT의 active window가 COMP2 pre-sub/div2 근처 switching shape에도 민감하다는
단서다.

하지만 `mlkem_pwm`이 `104.827 -> 128.534`로 악화되어 전체 worst가 Stage 1 control보다
커졌다. 따라서 단독 accept 및 Stage 6 조합 후보에서는 제외한다.
