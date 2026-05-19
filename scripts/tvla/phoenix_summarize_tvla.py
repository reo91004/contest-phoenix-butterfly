#!/usr/bin/env python3
"""Summarize PHOENIX TVLA npz files and optionally emit simple plots."""

from __future__ import annotations

import argparse
import csv
import json
import os
from datetime import datetime, timezone
from pathlib import Path

import numpy as np


os.environ.setdefault("MPLCONFIGDIR", "/tmp/matplotlib")


def scalar(value, default=None):
    try:
        arr = np.asarray(value)
        if arr.shape == ():
            return arr.item()
    except Exception:
        pass
    return default if value is None else value


def load_embedded_metadata(path: Path, z) -> dict:
    companion = path.with_suffix(".metadata.json")
    if companion.exists():
        return json.loads(companion.read_text(encoding="utf-8"))
    if "metadata_json" in z.files:
        return json.loads(str(scalar(z["metadata_json"], "{}")))
    return {}


def clip_stats(arr: np.ndarray) -> dict[str, object]:
    clipped = int(np.count_nonzero((arr <= -0.4999) | (arr >= 0.4997)))
    return {
        "min": float(arr.min()),
        "max": float(arr.max()),
        "std": float(arr.std()),
        "clipped_samples": clipped,
        "clipped_ratio": float(clipped / arr.size),
    }


def summarize(path: Path) -> dict[str, object]:
    z = np.load(path)
    fixed = z["traces_fixed"]
    random_arr = z["traces_random"]
    t_values = z["t_values"]
    embedded = load_embedded_metadata(path, z)
    peak_idx = int(np.argmax(np.abs(t_values)))
    operation = str(scalar(z["operation"]))
    fixed_clip = clip_stats(fixed)
    random_clip = clip_stats(random_arr)
    threshold = (
        float(scalar(z["threshold"], embedded.get("threshold", 4.5)))
        if "threshold" in z.files
        else float(embedded.get("threshold", 4.5))
    )
    max_abs_t = float(np.max(np.abs(t_values)))
    result = "LEAKAGE_CANDIDATE" if max_abs_t >= threshold else "NO_THRESHOLD_CROSSING"
    gain = scalar(z["gain"], None) if "gain" in z.files else None
    if gain is None:
        gain = embedded.get("capture", {}).get("gain", "unknown")
    gain_db = scalar(z["scope_gain_db_actual"], None) if "scope_gain_db_actual" in z.files else None
    if gain_db is None:
        gain_db = embedded.get("capture", {}).get("scope_gain_db_actual", "unknown")
    capture = embedded.get("capture", {})
    return {
        "file": str(path),
        "metadata_file": str(path.with_suffix(".metadata.json")),
        "operation": operation,
        "traces_per_group": int(fixed.shape[0]),
        "samples": int(fixed.shape[1]),
        "slots": ",".join(str(int(x)) for x in z["slots"]),
        "words_per_slot": int(z["words_per_slot"]),
        "secret_dist": str(scalar(z["secret_dist"], capture.get("secret_dist", "unknown")))
        if "secret_dist" in z.files
        else str(capture.get("secret_dist", "unknown")),
        "secret_dist_arg": str(scalar(z["secret_dist_arg"], capture.get("secret_dist_arg", "unknown")))
        if "secret_dist_arg" in z.files
        else str(capture.get("secret_dist_arg", "unknown")),
        "mlkem_eta": str(scalar(z["mlkem_eta"], capture.get("mlkem_eta", "")))
        if "mlkem_eta" in z.files
        else str(capture.get("mlkem_eta", "")),
        "mldsa_eta": str(scalar(z["mldsa_eta"], capture.get("mldsa_eta", "")))
        if "mldsa_eta" in z.files
        else str(capture.get("mldsa_eta", "")),
        "word_format": str(capture.get("word_format", "")),
        "gain": str(gain),
        "gain_db": str(gain_db),
        "cycles_fixed": ",".join(str(int(x)) for x in np.unique(z["cycles_fixed"])),
        "cycles_random": ",".join(str(int(x)) for x in np.unique(z["cycles_random"])),
        "threshold": threshold,
        "result": result,
        "max_abs_t": max_abs_t,
        "peak_idx": peak_idx,
        "peak_t": float(t_values[peak_idx]),
        "fixed_clipped_samples": fixed_clip["clipped_samples"],
        "random_clipped_samples": random_clip["clipped_samples"],
        "clipped_samples": int(fixed_clip["clipped_samples"]) + int(random_clip["clipped_samples"]),
        "fixed_min": fixed_clip["min"],
        "fixed_max": fixed_clip["max"],
        "random_min": random_clip["min"],
        "random_max": random_clip["max"],
        "elapsed_s": float(z["elapsed_s"]),
        "means_plot": "",
        "tvalues_plot": "",
    }


def plot_paths(path: Path, out_dir: Path) -> dict[str, str]:
    stem = path.stem
    return {
        "means_plot": str(out_dir / f"{stem}_means.png"),
        "tvalues_plot": str(out_dir / f"{stem}_tvalues.png"),
    }


def write_metadata(path: Path, row: dict[str, object]) -> Path:
    z = np.load(path)
    embedded = load_embedded_metadata(path, z)
    metadata = {
        "created_utc": embedded.get("created_utc"),
        "summarized_utc": datetime.now(timezone.utc).isoformat(),
        "source_npz": str(path),
        "summary": row,
        "capture": embedded.get("capture", {}),
        "hardware": embedded.get("hardware", {}),
        "methodology": embedded.get("methodology", {}),
        "dut": embedded.get("dut", {}),
        "files": embedded.get("files", {}),
        "artifacts": {
            "summary_csv": row.get("summary_csv"),
            "means_plot": row.get("means_plot"),
            "tvalues_plot": row.get("tvalues_plot"),
        },
    }
    out = path.with_suffix(".metadata.json")
    with out.open("w", encoding="utf-8") as f:
        json.dump(metadata, f, indent=2, sort_keys=True)
        f.write("\n")
    return out


def maybe_plot(path: Path, out_dir: Path, row: dict[str, object]) -> None:
    try:
        import matplotlib.pyplot as plt
    except Exception as exc:
        print(f"[TVLA-SUMMARY] matplotlib unavailable, skipping plots: {exc}")
        return

    z = np.load(path)
    fixed_mean = z["traces_fixed"].mean(axis=0)
    random_mean = z["traces_random"].mean(axis=0)
    t_values = z["t_values"]
    peak_idx = int(row["peak_idx"])
    threshold = float(row["threshold"])
    paths = plot_paths(path, out_dir)

    plt.figure(figsize=(10, 4))
    plt.plot(fixed_mean, label="fixed mean", linewidth=1)
    plt.plot(random_mean, label="random mean", linewidth=1)
    plt.title(f"{row['operation']} mean traces ({row['traces_per_group']}/group)")
    plt.legend()
    plt.xlabel("sample")
    plt.ylabel("amplitude")
    plt.tight_layout()
    plt.savefig(paths["means_plot"], dpi=160)
    plt.close()

    plt.figure(figsize=(10, 4))
    plt.plot(t_values, linewidth=1)
    plt.axhline(threshold, color="red", linestyle="--", linewidth=1)
    plt.axhline(-threshold, color="red", linestyle="--", linewidth=1)
    plt.scatter([peak_idx], [t_values[peak_idx]], color="black", s=16, zorder=3)
    plt.title(f"{row['operation']} Welch t, max |t|={float(row['max_abs_t']):.3f}")
    plt.xlabel("sample")
    plt.ylabel("Welch t")
    plt.tight_layout()
    plt.savefig(paths["tvalues_plot"], dpi=160)
    plt.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("npz", nargs="+", type=Path)
    parser.add_argument("--csv", type=Path, default=Path("reports/tvla/summary.csv"))
    parser.add_argument("--manifest", type=Path, default=Path("reports/tvla/manifest.json"))
    parser.add_argument("--plots", action="store_true")
    args = parser.parse_args()

    args.csv.parent.mkdir(parents=True, exist_ok=True)
    rows = [summarize(path) for path in args.npz]
    for path, row in zip(args.npz, rows):
        row["summary_csv"] = str(args.csv)
        if args.plots:
            row.update(plot_paths(path, args.csv.parent))
    for path, row in zip(args.npz, rows):
        row["metadata_file"] = str(write_metadata(path, row))
    with args.csv.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    print(f"[TVLA-SUMMARY] wrote {args.csv}")

    if args.plots:
        for path, row in zip(args.npz, rows):
            maybe_plot(path, args.csv.parent, row)
        print(f"[TVLA-SUMMARY] plots in {args.csv.parent}")

    manifest = {
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "csv": str(args.csv),
        "rows": rows,
    }
    args.manifest.parent.mkdir(parents=True, exist_ok=True)
    with args.manifest.open("w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)
        f.write("\n")
    print(f"[TVLA-SUMMARY] wrote {args.manifest}")

    for row in rows:
        print(
            f"[TVLA-SUMMARY] {row['operation']} traces/group={row['traces_per_group']} "
            f"max_abs_t={row['max_abs_t']:.3f} clipped={row['clipped_samples']}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
