set script_dir [file normalize [file dirname [info script]]]
set project_dir [file normalize [file join $script_dir ..]]

create_project ticket_price $project_dir -part xc7a75tfgg484-2 -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set source_files [list \
    [file join $project_dir src key_filter.v] \
    [file join $project_dir src blink_controller.v] \
    [file join $project_dir src binary_to_bcd.v] \
    [file join $project_dir src seven_seg_display.v] \
    [file join $project_dir src fare_calculator.v] \
    [file join $project_dir src station_mapper.v] \
    [file join $project_dir src triangle_base_rom.v] \
    [file join $project_dir src distance_lookup.v] \
    [file join $project_dir src ticket_price_top.v]]

add_files -fileset sources_1 -norecurse $source_files
add_files -fileset sources_1 -norecurse [file join $project_dir data distance_rom.mem]
set_property file_type {Memory Initialization Files} \
    [get_files [file join $project_dir data distance_rom.mem]]

add_files -fileset constrs_1 -norecurse \
    [file join $project_dir constr ticket_price_top.xdc]
add_files -fileset sim_1 -norecurse \
    [file join $project_dir sim tb_ticket_price_top.v]

set_property top ticket_price_top [get_filesets sources_1]
set_property top tb_ticket_price_top [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
close_project
exit
