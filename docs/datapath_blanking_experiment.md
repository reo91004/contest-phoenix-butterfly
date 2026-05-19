# Data-Path Blanking Side-Channel Experiment

Date: 2026-05-20 KST

## Goal

Evaluate whether a conservative data-path blanking countermeasure reduces first-order
fixed-vs-random TVLA leakage in the PHOENIX ML-KEM / ML-DSA datapath without changing
functional behavior or cycle counts.

## Baseline

Baseline commit:

- `cd69410 Add ML-KEM and ML-DSA TVLA tooling`

Baseline TVLA command:

```sh
OUTDIR=reports/tvla/mlkem_mldsa_secretdist_20260519_cw305_husky_1000 \
OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' \
TRACES=1000 SECRET_DIST=auto \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```

Baseline summary:

| Operation | Secret distribution | Max abs t | Result | Cycles |
|---|---|---:|---|---:|
| `mlkem_ntt` | `mlkem_cbd`, eta=2 | 84.901 | `LEAKAGE_CANDIDATE` | 248 |
| `mlkem_intt` | `mlkem_cbd`, eta=2 | 65.052 | `LEAKAGE_CANDIDATE` | 248 |
| `mlkem_pwm` | `mlkem_cbd`, eta=2 | 114.713 | `LEAKAGE_CANDIDATE` | 149 |
| `mldsa_ntt` | `mldsa_eta`, eta=2 | 132.180 | `LEAKAGE_CANDIDATE` | 538 |
| `mldsa_intt` | `mldsa_eta`, eta=2 | 135.012 | `LEAKAGE_CANDIDATE` | 538 |
| `mldsa_pwm` | `mldsa_eta`, eta=2 | 144.055 | `LEAKAGE_CANDIDATE` | 140 |

Baseline artifacts:

- `reports/tvla/mlkem_mldsa_secretdist_20260519_cw305_husky_1000/summary.csv`
- `reports/tvla/mlkem_mldsa_secretdist_20260519_cw305_husky_1000/mlkem_mldsa_tvla_overview.png`

## Countermeasure Strategy

Stage 1 is deterministic zero blanking. This is a hygiene countermeasure, not a
replacement for masking or shuffling:

- When an SBU input transaction is invalid, force SBU input registers to zero and
  a safe selector.
- When an SBU pipeline stage carries invalid data, force its data registers to zero.
- When SBU output valid is false, force output registers to zero.
- In ML-KEM cascade PWM routing, force cascade registers and delayed zeta pipe to zero
  when the cascade transaction is invalid.

Expected benefit:

- Remove stale secret-dependent values from invalid, drain, and idle cycles.
- Reduce boundary and pipeline-retention leakage.

Expected limitation:

- Active valid cycles still compute on unmasked secret-dependent operands, so large
  TVLA peaks may remain.

## Experiment Plan

1. Implement stage-1 zero blanking in the SBU and cascade path.
2. Run RTL regression tests that cover arithmetic, all SBU modes, and CW305 wrapper IO.
3. Rebuild CW305 bitstream.
4. Run a small hardware smoke TVLA.
5. Run 1000 vs 1000 TVLA for all six operations using the same distribution as baseline.
6. Compare max abs t, peak position, clipping, and cycle counts against baseline.
7. If leakage remains high, continue with follow-up variants:
   - Stage 1b: also blank top-level PE input wires before SBU entry.
   - Stage 2: add optional random dummy/idle toggling outside valid writeback.
   - Stage 3: evaluate coefficient/order shuffling for active-cycle leakage.

## Stage 1 Log

Status: implemented and measured.

Implementation files:

- `rtl/sbu/superbutterfly_sbu_routed.v`
- `rtl/phoenix/sbu_pair_pe.v`

Implementation notes:

- `superbutterfly_sbu_routed` now blanks SBU input registers to zero with a safe
  modular-add selector whenever `valid_i` is false.
- `superbutterfly_sbu_routed` now blanks registered SBU outputs whenever the
  internal output-valid bit is false.
- `sbu_pair_pe` now blanks ML-KEM cascade data registers and the delayed `c`
  pipe entry when the corresponding cascade transaction is invalid.
- An intermediate variant also blanked an internal SBU stage-2 register bank, but
  it added a selector-driven mux on the critical path and produced WNS = -0.040 ns.
  The final stage-1 variant relies on the upstream input blanking for that path and
  meets timing.

Verification commands:

```sh
bash sim/run_verilator.sh
python scripts/diagnostics/check_phoenix_consistency.py
python scripts/diagnostics/check_bank_conflicts.py
bash sim/run_verilator.sh 'tb_superbutterfly_all_modes tb_phoenix_core tb_phoenix_host_io tb_phoenix_cw305_wrapper tb_phoenix_mldsa_pwm_io'
```

Verification results:

- Full Verilator regression: pass. `tb_barrett_reduce` remains inconclusive, as in
  the pre-existing test behavior.
- Consistency diagnostic: pass.
- Bank-conflict diagnostic: pass.
- Timing-friendly post-patch key regression: pass.
- Hardware smoke TVLA: pass for `mlkem_ntt`, `mldsa_ntt`, and `mldsa_pwm` with
  one trace per group.
- Final CW305 bitstream: `boards/cw305/output/phoenix_cw305.bit`, generated
  2026-05-20 00:33:32 KST.
- Final post-route timing: WNS = 0.174 ns, TNS = 0.000 ns, WHS = 0.079 ns, THS = 0.000 ns.

Hardware smoke command:

```sh
OUTDIR=reports/tvla/smoke_blanking_stage1_20260520 \
OPS='mlkem_ntt mldsa_ntt mldsa_pwm' TRACES=1 SECRET_DIST=auto \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```

TVLA command:

```sh
OUTDIR=reports/tvla/mlkem_mldsa_blanking_stage1_20260520_cw305_husky_1000 \
OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' \
TRACES=1000 SECRET_DIST=auto \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```

Comparison artifacts:

- `reports/tvla/mlkem_mldsa_blanking_stage1_20260520_cw305_husky_1000/summary.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage1_20260520_cw305_husky_1000/comparison_vs_baseline.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage1_20260520_cw305_husky_1000/comparison_vs_baseline.png`
- `reports/tvla/mlkem_mldsa_blanking_stage1_20260520_cw305_husky_1000/mlkem_mldsa_tvla_overview.png`

Comparison command:

```sh
python scripts/tvla/phoenix_compare_tvla.py \
  --baseline reports/tvla/mlkem_mldsa_secretdist_20260519_cw305_husky_1000 \
  --candidate reports/tvla/mlkem_mldsa_blanking_stage1_20260520_cw305_husky_1000 \
  --candidate-label 'stage1 blanking'
```

Results:

| Operation | Baseline max abs t | Stage 1 max abs t | Delta | Delta % | Cycles |
|---|---:|---:|---:|---:|---:|
| `mlkem_ntt` | 84.901 | 93.074 | +8.173 | +9.63% | 248 |
| `mlkem_intt` | 65.052 | 181.036 | +115.984 | +178.29% | 248 |
| `mlkem_pwm` | 114.713 | 118.880 | +4.167 | +3.63% | 149 |
| `mldsa_ntt` | 132.180 | 138.255 | +6.075 | +4.60% | 538 |
| `mldsa_intt` | 135.012 | 96.137 | -38.875 | -28.79% | 538 |
| `mldsa_pwm` | 144.055 | 119.472 | -24.583 | -17.07% | 140 |

All six operations remain `LEAKAGE_CANDIDATE`. No clipping was observed, and cycle
counts stayed identical to baseline.

Initial interpretation:

- Stage 1 is functionally and timing-clean, but it is not a sufficient TVLA
  countermeasure.
- The mixed result is consistent with deterministic blanking removing stale
  invalid-cycle retention while leaving active valid-cycle arithmetic unmasked.
- `mldsa_intt` and `mldsa_pwm` improved, which suggests some boundary or retention
  leakage existed there.
- `mlkem_intt` worsened strongly. One plausible explanation is that deterministic
  zero blanking reduces unrelated switching/noise in surrounding invalid cycles,
  making active secret-dependent arithmetic peaks sharper. This needs a follow-up
  A/B rerun before treating the magnitude as intrinsic.
