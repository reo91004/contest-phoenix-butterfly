# Stage 1: invalid SBU/cascade/output zero blanking

## 목적

Stage 1은 invalid/drain cycle에서 이전 secret-dependent operand가 SBU pipeline,
SBU output, ML-KEM cascade register에 남아 leakage를 만들 수 있는지 확인한
실험이다.

## 기준 RTL

기준은 original baseline이다. Stage 1은 baseline에 deterministic zero blanking을
추가했다.

## RTL 변경

변경 위치:

- `rtl/sbu/superbutterfly_sbu_routed.v`
- `rtl/phoenix/sbu_pair_pe.v`

SBU stage-1 input register는 `valid_i=0`일 때 safe selector와 zero operand를
받는다.

```verilog
else begin
    sel1 <= SEL_BLANK;
    a1   <= 32'b0;
    b1   <= 32'b0;
    c1   <= 32'b0;
    v1   <= 1'b0;
end
```

SBU output register도 delayed valid가 false이면 zero를 낸다.

```verilog
else begin
    y0r <= 32'b0;
    y1r <= 32'b0;
    vr  <= 1'b0;
end
```

ML-KEM cascade path에서는 SBU0 output이 invalid이면 SBU1로 넘어가는 cascade
register를 zero로 채운다.

```verilog
cascade_a_r <= sbu0_valid_out ? sbu0_out0 : 32'b0;
cascade_b_r <= sbu0_valid_out ? sbu0_out1 : 32'b0;
cascade_c_pipe[0] <= valid0_in ? sbu0_c : 32'b0;
```

## 검증

- diagnostics 통과.
- Verilator regression 통과.
- post-route timing pass: WNS `0.174 ns`, TNS `0.000 ns`, WHS `0.079 ns`, THS `0.000 ns`.
- cycle count는 baseline과 동일.

## TVLA 결과

| Operation | Baseline | Stage 1 | 변화 |
|---|---:|---:|---:|
| `mlkem_ntt` | 84.901 | 93.074 | 악화 |
| `mlkem_intt` | 65.052 | 181.036 | 크게 악화 |
| `mlkem_pwm` | 114.713 | 118.880 | 악화 |
| `mldsa_ntt` | 132.180 | 138.255 | 악화 |
| `mldsa_intt` | 135.012 | 96.137 | 개선 |
| `mldsa_pwm` | 144.055 | 119.472 | 개선 |

Artifact:

`reports/tvla/mlkem_mldsa_blanking_stage1_20260520_cw305_husky_1000`

## 판단

Stage 1은 일부 stale-state leakage가 있음을 보여줬다. `mldsa_intt`와
`mldsa_pwm`은 낮아졌다. 그러나 `mlkem_intt`가 크게 악화했기 때문에 단독
countermeasure로는 reject다.

## 복구 방법

Stage 1을 되돌리려면 invalid cycle에서 zero를 강제하는 조건을 제거하고,
baseline처럼 register가 기존 update policy를 따르도록 되돌린다. 특히
`superbutterfly_sbu_routed.v`의 `valid_i=0` branch와 `sbu_pair_pe.v`의
cascade zeroing이 핵심 복구 지점이다.
