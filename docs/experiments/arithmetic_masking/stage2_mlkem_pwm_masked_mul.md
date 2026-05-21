# Stage AM2: ML-KEM PWM Masked Multiplication

## 목적

ML-KEM PWM의 active secret-secret multiplication leakage를 낮추는지 확인한다. 이전
datapath dummy blanking은 선택되지 않는 주변 cone의 switching을 조절했다. AM2는 그보다
직접적으로, 실제로 architectural output에 들어가는 ML-KEM COMP3 곱셈을 two-share masked
multiplication으로 계산한다.

## 코드 단위 적용

### Random tape

`rtl/phoenix/phoenix_top.v`에 `u_pm_rand`를 추가했다. host protocol에서는 region 2다.
Python은 trace 시작 전에 region 2에 packed lane random tape를 preload한다.

```text
32-bit random tape word = {r_hi, r_lo}
r_lo, r_hi: each random mod 3329
```

PWM은 memory-up/down 양쪽 operand를 모두 쓰므로 random tape도 up/down read timing에 맞춰
읽는다. PWM cascade에서는 `sbu_pair_pe.v`가 random word를 기존 cascade timing에 맞춰
delay해서 SBU1로 넘긴다.

### COMP3 masked multiplication

`rtl/comp/comp3_mlkem_masked_mul.v`의 `comp3_mlkem_masked_mul_pipe`가 실제 사용되는
masked multiplier다.

각 lane에서 다음을 계산한다.

```text
p00 = x0*y0
p01 = x0*y1
p10 = x1*y0
p11 = x1*y1

z0 = p00 + r
z1 = p01 + p10 + p11 - r
```

`z0/z1`은 각각 share0/share1 결과가 된다. SBU 출력 mux는 share0을 기존 output으로,
share1을 새 mask output으로 내보내고, top-level writeback은 두 share를 각각 region
0/1 memory에 저장한다.

### Timing shell

처음의 완전 combinational masked multiplier는 30ns timing을 만족하지 못했다. 최종
구현은 masked COMP3 내부에서 partial product/reduction 결과를 한 번 register하고,
SBU 전체 visible latency는 8 cycle로 유지했다.

```text
s1  input register
s2  legacy COMP3/COMP2 alignment + masked COMP3 partial register
s3  masked COMP3 output alignment
s4-s7 delay_line DEPTH=4
s8  output register
visible latency = 8 cycles
```

## 검증

`tb_mlkem_masked_sbu`는 `SBU_PWM0`과 `SBU_PWM1`을 포함해 recombine 결과가 unmasked
golden과 일치하는지 확인한다.

```text
tb_mlkem_masked_sbu: checks=1200 errors=0 PASS
```

CW305 30ns build도 통과했다.

| 항목 | 값 |
|---|---:|
| WNS | `0.016 ns` |
| TNS | `0.000 ns` |
| WHS | `0.065 ns` |
| THS | `0.000 ns` |
| LUT | `19894` |
| FF | `4469` |
| RAMB36 | `24` |
| DSP | `0` |

## TVLA 결과

```bash
OUTDIR=reports/tvla/arithmetic_masking_mlkem_full_260521 \
OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' \
TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0x5EED \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```

`mlkem_pwm` 결과:

| 기준 | max `|t|` | peak index | cycles | clipping | 판단 |
|---|---:|---:|---:|---:|---|
| `5c0a201` 후보 | 96.004 | 56 | 149 | 0 | leakage candidate |
| AM masked | 3.776 | 359 | 149 | 0 | pass |

Repeat:

```bash
OUTDIR=reports/tvla/arithmetic_masking_am2_mlkem_pwm_repeat_260521 \
OPS='mlkem_pwm' \
TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0xC0DEC \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```

Repeat 결과:

| 기준 | max `|t|` | peak index | cycles | clipping | 판단 |
|---|---:|---:|---:|---:|---|
| seed `0x5EED` | 3.776 | 359 | 149 | 0 | pass |
| repeat `0xC0DEC` | 3.029 | 133 | 149 | 0 | pass |

## 판단

AM2의 ML-KEM PWM masked multiplication은 accepted 후보로 본다. active secret-secret
multiplication에 random tape를 넣은 two-share multiplication이 `mlkem_pwm`을
`96.004 -> 3.776`으로 낮췄고, repeat에서도 `3.029`로 threshold 아래를 유지했다.
cycle count는 149로 유지됐다.
