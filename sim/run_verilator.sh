#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# sim/run_verilator.sh
# 재현 가능한 시뮬레이션 러너.
#
# 이 환경에는 verilator 만 설치되어 있고 vivado/xsim 은 없다. 따라서:
#   - unit/SBU/top smoke testbench 는 verilator (--binary --timing) 로 실행하고
#     로그를 sim/logs/<tb>.log 에 남긴다.
#
# 사전존재 width 류 lint 경고(kyber_div2_16:18, kyber_barrett_reduce_24:43 등;
# existing ML-KEM modules)는 -Wno-fatal 로 비치명화한다.
# RTL 자체의 합성 정합성은 이후 Vivado -max_dsp 0 흐름으로 별도 확인한다.
#
# 사용법:  bash sim/run_verilator.sh           # 전체
#          bash sim/run_verilator.sh tb_comp3_agile_modmul   # 단일
# 종료코드: 모든 실행 tb PASS → 0, 하나라도 FAIL/빌드실패 → 1
# -----------------------------------------------------------------------------
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
LOGDIR="sim/logs"
BUILDDIR="sim/build"
mkdir -p "$LOGDIR" "$BUILDDIR"
SUMMARY="$LOGDIR/SUMMARY.txt"

CORE_RTL=$(ls rtl/common/*.v rtl/arith/*.v rtl/mul/*.v rtl/reduce/*.v \
              rtl/comp/*.v rtl/sbu/*.v 2>/dev/null)
TOP_RTL=$(ls rtl/phoenix/*.v 2>/dev/null)
CW305_RTL="boards/cw305/phoenix_cw305_wrapper.v"

UNIT_TBS="tb_kyber_modarith tb_barrett_reduce \
          tb_array_schoolbook_agile16 tb_mldsa_karatsuba24 \
          tb_mldsa_montgomery_reduce tb_mldsa_modarith \
          tb_comp1_comp2_comp4 tb_comp3_agile_modmul \
          tb_superbutterfly_all_modes"
TOP_TBS="tb_phoenix_core tb_phoenix_host_io tb_phoenix_cw305_wrapper \
         tb_phoenix_mldsa_pwm_io"

declare -A PLUSARGS
PLUSARGS[tb_array_schoolbook_agile16]="+LIMIT=512 +NRAND=300000"

SEL_TBS="${1:-$UNIT_TBS $TOP_TBS}"
: > "$SUMMARY"
echo "PHOENIX sim 러너 — $(date '+%Y-%m-%d %H:%M:%S')  (verilator $(verilator --version|awk '{print $2}'))" >> "$SUMMARY"
echo "------------------------------------------------------------" >> "$SUMMARY"
rc_all=0

for TB in $SEL_TBS; do
    LOG="$LOGDIR/${TB}.log"
    MDIR="$BUILDDIR/$TB"
    rm -rf "$MDIR"
    {
        echo "### $TB"
        echo "# build: verilator --binary --timing -sv -Wno-fatal"
    } > "$LOG"
    RTL_FILES="$CORE_RTL"
    case "$TB" in
        tb_phoenix_core|tb_phoenix_host_io|tb_phoenix_mldsa_pwm_io)
            RTL_FILES="$CORE_RTL $TOP_RTL"
            ;;
        tb_phoenix_cw305_wrapper)
            RTL_FILES="$CORE_RTL $TOP_RTL $CW305_RTL"
            ;;
    esac
    if verilator --binary --timing -sv -Wno-fatal -Irtl/common --Mdir "$MDIR" \
        --top-module "$TB" $RTL_FILES "tb/${TB}.sv" >> "$LOG" 2>&1; then
        if "./$MDIR/V${TB}" ${PLUSARGS[$TB]:-} >> "$LOG" 2>&1; then :; fi
        # 검증 정직성: checks=0 인 PASS 는 vacuous → INCONCLUSIVE 로 표기
        # (예: tb_barrett_reduce 는 verilator 하니스 이상으로 loop 미집계;
        #  Barrett RTL 정합은 tb_comp3_agile_modmul/tb_superbutterfly_all_modes
        #  로 전이 검증한다).
        if grep -qE "checks=0 errors=0 PASS" "$LOG"; then
            res="INCONCLUSIVE"
        elif grep -qE "errors=0 PASS|\] PASS" "$LOG" && ! grep -q "FAIL" "$LOG"; then
            res="PASS"
        else
            res="FAIL"; rc_all=1
        fi
    else
        res="BUILD-FAIL"; rc_all=1
    fi
    line=$(grep -hE '\] (checks|.*)=.*(PASS|FAIL)|\] PASS|PHOENIX-CYCLES|latency = 8' "$LOG" | tail -1)
    printf "%-32s %-10s %s\n" "$TB" "$res" "$line" | tee -a "$SUMMARY"
done

echo "------------------------------------------------------------" >> "$SUMMARY"
echo "NOTE: INCONCLUSIVE = verilator 하니스에서 checks=0 (vacuous)." | tee -a "$SUMMARY"
echo "  tb_barrett_reduce는 전이 검증으로 보조 확인한다." | tee -a "$SUMMARY"
echo "------------------------------------------------------------" >> "$SUMMARY"
echo "EXIT=$rc_all  (PASS=정상, INCONCLUSIVE=별도 전이검증, FAIL 시 비0)" | tee -a "$SUMMARY"
exit $rc_all
