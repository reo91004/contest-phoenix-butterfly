# Stage 6: COMP3 inactive-cone dummy blanking

## 목적

Stage 5d에서 COMP3 inactive algorithm cone을 zero로 껐더니 ML-KEM PWM은 약간
좋아졌지만 ML-DSA NTT/INTT가 크게 악화했다. Stage 6의 질문은 다음이었다.

> inactive cone switching을 완전히 없앤 것이 문제였다면, zero 대신 fixed dummy
> 또는 public PRD dummy switching을 넣으면 B3 악화를 완화할 수 있는가?

## 기준 RTL

모든 Stage 6 하위 실험은 Stage 4b에서 새 branch로 시작했다. Stage 5d 위에 쌓지
않았다.

## 공통 구조

COMP3 내부 KEM cone과 DSA cone input을 분리했다.

- ML-KEM mode: KEM cone은 real `a_i/b_i`, inactive DSA cone은 dummy.
- ML-DSA mode: DSA cone은 real `a_i[23:0]/b_i[23:0]`, inactive KEM cone은 dummy.
- output mux는 그대로 유지.
- active arithmetic cone에는 dummy를 섞지 않음.

## Stage 6a: fixed balanced inactive-cone dummy

기존 이름: R1

inactive cone에 fixed balanced pattern을 넣었다.

- inactive KEM dummy 예: `32'h5555_AAAA`, `32'hAAAA_5555`.
- inactive DSA dummy 예: `24'h555555`, `24'h2AAAAA`.

| Operation | Stage 4b | Stage 6a | 변화 |
|---|---:|---:|---:|
| `mlkem_ntt` | 96.516 | 77.548 | 개선 |
| `mlkem_intt` | 42.888 | 76.189 | 악화 |
| `mlkem_pwm` | 103.869 | 105.481 | 거의 동일 |
| `mldsa_ntt` | 85.738 | 99.021 | 악화 |
| `mldsa_intt` | 112.877 | 128.424 | 악화 |
| `mldsa_pwm` | 78.170 | 91.610 | 악화 |

판단: fixed dummy는 Stage 5d zero cone보다 일부 부드러웠지만 Stage 4b보다 worst가
나빠 reject.

## Stage 6b: public PRD inactive-cone dummy

기존 이름: R2

inactive cone에 trace-varying public PRD dummy를 넣었다. `superbutterfly_sbu_routed`
가 active valid COMP3 cycle용 dummy LFSR을 소유하고, COMP3 stage가 valid
transaction을 들고 있을 때 advance하도록 했다.

Stage 6b TVLA overview:

![Stage 6b TVLA overview](../../../reports/tvla/mlkem_mldsa_stage6_r2_prd_dummy_comp3_20260520_cw305_husky_1000/mlkem_mldsa_tvla_overview.png)

Stage 6b vs Stage 4b:

![Stage 6b vs Stage 4b](../../../reports/tvla/mlkem_mldsa_stage6_r2_prd_dummy_comp3_20260520_cw305_husky_1000/comparison_vs_stage4b.png)

| Operation | Stage 4b | Stage 6b | 변화 |
|---|---:|---:|---:|
| `mlkem_ntt` | 96.516 | 29.532 | 크게 개선 |
| `mlkem_intt` | 42.888 | 27.140 | 개선 |
| `mlkem_pwm` | 103.869 | 52.516 | 크게 개선 |
| `mldsa_ntt` | 85.738 | 82.381 | 소폭 개선 |
| `mldsa_intt` | 112.877 | 121.557 | 악화 |
| `mldsa_pwm` | 78.170 | 85.713 | 악화 |

해석:

- ML-KEM 세 operation은 매우 좋아졌다.
- 하지만 ML-DSA INTT/PWM이 Stage 4b보다 악화했다.
- `mldsa_intt` peak index 123은 Stage 4b와 동일하게 유지됐다.

Stage 6b가 ML-KEM에서 좋은 이유는 active KEM arithmetic을 바꿨기 때문이 아니다.
ML-KEM mode에서는 active KEM cone은 그대로였고 inactive DSA cone만 public PRD
dummy를 받았다. 따라서 결과는 inactive dummy switching이 ML-KEM peak visibility를
크게 바꿀 수 있음을 보여준다.

판단: informative but rejected. 최종 RTL에는 들어가지 않는다.

## Stage 6c: same-seed LFSR replay, timing failed

기존 이름: R3a

Stage 6b와 같은 dummy datapath를 쓰되 operation 시작마다 같은 PRD sequence를
replay하려고 했다. 목적은 Stage 6b 개선이 trace-varying randomness 때문인지,
dummy switching shape 때문인지 분리하는 것이었다.

결과:

- post-route timing failed.
- WNS `-0.154 ns`, TNS `-0.549 ns`.
- smoke/full TVLA는 실행하지 않았다.

판단: 구현 형태로는 reject. 질문 자체는 여전히 유효했기 때문에 Stage 6d로 더
가벼운 replay 구조를 시도했다.

## Stage 6d: same-seed counter-scramble replay

기존 이름: R3b

Stage 6c의 timing 문제를 피하려고 counter-scramble 기반 replay dummy를 사용했다.

| Operation | Stage 4b | Stage 6d | 변화 |
|---|---:|---:|---:|
| `mlkem_ntt` | 96.516 | 62.775 | 개선 |
| `mlkem_intt` | 42.888 | 53.570 | 악화 |
| `mlkem_pwm` | 103.869 | 67.092 | 개선 |
| `mldsa_ntt` | 85.738 | 93.374 | 악화 |
| `mldsa_intt` | 112.877 | 163.051 | 크게 악화 |
| `mldsa_pwm` | 78.170 | 99.762 | 악화 |

Stage 6d는 Stage 6b의 ML-KEM 개선을 그대로 보존하지 못했다. 특히
`mldsa_intt=163.051`로 크게 악화했다.

판단: reject. Stage 6b의 ML-KEM 개선은 deterministic replay shape만으로는 설명되지
않고, trace-varying public PRD phase와 placement effect가 함께 작동했을 가능성이
크다.

## 최종 상태와 복구

Stage 6a/6b/6c/6d는 모두 최종 RTL에 반영하지 않았다. Stage 6 이후 source와
bitstream은 Stage 4b로 복구했다.

복구 방법:

- `comp3_agile_modmul.v`에서 `dummy_a_i/dummy_b_i` port와 inactive cone mux를 제거.
- `superbutterfly_sbu_routed.v`의 active COMP3 dummy LFSR와 dummy port 연결 제거.
- COMP3 instantiation을 Stage 4b 형태로 복구:

```verilog
comp3_agile_modmul u_comp3 (
    .a_i(mA),
    .b_i(mB),
    .opmode_i(opmode1),
    .c_o(comp3_p)
);
```

복구 후 상태:

- diagnostics 통과.
- Verilator regression 통과.
- timing: WNS `0.203 ns`, TNS `0.000 ns`, WHS `0.063 ns`, THS `0.000 ns`.
- utilization: 9727 LUTs, 3268 registers, 8 RAMB36-equivalent, 0 DSP.

## 판단

Stage 6은 inactive-cone dummy activity가 ML-KEM TVLA shape에 강한 lever라는 것을
보여줬다. 그러나 ML-DSA active DSA arithmetic window, 특히 `mldsa_intt` peak 123을
해결하지 못했다. 따라서 Stage 4b가 최종 선택 RTL로 남는다.
