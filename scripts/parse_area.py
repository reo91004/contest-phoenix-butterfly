#!/usr/bin/env python3
"""
Parse Vivado utilization reports and emit one CSV row per design.

Usage
-----
    python3 scripts/parse_area.py reports_phoenix/*/post_impl_utilization.rpt
    python3 scripts/parse_area.py reports_phoenix/*/post_impl_utilization.rpt > reports_phoenix/area.csv

Computes:
    - LUT, FF, BRAM (in 36k tiles), DSP totals (top of report)
    - SEC = floor(LUT/4) + floor(FF/8) + 200*BRAM + 100*DSP   (paper §5.4)
"""
from __future__ import annotations
import argparse
import csv
import os
import re
import sys


# Match table rows like:  | LUT as Logic | 826 | or | Block RAM Tile | 8.5 |
_RE_ROW = re.compile(r"\|\s*([A-Za-z0-9_+\-\. ()]+?)\s*\|\s*(\d+(?:\.\d+)?)\s*\|")


def _grab_first(text: str, *labels: str) -> float:
    for label in labels:
        for line in text.splitlines():
            m = _RE_ROW.match(line)
            if m and m.group(1).strip() == label:
                return float(m.group(2))
    return 0.0


def parse_report(path: str) -> dict:
    with open(path) as f:
        text = f.read()
    lut  = int(_grab_first(text, "Slice LUTs", "CLB LUTs", "LUT as Logic"))
    ff   = int(_grab_first(text, "Slice Registers", "CLB Registers", "Register as Flip Flop"))
    bram = (_grab_first(text, "Block RAM Tile") or
            _grab_first(text, "RAMB36/FIFO*", "RAMB36"))
    dsp  = int(_grab_first(text, "DSPs"))
    sec  = int(lut // 4 + ff // 8 + 200 * bram + 100 * dsp)
    design = os.path.basename(os.path.dirname(path))
    return {"design": design, "LUT": lut, "FF": ff,
            "BRAM": bram, "DSP": dsp, "SEC": sec, "report": path}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("reports", nargs="+")
    ap.add_argument("--csv", action="store_true")
    args = ap.parse_args()

    rows = [parse_report(r) for r in args.reports]
    if args.csv or not sys.stdout.isatty():
        w = csv.DictWriter(sys.stdout, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    else:
        widths = {k: max(len(k), max(len(str(r[k])) for r in rows)) for k in rows[0]}
        header = "  ".join(f"{k:<{widths[k]}}" for k in rows[0])
        print(header)
        for r in rows:
            print("  ".join(f"{str(r[k]):<{widths[k]}}" for k in r))
    return 0


if __name__ == "__main__":
    sys.exit(main())
