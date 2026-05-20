# Stage 5: Stage 4b 이후 small RTL 후보

## 목적

Stage 5는 현재 best candidate인 Stage 4b 위에서 작은 deterministic RTL blanking을
하나씩 더 넣어 TVLA worst를 낮출 수 있는지 확인한 실험이다.

## 기준 RTL

모든 Stage 5 하위 실험은 Stage 4b를 기준으로 새 branch에서 시작했다. 큰 구조는
바꾸지 않았다.

유지한 invariant:

- 9-bit instruction.
- SBU latency 8.
- two-SBU PE.
- ML-KEM packed layout.
- ML-DSA 1-word layout.
- 4-bank up/down memory.
- scheduler, memory layout, cycle count.

## 공통 검증

모든 Stage 5 후보는 아래 검증을 통과했다.

```bash
python3 scripts/diagnostics/check_phoenix_consistency.py
python3 scripts/diagnostics/check_bank_conflicts.py
bash sim/run_verilator.sh 'tb_comp3_agile_modmul tb_superbutterfly_all_modes tb_phoenix_core tb_phoenix_host_io tb_phoenix_cw305_wrapper tb_phoenix_mldsa_pwm_io'
```

모든 bitstream은 timing pass, 8 RAMB36-equivalent, 0 DSP를 유지했다.

## Stage 5a: combined exploratory probe

기존 이름: B1+B2+B3

세 후보를 한 번에 넣어 빠르게 방향을 본 exploratory run이다.

변경:

- exact PWM/pointwise read enable.
- ML-DSA PWM unused `a_i=0`.
- COMP3 KEM/DSA inactive cone zero blanking.

| Operation | Stage 4b | Stage 5a | 변화 |
|---|---:|---:|---:|
| `mlkem_ntt` | 96.516 | 94.885 | 소폭 개선 |
| `mlkem_intt` | 42.888 | 73.087 | 악화 |
| `mlkem_pwm` | 103.869 | 100.403 | 소폭 개선 |
| `mldsa_ntt` | 85.738 | 104.081 | 악화 |
| `mldsa_intt` | 112.877 | 143.709 | 악화 |
| `mldsa_pwm` | 78.170 | 86.290 | 악화 |

판단: worst가 `143.709`로 악화해 reject.

## Stage 5b: exact PWM/pointwise read enable

기존 이름: B1

변경 위치: `rtl/phoenix/phoenix_top.v`

Stage 4b에서는 pointwise operation에서 memory-up/down의 4 bank를 모두 enable했다.
Stage 5b는 실제로 쓰는 bank만 enable하도록 좁혔다.

- FFT/NTT/INTT는 기존 4-bank read 유지.
- ML-KEM PWM은 실제 `bk0a` 1-bank만 enable.
- ML-DSA PWM은 실제 `bk0a`, `bk1a` 2-bank만 enable.

| Operation | Stage 4b | Stage 5b | 변화 |
|---|---:|---:|---:|
| `mlkem_ntt` | 96.516 | 81.128 | 개선 |
| `mlkem_intt` | 42.888 | 42.750 | 거의 동일 |
| `mlkem_pwm` | 103.869 | 114.922 | 악화 |
| `mldsa_ntt` | 85.738 | 98.093 | 악화 |
| `mldsa_intt` | 112.877 | 127.224 | 악화 |
| `mldsa_pwm` | 78.170 | 68.124 | 개선 |

판단: `mldsa_pwm`과 `mlkem_ntt`는 좋아졌지만 worst가 `127.224`로 악화해 reject.

복구: `core_mu_read_en`, `core_md_read_en`을 Stage 4b의 pointwise `4'hf` 정책으로
되돌린다.

## Stage 5c: ML-DSA PWM unused `a_i` zero

기존 이름: B2

변경 위치: `rtl/phoenix/phoenix_top.v`

ML-DSA PWM에서 SBU의 `a_i`는 selected output에 직접 필요하지 않다고 보고
`sbu0_a`, `sbu1_a`를 `0`으로 넣었다. `sbu*_b=memory-down`,
`sbu*_c=memory-up`은 유지했다.

| Operation | Stage 4b | Stage 5c | 변화 |
|---|---:|---:|---:|
| `mlkem_ntt` | 96.516 | 125.233 | 크게 악화 |
| `mlkem_intt` | 42.888 | 44.928 | 소폭 악화 |
| `mlkem_pwm` | 103.869 | 102.970 | 거의 동일 |
| `mldsa_ntt` | 85.738 | 85.787 | 동일 |
| `mldsa_intt` | 112.877 | 122.087 | 악화 |
| `mldsa_pwm` | 78.170 | 69.215 | 개선 |

판단: target인 `mldsa_pwm`은 개선됐지만 `mlkem_ntt`가 크게 악화해 reject.

복구: ML-DSA PWM의 `sbu0_a`, `sbu1_a`를 Stage 4b처럼 memory-up word로 되돌린다.

## Stage 5d: COMP3 inactive algorithm-cone zero blanking

기존 이름: B3

변경 위치: `rtl/comp/comp3_agile_modmul.v`

COMP3 내부에서 선택되지 않는 algorithm cone의 multiplier/reducer input을 zero로
막았다.

- `opmode_i=0` ML-KEM mode: KEM cone real, DSA cone zero.
- `opmode_i=1` ML-DSA mode: DSA cone real, KEM cone zero.
- output mux는 유지.

| Operation | Stage 4b | Stage 5d | 변화 |
|---|---:|---:|---:|
| `mlkem_ntt` | 96.516 | 84.269 | 개선 |
| `mlkem_intt` | 42.888 | 79.262 | 악화 |
| `mlkem_pwm` | 103.869 | 95.295 | 개선 |
| `mldsa_ntt` | 85.738 | 119.838 | 악화 |
| `mldsa_intt` | 112.877 | 150.301 | 크게 악화 |
| `mldsa_pwm` | 78.170 | 92.039 | 악화 |

판단: COMP3 inactive cone이 TVLA shape에 실제로 영향을 준다는 신호는 얻었다.
하지만 inactive cone을 완전히 zero로 끄면 ML-DSA NTT/INTT가 크게 악화했다.
따라서 reject.

복구: `comp3_agile_modmul.v`에서 KEM/DSA cone input gating을 제거하고 Stage 4b처럼
두 cone이 모두 real `a_i/b_i`를 보게 되돌린다.

## Stage 5e: flopped/predecoded blanking control gate decision

기존 이름: B4

Stage 5e는 실행하지 않았다. 이유는 Stage 5b/5c/5d가 모두 function/timing은
clean했지만 TVLA worst를 Stage 4b보다 낮추지 못했기 때문이다. 특히 Stage 5d가
자연스러운 predecessor였는데 `mldsa_intt`를 `150.301`까지 악화시켰다.

## 최종 판단

Stage 5의 작은 deterministic blanking 후보는 모두 reject다. Stage 5 이후 source와
bitstream은 Stage 4b로 복구했다.

복구 후 Stage 4b 상태:

- diagnostics 통과.
- Verilator regression 통과.
- timing: WNS `0.203 ns`, TNS `0.000 ns`, WHS `0.063 ns`, THS `0.000 ns`.
- utilization: 9727 LUTs, 3268 registers, 8 RAMB36-equivalent, 0 DSP.

Stage 5의 의미는 “더 많이 zero로 끄면 항상 좋아진다”가 틀렸다는 것을 확인한
데 있다. 일부 unused switching은 leakage source이면서 동시에 active arithmetic
peak를 가리는 noise처럼 작동할 수 있다.
