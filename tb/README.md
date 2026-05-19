# 테스트벤치 개요

Testbench는 리팩터된 ML-KEM / ML-DSA RTL을 bottom-up으로 검증한다. 범위는
arithmetic primitive, COMP block, routed/reference SBU 일치, top-level command
smoke test이다.

## 검증 항목

| Testbench | 대상 | 목적 |
|---|---|---|
| `tb_kyber_modarith.sv` | ML-KEM modular arithmetic | packed 16비트 lane add/sub/div2 |
| `tb_barrett_reduce.sv` | ML-KEM Barrett reducer | standalone reducer harness, `checks=0`은 inconclusive로 처리 |
| `tb_array_schoolbook_agile16.sv` | integer schoolbook16 | LUT-only halfword multiplier |
| `tb_mldsa_karatsuba24.sv` | ML-DSA 24비트 multiplier | raw integer product 구조 |
| `tb_mldsa_montgomery_reduce.sv` | ML-DSA reducer | FIPS 204 Montgomery reduction |
| `tb_mldsa_modarith.sv` | ML-DSA add/sub/div2 | `8380417` modulo arithmetic |
| `tb_comp1_comp2_comp4.sv` | COMP1/2/4 | ML-KEM lane 및 ML-DSA 32비트 arithmetic |
| `tb_comp3_agile_modmul.sv` | COMP3 | ML-KEM Barrett product 및 ML-DSA Montgomery product |
| `tb_superbutterfly_all_modes.sv` | SBU | routed/reference/golden 일치, latency 8 |
| `tb_phoenix_core.sv` | `phoenix_top` | command completion 및 cycle telemetry |
| `tb_phoenix_host_io.sv` | host memory port | idle read/write 및 busy gating |
| `tb_phoenix_cw305_wrapper.sv` | CW305 bridge | memory command 및 start/status smoke |
| `tb_phoenix_mldsa_pwm_io.sv` | `phoenix_top` ML-DSA PWM | 256-word pointwise multiplication memory I/O |

## 현재 cycle smoke

`tb_phoenix_core.sv`는 다음 형식의 line을 출력한다.

```text
[PHOENIX-CYCLES] op=<name> cycles=<n>
```

현재 Verilator smoke 값은 다음이다.

| Operation | Cycles |
|---|---:|
| `mlkem_ntt` | 248 |
| `mlkem_intt` | 248 |
| `mlkem_pwm` | 149 |
| `mldsa_ntt` | 538 |
| `mldsa_intt` | 538 |
| `mldsa_pwm` | 140 |

`tb_phoenix_core.sv`는 `instr[8:7] = 10`, `11`에 대해서 즉시 종료되는
reserved-field smoke도 함께 수행한다.

## 실행

```bash
bash sim/run_verilator.sh
bash sim/run_verilator.sh tb_superbutterfly_all_modes
bash sim/run_verilator.sh tb_phoenix_core
```

이 단계의 활성 test는 모두 Verilator에서 실행되는 것을 기준으로 한다.
