#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 1000 vs 1000 fixed-vs-random TVLA capture for the ML-KEM / ML-DSA PHOENIX RTL.
#
# Usage:
#   bash scripts/tvla/run_mlkem_mldsa_1000.sh
#   OPS="mldsa_pwm" TRACES=1000 SECRET_DIST=auto bash scripts/tvla/run_mlkem_mldsa_1000.sh
# -----------------------------------------------------------------------------
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTDIR="${OUTDIR:-$ROOT/reports/tvla/mlkem_mldsa_secretdist_20260519_cw305_husky_1000}"
LOG="$OUTDIR/tvla_run.log"
TRACES="${TRACES:-1000}"
OPS="${OPS:-mlkem_ntt mlkem_intt mlkem_pwm mldsa_ntt mldsa_intt mldsa_pwm}"
BITFILE="${BITFILE:-$ROOT/boards/cw305/output/phoenix_cw305.bit}"
PYTHON="${PYTHON:-python}"
SECRET_DIST="${SECRET_DIST:-auto}"
MLKEM_ETA="${MLKEM_ETA:-2}"
MLDSA_ETA="${MLDSA_ETA:-2}"
TRACE_ORDER="${TRACE_ORDER:-paired}"
ORDER_SEED="${ORDER_SEED:-0x5EED}"

mkdir -p "$OUTDIR"
[ -s "$LOG" ] && printf '\n' >> "$LOG"

echo "================ session $(date '+%Y-%m-%d %H:%M:%S') ================" | tee -a "$LOG"
echo "run_mlkem_mldsa_1000.sh start $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG"
echo "fixed-mode=secret secret-dist=$SECRET_DIST traces/group=$TRACES ops=[$OPS]" | tee -a "$LOG"
echo "mlkem-eta=$MLKEM_ETA mldsa-eta=$MLDSA_ETA" | tee -a "$LOG"
echo "trace-order=$TRACE_ORDER order-seed=$ORDER_SEED" | tee -a "$LOG"
echo "DUT bitstream: $BITFILE" | tee -a "$LOG"
if [ ! -f "$BITFILE" ]; then
    echo "[FAIL] missing bitstream: $BITFILE" | tee -a "$LOG"
    echo "Build it first: cd boards/cw305 && vivado -mode batch -source build_phoenix_bitstream.tcl" | tee -a "$LOG"
    exit 2
fi
echo "DUT bitstream mtime: $(stat -c '%y' "$BITFILE" 2>/dev/null)" | tee -a "$LOG"

slots_for_op() {
    case "$1" in
        mlkem_ntt|mlkem_intt|ntt|intt|mldsa_ntt|mldsa_intt) echo "0,1,2,3" ;;
        *) echo "0,1,2,3,4,5,6,7" ;;
    esac
}

samples_for_op() {
    case "$1" in
        mldsa_ntt|mldsa_intt) echo 2500 ;;
        *) echo 1200 ;;
    esac
}

words_for_op() {
    case "$1" in
        mlkem_ntt|mlkem_intt|mlkem_pwm|ntt|intt|pwm) echo 32 ;;
        *) echo 64 ;;
    esac
}

rc_all=0
for OP in $OPS; do
    OUT="$OUTDIR/phoenix_${OP}_full_${TRACES}_db10.npz"
    SLOTS="$(slots_for_op "$OP")"
    SAMP="$(samples_for_op "$OP")"
    WORDS="$(words_for_op "$OP")"
    echo "=== [$(date '+%H:%M:%S')] capture $OP ($TRACES fixed + $TRACES random, slots=$SLOTS words/slot=$WORDS samples=$SAMP) ===" | tee -a "$LOG"
    if "$PYTHON" "$ROOT/scripts/tvla/phoenix_capture_tvla.py" \
        --operation "$OP" \
        --fixed-mode secret \
        --secret-dist "$SECRET_DIST" \
        --mlkem-eta "$MLKEM_ETA" \
        --mldsa-eta "$MLDSA_ETA" \
        --traces "$TRACES" \
        --slots "$SLOTS" \
        --words-per-slot "$WORDS" \
        --samples "$SAMP" \
        --gain-db 10 \
        --trace-order "$TRACE_ORDER" \
        --order-seed "$ORDER_SEED" \
        --bitfile "$BITFILE" \
        --out "$OUT" >> "$LOG" 2>&1; then
        grep -E '^\[TVLA\] (fixed-mode|operation|max_abs_t|RESULT)' "$LOG" | tail -4 | tee -a "$LOG"
    else
        echo "[FAIL] capture $OP (exit $?)" | tee -a "$LOG"
        rc_all=1
    fi
done

echo "=== [$(date '+%H:%M:%S')] summarize ===" | tee -a "$LOG"
"$PYTHON" "$ROOT/scripts/tvla/phoenix_summarize_tvla.py" \
    "$OUTDIR"/phoenix_*_full_${TRACES}_db10.npz \
    --csv "$OUTDIR/summary.csv" \
    --manifest "$OUTDIR/manifest.json" \
    --plots >> "$LOG" 2>&1 || rc_all=1

echo "run_mlkem_mldsa_1000.sh done rc=$rc_all $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG"
exit "$rc_all"
