#!/usr/bin/env python3
"""
Parse simulation log lines emitted by the testbench / phoenix_core's
cycle_counter readback into a CSV.

Expected log format (one event per line):
    [PHOENIX-CYCLES] op=<name> cycles=<n>

Usage
-----
    python3 scripts/parse_cycles.py sim.log
    python3 scripts/parse_cycles.py sim.log --csv > reports_phoenix/cycles.csv

Current RTL smoke-cycle reference:
    SBU latency           : 8
    ML-KEM NTT / INTT     : 248
    ML-KEM PWM            : 149
    ML-DSA NTT / INTT     : 538
    ML-DSA PWM            : 140
"""
from __future__ import annotations
import argparse
import csv
import re
import sys


_RE_LINE = re.compile(r"\[PHOENIX-CYCLES\]\s+op=(\S+)\s+cycles=(\d+)")

RTL_REFERENCE = {
    "sbu_latency":              8,
    "mlkem_ntt":                248,
    "mlkem_intt":               248,
    "mlkem_pwm":                149,
    "mldsa_ntt":                538,
    "mldsa_intt":               538,
    "mldsa_pwm":                140,
}


def parse(path: str) -> list[dict]:
    rows = []
    with open(path) as f:
        for line in f:
            m = _RE_LINE.search(line)
            if not m:
                continue
            op, cycles = m.group(1), int(m.group(2))
            reference = RTL_REFERENCE.get(op, "")
            rows.append({"op": op, "cycles": cycles,
                         "reference": reference,
                         "diff": (cycles - reference) if isinstance(reference, int) else ""})
    return rows


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("--csv", action="store_true")
    args = ap.parse_args()

    rows = parse(args.log)
    if not rows:
        print("no [PHOENIX-CYCLES] lines found in", args.log, file=sys.stderr)
        return 1
    if args.csv or not sys.stdout.isatty():
        w = csv.DictWriter(sys.stdout, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    else:
        for r in rows:
            print(f"{r['op']:<24} ours={r['cycles']:>8}  reference={r['reference']!s:>8}  diff={r['diff']!s:>8}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
