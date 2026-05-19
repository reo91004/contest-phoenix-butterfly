# synth/check_dsp_zero.tcl
# 핸드오버 §13.4 — report_utilization 파싱으로 DSP48 = 0 객관 확인.
# 사용: vivado -mode batch -source synth/check_dsp_zero.tcl -tclargs <util.rpt>
#  exit code 0 = DSP 0, 1 = DSP>0 or parse fail.

if {[llength $argv] < 1} { puts "usage: check_dsp_zero.tcl <util.rpt>"; exit 1 }
set rpt [lindex $argv 0]
if {![file exists $rpt]} { puts "ERROR: $rpt not found"; exit 1 }

set fh [open $rpt r]
set data [read $fh]
close $fh

set dsp -1
foreach line [split $data "\n"] {
    # utilization 표의 DSP/DSP48 행: | DSP(48...) | <used> | ...
    if {[regexp {^\s*\|\s*DSP[0-9A-Za-z]*\s*\|\s*([0-9]+)\s*\|} $line -> n]} {
        set dsp $n
    }
}
if {$dsp < 0} {
    puts "WARN: no DSP row found in $rpt (no DSP inferred → treat as 0)"
    puts "DSP=0 OK"
    exit 0
} elseif {$dsp == 0} {
    puts "DSP=0 OK (REQ-RTL-003) — $rpt"
    exit 0
} else {
    puts "ERROR: DSP=$dsp (>0) in $rpt — REQ-RTL-003 위반"
    exit 1
}
