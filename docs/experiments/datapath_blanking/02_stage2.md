# Stage 2: memory read-output blanking

## 목적

Stage 2는 core가 읽지 않는 cycle 또는 선택되지 않은 memory side에서 BRAM
read-output register가 이전 secret memory 값을 유지하는지 확인했다. Stage 2b는
read-side 정책을 바꿔 unused-side switching이 noise처럼 작동하는지 본 ablation이다.

## 기준 RTL

기준은 Stage 1이다. Stage 2는 Stage 1 위에 memory read-output zero blanking과
top-level read enable 정리를 추가했다.

## RTL 변경

변경 위치:

- `rtl/phoenix/poly_memory_updown.v`
- `rtl/phoenix/phoenix_top.v`

BRAM port-A output은 read enable이 없으면 zero를 낸다.

```verilog
a_dout <= a_en ? mem[a_addr] : {DATA_W{1'b0}};
```

Top-level core read enable은 operation과 `idx_valid`에 맞춰 생성한다.

```verilog
wire core_reads_both_sides = is_mlkem_pwm || is_mldsa_pwm;
wire [3:0] core_mu_read_en =
    (idx_valid && (!ctl_mem_down || core_reads_both_sides)) ? 4'hf : 4'b0;
wire [3:0] core_md_read_en =
    (idx_valid && ( ctl_mem_down || core_reads_both_sides)) ? 4'hf : 4'b0;
```

의미:

- NTT/INTT는 선택된 memory side만 읽는다.
- ML-KEM PWM과 ML-DSA PWM은 memory-up/down 양쪽을 모두 읽는다.
- invalid cycle에서는 read enable을 내리지 않아 memory output이 zero가 된다.

## Stage 2 결과

검증:

- diagnostics 통과.
- Verilator regression 통과.
- timing pass: WNS `0.087 ns`.
- 8 RAMB36-equivalent, 0 DSP 유지.

| Operation | Baseline | Stage 2 | 변화 |
|---|---:|---:|---:|
| `mlkem_ntt` | 84.901 | 108.431 | 악화 |
| `mlkem_intt` | 65.052 | 32.655 | 크게 개선 |
| `mlkem_pwm` | 114.713 | 108.878 | 소폭 개선 |
| `mldsa_ntt` | 132.180 | 140.159 | 악화 |
| `mldsa_intt` | 135.012 | 134.793 | 거의 동일 |
| `mldsa_pwm` | 144.055 | 155.781 | 악화 |

Artifact:

`reports/tvla/mlkem_mldsa_blanking_stage2_20260520_cw305_husky_1000`

Stage 2 repeat에서 `mlkem_intt`는 `32.480`으로 재현되어, memory read-output
retention이 ML-KEM INTT leakage에 실제 영향을 준다고 판단했다.

## Stage 2b: read-side ablation

Stage 2b는 Stage 2의 memory read-output blanking은 유지하되, unused memory-side
read switching을 더 남기는 방향으로 실험했다. 목적은 Stage 2가 active arithmetic
leakage를 가리던 switching까지 제거한 것인지 확인하는 것이었다.

| Operation | Baseline | Stage 2b | 변화 |
|---|---:|---:|---:|
| `mlkem_ntt` | 84.901 | 107.580 | 악화 |
| `mlkem_intt` | 65.052 | 57.613 | 소폭 개선 |
| `mlkem_pwm` | 114.713 | 125.636 | 악화 |
| `mldsa_ntt` | 132.180 | 132.873 | 거의 동일 |
| `mldsa_intt` | 135.012 | 121.394 | 개선 |
| `mldsa_pwm` | 144.055 | 137.125 | 소폭 개선 |

Stage 2b는 Stage 2의 강한 `mlkem_intt` 개선을 약화시키고 ML-KEM PWM을 악화시켜
reject했다.

## 판단

Stage 2는 memory read-output retention이 실제 leakage source임을 보여줬지만
전체 TVLA pass에는 부족했다. 이후 Stage는 Stage 2의 memory blanking을 유지한 채
SBU 내부 invalid-cycle flushing을 더 실험했다.

## 복구 방법

Stage 2를 되돌리려면 `poly_memory_updown.v`의 `a_dout <= a_en ? ... : 0`을
baseline형 always-read output으로 되돌리고, `phoenix_top.v`의 core read enable
조건을 이전 정책으로 복구한다. Stage 2b는 read enable 정책만 되돌리면 Stage 2로
돌아간다.
