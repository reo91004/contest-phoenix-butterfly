#!/usr/bin/env python3
"""Capture fixed-vs-random PHOENIX traces on CW305 and run Welch t-test."""

from __future__ import annotations

import argparse
import hashlib
import json
import random
import secrets
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import chipwhisperer as cw
import numpy as np

from phoenix_cw305_lib import (
    DEFAULT_BITFILE,
    DEFAULT_DEFINES,
    INSTR,
    SCOPE_SN,
    TARGET_SN,
    PhoenixCW305,
    connect_target,
)


KEM_Q = 3329
MLDSA_Q = 8380417
MLDSA_R_MOD_Q = 4193792
DEFAULT_MLKEM_ETA = 2
DEFAULT_MLDSA_ETA = 2


def parse_slots(text: str) -> list[int]:
    slots = [int(x, 0) for x in text.split(",") if x.strip()]
    for slot in slots:
        if not 0 <= slot < 8:
            raise ValueError(f"slot out of range: {slot}")
    return slots


def is_mlkem_operation(operation: str) -> bool:
    return operation in {"ntt", "intt", "pwm", "mlkem_ntt", "mlkem_intt", "mlkem_pwm"}


def is_mldsa_operation(operation: str) -> bool:
    return operation in {"mldsa_ntt", "mldsa_intt", "mldsa_pwm"}


def pack_mlkem_word(lo: int, hi: int) -> int:
    return ((hi % KEM_Q) << 16) | (lo % KEM_Q)


def mldsa_to_mont(x: int) -> int:
    return ((x % MLDSA_Q) * MLDSA_R_MOD_Q) % MLDSA_Q


def _uniform_word(randbelow, operation: str) -> int:
    """Generate one operation-formatted uniform operand word.

    ML-KEM uses two packed 16-bit lanes. ML-DSA uses one 32-bit container whose
    low bits hold a normalized Montgomery residue modulo 8380417.
    """

    if is_mlkem_operation(operation):
        return pack_mlkem_word(randbelow(KEM_Q), randbelow(KEM_Q))
    if is_mldsa_operation(operation):
        return mldsa_to_mont(randbelow(MLDSA_Q))
    raise ValueError(f"unsupported operation: {operation}")


def mlkem_cbd_coeff(randbits, eta: int) -> int:
    """Sample one ML-KEM secret coefficient from CBD_eta and encode it mod q."""

    a = int(randbits(eta)).bit_count()
    b = int(randbits(eta)).bit_count()
    return (a - b) % KEM_Q


def mldsa_eta_coeff(randbelow, eta: int) -> int:
    """Sample one ML-DSA secret coefficient uniformly from [-eta, eta]."""

    return randbelow(2 * eta + 1) - eta


def resolve_secret_dist(secret_dist: str, operation: str) -> str:
    """Resolve the requested distribution for the selected operation."""

    if secret_dist == "none":
        return "none"
    if secret_dist == "auto":
        if is_mlkem_operation(operation):
            return "mlkem_cbd"
        if is_mldsa_operation(operation):
            return "mldsa_eta"
    if secret_dist == "mlkem_cbd" and is_mlkem_operation(operation):
        return "mlkem_cbd"
    if secret_dist == "mldsa_eta" and is_mldsa_operation(operation):
        return "mldsa_eta"
    raise ValueError(f"secret distribution {secret_dist!r} is not compatible with {operation!r}")


def _distributed_word(
    randbelow,
    randbits,
    operation: str,
    secret_dist: str,
    mlkem_eta: int,
    mldsa_eta: int,
) -> int:
    if secret_dist == "none":
        return _uniform_word(randbelow, operation)
    if secret_dist == "mlkem_cbd":
        return pack_mlkem_word(
            mlkem_cbd_coeff(randbits, mlkem_eta),
            mlkem_cbd_coeff(randbits, mlkem_eta),
        )
    if secret_dist == "mldsa_eta":
        return mldsa_to_mont(mldsa_eta_coeff(randbelow, mldsa_eta))
    raise ValueError(f"unsupported secret distribution: {secret_dist}")


def random_words(
    count: int,
    operation: str,
    secret_dist: str,
    mlkem_eta: int,
    mldsa_eta: int,
) -> list[int]:
    return [
        _distributed_word(
            secrets.randbelow,
            secrets.randbits,
            operation,
            secret_dist,
            mlkem_eta,
            mldsa_eta,
        )
        for _ in range(count)
    ]


def const_fixed_words(count: int, value: int, operation: str) -> list[int]:
    if is_mlkem_operation(operation):
        return [pack_mlkem_word(value, value) for _ in range(count)]
    if is_mldsa_operation(operation):
        return [mldsa_to_mont(value) for _ in range(count)]
    raise ValueError(f"unsupported operation: {operation}")


def build_fixed_secret(
    slots: list[int],
    words_per_slot: int,
    operation: str,
    seed: int,
    secret_dist: str,
    mlkem_eta: int,
    mldsa_eta: int,
) -> dict[int, list[int]]:
    rng = random.Random(seed)
    return {
        slot: [
            _distributed_word(
                rng.randrange,
                rng.getrandbits,
                operation,
                secret_dist,
                mlkem_eta,
                mldsa_eta,
            )
            for _ in range(words_per_slot)
        ]
        for slot in slots
    }


def fixed_secret_digest(slots: list[int], fixed_map: dict[int, list[int]]) -> str:
    h = hashlib.sha256()
    for slot in slots:
        for w in fixed_map[slot]:
            h.update(int(w).to_bytes(4, "little"))
    return h.hexdigest()


def load_group(
    dut: PhoenixCW305,
    slots: list[int],
    words_per_slot: int,
    fixed: bool,
    operation: str,
    fixed_mode: str,
    fixed_value: int,
    fixed_map: dict[int, list[int]] | None,
    secret_dist: str,
    mlkem_eta: int,
    mldsa_eta: int,
) -> None:
    if fixed:
        if fixed_mode == "secret":
            if fixed_map is None:
                raise RuntimeError("fixed secret map was not initialized")
            data_map = fixed_map
        else:
            data_map = {
                slot: const_fixed_words(words_per_slot, fixed_value, operation)
                for slot in slots
            }
    else:
        data_map = {
            slot: random_words(words_per_slot, operation, secret_dist, mlkem_eta, mldsa_eta)
            for slot in slots
        }
    for slot in slots:
        dut.load_slot_words(slot, data_map[slot])


def describe_distribution(operation: str, secret_dist: str, mlkem_eta: int, mldsa_eta: int) -> str:
    if secret_dist == "mlkem_cbd":
        return f"ML-KEM CBD_eta={mlkem_eta} secret coefficients packed as two lanes mod 3329"
    if secret_dist == "mldsa_eta":
        return (
            f"ML-DSA eta={mldsa_eta} secret coefficients in [-eta,eta], "
            "encoded mod 8380417 in Montgomery form"
        )
    if is_mlkem_operation(operation):
        return "ML-KEM uniform operands: two packed lanes mod 3329"
    return "ML-DSA uniform operands: one Montgomery residue mod 8380417 per u32"


def word_format(operation: str, secret_dist: str, mlkem_eta: int, mldsa_eta: int) -> str:
    if secret_dist == "mlkem_cbd":
        return f"mlkem_packed_2x16_cbd_eta{mlkem_eta}_mod3329"
    if secret_dist == "mldsa_eta":
        return f"mldsa_eta{mldsa_eta}_montgomery_residue_mod8380417_in_u32"
    if is_mlkem_operation(operation):
        return "mlkem_packed_2x16_uniform_mod3329"
    return "mldsa_uniform_montgomery_residue_mod8380417_in_u32"


def configure_scope(scope, samples: int, gain: int, gain_db: float | None, target_freq_hz: float, adc_mul: int):
    scope.default_setup()
    scope.io.hs2 = None
    if adc_mul == 1:
        scope.clock.pll.set_bypass_adc(True)
    else:
        scope.clock.pll.set_bypass_adc(False)
        scope.clock.clkgen_freq = target_freq_hz
        scope.clock.adc_mul = adc_mul
        scope.clock.clkgen_src = "extclk"
    if gain_db is None:
        scope.gain.gain = gain
    else:
        scope.gain.db = gain_db
    scope.adc.samples = samples
    scope.adc.offset = 0
    scope.adc.basic_mode = "rising_edge"
    scope.trigger.triggers = "tio4"
    if adc_mul != 1:
        scope.clock.reset_adc()
    return {"gain": int(scope.gain.gain), "gain_db": float(scope.gain.db)}


def capture_operation(scope, dut: PhoenixCW305, instr: int, timeout_s: float):
    dut.prepare_start(instr)
    scope.arm()
    dut.pulse_go()
    ret = scope.capture()
    if ret:
        raise TimeoutError("scope capture timed out")
    trace = np.asarray(scope.get_last_trace(), dtype=np.float32)
    dut.wait_done(timeout_s)
    status = dut.read_status()
    return trace, status


def welch_t(fixed: np.ndarray, random_arr: np.ndarray) -> np.ndarray:
    n0 = fixed.shape[0]
    n1 = random_arr.shape[0]
    m0 = fixed.mean(axis=0)
    m1 = random_arr.mean(axis=0)
    v0 = fixed.var(axis=0, ddof=1) if n0 > 1 else np.zeros_like(m0)
    v1 = random_arr.var(axis=0, ddof=1) if n1 > 1 else np.zeros_like(m1)
    denom = np.sqrt((v0 / max(n0, 1)) + (v1 / max(n1, 1)))
    return np.divide(m0 - m1, denom, out=np.zeros_like(m0), where=denom != 0)


def clipping_count(arr: np.ndarray) -> int:
    return int(np.count_nonzero((arr <= -0.4999) | (arr >= 0.4997)))


def write_metadata(path: Path, metadata: dict) -> Path:
    meta_path = path.with_suffix(".metadata.json")
    with meta_path.open("w", encoding="utf-8") as f:
        json.dump(metadata, f, indent=2, sort_keys=True)
        f.write("\n")
    return meta_path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bitfile", type=Path, default=DEFAULT_BITFILE)
    parser.add_argument("--defines", type=Path, default=DEFAULT_DEFINES)
    parser.add_argument("--target-sn", default=TARGET_SN)
    parser.add_argument("--scope-sn", default=SCOPE_SN)
    parser.add_argument("--operation", choices=sorted(INSTR), default="mlkem_ntt")
    parser.add_argument("--traces", type=int, default=100)
    parser.add_argument("--samples", type=int, default=24000)
    parser.add_argument("--gain", type=int, default=25)
    parser.add_argument("--gain-db", type=float, default=None)
    parser.add_argument("--slots", default="0,1,2,3")
    parser.add_argument("--words-per-slot", type=int, default=1024)
    parser.add_argument(
        "--fixed-mode",
        choices=["secret", "const"],
        default="secret",
        help="secret: one fixed polynomial drawn from the same distribution as random; const: broadcast constant.",
    )
    parser.add_argument("--fixed-seed", type=lambda x: int(x, 0), default=0xC0FFEE)
    parser.add_argument("--fixed-value", type=int, default=0)
    parser.add_argument(
        "--secret-dist",
        choices=["none", "auto", "mlkem_cbd", "mldsa_eta"],
        default="auto",
        help=(
            "auto: ML-KEM uses CBD_eta and ML-DSA uses eta-small secret "
            "coefficients; none: matched uniform operands."
        ),
    )
    parser.add_argument(
        "--mlkem-eta",
        type=int,
        choices=[2, 3],
        default=DEFAULT_MLKEM_ETA,
        help="ML-KEM secret CBD eta. ML-KEM-768/1024 use 2; ML-KEM-512 uses 3.",
    )
    parser.add_argument(
        "--mldsa-eta",
        type=int,
        choices=[2, 4],
        default=DEFAULT_MLDSA_ETA,
        help="ML-DSA secret eta. ML-DSA-44/87 use 2; ML-DSA-65 uses 4.",
    )
    parser.add_argument("--pll-freq", type=float, default=33.333e6)
    parser.add_argument("--adc-mul", type=int, default=1)
    parser.add_argument("--threshold", type=float, default=4.5)
    parser.add_argument("--out", type=Path, default=Path("reports/tvla/phoenix_tvla.npz"))
    parser.add_argument("--no-force", action="store_true")
    args = parser.parse_args()

    slots = parse_slots(args.slots)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    secret_dist = resolve_secret_dist(args.secret_dist, args.operation)
    dist_description = describe_distribution(
        args.operation,
        secret_dist,
        args.mlkem_eta,
        args.mldsa_eta,
    )

    if args.fixed_mode == "secret":
        fixed_map = build_fixed_secret(
            slots,
            args.words_per_slot,
            args.operation,
            args.fixed_seed,
            secret_dist,
            args.mlkem_eta,
            args.mldsa_eta,
        )
        fixed_digest = fixed_secret_digest(slots, fixed_map)
        print(
            f"[TVLA] fixed-mode=secret seed=0x{args.fixed_seed:X} "
            f"secret-dist={secret_dist} digest={fixed_digest[:16]}... "
            "(fixed/random same distribution)"
        )
    else:
        fixed_map = None
        fixed_digest = None
        print(f"[TVLA] fixed-mode=const value={args.fixed_value} (reference mode)")

    bitfile_mtime = (
        datetime.fromtimestamp(args.bitfile.stat().st_mtime, timezone.utc).isoformat()
        if args.bitfile.exists()
        else None
    )

    scope = None
    target = None
    try:
        target = connect_target(
            bitfile=args.bitfile,
            defines=args.defines,
            sn=args.target_sn,
            force=not args.no_force,
            pll_freq_hz=args.pll_freq,
        )
        dut = PhoenixCW305(target)
        scope = cw.scope(sn=args.scope_sn)
        scope_gain = configure_scope(scope, args.samples, args.gain, args.gain_db, args.pll_freq, args.adc_mul)

        fixed_traces = []
        random_traces = []
        fixed_cycles = []
        random_cycles = []

        print(
            f"[TVLA] operation={args.operation} instr=0x{INSTR[args.operation]:03x} "
            f"traces/group={args.traces} slots={slots} words/slot={args.words_per_slot} "
            f"samples={args.samples} secret-dist={secret_dist}"
        )
        t0 = time.monotonic()
        for i in range(args.traces):
            load_group(
                dut,
                slots,
                args.words_per_slot,
                fixed=True,
                operation=args.operation,
                fixed_mode=args.fixed_mode,
                fixed_value=args.fixed_value,
                fixed_map=fixed_map,
                secret_dist=secret_dist,
                mlkem_eta=args.mlkem_eta,
                mldsa_eta=args.mldsa_eta,
            )
            trace, status = capture_operation(scope, dut, INSTR[args.operation], timeout_s=5.0)
            fixed_traces.append(trace)
            fixed_cycles.append(status.field1)

            load_group(
                dut,
                slots,
                args.words_per_slot,
                fixed=False,
                operation=args.operation,
                fixed_mode=args.fixed_mode,
                fixed_value=args.fixed_value,
                fixed_map=fixed_map,
                secret_dist=secret_dist,
                mlkem_eta=args.mlkem_eta,
                mldsa_eta=args.mldsa_eta,
            )
            trace, status = capture_operation(scope, dut, INSTR[args.operation], timeout_s=5.0)
            random_traces.append(trace)
            random_cycles.append(status.field1)

            if (i + 1) % max(1, min(10, args.traces)) == 0:
                print(f"[TVLA] captured {i + 1}/{args.traces} pairs")

        fixed_arr = np.vstack(fixed_traces)
        random_arr = np.vstack(random_traces)
        t_values = welch_t(fixed_arr, random_arr)
        max_abs_t = float(np.max(np.abs(t_values)))
        peak_idx = int(np.argmax(np.abs(t_values)))
        elapsed_s = time.monotonic() - t0
        cycles_fixed_arr = np.asarray(fixed_cycles, dtype=np.uint32)
        cycles_random_arr = np.asarray(random_cycles, dtype=np.uint32)

        metadata = {
            "created_utc": datetime.now(timezone.utc).isoformat(),
            "command": sys.argv,
            "operation": args.operation,
            "instruction": int(INSTR[args.operation]),
            "result": "LEAKAGE_CANDIDATE" if max_abs_t >= args.threshold else "NO_THRESHOLD_CROSSING",
            "threshold": args.threshold,
            "stats": {
                "max_abs_t": max_abs_t,
                "peak_idx": peak_idx,
                "peak_t": float(t_values[peak_idx]),
                "fixed_clip_samples": clipping_count(fixed_arr),
                "random_clip_samples": clipping_count(random_arr),
                "fixed_min": float(fixed_arr.min()),
                "fixed_max": float(fixed_arr.max()),
                "random_min": float(random_arr.min()),
                "random_max": float(random_arr.max()),
                "fixed_std": float(fixed_arr.std()),
                "random_std": float(random_arr.std()),
                "cycles_fixed_unique": [int(x) for x in np.unique(cycles_fixed_arr)],
                "cycles_random_unique": [int(x) for x in np.unique(cycles_random_arr)],
                "elapsed_s": elapsed_s,
            },
            "capture": {
                "traces_per_group": args.traces,
                "samples": args.samples,
                "gain": args.gain,
                "gain_db_requested": args.gain_db,
                "scope_gain_actual": scope_gain["gain"],
                "scope_gain_db_actual": scope_gain["gain_db"],
                "slots": slots,
                "words_per_slot": args.words_per_slot,
                "fixed_mode": args.fixed_mode,
                "fixed_seed": args.fixed_seed if args.fixed_mode == "secret" else None,
                "fixed_secret_sha256": fixed_digest,
                "fixed_value": args.fixed_value if args.fixed_mode == "const" else None,
                "secret_dist": secret_dist,
                "secret_dist_arg": args.secret_dist,
                "mlkem_eta": args.mlkem_eta if secret_dist == "mlkem_cbd" else None,
                "mldsa_eta": args.mldsa_eta if secret_dist == "mldsa_eta" else None,
                "distribution": dist_description,
                "word_format": word_format(
                    args.operation,
                    secret_dist,
                    args.mlkem_eta,
                    args.mldsa_eta,
                ),
                "pll_freq_hz": args.pll_freq,
                "adc_mul": args.adc_mul,
                "trigger": "tio4",
                "adc_mode": "direct_extclk" if args.adc_mul == 1 else "extclk_pll",
            },
            "hardware": {
                "target": "CW305 Artix-7",
                "target_sn": args.target_sn,
                "scope": "ChipWhisperer Husky Plus",
                "scope_sn": args.scope_sn,
            },
            "methodology": {
                "kind": "non-specific fixed-vs-random TVLA (Welch t)",
                "fixed_class": (
                    "single constant broadcast to all coefficients"
                    if args.fixed_mode == "const"
                    else f"one seeded fixed polynomial from {secret_dist}"
                ),
                "random_class": f"fresh per-trace polynomial from {secret_dist}",
                "rationale": (
                    "fixed and random classes use the same distribution; this avoids "
                    "const-vs-random Hamming-weight artifacts while testing whether "
                    "the implementation leaks one fixed secret against fresh secrets."
                ),
                "secret_distribution_scope": (
                    "operand-level TVLA, not a full ML-KEM or ML-DSA keygen/sign/decap "
                    "flow. ML-DSA NTT uses eta-small secret coefficients. ML-DSA PWM "
                    "and INTT are still operator-level tests over the selected operand "
                    "distribution; they do not model an entire signing transcript."
                    if secret_dist != "none"
                    else "matched-uniform operand baseline; not a real secret-key distribution."
                ),
                "operand_coverage": (
                    "slots 0..3 map to memory-up banks and slots 4..7 map to "
                    "memory-down banks. NTT/INTT load slots 0..3; PWM loads slots "
                    "0..7 so both multiplier operands are controlled by the TVLA class."
                ),
                "interleave": "per-iteration fixed then random",
                "limitation": (
                    "NO_THRESHOLD_CROSSING means no 1st-order leakage detected for this fixed seed "
                    "at this trace count; it is not a proof of absence."
                ),
            },
            "dut": {
                "bitstream": str(args.bitfile),
                "bitstream_mtime_utc": bitfile_mtime,
                "caveat": "TVLA measures the loaded bitstream, not source RTL by itself.",
            },
            "files": {
                "npz": str(args.out),
                "bitfile": str(args.bitfile),
                "defines": str(args.defines),
            },
        }
        metadata_json = json.dumps(metadata, sort_keys=True)

        np.savez_compressed(
            args.out,
            traces_fixed=fixed_arr,
            traces_random=random_arr,
            t_values=t_values,
            cycles_fixed=cycles_fixed_arr,
            cycles_random=cycles_random_arr,
            operation=args.operation,
            slots=np.asarray(slots, dtype=np.uint8),
            words_per_slot=args.words_per_slot,
            samples=args.samples,
            gain=args.gain,
            gain_db=np.nan if args.gain_db is None else args.gain_db,
            scope_gain_actual=scope_gain["gain"],
            scope_gain_db_actual=scope_gain["gain_db"],
            pll_freq=args.pll_freq,
            adc_mul=args.adc_mul,
            threshold=args.threshold,
            elapsed_s=elapsed_s,
            fixed_mode=args.fixed_mode,
            fixed_seed=(args.fixed_seed if args.fixed_mode == "secret" else -1),
            fixed_secret_sha256=(fixed_digest or ""),
            secret_dist=secret_dist,
            secret_dist_arg=args.secret_dist,
            mlkem_eta=args.mlkem_eta,
            mldsa_eta=args.mldsa_eta,
            metadata_json=metadata_json,
        )
        meta_path = write_metadata(args.out, metadata)

        print(f"[TVLA] max_abs_t={max_abs_t:.3f}")
        print(f"[TVLA] saved={args.out}")
        print(f"[TVLA] metadata={meta_path}")
        if max_abs_t >= args.threshold:
            print(f"[TVLA] RESULT=LEAKAGE_CANDIDATE threshold={args.threshold}")
        else:
            print(f"[TVLA] RESULT=NO_THRESHOLD_CROSSING threshold={args.threshold}")
        return 0
    finally:
        if target is not None:
            target.dis()
        if scope is not None:
            scope.dis()


if __name__ == "__main__":
    raise SystemExit(main())
