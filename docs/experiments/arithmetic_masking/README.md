# ML-KEM / ML-DSA First-Order Arithmetic Masking

작성일: 2026-05-21 KST

이 폴더는 `5c0a201`의 **COMP3 internal Stage 2 논문 후보 RTL** 위에
first-order arithmetic masking을 올린 실험 기록이다. 처음에는 ML-KEM만 masking했고,
AM4에서 ML-DSA까지 확장했다.

현재 작업트리의 active RTL은 **ML-KEM + ML-DSA two-share arithmetic masking** 상태다.
이전 논문 후보 단독 RTL의 보고서는 `docs/experiments/stage2_dsa_mul_only_prd.md`에
보존되어 있다.

## Stage 흐름

| 문서 | 내용 | 판단 |
|---|---|---|
| `stage1_mlkem_ntt_intt_shares.md` | ML-KEM NTT/INTT share memory와 share-wise linear/public-constant arithmetic | plumbing 검증 |
| `stage2_mlkem_pwm_masked_mul.md` | ML-KEM PWM two-share masked multiplication과 random tape | ML-KEM PWM masking 검증 |
| `stage3_mlkem_full_masked.md` | ML-KEM masking full six-op run | ML-KEM pass, ML-DSA fail |
| `stage4_mldsa_full_masked.md` | ML-DSA까지 two-share masking 확장 | six-op 1000/1000 pass 후보 |

## 핵심 아이디어

각 coefficient를 두 share로 쪼개고, RTL 내부에서는 share를 recombine하지 않는다.
연산 결과도 share0/share1 형태로 memory에 다시 저장한다.

```text
value = share0 + share1 mod q
share1 = fresh random residue
share0 = value - share1 mod q
```

| Scheme | Modulus | 저장 형식 |
|---|---:|---|
| ML-KEM | `3329` | 32-bit word 안에 16-bit lane 2개 |
| ML-DSA | `8380417` | Montgomery residue를 32-bit word에 저장 |

ML-DSA는 Solinas branch와 달리 arithmetic domain을 바꾸지 않았다. 기존
`mldsa_karatsuba24 -> mldsa_montgomery_reduce` 의미를 유지한 채 share masking만
추가했다.

## Host Memory Region

CW305 command key의 unused bits `[120:119]`를 `region`으로 사용한다. 기존 4-bit
`slot`과 10-bit address 구조는 유지했다.

| Region | 의미 | RTL memory |
|---:|---|---|
| 0 | data/share0 memory | `u_pm` |
| 1 | share1 mask memory | `u_pm_mask` |
| 2 | PWM masked multiplication random tape | `u_pm_rand` |

Python capture script는 TVLA trace마다 region 0/1을 fresh share로 preload한다.
PWM에서는 region 2 random tape도 같이 preload한다. fixed TVLA group에서도 secret value만
fixed이고 mask/random tape는 trace마다 새로 만든다.

## Datapath 적용 위치

| Block | 적용 방식 |
|---|---|
| Memory read/write | share0은 region 0, share1은 region 1에서 같은 bank/address로 read/write |
| COMP1 | ML-KEM/ML-DSA add/div2 계열을 share-wise 계산 |
| COMP2 | INTT pre-sub/div2를 share-wise 계산 |
| COMP3 public constant multiply | zeta/public constant를 `share0=constant`, `share1=0`으로 두고 share-wise multiplication |
| COMP3 PWM secret-secret multiply | two-share masked multiplication과 random tape `r` 사용 |
| COMP4 | post-add/sub 계열을 share-wise 계산 |
| Host/Python 검증 | readback 후에만 `share0 + share1 mod q`로 recombine |

Secret-secret multiplication은 다음 형태다.

```text
x = x0 + x1
y = y0 + y1

z0 = x0*y0 + r
z1 = x0*y1 + x1*y0 + x1*y1 - r
z  = z0 + z1 = x*y mod q
```

ML-KEM은 packed lane별 modular multiplication을 사용하고, ML-DSA는 네 개의
Montgomery product를 사용한다.

## 구현 파일

| 파일 | 변경 내용 |
|---|---|
| `rtl/comp/comp3_mlkem_masked_mul.v` | ML-KEM packed-lane two-share multiplier |
| `rtl/comp/comp3_mldsa_masked_mul.v` | ML-DSA four-product masked Montgomery multiplier |
| `rtl/sbu/superbutterfly_sbu_routed.v` | ML-KEM/ML-DSA share-wise COMP1/2/3/4, mask output, random input |
| `rtl/sbu/superbutterfly_sbu.v` | SBU wrapper mask/random port 추가 |
| `rtl/sbu/superbutterfly_sbu_ref.v` | ref path compatibility, mask output zero |
| `rtl/phoenix/sbu_pair_pe.v` | 두 SBU와 PWM cascade의 mask/random 전달 |
| `rtl/phoenix/phoenix_top.v` | mask memory, random tape memory, region host mux, share writeback |
| `boards/cw305/phoenix_cw305_wrapper.v` | command key `[120:119]` region decode |
| `scripts/tvla/phoenix_cw305_lib.py` | `region` 인자와 `load_region_words()` 추가 |
| `scripts/tvla/phoenix_capture_tvla.py` | trace마다 share split과 random tape preload |
| `model/golden_arithmetic.py` | share split/recombine helper |
| `tb/tb_mlkem_masked_sbu.sv` | ML-KEM SBU share recombine 검증 |
| `tb/tb_mldsa_masked_sbu.sv` | ML-DSA SBU share recombine 검증 |

## 현재 Bitstream

AM4 기준 30ns constraint로 bitstream을 재생성했고 timing을 만족했다.

| 항목 | 값 |
|---|---:|
| bitstream | `boards/cw305/output/phoenix_cw305.bit` |
| bitstream mtime | `2026-05-21 13:28:47 +0900` |
| WNS | `0.155 ns` |
| TNS | `0.000 ns` |
| WHS | `0.077 ns` |
| THS | `0.000 ns` |
| LUT | `26122` |
| FF | `5151` |
| RAMB36 | `24` |
| DSP | `0` |

AM3의 ML-KEM-only masking bitstream은 LUT `19894`, FF `4469`, RAMB36 `24`, DSP `0`였다.
AM4에서 LUT가 증가한 주된 이유는 ML-DSA PWM masked multiplication이 각 SBU마다
네 개의 `mldsa_karatsuba24 + mldsa_montgomery_reduce` product cone을 병렬로 만들기
때문이다.

## 검증 상태

다음 검증을 통과했다.

```bash
python3 -m py_compile scripts/tvla/phoenix_capture_tvla.py scripts/tvla/phoenix_cw305_lib.py model/golden_arithmetic.py
python3 scripts/diagnostics/check_phoenix_consistency.py
python3 scripts/diagnostics/check_bank_conflicts.py
bash sim/run_verilator.sh 'tb_comp1_comp2_comp4 tb_comp3_agile_modmul tb_mldsa_masked_sbu tb_mlkem_masked_sbu tb_superbutterfly_all_modes tb_phoenix_core tb_phoenix_host_io tb_phoenix_cw305_wrapper tb_phoenix_mldsa_pwm_io'
```

주요 testbench 결과:

| Testbench | 결과 |
|---|---|
| `tb_mldsa_masked_sbu` | `checks=1200 errors=0 PASS` |
| `tb_mlkem_masked_sbu` | `checks=1200 errors=0 PASS` |
| `tb_superbutterfly_all_modes` | `checks=4000 errors=0 PASS` |
| `tb_phoenix_core` | `checks=8 errors=0 PASS` |
| `tb_phoenix_host_io` | `checks=7 errors=0 PASS` |
| `tb_phoenix_cw305_wrapper` | `checks=10 errors=0 PASS` |
| `tb_phoenix_mldsa_pwm_io` | `checks=512 errors=0 PASS` |

## TVLA 결과

AM4 full six-op TVLA:

```bash
OUTDIR=reports/tvla/arithmetic_masking_mldsa_full_260521 \
OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' \
TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0x5EED \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```

| Operation | Original baseline | AM4 masked | peak index | cycles | clipping | 판단 |
|---|---:|---:|---:|---:|---:|---|
| `mlkem_ntt` | 84.901 | 2.904 | 897 | 248 | 0 | pass |
| `mlkem_intt` | 65.052 | 3.451 | 809 | 248 | 0 | pass |
| `mlkem_pwm` | 114.713 | 3.147 | 531 | 149 | 0 | pass |
| `mldsa_ntt` | 132.180 | 3.435 | 850 | 538 | 0 | pass |
| `mldsa_intt` | 135.012 | 4.053 | 1122 | 538 | 0 | pass |
| `mldsa_pwm` | 144.055 | 2.969 | 797 | 140 | 0 | pass |

Overview:

![ML-KEM and ML-DSA arithmetic masking TVLA overview](../../../reports/tvla/arithmetic_masking_mldsa_full_260521/mlkem_mldsa_tvla_overview.png)

Original baseline comparison:

![Comparison vs original baseline](../../../reports/tvla/arithmetic_masking_mldsa_full_260521/comparison_vs_original_baseline.png)

사용자 요청에 따라 AM4 seed repeat는 아직 수행하지 않았다. 현재 판정은
**single shuffled 1000/1000 full six-op pass 후보**다.

## 결론

- Datapath blanking/dummy 실험은 inactive 또는 unused path leakage를 줄이는 데 의미가
  있었지만, active arithmetic leakage를 완전히 없애지는 못했다.
- Arithmetic masking은 실제 계산되는 operand를 share로 나누고, SBU 전체가 share를
  유지하도록 만드는 더 강한 countermeasure다.
- AM4에서는 ML-KEM과 ML-DSA 여섯 operation 모두 original baseline 대비 약 94-98%
  감소했고, threshold 4.5 아래로 내려갔다.
- 최종 보고서에서는 repeat/확장 trace 전에는 "pass 후보"로 표현하고, 제출용으로는
  seed repeat 또는 더 큰 trace 수 실험을 추가하는 편이 안전하다.
