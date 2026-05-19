# PHOENIX CW305 Vivado project generator
#
# Usage, from this directory:
#   vivado -mode batch -source create_phoenix_project.tcl
#   vivado -mode gui   -source create_phoenix_project.tcl
#
# This creates a normal Vivado .xpr so Project Manager run buttons work.
# Generated project artifacts are ignored by Git; keep this Tcl as source.

set TOP_MODULE cw305_phoenix_top
set PART [expr {[llength $argv] >= 1 ? [lindex $argv 0] : "xc7a100tftg256-2"}]
set PROJ_NAME phoenix_cw305
set PROJ_DIR [file normalize "./vivado_project"]

create_project -force $PROJ_NAME $PROJ_DIR -part $PART

set_property target_language Verilog [current_project]
set_property default_lib work [current_project]

set srcs [list \
    cw305_aes_defines.v \
    clog2.v \
    cdc_pulse.v \
    clocks.v \
    cw305_usb_reg_fe.v \
    cw305_reg_aes.v \
]

foreach dir {common arith mul reduce comp sbu phoenix} {
    foreach f [lsort [glob ../../rtl/$dir/*.v]] {
        lappend srcs $f
    }
}

lappend srcs phoenix_cw305_wrapper.v
lappend srcs cw305_phoenix_top.v

add_files -norecurse -fileset sources_1 $srcs
add_files -norecurse -fileset constrs_1 constraints/cw305_phoenix_30ns.xdc
add_files -norecurse -fileset utils_1 ./report_core_hierarchy.tcl

set_property include_dirs [list ../.. ../../rtl/common .] [get_filesets sources_1]
set_property top $TOP_MODULE [get_filesets sources_1]
update_compile_order -fileset sources_1

# Match the batch bitstream flow: no DSP inference for PHOENIX arithmetic.
set synth_run [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.MAX_DSP 0 $synth_run

# Match implementation directives used by build_phoenix_bitstream.tcl.
set impl_run [get_runs impl_1]
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE ExtraTimingOpt $impl_run
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE NoTimingRelaxation $impl_run
set_property STEPS.ROUTE_DESIGN.TCL.POST [file normalize "./report_core_hierarchy.tcl"] $impl_run

puts "============================================"
puts "PHOENIX CW305 Vivado project created"
puts "Project: $PROJ_DIR/$PROJ_NAME.xpr"
puts "Part: $PART"
puts "Top: $TOP_MODULE"
puts "PPT hierarchy row: u_phoenix/u_core (phoenix_top)"
puts "Open with:"
puts "  vivado $PROJ_DIR/$PROJ_NAME.xpr"
puts "============================================"
