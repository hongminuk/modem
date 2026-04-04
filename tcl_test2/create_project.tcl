# ==============================================================================
# build.tcl - Recreate Single Carrier Modem Vivado project
#
# Usage:
#   vivado -mode batch -source build.tcl
#   or from Vivado Tcl console:
#   source build.tcl
# ==============================================================================

# --- Project configuration ----------------------------------------------------
set project_name  "single_carrier_modem"
set part          "xc7z020clg400-3"
set top_module    "qpsk_frame_sync_top"
set sim_top       "tb_qpsk_frame_sync_top"

# --- Resolve paths relative to this script ------------------------------------
set script_dir [file dirname [file normalize [info script]]]
set src_dir    [file join $script_dir "src"]
set build_dir  [file join $script_dir "Vivado_Project"]

# --- Clean previous build (optional) -----------------------------------------
if {[file exists $build_dir]} {
    puts "INFO: Removing previous build directory: $build_dir"
    file delete -force $build_dir
}

# --- Create project -----------------------------------------------------------
create_project $project_name $build_dir -part $part -force
set proj [current_project]

set_property target_language    Verilog         $proj
set_property simulator_language MIXED           $proj
set_property default_lib        xil_defaultlib  $proj

# --- Add RTL sources ----------------------------------------------------------
set rtl_files [glob -directory [file join $src_dir rtl] *.sv]
add_files -fileset sources_1 $rtl_files

# Mark qpsk_rrc_step1_top.sv as not used in synthesis (auto-disabled in original)
set_property IS_ENABLED 0 [get_files -of_objects [get_filesets sources_1] \
    [file join $src_dir rtl qpsk_rrc_step1_top.sv]]

set_property top $top_module [current_fileset]

# --- Add simulation sources ---------------------------------------------------
set sim_files [glob -directory [file join $src_dir sim] *.sv]
add_files -fileset sim_1 $sim_files

# Add waveform config
add_files -fileset sim_1 [file join $src_dir wcfg tb_qpsk_frame_sync_top_behav.wcfg]

set_property top     $sim_top        [get_filesets sim_1]
set_property top_lib xil_defaultlib  [get_filesets sim_1]

# Set waveform config for simulation
set_property xsim.view [file join $src_dir wcfg tb_qpsk_frame_sync_top_behav.wcfg] \
    [get_filesets sim_1]

# --- Copy COE file into IP directory ------------------------------------------
set coe_src [file join $src_dir coe rrc_sps4_beta0p35_span10_q16p.coe]

# --- Create FIR IP: fir_rrc (TX RRC filter) -----------------------------------
create_ip -name fir_compiler -vendor xilinx.com -library ip -version 7.2 \
    -module_name fir_rrc

set_property -dict [list \
    CONFIG.CoefficientSource        {COE_File} \
    CONFIG.Coefficient_File         $coe_src \
    CONFIG.Coefficient_Sets         {1} \
    CONFIG.Coefficient_Sign         {Signed} \
    CONFIG.Quantization             {Integer_Coefficients} \
    CONFIG.Coefficient_Width        {16} \
    CONFIG.Coefficient_Fractional_Bits {0} \
    CONFIG.Coefficient_Structure    {Inferred} \
    CONFIG.Data_Width               {16} \
    CONFIG.Output_Rounding_Mode     {Full_Precision} \
    CONFIG.Output_Width             {34} \
    CONFIG.M_DATA_Has_TREADY        {true} \
    CONFIG.Has_ARESETn              {true} \
    CONFIG.Sample_Frequency         {0.001} \
    CONFIG.Clock_Frequency          {300.0} \
] [get_ips fir_rrc]

generate_target all [get_ips fir_rrc]

# --- Create FIR IP: fir_rrc_rx (RX matched filter) ---------------------------
create_ip -name fir_compiler -vendor xilinx.com -library ip -version 7.2 \
    -module_name fir_rrc_rx

set_property -dict [list \
    CONFIG.CoefficientSource        {COE_File} \
    CONFIG.Coefficient_File         $coe_src \
    CONFIG.Coefficient_Sets         {1} \
    CONFIG.Coefficient_Sign         {Signed} \
    CONFIG.Quantization             {Integer_Coefficients} \
    CONFIG.Coefficient_Width        {16} \
    CONFIG.Coefficient_Fractional_Bits {0} \
    CONFIG.Coefficient_Structure    {Inferred} \
    CONFIG.Data_Width               {34} \
    CONFIG.Data_Fractional_Bits     {0} \
    CONFIG.Output_Rounding_Mode     {Full_Precision} \
    CONFIG.Output_Width             {52} \
    CONFIG.M_DATA_Has_TREADY        {true} \
    CONFIG.Has_ARESETn              {true} \
    CONFIG.Sample_Frequency         {0.001} \
    CONFIG.Clock_Frequency          {300.0} \
] [get_ips fir_rrc_rx]

generate_target all [get_ips fir_rrc_rx]

# --- Synthesis & implementation runs (create with defaults) -------------------
# Runs are auto-created by create_project; just ensure strategy is set
set_property strategy "Vivado Synthesis Defaults" [get_runs synth_1]
set_property strategy "Vivado Implementation Defaults" [get_runs impl_1]

# --- Update compile order ----------------------------------------------------
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "================================================================"
puts " Project created successfully: $build_dir/${project_name}.xpr"
puts " Part:       $part"
puts " Top module: $top_module"
puts " Sim top:    $sim_top"
puts "================================================================"
