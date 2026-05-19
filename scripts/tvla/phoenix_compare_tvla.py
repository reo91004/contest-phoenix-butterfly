#!/usr/bin/env python3
"""Compare two PHOENIX TVLA summary directories and emit CSV/PNG artifacts."""

from __future__ import annotations

import argparse
import csv
import math
import os
from pathlib import Path

import numpy as np


os.environ.setdefault("MPLCONFIGDIR", "/tmp/matplotlib")


DEFAULT_ORDER = (
    "mlkem_ntt",
    "mlkem_intt",
    "mlkem_pwm",
    "mldsa_ntt",
    "mldsa_intt",
    "mldsa_pwm",
)


def load_summary(path: Path) -> dict[str, dict[str, str]]:
    with (path / "summary.csv").open(newline="") as f:
        return {row["operation"]: row for row in csv.DictReader(f)}


def compare_rows(
    baseline: dict[str, dict[str, str]],
    candidate: dict[str, dict[str, str]],
    order: tuple[str, ...],
) -> list[dict[str, str]]:
    rows = []
    for op in order:
        base_row = baseline[op]
        cand_row = candidate[op]
        base_t = float(base_row["max_abs_t"])
        cand_t = float(cand_row["max_abs_t"])
        delta = cand_t - base_t
        delta_pct = delta / base_t * 100.0 if base_t else math.nan
        rows.append(
            {
                "operation": op,
                "baseline_max_abs_t": f"{base_t:.6f}",
                "candidate_max_abs_t": f"{cand_t:.6f}",
                "delta": f"{delta:.6f}",
                "delta_pct": f"{delta_pct:.2f}",
                "baseline_peak_idx": base_row["peak_idx"],
                "candidate_peak_idx": cand_row["peak_idx"],
                "baseline_cycles": base_row["cycles_fixed"],
                "candidate_cycles": cand_row["cycles_fixed"],
                "baseline_result": base_row["result"],
                "candidate_result": cand_row["result"],
            }
        )
    return rows


def write_csv(path: Path, rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def write_comparison_plot(path: Path, rows: list[dict[str, str]], candidate_label: str) -> None:
    import matplotlib.pyplot as plt

    labels = [row["operation"].replace("_", "\n") for row in rows]
    x = np.arange(len(rows))
    width = 0.38
    base = [float(row["baseline_max_abs_t"]) for row in rows]
    cand = [float(row["candidate_max_abs_t"]) for row in rows]

    fig, ax = plt.subplots(figsize=(11, 4.8))
    ax.bar(x - width / 2, base, width, label="baseline", color="#4C78A8")
    ax.bar(x + width / 2, cand, width, label=candidate_label, color="#F58518")
    ax.axhline(4.5, color="crimson", linestyle="--", linewidth=1, label="TVLA threshold 4.5")
    ax.set_xticks(x)
    ax.set_xticklabels(labels)
    ax.set_ylabel("max |t|")
    ax.set_title("PHOENIX 1000 vs 1000 TVLA comparison")
    ax.legend(ncol=3, fontsize=9)
    ax.grid(axis="y", alpha=0.25)
    for idx, (base_t, cand_t) in enumerate(zip(base, cand)):
        ax.text(idx, max(base_t, cand_t) + 5.0, f"{cand_t - base_t:+.1f}", ha="center", va="bottom", fontsize=8)
    fig.tight_layout()
    fig.savefig(path, dpi=170)
    plt.close(fig)


def write_tvalue_overview(path: Path, summary_dir: Path, order: tuple[str, ...], title: str) -> None:
    import matplotlib.pyplot as plt

    fig, axes = plt.subplots(2, 3, figsize=(13, 6.5), sharex=False)
    for ax, op in zip(axes.ravel(), order):
        z = np.load(summary_dir / f"phoenix_{op}_full_1000_db10.npz")
        t_values = z["t_values"]
        peak_idx = int(np.argmax(np.abs(t_values)))
        ax.plot(t_values, linewidth=0.8, color="#2F4B7C")
        ax.axhline(4.5, color="crimson", linestyle="--", linewidth=0.8)
        ax.axhline(-4.5, color="crimson", linestyle="--", linewidth=0.8)
        ax.scatter([peak_idx], [t_values[peak_idx]], s=12, color="black", zorder=3)
        ax.set_title(f"{op}: max |t|={np.max(np.abs(t_values)):.1f} @ {peak_idx}", fontsize=10)
        ax.set_xlabel("sample")
        ax.set_ylabel("t")
        ax.grid(alpha=0.2)
    fig.suptitle(title, y=1.02)
    fig.tight_layout()
    fig.savefig(path, dpi=170, bbox_inches="tight")
    plt.close(fig)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--candidate", required=True, type=Path)
    parser.add_argument("--candidate-label", default="candidate")
    parser.add_argument("--out-csv", type=Path)
    parser.add_argument("--out-plot", type=Path)
    parser.add_argument("--out-overview", type=Path)
    args = parser.parse_args()

    baseline = load_summary(args.baseline)
    candidate = load_summary(args.candidate)
    order = tuple(op for op in DEFAULT_ORDER if op in baseline and op in candidate)
    rows = compare_rows(baseline, candidate, order)

    out_csv = args.out_csv or args.candidate / "comparison_vs_baseline.csv"
    out_plot = args.out_plot or args.candidate / "comparison_vs_baseline.png"
    out_overview = args.out_overview or args.candidate / "mlkem_mldsa_tvla_overview.png"

    write_csv(out_csv, rows)
    write_comparison_plot(out_plot, rows, args.candidate_label)
    write_tvalue_overview(
        out_overview,
        args.candidate,
        order,
        f"{args.candidate_label} TVLA t-values (1000 vs 1000)",
    )
    print(out_csv)
    print(out_plot)
    print(out_overview)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
