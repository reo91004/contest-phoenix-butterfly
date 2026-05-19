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
