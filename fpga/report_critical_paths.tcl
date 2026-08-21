# -----------------------------------------------------------------------------
# Script: report_critical_paths.tcl
# Description: Reports the top critical timing paths using Quartus Timing Analyzer.
# Usage: quartus_sta -t report_critical_paths.tcl [project_name] [num_paths]
# Default: project_name = "npu", num_paths = 20
# -----------------------------------------------------------------------------

package require ::quartus::project
package require ::quartus::sta

# Parse arguments
set project_name "npu"
set num_paths 20

if { [llength $quartus(args)] >= 1 } {
    set project_name [lindex $quartus(args) 0]
}
if { [llength $quartus(args)] >= 2 } {
    set num_paths [lindex $quartus(args) 1]
}

post_message -type info "Running Timing Analysis for project '$project_name' (Top $num_paths paths)..."

# Open project if not already open
if { ![is_project_open] } {
    if { [project_exists $project_name] } {
        project_open $project_name
    } else {
        post_message -type error "Project '$project_name' not found in current directory ([pwd])."
        qexit -error
    }
}

# Create timing netlist and read constraints
if { [catch { create_timing_netlist } err] } {
    post_message -type error "Failed to create timing netlist: $err"
    project_close
    qexit -error
}

read_sdc
update_timing_netlist

# ---------------------------------------------------------
# Report Top Critical Setup Paths
# ---------------------------------------------------------
post_message -type info "================================================================================"
post_message -type info " Top $num_paths Critical Setup (Worst-Case Slack) Paths"
post_message -type info "================================================================================"

report_timing \
    -npaths $num_paths \
    -setup \
    -detail full_path \
    -stdout

# ---------------------------------------------------------
# Report Top Critical Hold Paths
# ---------------------------------------------------------
post_message -type info "================================================================================"
post_message -type info " Top $num_paths Critical Hold (Worst-Case Slack) Paths"
post_message -type info "================================================================================"

report_timing \
    -npaths $num_paths \
    -hold \
    -detail full_path \
    -stdout

# Clean up
delete_timing_netlist
project_close

post_message -type info "Timing report completed successfully."
