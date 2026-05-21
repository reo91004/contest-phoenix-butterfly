# Stage AM1: ML-KEM NTT/INTT Share-Preserving Arithmetic

## 목적

ML-KEM NTT/INTT에서 share memory plumbing과 share-wise linear/public-constant arithmetic이
기능적으로 맞는지 검증한다. 이 단계에서는 secret-secret multiplication random tape가
핵심이 아니다. 목적은 다음 두 가지다.

- region 0/1 memory에서 share0/share1을 같은 bank/address로 읽고 다시 share로 writeback한다.
- COMP1/COMP2/COMP3/COMP4가 ML-KEM NTT/INTT에서 recombine 후 기존 unmasked golden과
  일치한다.

## 코드 단위 적용

### Host preload

`scripts/tvla/phoenix_capture_tvla.py`의 `load_group()`은 ML-KEM operation이면 각 word를
fresh share로 쪼갠 뒤 region 0/1에 preload한다.

```text
region 0: share0 = value - share1 mod 3329
region 1: share1 = random mod 3329
```

fixed TVLA group에서도 secret value만 fixed이고 share1은 trace마다 새로 뽑힌다.

### Memory

`rtl/phoenix/phoenix_top.v`에 `u_pm_mask`를 추가했다. 기존 `u_pm`은 share0 memory가 되고,
`u_pm_mask`는 동일한 up/down, 4-bank, address 구조로 share1을 저장한다.

### SBU

`rtl/sbu/superbutterfly_sbu_routed.v`에서 ML-KEM mask path를 추가했다.

| 연산 | share-wise 처리 |
|---|---|
| COMP2 INTT pre-sub/div2 | `b1m - a1m`, div2 |
| COMP3 NTT/INTT public constant multiplication | `c_mask=0`, operand share를 곱해 share output 유지 |
| COMP1 add/div2 | share0/share1 각각 동일한 add/div2 |
| COMP4 post-sub | share0/share1 각각 동일한 subtraction |

zeta/public constant는 secret share가 아니므로 `share0=constant`, `share1=0`으로 둔다.

## 검증

`tb_mlkem_masked_sbu`에서 NTT/INTT mode를 포함해 SBU 출력 share를 recombine한 뒤 기존
golden과 비교했다.

```text
tb_mlkem_masked_sbu: checks=1200 errors=0 PASS
```

core/wrapper regression도 통과했다.

```bash
python3 scripts/diagnostics/check_phoenix_consistency.py
python3 scripts/diagnostics/check_bank_conflicts.py
bash sim/run_verilator.sh 'tb_comp1_comp2_comp4 tb_comp3_agile_modmul tb_mlkem_masked_sbu tb_superbutterfly_all_modes tb_phoenix_core tb_phoenix_host_io tb_phoenix_cw305_wrapper tb_phoenix_mldsa_pwm_io'
```

## TVLA 결과

AM3 full run에서 NTT/INTT 결과를 확인했다.

```bash
OUTDIR=reports/tvla/arithmetic_masking_mlkem_full_260521 \
OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' \
TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0x5EED \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```

| Operation | `5c0a201` 후보 | AM masked | peak index | cycles | clipping | 판단 |
|---|---:|---:|---:|---:|---:|---|
| `mlkem_ntt` | 68.726 | 2.788 | 863 | 248 | 0 | pass |
| `mlkem_intt` | 43.319 | 3.776 | 782 | 248 | 0 | pass |

## 판단

AM1의 share-preserving NTT/INTT path는 accepted다. 두 operation 모두 `5c0a201` 후보보다
90% 이상 낮아졌고, 1000/1000 fixed-vs-random TVLA에서 threshold 4.5 아래다.
