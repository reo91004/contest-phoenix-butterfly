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

## OpenTitan Reference Model

The OpenTitan material suggests two related but distinct patterns that should not
be conflated:

- OTBN-style blanking: force data paths that are not needed by the current
  instruction to zero, and drive the blanking controls from flops rather than
  raw decode logic. The OTBN technical specification describes this as forcing
  unused paths to zero and applies it to register-file read/write paths and
  unused bignum ALU/MAC paths:
  <https://opentitan.org/book/hw/ip/otbn/>
- AES-style PRD clearing: overwrite major key/data/state registers with
  pseudo-random data during reset, explicit clear, and selected internal clear
  points. The AES programmer guide documents PRD clearing on reset and
  de-initialization:
  <https://opentitan.org/book/hw/ip/aes/doc/programmers_guide.html>
- AES GHASH goes one step further: after overwriting state/hash registers with
  PRD, it runs the multipliers so multiplier-internal state and correction-term
  registers are also cleared. The AES theory document describes this explicitly:
  <https://opentitan.org/book/hw/ip/aes/doc/theory_of_operation.html>

Mapping to PHOENIX:

- Stage 1 and Stage 2 are OTBN-style deterministic blanking experiments.
- Stage 3 will be AES-style PRD invalid-cycle flushing for SBU pipelines. The
  valid functional transaction is unchanged; only invalid/drain/idle cycles get
  PRD operands and a dummy selector. This is intended to clear stale SBU
  pipeline state and to keep the multiplier from retaining a previous
  secret-dependent value. It is not first-order masking.
- The TVLA capture script interleaves traces as `fixed` then `random` for each
  pair, rather than capturing all fixed traces before all random traces. This
  reduces long-term drift confounding, but Stage 3 results must still be read
  as an implementation-specific ablation because a deterministic free-running
  PRD sequence can have pair-order phase effects.

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

Repeat check:

- A second Stage 1 run over `mlkem_intt`, `mldsa_intt`, and `mldsa_pwm` produced
  max abs t values of 192.295, 98.240, and 166.229.
- The `mlkem_intt` worsening and `mldsa_intt` improvement therefore reproduced.
- `mldsa_pwm` varied significantly between runs, so the Stage 1 apparent PWM
  improvement should not be treated as stable.

## Stage 2 Log

Status: implemented and measured.

Strategy:

- Add a read enable to each polynomial-memory port-A BRAM output register.
- Force BRAM read outputs to zero when neither a valid core read nor a valid host
  access is being issued.
- During FFT-like operations, enable only the memory side selected by
  `ctl_mem_down`; during pointwise multiplication, enable both memory sides.
- Blank writeback address-pipe stage 0 when `idx_valid` is false. This keeps
  invalid writeback metadata from retaining the previous transaction while still
  allowing older valid metadata to drain through the pipe.

Implementation files:

- `rtl/phoenix/poly_memory_updown.v`
- `rtl/phoenix/phoenix_top.v`

Verification results:

- Key Verilator regression: pass for `tb_phoenix_host_io`, `tb_phoenix_core`,
  `tb_phoenix_cw305_wrapper`, `tb_phoenix_mldsa_pwm_io`, and
  `tb_superbutterfly_all_modes`.
- Consistency diagnostic: pass.
- Bank-conflict diagnostic: pass.
- Vivado still inferred 8 RAMB36 true dual-port memories.
- Final CW305 bitstream: `boards/cw305/output/phoenix_cw305.bit`, generated
  2026-05-20 00:53:28 KST.
- Final post-route timing: WNS = 0.087 ns, TNS = 0.000 ns, WHS = 0.078 ns, THS = 0.000 ns.
- Hardware smoke TVLA: pass for `mlkem_intt`, `mldsa_intt`, and `mldsa_pwm` with
  one trace per group.

TVLA command:

```sh
OUTDIR=reports/tvla/mlkem_mldsa_blanking_stage2_20260520_cw305_husky_1000 \
OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' \
TRACES=1000 SECRET_DIST=auto \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```

Comparison artifacts:

- `reports/tvla/mlkem_mldsa_blanking_stage2_20260520_cw305_husky_1000/summary.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage2_20260520_cw305_husky_1000/comparison_vs_baseline.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage2_20260520_cw305_husky_1000/comparison_vs_baseline.png`
- `reports/tvla/mlkem_mldsa_blanking_stage2_20260520_cw305_husky_1000/comparison_vs_stage1.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage2_20260520_cw305_husky_1000/comparison_vs_stage1.png`
- `reports/tvla/mlkem_mldsa_blanking_stage2_20260520_cw305_husky_1000/mlkem_mldsa_tvla_overview.png`

Results vs baseline:

| Operation | Baseline max abs t | Stage 2 max abs t | Delta | Delta % | Cycles |
|---|---:|---:|---:|---:|---:|
| `mlkem_ntt` | 84.901 | 108.431 | +23.530 | +27.71% | 248 |
| `mlkem_intt` | 65.052 | 32.655 | -32.398 | -49.80% | 248 |
| `mlkem_pwm` | 114.713 | 108.878 | -5.835 | -5.09% | 149 |
| `mldsa_ntt` | 132.180 | 140.159 | +7.979 | +6.04% | 538 |
| `mldsa_intt` | 135.012 | 134.793 | -0.219 | -0.16% | 538 |
| `mldsa_pwm` | 144.055 | 155.781 | +11.726 | +8.14% | 140 |

Stage 2 interpretation:

- Stage 2 is functionally and timing-clean.
- Stage 2 substantially fixes the Stage 1 `mlkem_intt` regression and improves it
  below the original baseline, which points to a real BRAM-output or read-side
  retention component for ML-KEM INTT.
- It does not fix first-order leakage overall. All six operations still exceed
  the 4.5 threshold.
- The NTT operations and ML-DSA PWM remain dominated by active-cycle arithmetic
  leakage, not only invalid-cycle data retention.

Repeat check:

- After the Stage 2b rejection, the active Stage 2 bitstream was rebuilt at
  2026-05-20 01:19:10 KST and again met timing with WNS = 0.087 ns.
- A repeat Stage 2 run over `mlkem_ntt`, `mlkem_intt`, and `mldsa_pwm` produced
  max abs t values of 113.954, 32.480, and 169.739.
- The `mlkem_intt` improvement is stable across Stage 2 captures.
- The `mlkem_ntt` and `mldsa_pwm` regressions are also stable enough to treat as
  real for this blanking family.

## Stage 2b Log

Status: measured, not kept as the active RTL variant.

Strategy:

- Keep the Stage 2 BRAM output invalid-cycle blanking.
- During valid core reads, enable both memory-up and memory-down sides for all
  operations instead of enabling only the selected FFT-like side.
- Rationale: Stage 2 may have reduced unrelated active-cycle switching/noise in
  unused memory sides, making active arithmetic leakage more visible. Stage 2b
  tests whether retaining that switching improves TVLA without giving up invalid
  blanking.

Verification results:

- Key Verilator regression: pass for `tb_phoenix_host_io`, `tb_phoenix_core`,
  `tb_phoenix_cw305_wrapper`, and `tb_phoenix_mldsa_pwm_io`.
- Consistency diagnostic: pass.
- Bank-conflict diagnostic: pass.
- Vivado still inferred 8 RAMB36 true dual-port memories.
- Final post-route timing: WNS = 0.422 ns, TNS = 0.000 ns, WHS = 0.062 ns, THS = 0.000 ns.
- Hardware smoke TVLA: pass for `mlkem_intt`, `mldsa_ntt`, and `mldsa_pwm` with
  one trace per group.

Results vs baseline:

| Operation | Baseline max abs t | Stage 2b max abs t | Delta | Delta % | Cycles |
|---|---:|---:|---:|---:|---:|
| `mlkem_ntt` | 84.901 | 107.580 | +22.679 | +26.71% | 248 |
| `mlkem_intt` | 65.052 | 57.613 | -7.439 | -11.44% | 248 |
| `mlkem_pwm` | 114.713 | 125.636 | +10.923 | +9.52% | 149 |
| `mldsa_ntt` | 132.180 | 132.873 | +0.693 | +0.52% | 538 |
| `mldsa_intt` | 135.012 | 121.394 | -13.618 | -10.09% | 538 |
| `mldsa_pwm` | 144.055 | 137.125 | -6.930 | -4.81% | 140 |

Repeat check:

- A second Stage 2b run over `mlkem_ntt`, `mlkem_pwm`, and `mldsa_pwm` produced
  max abs t values of 108.827, 125.885, and 163.062.
- `mlkem_ntt` and `mlkem_pwm` therefore reproduced as worse than baseline.
- `mldsa_pwm` remained highly variable and cannot be claimed as improved.

Stage 2b interpretation:

- Stage 2b is functionally and timing-clean, but it is not a better active RTL
  choice than Stage 2.
- It weakens the strong Stage 2 `mlkem_intt` improvement and makes ML-KEM PWM
  worse in repeated captures.
- It confirms that deterministic blanking experiments are now mostly moving
  relative peak visibility around; they are not removing the active-cycle
  arithmetic leakage source.

## Stage 3a Log

Status: measured, not accepted as the final active countermeasure.

Strategy:

- Keep Stage 2 memory read-output blanking.
- Replace the SBU invalid-cycle zero input with a deterministic public LFSR
  pattern.
- Use `SBU_MLDSA_PWM` as the invalid-cycle dummy selector so COMP3 receives PRD
  operands and the ML-DSA multiplier/reduction path is exercised while
  `valid_o` remains false.
- This is an AES-style PRD flush ablation, not masking. Functional valid-cycle
  inputs, output-valid timing, writeback timing, and operation cycle counts are
  unchanged.

Implementation file:

- `rtl/sbu/superbutterfly_sbu_routed.v`

Verification results:

- Key Verilator regression: pass for `tb_phoenix_host_io`, `tb_phoenix_core`,
  `tb_phoenix_cw305_wrapper`, `tb_phoenix_mldsa_pwm_io`, and
  `tb_superbutterfly_all_modes`.
- Consistency diagnostic: pass.
- Bank-conflict diagnostic: pass.
- Vivado still inferred 8 RAMB36 true dual-port memories.
- Final post-route timing: WNS = 0.071 ns, TNS = 0.000 ns, WHS = 0.053 ns,
  THS = 0.000 ns.
- Hardware smoke TVLA: pass for `mlkem_intt`, `mldsa_ntt`, and `mldsa_pwm`
  with one trace per group.

TVLA command:

```sh
OUTDIR=reports/tvla/mlkem_mldsa_blanking_stage3a_prd_20260520_cw305_husky_1000 \
OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' \
TRACES=1000 SECRET_DIST=auto \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```

Comparison artifacts:

- `reports/tvla/mlkem_mldsa_blanking_stage3a_prd_20260520_cw305_husky_1000/summary.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage3a_prd_20260520_cw305_husky_1000/comparison_vs_baseline.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage3a_prd_20260520_cw305_husky_1000/comparison_vs_baseline.png`
- `reports/tvla/mlkem_mldsa_blanking_stage3a_prd_20260520_cw305_husky_1000/comparison_vs_stage2.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage3a_prd_20260520_cw305_husky_1000/comparison_vs_stage2.png`
- `reports/tvla/mlkem_mldsa_blanking_stage3a_prd_20260520_cw305_husky_1000/mlkem_mldsa_tvla_overview.png`

Results vs baseline:

| Operation | Baseline max abs t | Stage 3a max abs t | Delta | Delta % | Cycles |
|---|---:|---:|---:|---:|---:|
| `mlkem_ntt` | 84.901 | 107.246 | +22.345 | +26.32% | 248 |
| `mlkem_intt` | 65.052 | 102.237 | +37.184 | +57.16% | 248 |
| `mlkem_pwm` | 114.713 | 129.216 | +14.503 | +12.64% | 149 |
| `mldsa_ntt` | 132.180 | 96.864 | -35.316 | -26.72% | 538 |
| `mldsa_intt` | 135.012 | 148.236 | +13.224 | +9.79% | 538 |
| `mldsa_pwm` | 144.055 | 70.810 | -73.245 | -50.85% | 140 |

Results vs Stage 2:

| Operation | Stage 2 max abs t | Stage 3a max abs t | Delta | Delta % |
|---|---:|---:|---:|---:|
| `mlkem_ntt` | 108.431 | 107.246 | -1.185 | -1.09% |
| `mlkem_intt` | 32.655 | 102.237 | +69.582 | +213.08% |
| `mlkem_pwm` | 108.878 | 129.216 | +20.338 | +18.68% |
| `mldsa_ntt` | 140.159 | 96.864 | -43.295 | -30.89% |
| `mldsa_intt` | 134.793 | 148.236 | +13.443 | +9.97% |
| `mldsa_pwm` | 155.781 | 70.810 | -84.971 | -54.55% |

Stage 3a interpretation:

- The result is strongly asymmetric by scheme. ML-KEM worsened or stayed bad,
  while ML-DSA NTT and ML-DSA PWM improved substantially.
- The most plausible cause is that Stage 3a used an ML-DSA dummy selector for
  every invalid cycle. That is scheme-matched for ML-DSA, but it forces the
  24-bit ML-DSA COMP3 path to toggle around ML-KEM operations whose active
  path is the packed two-lane 16-bit ML-KEM multiplier. This can add
  deterministic phase-dependent switching rather than useful de-correlation.
- `mlkem_intt` is the clearest rejection signal: Stage 2 had a stable
  improvement near 32.5, but Stage 3a raised it to 102.2. Therefore the PRD
  mechanism itself is not enough; the dummy selector must be operation-matched
  or the PRD source must be placed somewhere less disruptive.
- `mldsa_pwm` improved from 144.1 baseline / 155.8 Stage 2 to 70.8. This is
  real enough to preserve as a useful clue: PRD flushing of the ML-DSA
  multiplier path can reduce a large part of the ML-DSA pointwise leakage, even
  though it does not cross the 4.5 TVLA threshold.

Next ablation:

- Stage 3b: keep PRD invalid-cycle operands, but drive the invalid-cycle
  selector from the current operation selector (`sel_i`) instead of always using
  `SBU_MLDSA_PWM`. This keeps the SuperButterfly latency and functional behavior
  unchanged while making the dummy flush scheme/op matched.

## Stage 3b Log

Status: measured, not accepted as the final active countermeasure.

Strategy:

- Keep the Stage 3a public LFSR PRD invalid-cycle operands.
- Change only the invalid-cycle selector: use the current operation selector
  `sel_i` instead of hard-wiring `SBU_MLDSA_PWM`.
- Rationale: Stage 3a improved ML-DSA NTT/PWM but worsened ML-KEM. The likely
  cause was an ML-DSA dummy multiplier/reducer being used around ML-KEM
  operations. Stage 3b isolates selector/opmode matching from the PRD data
  source itself.

Implementation file:

- `rtl/sbu/superbutterfly_sbu_routed.v`

Verification results:

- Key Verilator regression: pass for `tb_phoenix_host_io`, `tb_phoenix_core`,
  `tb_phoenix_cw305_wrapper`, `tb_phoenix_mldsa_pwm_io`, and
  `tb_superbutterfly_all_modes`.
- Consistency diagnostic: pass.
- Bank-conflict diagnostic: pass.
- Vivado still inferred 8 RAMB36 true dual-port memories.
- Final post-route timing: WNS = 0.325 ns, TNS = 0.000 ns, WHS = 0.077 ns,
  THS = 0.000 ns.
- Hardware smoke TVLA: pass for `mlkem_intt`, `mldsa_ntt`, and `mldsa_pwm`
  with one trace per group.

TVLA command:

```sh
OUTDIR=reports/tvla/mlkem_mldsa_blanking_stage3b_prd_opmatched_20260520_cw305_husky_1000 \
OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' \
TRACES=1000 SECRET_DIST=auto \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```

Comparison artifacts:

- `reports/tvla/mlkem_mldsa_blanking_stage3b_prd_opmatched_20260520_cw305_husky_1000/summary.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage3b_prd_opmatched_20260520_cw305_husky_1000/comparison_vs_baseline.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage3b_prd_opmatched_20260520_cw305_husky_1000/comparison_vs_baseline.png`
- `reports/tvla/mlkem_mldsa_blanking_stage3b_prd_opmatched_20260520_cw305_husky_1000/comparison_vs_stage2.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage3b_prd_opmatched_20260520_cw305_husky_1000/comparison_vs_stage2.png`
- `reports/tvla/mlkem_mldsa_blanking_stage3b_prd_opmatched_20260520_cw305_husky_1000/mlkem_mldsa_tvla_overview.png`

Results vs baseline:

| Operation | Baseline max abs t | Stage 3b max abs t | Delta | Delta % | Cycles |
|---|---:|---:|---:|---:|---:|
| `mlkem_ntt` | 84.901 | 121.281 | +36.381 | +42.85% | 248 |
| `mlkem_intt` | 65.052 | 67.855 | +2.802 | +4.31% | 248 |
| `mlkem_pwm` | 114.713 | 123.381 | +8.669 | +7.56% | 149 |
| `mldsa_ntt` | 132.180 | 87.880 | -44.300 | -33.51% | 538 |
| `mldsa_intt` | 135.012 | 131.437 | -3.576 | -2.65% | 538 |
| `mldsa_pwm` | 144.055 | 72.497 | -71.558 | -49.67% | 140 |

Results vs Stage 2:

| Operation | Stage 2 max abs t | Stage 3b max abs t | Delta | Delta % |
|---|---:|---:|---:|---:|
| `mlkem_ntt` | 108.431 | 121.281 | +12.851 | +11.85% |
| `mlkem_intt` | 32.655 | 67.855 | +35.200 | +107.79% |
| `mlkem_pwm` | 108.878 | 123.381 | +14.503 | +13.32% |
| `mldsa_ntt` | 140.159 | 87.880 | -52.279 | -37.30% |
| `mldsa_intt` | 134.793 | 131.437 | -3.357 | -2.49% |
| `mldsa_pwm` | 155.781 | 72.497 | -83.284 | -53.46% |

Stage 3b interpretation:

- Operation-matching the dummy selector fixed part of the Stage 3a ML-KEM INTT
  regression, but not enough to beat Stage 2. ML-KEM NTT and PWM remain worse
  than both baseline and Stage 2.
- ML-DSA NTT and PWM improvements reproduced. This makes it unlikely that the
  Stage 3a ML-DSA improvements were only a one-off capture artifact.
- The cleanest reading is scheme-specific: PRD invalid-cycle flushing in the
  SBU is useful for the ML-DSA datapath, especially ML-DSA PWM, but it is
  counterproductive for ML-KEM in this placement.
- Therefore the next logically consistent variant is not "more PRD everywhere."
  It is a hybrid: preserve Stage 2 zero blanking for ML-KEM invalid cycles and
  apply PRD op-matched invalid flushing only when `sel_i[8]` selects ML-DSA.

## Stage 3c Log

Status: measured, not accepted as the final active countermeasure.

Strategy:

- Keep Stage 2 zero blanking for ML-KEM invalid cycles.
- Apply Stage 3b op-matched PRD invalid flushing only when the current selector
  is ML-DSA (`sel_i[8] == 1`).
- Rationale: Stage 3b showed useful ML-DSA NTT/PWM reductions but harmful
  ML-KEM reductions. Stage 3c tests whether a scheme-gated hybrid can keep both
  sides' best behavior.

Implementation file:

- `rtl/sbu/superbutterfly_sbu_routed.v`

Verification results:

- Key Verilator regression: pass for `tb_phoenix_host_io`, `tb_phoenix_core`,
  `tb_phoenix_cw305_wrapper`, `tb_phoenix_mldsa_pwm_io`, and
  `tb_superbutterfly_all_modes`.
- Consistency diagnostic: pass.
- Bank-conflict diagnostic: pass.
- Vivado still inferred 8 RAMB36 true dual-port memories.
- Final post-route timing: WNS = 0.255 ns, TNS = 0.000 ns, WHS = 0.071 ns,
  THS = 0.000 ns.
- Hardware smoke TVLA: pass for `mlkem_intt`, `mldsa_ntt`, and `mldsa_pwm`
  with one trace per group.

TVLA command:

```sh
OUTDIR=reports/tvla/mlkem_mldsa_blanking_stage3c_hybrid_20260520_cw305_husky_1000 \
OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' \
TRACES=1000 SECRET_DIST=auto \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```

Comparison artifacts:

- `reports/tvla/mlkem_mldsa_blanking_stage3c_hybrid_20260520_cw305_husky_1000/summary.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage3c_hybrid_20260520_cw305_husky_1000/comparison_vs_baseline.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage3c_hybrid_20260520_cw305_husky_1000/comparison_vs_baseline.png`
- `reports/tvla/mlkem_mldsa_blanking_stage3c_hybrid_20260520_cw305_husky_1000/comparison_vs_stage2.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage3c_hybrid_20260520_cw305_husky_1000/comparison_vs_stage2.png`
- `reports/tvla/mlkem_mldsa_blanking_stage3c_hybrid_20260520_cw305_husky_1000/mlkem_mldsa_tvla_overview.png`

Results vs baseline:

| Operation | Baseline max abs t | Stage 3c max abs t | Delta | Delta % | Cycles |
|---|---:|---:|---:|---:|---:|
| `mlkem_ntt` | 84.901 | 142.259 | +57.358 | +67.56% | 248 |
| `mlkem_intt` | 65.052 | 79.685 | +14.632 | +22.49% | 248 |
| `mlkem_pwm` | 114.713 | 114.232 | -0.480 | -0.42% | 149 |
| `mldsa_ntt` | 132.180 | 106.959 | -25.221 | -19.08% | 538 |
| `mldsa_intt` | 135.012 | 114.004 | -21.008 | -15.56% | 538 |
| `mldsa_pwm` | 144.055 | 68.711 | -75.344 | -52.30% | 140 |

Results vs Stage 2:

| Operation | Stage 2 max abs t | Stage 3c max abs t | Delta | Delta % |
|---|---:|---:|---:|---:|
| `mlkem_ntt` | 108.431 | 142.259 | +33.829 | +31.20% |
| `mlkem_intt` | 32.655 | 79.685 | +47.030 | +144.02% |
| `mlkem_pwm` | 108.878 | 114.232 | +5.354 | +4.92% |
| `mldsa_ntt` | 140.159 | 106.959 | -33.200 | -23.69% |
| `mldsa_intt` | 134.793 | 114.004 | -20.790 | -15.42% |
| `mldsa_pwm` | 155.781 | 68.711 | -87.070 | -55.89% |

Stage 3c interpretation:

- Stage 3c did keep the ML-DSA benefit, and `mldsa_pwm` reached the lowest
  observed value so far at 68.7.
- The ML-KEM side still regressed badly, especially `mlkem_ntt`. This is the
  key clue: ML-KEM invalid operands were zero in Stage 3c, so the regression
  cannot be explained only by PRD being fed into ML-KEM arithmetic.
- The remaining new switching source during ML-KEM is the free-running LFSR
  itself. Because `blank_lfsr` advances every clock, Stage 3c still adds an
  always-on public toggling source even in ML-KEM operations where PRD is not
  used. That is not faithful to OpenTitan's operation-scoped PRD clearing model
  and appears to be counterproductive for the ML-KEM traces.

Next ablation:

- Stage 3d: keep the Stage 3c hybrid input behavior, but advance the LFSR only
  when an ML-DSA invalid-cycle flush is actually being emitted. This removes
  the always-on PRD toggling from ML-KEM measurements while preserving the
  ML-DSA flush mechanism.

## Stage 3d Log

Status: measured, best balanced RTL candidate so far, but still not a TVLA pass.

Strategy:

- Keep Stage 3c's scheme-gated behavior: ML-KEM invalid cycles use Stage 2 zero
  blanking, and only ML-DSA invalid cycles use op-matched PRD flushing.
- Gate the PRD LFSR itself with the same ML-DSA invalid-cycle condition. The
  public dummy generator no longer free-runs during ML-KEM operations.
- Rationale: Stage 3c showed that even when PRD was not selected into ML-KEM
  invalid operands, the always-on LFSR still correlated with worse ML-KEM TVLA
  scores. This ablation tests whether that extra public switching source was
  the cause.

Implementation file:

- `rtl/sbu/superbutterfly_sbu_routed.v`

Functional correctness guardrails:

- The valid datapath is unchanged: when `valid_i` is high, `sel_i`, `a_i`,
  `b_i`, and `c_i` are registered exactly as before.
- The PRD branch still drives `v1 = 0`, so downstream computation from that
  branch is invalid-cycle flushing only.
- ML-KEM invalid cycles still take the zero-blanking branch.
- ML-DSA invalid cycles use `sel_i` as the dummy operation selector, preserving
  the array/schoolbook operation shape rather than forcing all dummy cycles into
  one operation class.

Verification results:

- Key Verilator regression: pass for `tb_phoenix_host_io`, `tb_phoenix_core`,
  `tb_phoenix_cw305_wrapper`, `tb_phoenix_mldsa_pwm_io`, and
  `tb_superbutterfly_all_modes`.
- Consistency diagnostic: pass.
- Bank-conflict diagnostic: pass.
- Final post-route timing: WNS = 0.033 ns, TNS = 0.000 ns, WHS = 0.066 ns,
  THS = 0.000 ns. This is still passing, but much tighter than previous
  candidates and should be treated as a hardware-integration risk.
- A three-operation subset repeat (`mlkem_ntt`, `mlkem_intt`, `mldsa_pwm`) gave
  92.196, 43.997, and 70.945 respectively, matching the full-run direction.

TVLA command:

```sh
OUTDIR=reports/tvla/mlkem_mldsa_blanking_stage3d_gated_lfsr_20260520_cw305_husky_1000 \
OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' \
TRACES=1000 SECRET_DIST=auto \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```

Comparison artifacts:

- `reports/tvla/mlkem_mldsa_blanking_stage3d_gated_lfsr_20260520_cw305_husky_1000/summary.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage3d_gated_lfsr_20260520_cw305_husky_1000/comparison_vs_baseline.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage3d_gated_lfsr_20260520_cw305_husky_1000/comparison_vs_baseline.png`
- `reports/tvla/mlkem_mldsa_blanking_stage3d_gated_lfsr_20260520_cw305_husky_1000/comparison_vs_stage2.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage3d_gated_lfsr_20260520_cw305_husky_1000/comparison_vs_stage2.png`
- `reports/tvla/mlkem_mldsa_blanking_stage3d_gated_lfsr_20260520_cw305_husky_1000/mlkem_mldsa_tvla_overview.png`

Results vs baseline:

| Operation | Baseline max abs t | Stage 3d max abs t | Delta | Delta % | Cycles |
|---|---:|---:|---:|---:|---:|
| `mlkem_ntt` | 84.901 | 95.158 | +10.258 | +12.08% | 248 |
| `mlkem_intt` | 65.052 | 44.948 | -20.105 | -30.91% | 248 |
| `mlkem_pwm` | 114.713 | 123.480 | +8.767 | +7.64% | 149 |
| `mldsa_ntt` | 132.180 | 92.929 | -39.250 | -29.69% | 538 |
| `mldsa_intt` | 135.012 | 130.465 | -4.547 | -3.37% | 538 |
| `mldsa_pwm` | 144.055 | 71.915 | -72.140 | -50.08% | 140 |

Results vs Stage 2:

| Operation | Stage 2 max abs t | Stage 3d max abs t | Delta | Delta % |
|---|---:|---:|---:|---:|
| `mlkem_ntt` | 108.431 | 95.158 | -13.272 | -12.24% |
| `mlkem_intt` | 32.655 | 44.948 | +12.293 | +37.65% |
| `mlkem_pwm` | 108.878 | 123.480 | +14.602 | +13.41% |
| `mldsa_ntt` | 140.159 | 92.929 | -47.229 | -33.70% |
| `mldsa_intt` | 134.793 | 130.465 | -4.328 | -3.21% |
| `mldsa_pwm` | 155.781 | 71.915 | -83.865 | -53.84% |

Stage 3d interpretation:

- Gating the LFSR strongly supports the Stage 3c root-cause hypothesis. ML-KEM
  NTT fell from 142.259 in Stage 3c to 95.158 in Stage 3d, and ML-KEM INTT fell
  from 79.685 to 44.948. Because ML-KEM invalid operands were zero in both
  stages, the unusual Stage 3c regression was most likely caused by always-on
  dummy-generator switching rather than by dummy operands entering the ML-KEM
  arithmetic.
- The ML-DSA benefit remains. `mldsa_pwm` is still roughly half of baseline
  (71.915 vs 144.055), and `mldsa_ntt` is down by about 30%.
- `mlkem_pwm` remains worse than both baseline and Stage 2. Since Stage 3d does
  not emit PRD during ML-KEM invalid cycles, this is unlikely to be a simple
  invalid-cycle PRD problem. More plausible causes are placement/routing changes
  from the extra PRD logic, active-cycle cascade leakage in the PWM datapath, or
  capture-order/predecessor-state bias in the current paired TVLA methodology.
- All six operations still exceed the 4.5 fixed-vs-random TVLA threshold. Stage
  3d is therefore not a complete side-channel countermeasure. It is a useful
  blanking/flush improvement for ML-DSA idle/residual behavior, while active
  secret-dependent arithmetic still needs deeper protection such as masking,
  hiding, or a more targeted architectural change.

Next ablation:

- Methodology check: add a balanced shuffled capture order. The current capture
  loop records one fixed trace and then one random trace every iteration. That
  is good for slow drift cancellation, but it can confound residual-state
  experiments because fixed traces always follow a previous random trace and
  random traces always follow the just-captured fixed trace. A shuffled order
  will test whether the Stage 3d ranking is robust to trace predecessor order.

## Stage 3d Methodology Check: Shuffled Capture Order

Status: measured.

Purpose:

- Keep the Stage 3d bitstream unchanged.
- Keep the same 1000 fixed vs 1000 random trace count, same secret distributions,
  same slots, and same fixed secret seed.
- Change only the capture schedule from deterministic fixed-then-random pairs to
  a balanced shuffled order.
- This isolates whether the current paired TVLA loop is creating
  predecessor-state bias in residual-blanking experiments.

Implementation files:

- `scripts/tvla/phoenix_capture_tvla.py`
- `scripts/tvla/run_mlkem_mldsa_1000.sh`

Command:

```sh
OUTDIR=reports/tvla/mlkem_mldsa_blanking_stage3d_gated_lfsr_shuffle_20260520_cw305_husky_1000 \
OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' \
TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0x5EED \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```

Artifacts:

- `reports/tvla/mlkem_mldsa_blanking_stage3d_gated_lfsr_shuffle_20260520_cw305_husky_1000/summary.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage3d_gated_lfsr_shuffle_20260520_cw305_husky_1000/comparison_vs_stage3d_paired.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage3d_gated_lfsr_shuffle_20260520_cw305_husky_1000/comparison_vs_stage3d_paired.png`
- `reports/tvla/mlkem_mldsa_blanking_stage3d_gated_lfsr_shuffle_20260520_cw305_husky_1000/comparison_vs_baseline.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage3d_gated_lfsr_shuffle_20260520_cw305_husky_1000/comparison_vs_baseline.png`
- `reports/tvla/mlkem_mldsa_blanking_stage3d_gated_lfsr_shuffle_20260520_cw305_husky_1000/comparison_vs_stage2.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage3d_gated_lfsr_shuffle_20260520_cw305_husky_1000/comparison_vs_stage2.png`
- `reports/tvla/mlkem_mldsa_blanking_stage3d_gated_lfsr_shuffle_20260520_cw305_husky_1000/mlkem_mldsa_tvla_overview.png`

Results vs Stage 3d paired:

| Operation | Stage 3d paired max abs t | Stage 3d shuffled max abs t | Delta | Delta % |
|---|---:|---:|---:|---:|
| `mlkem_ntt` | 95.158 | 99.210 | +4.051 | +4.26% |
| `mlkem_intt` | 44.948 | 44.315 | -0.633 | -1.41% |
| `mlkem_pwm` | 123.480 | 114.901 | -8.579 | -6.95% |
| `mldsa_ntt` | 92.929 | 94.490 | +1.560 | +1.68% |
| `mldsa_intt` | 130.465 | 127.071 | -3.394 | -2.60% |
| `mldsa_pwm` | 71.915 | 71.935 | +0.020 | +0.03% |

Results vs baseline:

| Operation | Baseline max abs t | Stage 3d shuffled max abs t | Delta | Delta % |
|---|---:|---:|---:|---:|
| `mlkem_ntt` | 84.901 | 99.210 | +14.309 | +16.85% |
| `mlkem_intt` | 65.052 | 44.315 | -20.738 | -31.88% |
| `mlkem_pwm` | 114.713 | 114.901 | +0.189 | +0.16% |
| `mldsa_ntt` | 132.180 | 94.490 | -37.690 | -28.51% |
| `mldsa_intt` | 135.012 | 127.071 | -7.941 | -5.88% |
| `mldsa_pwm` | 144.055 | 71.935 | -72.120 | -50.06% |

Results vs Stage 2:

| Operation | Stage 2 max abs t | Stage 3d shuffled max abs t | Delta | Delta % |
|---|---:|---:|---:|---:|
| `mlkem_ntt` | 108.431 | 99.210 | -9.221 | -8.50% |
| `mlkem_intt` | 32.655 | 44.315 | +11.660 | +35.71% |
| `mlkem_pwm` | 108.878 | 114.901 | +6.023 | +5.53% |
| `mldsa_ntt` | 140.159 | 94.490 | -45.669 | -32.58% |
| `mldsa_intt` | 134.793 | 127.071 | -7.722 | -5.73% |
| `mldsa_pwm` | 155.781 | 71.935 | -83.845 | -53.82% |

Shuffled-order interpretation:

- The Stage 3d ranking is robust. Five of six operations moved by less than 7%
  relative to the paired Stage 3d run, and the peak indices stayed identical for
  all six operations. This means the main Stage 3d conclusions are not explained
  by fixed-then-random predecessor ordering.
- `mldsa_pwm` is especially stable: 71.915 paired vs 71.935 shuffled. This is
  strong evidence that the ML-DSA PWM improvement is an RTL effect of the
  scheme-gated PRD invalid-cycle flush, not a capture-order artifact.
- The unusual `mlkem_pwm` regression softened from 123.480 paired to 114.901
  shuffled. This suggests that the paired order was adding some run-order or
  predecessor-state sensitivity for PWM, but it does not make the operation safe:
  the shuffled result is still essentially equal to the original baseline and
  still far above the TVLA threshold.
- Because the shuffled ML-KEM PWM peak index stayed at 63, the remaining
  leakage is likely tied to the active PWM computation window rather than a
  random capture-order spike. Invalid-cycle blanking alone is not the right
  lever for that signal.

Decision after methodology check:

- Treat Stage 3d as the best blanking candidate so far for ML-DSA, especially
  `mldsa_pwm`.
- Do not claim first-order TVLA success. The next useful experiments should
  separate active arithmetic leakage from blanking/placement side effects,
  rather than adding more invalid-cycle PRD globally.

## Peak-Location Check

Status: analyzed from existing NPZ/summary files.

Purpose:

- Determine whether the large TVLA peaks move with blanking policy or stay tied
  to stable active-cycle locations.
- A stable peak index across baseline/blanking variants suggests active
  arithmetic leakage, not invalid-cycle residue.

Selected peak locations:

| Operation | Baseline peak | Stage 2 peak | Stage 3d shuffled peak | Notes |
|---|---:|---:|---:|---|
| `mlkem_ntt` | 219 | 116 | 217 | Blanking policy moves the dominant peak. |
| `mlkem_intt` | 250 | 188 | 182 | Stage 2/3d peaks are in the same region. |
| `mlkem_pwm` | 63 | 63 | 63 | Stable across all measured variants. |
| `mldsa_ntt` | 63 | 425 | 327 | PRD changes both magnitude and location. |
| `mldsa_intt` | 213 | 412 | 123 | Sensitive to blanking/placement. |
| `mldsa_pwm` | 115 | 115 | 134 | PRD changes the dominant peak cluster. |

PWM top-peak details:

- `mlkem_pwm` baseline top peaks: 63:114.7, 62:90.7, 64:85.3.
- `mlkem_pwm` Stage 3d shuffled top peaks: 63:114.9, 62:84.6, 64:80.9.
- `mldsa_pwm` baseline top peaks: 115:144.1, 106:116.1, 114:102.9.
- `mldsa_pwm` Stage 3d shuffled top peaks: 134:-71.9, 114:68.4,
  106:68.1, 115:68.0.

Interpretation:

- `mlkem_pwm` is dominated by the same active-cycle window at sample/cycle index
  63 regardless of blanking policy. This explains why invalid-cycle PRD does
  not materially improve ML-KEM PWM.
- `mldsa_pwm` is different: PRD invalid flushing changes both the dominant peak
  and its magnitude. This supports the idea that residual or idle pipeline state
  contributes to the ML-DSA PWM measurement.

## Stage 3e Log: No-PRD Control

Status: measured control, not an accepted countermeasure.

Strategy:

- Keep the Stage 3d code shape but set `USE_PRD_INVALID_BLANKING = 1'b0`.
- This disables PRD invalid-cycle flushing and returns the SBU to zero blanking
  for invalid cycles.
- Purpose: verify whether the Stage 3d ML-DSA benefit really comes from PRD
  invalid flushing, or whether it could be a placement/build artifact.

Verification results:

- Key Verilator regression: pass for `tb_phoenix_host_io`, `tb_phoenix_core`,
  `tb_phoenix_cw305_wrapper`, `tb_phoenix_mldsa_pwm_io`, and
  `tb_superbutterfly_all_modes`.
- Consistency diagnostic: pass.
- Bank-conflict diagnostic: pass.
- Final post-route timing: WNS = 0.087 ns, TNS = 0.000 ns, WHS = 0.078 ns,
  THS = 0.000 ns.

Command:

```sh
OUTDIR=reports/tvla/mlkem_mldsa_blanking_stage3e_no_prd_shuffle_20260520_cw305_husky_1000 \
OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' \
TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0x5EED \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```

Artifacts:

- `reports/tvla/mlkem_mldsa_blanking_stage3e_no_prd_shuffle_20260520_cw305_husky_1000/summary.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage3e_no_prd_shuffle_20260520_cw305_husky_1000/comparison_vs_stage3d_shuffle.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage3e_no_prd_shuffle_20260520_cw305_husky_1000/comparison_vs_stage2.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage3e_no_prd_shuffle_20260520_cw305_husky_1000/comparison_vs_baseline.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage3e_no_prd_shuffle_20260520_cw305_husky_1000/mlkem_mldsa_tvla_overview.png`

Results vs Stage 3d shuffled:

| Operation | Stage 3d shuffled max abs t | Stage 3e max abs t | Delta | Delta % |
|---|---:|---:|---:|---:|
| `mlkem_ntt` | 99.210 | 105.942 | +6.732 | +6.79% |
| `mlkem_intt` | 44.315 | 35.023 | -9.292 | -20.97% |
| `mlkem_pwm` | 114.901 | 114.851 | -0.050 | -0.04% |
| `mldsa_ntt` | 94.490 | 146.369 | +51.880 | +54.91% |
| `mldsa_intt` | 127.071 | 125.538 | -1.533 | -1.21% |
| `mldsa_pwm` | 71.935 | 141.801 | +69.865 | +97.12% |

Stage 3e interpretation:

- Disabling PRD almost completely removes the Stage 3d ML-DSA PWM improvement:
  71.935 becomes 141.801.
- ML-DSA NTT also regresses strongly: 94.490 becomes 146.369.
- Therefore the Stage 3d ML-DSA NTT/PWM reduction is not just a shuffled-order
  artifact or a generic placement artifact. It depends on the PRD invalid-cycle
  flush being enabled.
- ML-KEM PWM stays around the same active peak at index 63. Again, this supports
  the conclusion that ML-KEM PWM needs a different countermeasure than
  invalid-cycle blanking.

## Stage 3f Log: Targeted ML-DSA NTT/PWM PRD

Status: measured tradeoff candidate, not accepted as the balanced final patch.

Strategy:

- Enable PRD invalid-cycle flushing only when `sel_i` is `SBU_MLDSA_NTT` or
  `SBU_MLDSA_PWM`.
- Leave ML-KEM and ML-DSA INTT invalid cycles on zero blanking.
- Rationale: Stage 3e showed PRD is necessary for ML-DSA NTT/PWM, while ML-DSA
  INTT did not clearly benefit from PRD in Stage 3d.

Verification results:

- Key Verilator regression: pass for `tb_phoenix_host_io`, `tb_phoenix_core`,
  `tb_phoenix_cw305_wrapper`, `tb_phoenix_mldsa_pwm_io`, and
  `tb_superbutterfly_all_modes`.
- Consistency diagnostic: pass.
- Bank-conflict diagnostic: pass.
- Final post-route timing: WNS = 0.206 ns, TNS = 0.000 ns, WHS = 0.090 ns,
  THS = 0.000 ns. This is the healthiest timing margin among Stage 3d/3e/3f.

Command:

```sh
OUTDIR=reports/tvla/mlkem_mldsa_blanking_stage3f_targeted_prd_shuffle_20260520_cw305_husky_1000 \
OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' \
TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0x5EED \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```

Artifacts:

- `reports/tvla/mlkem_mldsa_blanking_stage3f_targeted_prd_shuffle_20260520_cw305_husky_1000/summary.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage3f_targeted_prd_shuffle_20260520_cw305_husky_1000/comparison_vs_stage3d_shuffle.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage3f_targeted_prd_shuffle_20260520_cw305_husky_1000/comparison_vs_stage3e_shuffle.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage3f_targeted_prd_shuffle_20260520_cw305_husky_1000/comparison_vs_baseline.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage3f_targeted_prd_shuffle_20260520_cw305_husky_1000/comparison_vs_stage2.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage3f_targeted_prd_shuffle_20260520_cw305_husky_1000/mlkem_mldsa_tvla_overview.png`

Results vs Stage 3d shuffled:

| Operation | Stage 3d shuffled max abs t | Stage 3f max abs t | Delta | Delta % |
|---|---:|---:|---:|---:|
| `mlkem_ntt` | 99.210 | 97.873 | -1.337 | -1.35% |
| `mlkem_intt` | 44.315 | 69.397 | +25.082 | +56.60% |
| `mlkem_pwm` | 114.901 | 113.071 | -1.830 | -1.59% |
| `mldsa_ntt` | 94.490 | 84.613 | -9.877 | -10.45% |
| `mldsa_intt` | 127.071 | 147.020 | +19.949 | +15.70% |
| `mldsa_pwm` | 71.935 | 69.409 | -2.526 | -3.51% |

Results vs baseline:

| Operation | Baseline max abs t | Stage 3f max abs t | Delta | Delta % |
|---|---:|---:|---:|---:|
| `mlkem_ntt` | 84.901 | 97.873 | +12.972 | +15.28% |
| `mlkem_intt` | 65.052 | 69.397 | +4.345 | +6.68% |
| `mlkem_pwm` | 114.713 | 113.071 | -1.642 | -1.43% |
| `mldsa_ntt` | 132.180 | 84.613 | -47.567 | -35.99% |
| `mldsa_intt` | 135.012 | 147.020 | +12.008 | +8.89% |
| `mldsa_pwm` | 144.055 | 69.409 | -74.646 | -51.82% |

INTT repeat:

```sh
OUTDIR=reports/tvla/mlkem_mldsa_blanking_stage3f_targeted_prd_intt_repeat_20260520_cw305_husky_1000 \
OPS='mlkem_intt mldsa_intt' \
TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0xA11CE \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```

Repeat results:

| Operation | Stage 3f full max abs t | Stage 3f repeat max abs t | Repeat peak |
|---|---:|---:|---:|
| `mlkem_intt` | 69.397 | 71.813 | 209 |
| `mldsa_intt` | 147.020 | 151.225 | 412 |

Stage 3f interpretation:

- Stage 3f is excellent for the exact operations it targets: `mldsa_ntt` and
  `mldsa_pwm` are the lowest measured so far.
- The improvement is not free. Both INTT measurements regress, and the repeat
  confirms that the INTT regression is reproducible on this bitstream.
- The most plausible cause is physical/selector-policy interaction rather than
  a functional bug: functional regression and bank diagnostics pass, cycle
  counts are unchanged, and the peaks are stable. Narrowing PRD changes the
  synthesized cone and placement enough to hurt the INTT active/leakage windows.
- As a single all-operation bitstream, Stage 3d is still more balanced. Stage 3f
  is useful evidence that operation-specific PRD can optimize NTT/PWM, but it
  should not replace Stage 3d without an additional INTT-specific mitigation.

## Stage 3g Log: Balanced PRD Repeat

Status: measured repeat; superseded by Stage 4a as the active RTL, but still the
cleanest invalid-cycle-only countermeasure.

Strategy:

- Return from Stage 3f's NTT/PWM-only policy to the balanced Stage 3d policy:
  apply PRD invalid-cycle flushing to all ML-DSA selectors.
- Keep ML-KEM invalid cycles on zero blanking.
- Purpose: confirm that Stage 3d's balanced result is reproducible after the
  Stage 3e/3f ablations.

Verification results:

- Key Verilator regression: pass.
- Consistency diagnostic: pass.
- Bank-conflict diagnostic: pass.
- Final post-route timing: WNS = 0.033 ns, TNS = 0.000 ns, WHS = 0.066 ns,
  THS = 0.000 ns.

Command:

```sh
OUTDIR=reports/tvla/mlkem_mldsa_blanking_stage3g_balanced_prd_repeat_20260520_cw305_husky_1000 \
OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' \
TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0x5EED \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```

Results vs Stage 3d shuffled:

| Operation | Stage 3d shuffled max abs t | Stage 3g max abs t | Delta | Delta % |
|---|---:|---:|---:|---:|
| `mlkem_ntt` | 99.210 | 98.885 | -0.325 | -0.33% |
| `mlkem_intt` | 44.315 | 48.363 | +4.048 | +9.13% |
| `mlkem_pwm` | 114.901 | 120.513 | +5.612 | +4.88% |
| `mldsa_ntt` | 94.490 | 93.214 | -1.276 | -1.35% |
| `mldsa_intt` | 127.071 | 121.693 | -5.378 | -4.23% |
| `mldsa_pwm` | 71.935 | 74.868 | +2.932 | +4.08% |

Stage 3g interpretation:

- The balanced PRD policy is reproducible. All six operations stay within about
  10% of Stage 3d shuffled, and peak locations are stable.
- Compared with Stage 3f, the balanced policy fixes the reproducible INTT
  regression while giving up only a small amount on `mldsa_ntt` and `mldsa_pwm`.
- The downside is timing: WNS = 0.033 ns is passing but thin.

## Stage 4a Log: Active COMP Blanking

Status: measured; current active RTL candidate.

Strategy:

- Keep Stage 3g's balanced ML-DSA PRD invalid-cycle flushing.
- Add active-cycle blanking for COMP inputs that are not used by the selected
  operation:
  - COMP2 is driven only for inverse transform modes where `comp2_y` feeds the
    multiplier.
  - COMP1 is zeroed for operations such as ML-DSA PWM where its output is not
    selected.
  - COMP4 is driven only for NTT and ML-KEM PWM1 where its output is selected.
- Rationale: this is closer to OpenTitan-style datapath blanking than invalid
  cycle flushing alone, because it stops unused active arithmetic cones from
  switching on secret operands.

Functional correctness guardrails:

- SuperButterfly latency and valid handling are unchanged.
- Output mux behavior is unchanged.
- Only inputs to arithmetic blocks whose outputs are unused for the current
  selector are blanked.
- Verilator, consistency, and bank-conflict diagnostics all passed.

Verification and implementation:

- Implementation file: `rtl/sbu/superbutterfly_sbu_routed.v`
- Key Verilator regression: pass.
- Consistency diagnostic: pass.
- Bank-conflict diagnostic: pass.
- Final post-route timing: WNS = 0.238 ns, TNS = 0.000 ns, WHS = 0.087 ns,
  THS = 0.000 ns. This is much healthier than Stage 3g.

Command:

```sh
OUTDIR=reports/tvla/mlkem_mldsa_blanking_stage4a_active_comp_blanking_20260520_cw305_husky_1000 \
OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' \
TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0x5EED \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```

Artifacts:

- `reports/tvla/mlkem_mldsa_blanking_stage4a_active_comp_blanking_20260520_cw305_husky_1000/summary.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage4a_active_comp_blanking_20260520_cw305_husky_1000/comparison_vs_stage3g.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage4a_active_comp_blanking_20260520_cw305_husky_1000/comparison_vs_stage3f.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage4a_active_comp_blanking_20260520_cw305_husky_1000/comparison_vs_baseline.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage4a_active_comp_blanking_20260520_cw305_husky_1000/comparison_vs_stage2.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage4a_active_comp_blanking_20260520_cw305_husky_1000/mlkem_mldsa_tvla_overview.png`

Results vs Stage 3g:

| Operation | Stage 3g max abs t | Stage 4a max abs t | Delta | Delta % |
|---|---:|---:|---:|---:|
| `mlkem_ntt` | 98.885 | 88.877 | -10.008 | -10.12% |
| `mlkem_intt` | 48.363 | 69.162 | +20.799 | +43.01% |
| `mlkem_pwm` | 120.513 | 112.912 | -7.602 | -6.31% |
| `mldsa_ntt` | 93.214 | 93.286 | +0.072 | +0.08% |
| `mldsa_intt` | 121.693 | 116.608 | -5.085 | -4.18% |
| `mldsa_pwm` | 74.868 | 69.567 | -5.301 | -7.08% |

Results vs baseline:

| Operation | Baseline max abs t | Stage 4a max abs t | Delta | Delta % |
|---|---:|---:|---:|---:|
| `mlkem_ntt` | 84.901 | 88.877 | +3.977 | +4.68% |
| `mlkem_intt` | 65.052 | 69.162 | +4.109 | +6.32% |
| `mlkem_pwm` | 114.713 | 112.912 | -1.801 | -1.57% |
| `mldsa_ntt` | 132.180 | 93.286 | -38.894 | -29.43% |
| `mldsa_intt` | 135.012 | 116.608 | -18.404 | -13.63% |
| `mldsa_pwm` | 144.055 | 69.567 | -74.488 | -51.71% |

Key repeat:

```sh
OUTDIR=reports/tvla/mlkem_mldsa_blanking_stage4a_active_comp_blanking_key_repeat_20260520_cw305_husky_1000 \
OPS='mlkem_intt mldsa_intt mldsa_pwm' \
TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0xB10C \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```

Repeat results:

| Operation | Stage 4a full max abs t | Stage 4a repeat max abs t | Repeat peak |
|---|---:|---:|---:|
| `mlkem_intt` | 69.162 | 67.735 | 182 |
| `mldsa_intt` | 116.608 | 122.229 | 123 |
| `mldsa_pwm` | 69.567 | 71.009 | 114 |

Stage 4a interpretation:

- Stage 4a is the best all-operation candidate so far by the worst observed
  operation in the full run: the maximum drops to 116.608, compared with 121.693
  for Stage 3g and 127.071 for Stage 3d shuffled.
- The ML-DSA side is consistently better or comparable: `mldsa_pwm` stays near
  70 and `mldsa_intt` improves relative to Stage 3g.
- `mlkem_ntt` and `mlkem_pwm` improve relative to Stage 3g, but `mlkem_intt`
  regresses reproducibly. This is the main Stage 4a tradeoff.
- The likely cause is that INTT genuinely uses COMP2 in the active path, so the
  new selector-dependent blanking logic changes the nearby arithmetic cone and
  placement even though functional behavior is unchanged. This looks like a
  physical/leakage-shape tradeoff, not a logical correctness failure.
- Stage 4a still does not pass first-order TVLA. It is a stronger datapath
  blanking patch, not a masking scheme.

## Stage 4b Log: ML-KEM INTT COMP4 Exception

Status: measured; current best active RTL candidate.

Strategy:

- Keep Stage 4a active COMP blanking.
- Add one exception: for ML-KEM INTT (`SBU_INTT_GS`), drive COMP4 with the
  previous active inputs (`a6`, `p6`) instead of zeroing COMP4.
- Keep ML-DSA INTT COMP4 blanked.
- Rationale: Stage 4a's main regression was reproducible on `mlkem_intt`.
  During INTT, COMP2 and COMP1 are functionally used, while COMP4 is unused.
  Therefore the only active arithmetic cone changed specifically for INTT was
  COMP4 blanking. Stage 4b tests whether restoring COMP4 switching only for
  ML-KEM INTT recovers that operation without giving up the Stage 4a benefits.

Verification and implementation:

- Implementation file: `rtl/sbu/superbutterfly_sbu_routed.v`
- Key Verilator regression: pass.
- Consistency diagnostic: pass.
- Bank-conflict diagnostic: pass.
- Final post-route timing: WNS = 0.203 ns, TNS = 0.000 ns, WHS = 0.063 ns,
  THS = 0.000 ns.

Command:

```sh
OUTDIR=reports/tvla/mlkem_mldsa_blanking_stage4b_kem_intt_comp4_exception_20260520_cw305_husky_1000 \
OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' \
TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0x5EED \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```

Artifacts:

- `reports/tvla/mlkem_mldsa_blanking_stage4b_kem_intt_comp4_exception_20260520_cw305_husky_1000/summary.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage4b_kem_intt_comp4_exception_20260520_cw305_husky_1000/comparison_vs_stage4a.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage4b_kem_intt_comp4_exception_20260520_cw305_husky_1000/comparison_vs_stage3g.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage4b_kem_intt_comp4_exception_20260520_cw305_husky_1000/comparison_vs_baseline.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage4b_kem_intt_comp4_exception_20260520_cw305_husky_1000/comparison_vs_stage2.csv`
- `reports/tvla/mlkem_mldsa_blanking_stage4b_kem_intt_comp4_exception_20260520_cw305_husky_1000/mlkem_mldsa_tvla_overview.png`

Results vs Stage 4a:

| Operation | Stage 4a max abs t | Stage 4b max abs t | Delta | Delta % |
|---|---:|---:|---:|---:|
| `mlkem_ntt` | 88.877 | 96.516 | +7.639 | +8.60% |
| `mlkem_intt` | 69.162 | 42.888 | -26.274 | -37.99% |
| `mlkem_pwm` | 112.912 | 103.869 | -9.042 | -8.01% |
| `mldsa_ntt` | 93.286 | 85.738 | -7.548 | -8.09% |
| `mldsa_intt` | 116.608 | 112.877 | -3.731 | -3.20% |
| `mldsa_pwm` | 69.567 | 78.170 | +8.603 | +12.37% |

Results vs baseline:

| Operation | Baseline max abs t | Stage 4b max abs t | Delta | Delta % |
|---|---:|---:|---:|---:|
| `mlkem_ntt` | 84.901 | 96.516 | +11.616 | +13.68% |
| `mlkem_intt` | 65.052 | 42.888 | -22.165 | -34.07% |
| `mlkem_pwm` | 114.713 | 103.869 | -10.843 | -9.45% |
| `mldsa_ntt` | 132.180 | 85.738 | -46.442 | -35.14% |
| `mldsa_intt` | 135.012 | 112.877 | -22.135 | -16.39% |
| `mldsa_pwm` | 144.055 | 78.170 | -65.885 | -45.74% |

Key repeat:

```sh
OUTDIR=reports/tvla/mlkem_mldsa_blanking_stage4b_kem_intt_comp4_exception_key_repeat_20260520_cw305_husky_1000 \
OPS='mlkem_pwm mldsa_intt mldsa_pwm' \
TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0xC0DEC \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```

Repeat results:

| Operation | Stage 4b full max abs t | Stage 4b repeat max abs t | Repeat peak |
|---|---:|---:|---:|
| `mlkem_pwm` | 103.869 | 105.388 | 63 |
| `mldsa_intt` | 112.877 | 114.900 | 123 |
| `mldsa_pwm` | 78.170 | 74.680 | 109 |

Stage 4b interpretation:

- Stage 4b is the best all-operation blanking candidate measured so far by
  worst-operation score: the full-run maximum is 112.877, lower than Stage 4a
  (116.608), Stage 3g (121.693), and Stage 3d shuffled (127.071).
- The ML-KEM INTT regression from Stage 4a is fixed: 69.162 becomes 42.888.
  This supports the local root-cause hypothesis that zeroing unused COMP4 during
  ML-KEM INTT changed the active leakage shape unfavorably.
- The exception also helps `mlkem_pwm`, `mldsa_ntt`, and `mldsa_intt` in this
  build, but it costs `mlkem_ntt` and `mldsa_pwm` relative to Stage 4a.
- The key repeat confirms the important Stage 4b values are stable: `mlkem_pwm`
  stays around 105, `mldsa_intt` around 113-115, and `mldsa_pwm` around 75-78.
- Stage 4b is still not a TVLA pass. The remaining peaks are active arithmetic
  leakage candidates; data-path blanking alone is not sufficient to cross the
  4.5 threshold.

Current decision:

- Keep Stage 4b as the active RTL candidate because it gives the best
  all-operation balance while preserving SuperButterfly structure and passing
  all correctness diagnostics.
- Further improvements should target the remaining active peak locations, not
  add more global invalid-cycle PRD.

## Stage 5 Log: Post-Stage-4b Small RTL Candidates

Status: measured; all Stage 5 candidates rejected. Active RTL and active
CW305 bitstream were restored to Stage 4b after the measurements.

Scope:

- The handover plan in `docs/Handover/260520_181617_sca.md` was treated as the
  basis for the Stage 5 experiments.
- Stage 4b remained the A/B baseline.
- The accelerator-level invariants were not changed: 9-bit instruction format,
  SBU latency 8, two-SBU PE shape, ML-KEM packed layout, ML-DSA one-word
  layout, 4-bank up/down memory, scheduler, cycle counts, and memory layout
  were preserved.
- Each isolated branch changed only one RTL idea relative to Stage 4b. One
  exploratory combined B1+B2+B3 run was also measured first and then rejected.

Common verification:

```sh
python3 scripts/diagnostics/check_phoenix_consistency.py
python3 scripts/diagnostics/check_bank_conflicts.py
bash sim/run_verilator.sh 'tb_comp3_agile_modmul tb_superbutterfly_all_modes tb_phoenix_core tb_phoenix_host_io tb_phoenix_cw305_wrapper tb_phoenix_mldsa_pwm_io'
```

All Stage 5 candidates passed the consistency diagnostic, bank-conflict
diagnostic, and the listed Verilator regression. All Stage 5 bitstreams met
timing, kept 8 RAMB36-equivalent block RAM tiles, and used 0 DSPs.

Common TVLA command shape:

```sh
OUTDIR=reports/tvla/<stage5_run_name> \
OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' \
TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0x5EED \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```

All Stage 5 full runs used 1000 fixed vs 1000 random traces per operation,
secret distribution `auto`, shuffled trace order, seed `0x5EED`, and no
clipping. Cycle counts stayed unchanged: ML-KEM NTT/INTT 248, ML-KEM PWM 149,
ML-DSA NTT/INTT 538, and ML-DSA PWM 140.

### Stage 5 exploratory B1+B2+B3

RTL changes:

- Exact PWM/pointwise read enable in `rtl/phoenix/phoenix_top.v`.
- ML-DSA PWM unused `a_i` blanking in `rtl/phoenix/phoenix_top.v`.
- COMP3 KEM/DSA cone blanking in `rtl/comp/comp3_agile_modmul.v`.

Build and artifacts:

- Bitstream mtime: 2026-05-20 18:31:56 KST.
- Post-route timing: WNS = 0.090 ns, TNS = 0.000 ns, WHS = 0.079 ns,
  THS = 0.000 ns.
- TVLA directory:
  `reports/tvla/mlkem_mldsa_stage5_b123_exact_read_mldsa_a0_comp3_coneblank_20260520_cw305_husky_1000`
- Comparison artifacts:
  `comparison_vs_stage4b.csv`, `comparison_vs_stage4b.png`,
  `comparison_vs_original_baseline.csv`, `comparison_vs_original_baseline.png`,
  and `mlkem_mldsa_tvla_overview.png`.

Results vs Stage 4b:

| Operation | Stage 4b max abs t | B1+B2+B3 max abs t | Delta % | Stage 4b peak | Candidate peak | Cycles |
|---|---:|---:|---:|---:|---:|---:|
| `mlkem_ntt` | 96.516 | 94.885 | -1.69% | 116 | 217 | 248 |
| `mlkem_intt` | 42.888 | 73.087 | +70.41% | 236 | 83 | 248 |
| `mlkem_pwm` | 103.869 | 100.403 | -3.34% | 63 | 98 | 149 |
| `mldsa_ntt` | 85.738 | 104.081 | +21.39% | 506 | 506 | 538 |
| `mldsa_intt` | 112.877 | 143.709 | +27.31% | 123 | 123 | 538 |
| `mldsa_pwm` | 78.170 | 86.290 | +10.39% | 109 | 105 | 140 |

Decision:

- Rejected. The worst operation worsened from Stage 4b `mldsa_intt=112.877`
  to `mldsa_intt=143.709`.
- The small PWM improvements were not enough to offset the INTT/NTT regressions.

### Stage 5 B1: exact PWM/pointwise read enable

RTL change:

- Replaced the pointwise `4'hf` core read enables in
  `rtl/phoenix/phoenix_top.v` with operation-specific read masks.
- FFT/NTT/INTT kept 4-bank reads.
- ML-KEM PWM enabled only the actual `bk0a` read bank.
- ML-DSA PWM enabled only the actual `bk0a` and `bk1a` read banks.

Build and artifacts:

- Bitstream mtime: 2026-05-20 18:43:26 KST.
- Post-route timing: WNS = 0.089 ns, TNS = 0.000 ns, WHS = 0.084 ns,
  THS = 0.000 ns.
- TVLA directory:
  `reports/tvla/mlkem_mldsa_stage5_b1_exact_read_enable_20260520_cw305_husky_1000`
- Comparison artifacts:
  `comparison_vs_stage4b.csv`, `comparison_vs_stage4b.png`,
  `comparison_vs_original_baseline.csv`, `comparison_vs_original_baseline.png`,
  and `mlkem_mldsa_tvla_overview.png`.

Results vs Stage 4b:

| Operation | Stage 4b max abs t | B1 max abs t | Delta % | Stage 4b peak | Candidate peak | Cycles |
|---|---:|---:|---:|---:|---:|---:|
| `mlkem_ntt` | 96.516 | 81.128 | -15.94% | 116 | 181 | 248 |
| `mlkem_intt` | 42.888 | 42.750 | -0.32% | 236 | 249 | 248 |
| `mlkem_pwm` | 103.869 | 114.922 | +10.64% | 63 | 63 | 149 |
| `mldsa_ntt` | 85.738 | 98.093 | +14.41% | 506 | 424 | 538 |
| `mldsa_intt` | 112.877 | 127.224 | +12.71% | 123 | 123 | 538 |
| `mldsa_pwm` | 78.170 | 68.124 | -12.85% | 109 | 105 | 140 |

Decision:

- Rejected. The worst operation worsened to `mldsa_intt=127.224`.
- The result is informative: exact read enable helped `mldsa_pwm` and
  `mlkem_ntt`, but made the stable `mlkem_pwm` peak at index 63 worse. This
  suggests that unused-bank read switching was acting partly as physical noise
  around active PWM arithmetic rather than being the dominant leakage source.

### Stage 5 B2: ML-DSA PWM unused `a_i` blanking

RTL change:

- In `rtl/phoenix/phoenix_top.v`, ML-DSA PWM drives `sbu0_a` and `sbu1_a` with
  zero instead of the memory-up words.
- ML-DSA PWM `sbu*_b = memory-down` and `sbu*_c = memory-up` were unchanged.

Build and artifacts:

- Bitstream mtime: 2026-05-20 18:53:03 KST.
- Post-route timing: WNS = 0.025 ns, TNS = 0.000 ns, WHS = 0.053 ns,
  THS = 0.000 ns.
- TVLA directory:
  `reports/tvla/mlkem_mldsa_stage5_b2_mldsa_pwm_a_zero_20260520_cw305_husky_1000`
- Comparison artifacts:
  `comparison_vs_stage4b.csv`, `comparison_vs_stage4b.png`,
  `comparison_vs_original_baseline.csv`, `comparison_vs_original_baseline.png`,
  and `mlkem_mldsa_tvla_overview.png`.

Results vs Stage 4b:

| Operation | Stage 4b max abs t | B2 max abs t | Delta % | Stage 4b peak | Candidate peak | Cycles |
|---|---:|---:|---:|---:|---:|---:|
| `mlkem_ntt` | 96.516 | 125.233 | +29.75% | 116 | 116 | 248 |
| `mlkem_intt` | 42.888 | 44.928 | +4.76% | 236 | 116 | 248 |
| `mlkem_pwm` | 103.869 | 102.970 | -0.87% | 63 | 63 | 149 |
| `mldsa_ntt` | 85.738 | 85.787 | +0.06% | 506 | 351 | 538 |
| `mldsa_intt` | 112.877 | 122.087 | +8.16% | 123 | 123 | 538 |
| `mldsa_pwm` | 78.170 | 69.215 | -11.46% | 109 | 134 | 140 |

Decision:

- Rejected. The worst operation moved to `mlkem_ntt=125.233`, which is worse
  than Stage 4b.
- The intended target `mldsa_pwm` improved, so the unused `a_i` chain is a real
  local leakage contributor. However, the placement/toggling side effect on
  ML-KEM NTT is too large for this to be an accepted all-operation bitstream.

### Stage 5 B3: COMP3 algorithm-cone blanking

RTL change:

- In `rtl/comp/comp3_agile_modmul.v`, KEM multiplier inputs were zeroed when
  `opmode_i=1`, and DSA multiplier inputs were zeroed when `opmode_i=0`.
- The output mux was unchanged.

Build and artifacts:

- Bitstream mtime: 2026-05-20 19:03:04 KST.
- Post-route timing: WNS = 0.189 ns, TNS = 0.000 ns, WHS = 0.053 ns,
  THS = 0.000 ns.
- Current Vivado utilization for the B3 build was 8 block RAM tiles, 0 DSPs,
  9850 LUTs, and 3285 registers.
- Smoke TVLA passed for all six operations with one trace per group.
- TVLA directory:
  `reports/tvla/mlkem_mldsa_stage5_b3_comp3_coneblank_20260520_cw305_husky_1000`
- Comparison artifacts:
  `comparison_vs_stage4b.csv`, `comparison_vs_stage4b.png`,
  `comparison_vs_original_baseline.csv`, `comparison_vs_original_baseline.png`,
  and `mlkem_mldsa_tvla_overview.png`.

Results vs Stage 4b:

| Operation | Stage 4b max abs t | B3 max abs t | Delta % | Stage 4b peak | Candidate peak | Cycles |
|---|---:|---:|---:|---:|---:|---:|
| `mlkem_ntt` | 96.516 | 84.269 | -12.69% | 116 | 217 | 248 |
| `mlkem_intt` | 42.888 | 79.262 | +84.81% | 236 | 154 | 248 |
| `mlkem_pwm` | 103.869 | 95.295 | -8.25% | 63 | 56 | 149 |
| `mldsa_ntt` | 85.738 | 119.838 | +39.77% | 506 | 506 | 538 |
| `mldsa_intt` | 112.877 | 150.301 | +33.15% | 123 | 123 | 538 |
| `mldsa_pwm` | 78.170 | 92.039 | +17.74% | 109 | 105 | 140 |

Decision:

- Rejected. The worst operation worsened to `mldsa_intt=150.301`, and both
  `mlkem_intt` and `mldsa_ntt` regressed sharply.
- The lower `mlkem_pwm` value shows that COMP3 cone blanking can affect active
  PWM leakage, but the all-operation balance is much worse than Stage 4b.

### Stage 5 B4 gate decision

B4, flopped/predecoded blanking control, was not run in this execution. The
reason is the Stage 5 reject rule: the B1/B2/B3 candidates did pass
functionality and timing, but none produced an accepted leakage baseline to
build on. In particular, B3 is the natural predecessor for B4 in the handover
matrix, and B3 increased the Stage 4b worst case from 112.877 to 150.301.

This leaves B4 as a future security-style cleanup experiment rather than a
TVLA-improvement candidate for the current small-RTL loop. If it is revisited,
it should be tested as its own branch from Stage 4b and judged primarily for
glitch-hardening and no-regression behavior, not as a likely path to first-order
TVLA pass.

### Stage 5 final decision

- No Stage 5 small RTL candidate is accepted.
- Stage 4b remains the active RTL candidate.
- The active source tree was restored to Stage 4b after B3.
- The active CW305 bitstream was rebuilt from the restored Stage 4b source:
  `boards/cw305/output/phoenix_cw305.bit`, mtime 2026-05-20 19:13:43 KST.
- Restored Stage 4b post-route timing: WNS = 0.203 ns, TNS = 0.000 ns,
  WHS = 0.063 ns, THS = 0.000 ns.
- Restored Stage 4b utilization: 8 block RAM tiles, 0 DSPs, 9727 LUTs, and
  3268 registers.
- Restored Stage 4b verification passed:
  consistency diagnostic, bank-conflict diagnostic, the key Verilator
  regression listed above, and a hardware smoke TVLA over `mlkem_pwm`,
  `mldsa_intt`, and `mldsa_pwm`.

Interpretation:

- B1 and B2 confirmed plausible local leakage contributors in the pointwise
  path, especially `mldsa_pwm`, but also showed that removing switching can
  expose or reshape larger active-cycle peaks elsewhere.
- B3 confirmed that unused algorithm-cone switching in COMP3 matters, but
  deterministic cone blanking worsened the active INTT/NTT leakage shape too
  much for this physical implementation.
- Stage 5 strengthens the Stage 4b conclusion: small deterministic blanking
  changes are now mostly trading physical noise and peak visibility around.
  They do not remove the selected modular multiplication/reduction leakage.
- Since all Stage 5 candidates remain far above the 4.5 threshold and no
  candidate improved the Stage 4b worst case, this small-RTL-only loop should
  stop here. A real TVLA-pass plan needs a separate shuffling or partial-masking
  design rather than more unused-path blanking.

## Stage 6 Log: COMP3 Inactive-Cone Dummy Blanking

Status: complete. Stage 4b remained the A/B baseline for every Stage 6
candidate. TVLA methodology stayed fixed-vs-random only; no fixed-vs-fixed or
random-vs-random controls were part of this stage.

Purpose:

- Stage 5 B3 showed that zeroing the inactive COMP3 algorithm cone affects
  leakage, but worsens the all-operation balance badly.
- Stage 6 tests whether the B3 regression came from removing inactive-cone
  switching entirely, by feeding the inactive cone deterministic or public dummy
  operands while keeping the selected cone real.
- This is still a small RTL dummy-blanking experiment, not masking, shuffling,
  or a memory/scheduler change.

Common guardrails:

- 9-bit instruction format, SBU latency 8, two-SBU PE shape, memory layout,
  scheduler, cycle counts, 30 ns CW305 clock, and `adc_mul=1` sampling are
  unchanged.
- The COMP3 output mux is unchanged. Only the non-selected KEM/DSA cone inputs
  are modified.
- All runs use 1000 fixed vs 1000 random traces per operation, secret
  distribution `auto`, shuffled trace order, and `ORDER_SEED=0x5EED`.

### Stage 6 R1: fixed balanced inactive-cone dummy

RTL change:

- In `rtl/comp/comp3_agile_modmul.v`, KEM and DSA cone inputs were separated
  internally.
- ML-KEM mode keeps the KEM cone on real `a_i/b_i` and feeds the inactive DSA
  cone with `24'h555555` and `24'h2AAAAA`.
- ML-DSA mode keeps the DSA cone on real `a_i[23:0]/b_i[23:0]` and feeds the
  inactive KEM cone with `32'h5555_AAAA` and `32'hAAAA_5555`.
- Output selection remains `opmode_i ? dsa_out : kem_out`.

Verification and build:

- Consistency diagnostic: pass.
- Bank-conflict diagnostic: pass.
- Verilator regression passed for `tb_comp3_agile_modmul`,
  `tb_superbutterfly_all_modes`, `tb_phoenix_core`, `tb_phoenix_host_io`,
  `tb_phoenix_cw305_wrapper`, and `tb_phoenix_mldsa_pwm_io`.
- Bitstream: `boards/cw305/output/phoenix_cw305.bit`, mtime
  2026-05-20 23:04:27 KST.
- Post-route timing: WNS = 0.027 ns, TNS = 0.000 ns, WHS = 0.074 ns,
  THS = 0.000 ns.
- Utilization: 9846 LUTs, 3285 registers, 8 RAMB36-equivalent block RAM tiles,
  0 DSPs.
- Hardware smoke TVLA passed for all six operations with one trace per group
  after running with CW305/ChipWhisperer USB access.

Command:

```sh
OUTDIR=reports/tvla/mlkem_mldsa_stage6_r1_fixed_dummy_comp3_20260520_cw305_husky_1000 \
OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' \
TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0x5EED \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```

Artifacts:

- `reports/tvla/mlkem_mldsa_stage6_r1_fixed_dummy_comp3_20260520_cw305_husky_1000/summary.csv`
- `reports/tvla/mlkem_mldsa_stage6_r1_fixed_dummy_comp3_20260520_cw305_husky_1000/comparison_vs_stage4b.csv`
- `reports/tvla/mlkem_mldsa_stage6_r1_fixed_dummy_comp3_20260520_cw305_husky_1000/comparison_vs_original_baseline.csv`
- `reports/tvla/mlkem_mldsa_stage6_r1_fixed_dummy_comp3_20260520_cw305_husky_1000/comparison_vs_stage5_b3.csv`
- `reports/tvla/mlkem_mldsa_stage6_r1_fixed_dummy_comp3_20260520_cw305_husky_1000/mlkem_mldsa_tvla_overview.png`

Results vs Stage 4b:

| Operation | Stage 4b max abs t | R1 max abs t | Delta % | Stage 4b peak | R1 peak | Cycles |
|---|---:|---:|---:|---:|---:|---:|
| `mlkem_ntt` | 96.516 | 92.339 | -4.33% | 116 | 237 | 248 |
| `mlkem_intt` | 42.888 | 73.380 | +71.10% | 236 | 76 | 248 |
| `mlkem_pwm` | 103.869 | 102.752 | -1.08% | 63 | 56 | 149 |
| `mldsa_ntt` | 85.738 | 105.723 | +23.31% | 506 | 506 | 538 |
| `mldsa_intt` | 112.877 | 128.424 | +13.77% | 123 | 123 | 538 |
| `mldsa_pwm` | 78.170 | 88.347 | +13.02% | 109 | 115 | 140 |

Decision:

- Rejected. Worst operation worsened from Stage 4b `mldsa_intt=112.877` to
  `mldsa_intt=128.424`, and the stable `mldsa_intt` peak stayed at index 123.
- Fixed dummy switching did not reproduce the small Stage 5 B3 `mlkem_pwm`
  improvement in a useful all-operation way. It slightly improved `mlkem_ntt`
  and `mlkem_pwm`, but worsened `mlkem_intt`, `mldsa_ntt`, `mldsa_intt`, and
  `mldsa_pwm`.
- Compared with B3 zero cone blanking, R1 softens the worst `mldsa_intt`
  regression but still remains worse than Stage 4b. This suggests that
  restoring deterministic inactive-cone switching is not enough; the remaining
  leakage is still dominated by selected active arithmetic windows and physical
  placement/leakage-shape effects.

### Stage 6 R2: public PRD inactive-cone dummy

RTL change:

- `comp3_agile_modmul` was extended with `dummy_a_i` and `dummy_b_i` inputs.
- In ML-KEM mode, the selected KEM cone still receives real `a_i/b_i`, while
  the inactive DSA cone receives `dummy_a_i[23:0]/dummy_b_i[23:0]`.
- In ML-DSA mode, the selected DSA cone still receives real
  `a_i[23:0]/b_i[23:0]`, while the inactive KEM cone receives
  `dummy_a_i/dummy_b_i`.
- `superbutterfly_sbu_routed` now owns a public active-cycle COMP3 dummy LFSR.
  It advances when the COMP3 stage is carrying a valid transaction (`v1=1`).
- The active arithmetic cone and the output mux are unchanged. The dummy source
  is public and only drives the non-selected algorithm cone.

Verification and build:

- Consistency diagnostic: pass.
- Bank-conflict diagnostic: pass.
- Verilator regression passed for `tb_comp3_agile_modmul`,
  `tb_superbutterfly_all_modes`, `tb_phoenix_core`, `tb_phoenix_host_io`,
  `tb_phoenix_cw305_wrapper`, and `tb_phoenix_mldsa_pwm_io`.
- Bitstream: `boards/cw305/output/phoenix_cw305.bit`, mtime
  2026-05-20 23:17:34 KST.
- Post-route timing: WNS = 0.357 ns, TNS = 0.000 ns, WHS = 0.057 ns,
  THS = 0.000 ns.
- Utilization: 9854 LUTs, 3348 registers, 8 RAMB36-equivalent block RAM tiles,
  0 DSPs.
- Hardware smoke TVLA passed for all six operations with one trace per group.

Command:

```sh
OUTDIR=reports/tvla/mlkem_mldsa_stage6_r2_prd_dummy_comp3_20260520_cw305_husky_1000 \
OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' \
TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0x5EED \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```

Artifacts:

- `reports/tvla/mlkem_mldsa_stage6_r2_prd_dummy_comp3_20260520_cw305_husky_1000/summary.csv`
- `reports/tvla/mlkem_mldsa_stage6_r2_prd_dummy_comp3_20260520_cw305_husky_1000/comparison_vs_stage4b.csv`
- `reports/tvla/mlkem_mldsa_stage6_r2_prd_dummy_comp3_20260520_cw305_husky_1000/comparison_vs_original_baseline.csv`
- `reports/tvla/mlkem_mldsa_stage6_r2_prd_dummy_comp3_20260520_cw305_husky_1000/comparison_vs_stage5_b3.csv`
- `reports/tvla/mlkem_mldsa_stage6_r2_prd_dummy_comp3_20260520_cw305_husky_1000/comparison_vs_stage6_r1.csv`
- `reports/tvla/mlkem_mldsa_stage6_r2_prd_dummy_comp3_20260520_cw305_husky_1000/mlkem_mldsa_tvla_overview.png`

Results vs Stage 4b:

| Operation | Stage 4b max abs t | R2 max abs t | Delta % | Stage 4b peak | R2 peak | Cycles |
|---|---:|---:|---:|---:|---:|---:|
| `mlkem_ntt` | 96.516 | 29.532 | -69.40% | 116 | 217 | 248 |
| `mlkem_intt` | 42.888 | 27.140 | -36.72% | 236 | 149 | 248 |
| `mlkem_pwm` | 103.869 | 52.516 | -49.44% | 63 | 156 | 149 |
| `mldsa_ntt` | 85.738 | 82.381 | -3.92% | 506 | 63 | 538 |
| `mldsa_intt` | 112.877 | 121.557 | +7.69% | 123 | 123 | 538 |
| `mldsa_pwm` | 78.170 | 85.713 | +9.65% | 109 | 114 | 140 |

Decision:

- Rejected as an all-operation accepted branch because the worst operation
  worsened from Stage 4b `mldsa_intt=112.877` to `mldsa_intt=121.557`, and the
  `mldsa_intt` peak stayed at index 123.
- R2 is still the most informative Stage 6 result so far. All three ML-KEM
  operations improved strongly, and `mldsa_ntt` improved slightly. This is a
  very different signal from R1 fixed dummy and B3 zero blanking.
- The result suggests that trace-varying public inactive-cone switching can
  materially reduce ML-KEM peak visibility, but it still does not solve the
  selected ML-DSA INTT active arithmetic window.
- R3 is required to separate whether the R2 improvement comes from
  trace-varying/randomized dummy phase or from the public dummy switching shape.

### Stage 6 R3a: same-seed LFSR replay, timing-failed

RTL change:

- Starting from R2, `superbutterfly_sbu_routed` was changed so the public COMP3
  dummy LFSR reloads the same seed at each valid operation burst.
- The selected arithmetic cone and COMP3 output mux remained unchanged.
- The intent was to replay the same inactive-cone dummy sequence on every trace
  and separate deterministic switching shape from trace-varying dummy phase.

Verification and build:

- Consistency diagnostic: pass.
- Bank-conflict diagnostic: pass.
- Verilator regression passed for `tb_comp3_agile_modmul`,
  `tb_superbutterfly_all_modes`, `tb_phoenix_core`, `tb_phoenix_host_io`,
  `tb_phoenix_cw305_wrapper`, and `tb_phoenix_mldsa_pwm_io`.
- Bitstream generated at `boards/cw305/output/phoenix_cw305.bit`, mtime
  2026-05-20 23:29:46 KST, but it is timing-unsafe and must not be used for
  capture.
- Post-route timing failed: WNS = -0.154 ns, TNS = -0.549 ns, WHS = 0.062 ns,
  THS = 0.000 ns.
- Utilization: 9891 LUTs, 3348 registers, 8 RAMB36-equivalent block RAM tiles,
  0 DSPs.

Decision:

- Rejected as implemented. No smoke or full TVLA was run because the bitstream
  failed the fixed 30 ns timing requirement.
- The failure appears to be a physical/timing cost of adding a seed-reload mux
  and control around the 32-bit COMP3 dummy LFSR. This does not answer the R3
  leakage question, so the next attempt is a smaller same-seed replay source
  rather than a timing-unsafe capture.

### Stage 6 R3b: same-seed counter-scramble replay

RTL change:

- `superbutterfly_sbu_routed` keeps the R2/R3 dummy datapath into
  `comp3_agile_modmul`, but replaces the 32-bit seed-reloaded LFSR with an
  8-bit operation-local counter.
- The counter resets to `8'h00` at the start of each valid operation burst and
  increments on active COMP3 pipeline cycles.
- `dummy_a_i` and `dummy_b_i` are generated by fixed public byte scrambles of
  that counter. The sequence is deterministic and replayed across traces; it
  is not a trace-varying random dummy.

Verification and build:

- Consistency diagnostic: pass.
- Bank-conflict diagnostic: pass.
- Verilator regression passed for `tb_comp3_agile_modmul`,
  `tb_superbutterfly_all_modes`, `tb_phoenix_core`, `tb_phoenix_host_io`,
  `tb_phoenix_cw305_wrapper`, and `tb_phoenix_mldsa_pwm_io`.
- Bitstream: `boards/cw305/output/phoenix_cw305.bit`, mtime
  2026-05-20 23:36:02 KST.
- Post-route timing: WNS = 0.181 ns, TNS = 0.000 ns, WHS = 0.083 ns,
  THS = 0.000 ns.
- Utilization: 9894 LUTs, 3303 registers, 8 RAMB36-equivalent block RAM tiles,
  0 DSPs.
- Hardware smoke TVLA passed for all six operations with one trace per group.

Command:

```sh
OUTDIR=reports/tvla/mlkem_mldsa_stage6_r3b_replay_dummy_comp3_20260520_cw305_husky_1000 \
OPS='mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm' \
TRACES=1000 SECRET_DIST=auto TRACE_ORDER=shuffle ORDER_SEED=0x5EED \
bash scripts/tvla/run_mlkem_mldsa_1000.sh
```

Artifacts:

- `reports/tvla/mlkem_mldsa_stage6_r3b_replay_dummy_comp3_20260520_cw305_husky_1000/summary.csv`
- `reports/tvla/mlkem_mldsa_stage6_r3b_replay_dummy_comp3_20260520_cw305_husky_1000/comparison_vs_stage4b.csv`
- `reports/tvla/mlkem_mldsa_stage6_r3b_replay_dummy_comp3_20260520_cw305_husky_1000/comparison_vs_original_baseline.csv`
- `reports/tvla/mlkem_mldsa_stage6_r3b_replay_dummy_comp3_20260520_cw305_husky_1000/comparison_vs_stage5_b3.csv`
- `reports/tvla/mlkem_mldsa_stage6_r3b_replay_dummy_comp3_20260520_cw305_husky_1000/comparison_vs_stage6_r2.csv`
- `reports/tvla/mlkem_mldsa_stage6_r3b_replay_dummy_comp3_20260520_cw305_husky_1000/mlkem_mldsa_tvla_overview.png`

Results vs Stage 4b:

| Operation | Stage 4b max abs t | R3b max abs t | Delta % | Stage 4b peak | R3b peak | Cycles | Clipping |
|---|---:|---:|---:|---:|---:|---:|---:|
| `mlkem_ntt` | 96.516 | 62.775 | -34.96% | 116 | 114 | 248 | 0 |
| `mlkem_intt` | 42.888 | 53.570 | +24.91% | 236 | 149 | 248 | 0 |
| `mlkem_pwm` | 103.869 | 67.092 | -35.41% | 63 | 145 | 149 | 0 |
| `mldsa_ntt` | 85.738 | 93.374 | +8.91% | 506 | 392 | 538 | 0 |
| `mldsa_intt` | 112.877 | 163.051 | +44.45% | 123 | 123 | 538 | 0 |
| `mldsa_pwm` | 78.170 | 99.762 | +27.62% | 109 | 114 | 140 | 0 |

Results vs R2:

| Operation | R2 max abs t | R3b max abs t | Delta % | R2 peak | R3b peak |
|---|---:|---:|---:|---:|---:|
| `mlkem_ntt` | 29.532 | 62.775 | +112.57% | 217 | 114 |
| `mlkem_intt` | 27.140 | 53.570 | +97.38% | 149 | 149 |
| `mlkem_pwm` | 52.516 | 67.092 | +27.76% | 156 | 145 |
| `mldsa_ntt` | 82.381 | 93.374 | +13.34% | 63 | 392 |
| `mldsa_intt` | 121.557 | 163.051 | +34.14% | 123 | 123 |
| `mldsa_pwm` | 85.713 | 99.762 | +16.39% | 114 | 114 |

Decision:

- Rejected. The worst operation worsened from Stage 4b
  `mldsa_intt=112.877` to `mldsa_intt=163.051`, and the stable
  `mldsa_intt` peak stayed at index 123.
- R3b confirms that same-seed deterministic replay does not preserve the R2
  ML-KEM improvement. It still improves `mlkem_ntt` and `mlkem_pwm` vs Stage
  4b, but it worsens `mlkem_intt` and all ML-DSA operations.
- Since R2 is much better than R3b on every operation, the R2 ML-KEM benefit is
  unlikely to be explained by deterministic inactive-cone switching shape alone.
  It depends on the trace-varying public PRD phase and/or its placement effect.
- None of R1/R2/R3b is accepted as the final all-operation branch. Stage 4b
  remains the selected RTL policy unless a later, larger active-arithmetic
  protection experiment is approved.

### Stage 6 final source and bitstream state

- After rejecting R1/R2/R3b, the Stage 6 RTL changes were removed. The active
  source tree is back at the Stage 4b RTL policy; only documentation remains
  modified.
- Final diagnostics after restoring Stage 4b source:
  `check_phoenix_consistency.py` pass and `check_bank_conflicts.py` pass.
- Final Verilator regression after restoring Stage 4b source passed for
  `tb_comp3_agile_modmul`, `tb_superbutterfly_all_modes`, `tb_phoenix_core`,
  `tb_phoenix_host_io`, `tb_phoenix_cw305_wrapper`, and
  `tb_phoenix_mldsa_pwm_io`.
- Active CW305 bitstream was rebuilt from the restored Stage 4b source:
  `boards/cw305/output/phoenix_cw305.bit`, mtime 2026-05-20 23:48:34 KST.
- Restored Stage 4b post-route timing: WNS = 0.203 ns, TNS = 0.000 ns,
  WHS = 0.063 ns, THS = 0.000 ns.
- Restored Stage 4b utilization: 9727 LUTs, 3268 registers, 8
  RAMB36-equivalent block RAM tiles, 0 DSPs.
- No key-repeat run was scheduled for Stage 6 because every Stage 6 branch was
  rejected before reaching the repeat decision point.

## Current Ranking

All values are 1000 fixed vs 1000 random, secret-distribution TVLA, using the
available full six-operation runs.

| Run | Worst op | Worst max abs t | ML-KEM avg | ML-DSA avg |
|---|---:|---:|---:|---:|
| `baseline` | `mldsa_pwm` | 144.055 | 88.222 | 137.082 |
| `stage2` | `mldsa_pwm` | 155.781 | 83.321 | 143.578 |
| `stage3d_shuffle` | `mldsa_intt` | 127.071 | 86.142 | 97.832 |
| `stage3e_no_prd` | `mldsa_ntt` | 146.369 | 85.272 | 137.903 |
| `stage3f_targeted` | `mldsa_intt` | 147.020 | 93.447 | 100.347 |
| `stage3g_balanced` | `mldsa_intt` | 121.693 | 89.254 | 96.592 |
| `stage4a_active` | `mldsa_intt` | 116.608 | 90.317 | 93.154 |
| `stage4b_exception` | `mldsa_intt` | 112.877 | 81.091 | 92.262 |
| `stage5_b123` | `mldsa_intt` | 143.709 | 89.458 | 111.360 |
| `stage5_b1` | `mldsa_intt` | 127.224 | 79.600 | 97.814 |
| `stage5_b2` | `mlkem_ntt` | 125.233 | 91.044 | 92.363 |
| `stage5_b3` | `mldsa_intt` | 150.301 | 86.276 | 120.726 |
| `stage6_r1_fixed_dummy` | `mldsa_intt` | 128.424 | 89.490 | 107.498 |
| `stage6_r2_prd_dummy` | `mldsa_intt` | 121.557 | 36.396 | 96.550 |
| `stage6_r3b_replay_dummy` | `mldsa_intt` | 163.051 | 61.146 | 118.729 |

Summary:

- Stage 4b is the current best candidate by worst-operation t-value and by both
  ML-KEM/ML-DSA average t-values.
- The progression from Stage 3d to Stage 4b shows that invalid-cycle PRD helps
  ML-DSA, while active COMP blanking is needed to affect active arithmetic
  windows.
- Stage 5 did not find an accepted small RTL blanking candidate beyond Stage
  4b. The targeted local improvements were outweighed by reproducible
  regressions in other active windows.
- Stage 6 shows that inactive-cone dummy activity is a real lever for ML-KEM:
  R2 reduced the ML-KEM average sharply. However, every Stage 6 candidate kept
  or worsened the stable `mldsa_intt` active-window peak, so none beats Stage
  4b under the all-operation decision rule.
- The remaining worst operation is `mldsa_intt` at roughly 113-115. Since this
  is still far above 4.5 and occurs in a stable active window, the next class of
  work should be active arithmetic protection rather than more blanking-only
  policy changes.
