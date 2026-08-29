# Board and display pin mapping inherited from the existing XC7A75T project.
set_property PACKAGE_PIN Y18 [get_ports clk]
set_property PACKAGE_PIN N15 [get_ports sw4_rst_n]
set_property PACKAGE_PIN E3  [get_ports key1_n]
set_property PACKAGE_PIN G4  [get_ports key2_n]
set_property PACKAGE_PIN P19 [get_ports key3_n]
set_property PACKAGE_PIN R19 [get_ports key4_n]
set_property PACKAGE_PIN N14 [get_ports sw1]
set_property PACKAGE_PIN P16 [get_ports sw2]
set_property PACKAGE_PIN R17 [get_ports sw3]

# On-board LED1..LED4 pins from the matching Nuclei XC7A75T board constraints.
set_property PACKAGE_PIN E22 [get_ports {led[0]}]
set_property PACKAGE_PIN D22 [get_ports {led[1]}]
set_property PACKAGE_PIN D19 [get_ports {led[2]}]
set_property PACKAGE_PIN F20 [get_ports {led[3]}]

set_property PACKAGE_PIN AB18 [get_ports {seg[0]}]
set_property PACKAGE_PIN U17  [get_ports {seg[1]}]
set_property PACKAGE_PIN U18  [get_ports {seg[2]}]
set_property PACKAGE_PIN P14  [get_ports {seg[3]}]
set_property PACKAGE_PIN R14  [get_ports {seg[4]}]
set_property PACKAGE_PIN R18  [get_ports {seg[5]}]
set_property PACKAGE_PIN T18  [get_ports {seg[6]}]
set_property PACKAGE_PIN N17  [get_ports {seg[7]}]

set_property PACKAGE_PIN AA18 [get_ports {sel[0]}]
set_property PACKAGE_PIN W17  [get_ports {sel[1]}]
set_property PACKAGE_PIN V17  [get_ports {sel[2]}]
set_property PACKAGE_PIN AB20 [get_ports {sel[3]}]
set_property PACKAGE_PIN AA19 [get_ports {sel[4]}]
set_property PACKAGE_PIN V19  [get_ports {sel[5]}]
set_property PACKAGE_PIN V18  [get_ports {sel[6]}]
set_property PACKAGE_PIN Y19  [get_ports {sel[7]}]

set_property IOSTANDARD LVCMOS33 [get_ports {clk sw4_rst_n key1_n key2_n key3_n key4_n}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw1 sw2 sw3 led[*] seg[*] sel[*]}]

create_clock -name sys_clk -period 20.000 [get_ports clk]

set_false_path -from [get_ports {sw4_rst_n key1_n key2_n key3_n key4_n sw1 sw2 sw3}]
set_false_path -to [get_ports {led[*] seg[*] sel[*]}]

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
