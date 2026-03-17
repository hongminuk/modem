-- Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
-- Copyright 2022-2024 Advanced Micro Devices, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2024.2.1 (lin64) Build 5266912 Sun Dec 15 09:03:31 MST 2024
-- Date        : Mon Mar 16 15:06:05 2026
-- Host        : hong-System-Product-Name running 64-bit Ubuntu 22.04.5 LTS
-- Command     : write_vhdl -force -mode synth_stub -rename_top decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix -prefix
--               decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix_ fir_rrc_rx_stub.vhdl
-- Design      : fir_rrc_rx
-- Purpose     : Stub declaration of top-level module interface
-- Device      : xc7z020clg400-3
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix is
  Port ( 
    aresetn : in STD_LOGIC;
    aclk : in STD_LOGIC;
    s_axis_data_tvalid : in STD_LOGIC;
    s_axis_data_tready : out STD_LOGIC;
    s_axis_data_tdata : in STD_LOGIC_VECTOR ( 39 downto 0 );
    m_axis_data_tvalid : out STD_LOGIC;
    m_axis_data_tready : in STD_LOGIC;
    m_axis_data_tdata : out STD_LOGIC_VECTOR ( 55 downto 0 )
  );

  attribute CHECK_LICENSE_TYPE : string;
  attribute CHECK_LICENSE_TYPE of decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix : entity is "fir_rrc_rx,fir_compiler_v7_2_23,{}";
  attribute core_generation_info : string;
  attribute core_generation_info of decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix : entity is "fir_rrc_rx,fir_compiler_v7_2_23,{x_ipProduct=Vivado 2024.2.1,x_ipVendor=xilinx.com,x_ipLibrary=ip,x_ipName=fir_compiler,x_ipVersion=7.2,x_ipCoreRevision=23,x_ipLanguage=VERILOG,x_ipSimLanguage=MIXED,C_XDEVICEFAMILY=zynq,C_ELABORATION_DIR=./,C_COMPONENT_NAME=fir_rrc_rx,C_COEF_FILE=fir_rrc_rx.mif,C_COEF_FILE_LINES=21,C_FILTER_TYPE=0,C_INTERP_RATE=1,C_DECIM_RATE=1,C_ZERO_PACKING_FACTOR=1,C_SYMMETRY=1,C_NUM_FILTS=1,C_NUM_TAPS=41,C_NUM_CHANNELS=1,C_CHANNEL_PATTERN=fixed,C_ROUND_MODE=0,C_COEF_RELOAD=0,C_NUM_RELOAD_SLOTS=1,C_COL_MODE=1,C_COL_PIPE_LEN=4,C_COL_CONFIG=1,C_OPTIMIZATION=0,C_DATA_PATH_WIDTHS=17_17,C_DATA_IP_PATH_WIDTHS=34,C_DATA_PX_PATH_WIDTHS=34,C_DATA_WIDTH=34,C_COEF_PATH_WIDTHS=16_16,C_COEF_WIDTH=16,C_DATA_PATH_SRC=0_1,C_COEF_PATH_SRC=0_0,C_PX_PATH_SRC=0_1,C_DATA_PATH_SIGN=1_0,C_COEF_PATH_SIGN=0_0,C_ACCUM_PATH_WIDTHS=36_35,C_OUTPUT_WIDTH=52,C_OUTPUT_PATH_WIDTHS=52,C_ACCUM_OP_PATH_WIDTHS=52,C_EXT_MULT_CNFG=0_1_0_17,C_DATA_PATH_PSAMP_SRC=0,C_OP_PATH_PSAMP_SRC=0,C_NUM_MADDS=1,C_OPT_MADDS=none,C_OVERSAMPLING_RATE=21,C_INPUT_RATE=300000,C_OUTPUT_RATE=300000,C_DATA_MEMTYPE=0,C_COEF_MEMTYPE=2,C_IPBUFF_MEMTYPE=0,C_OPBUFF_MEMTYPE=0,C_DATAPATH_MEMTYPE=0,C_MEM_ARRANGEMENT=1,C_DATA_MEM_PACKING=0,C_COEF_MEM_PACKING=0,C_FILTS_PACKED=0,C_LATENCY=31,C_HAS_ARESETn=1,C_HAS_ACLKEN=0,C_DATA_HAS_TLAST=0,C_S_DATA_HAS_FIFO=1,C_S_DATA_HAS_TUSER=0,C_S_DATA_TDATA_WIDTH=40,C_S_DATA_TUSER_WIDTH=1,C_M_DATA_HAS_TREADY=1,C_M_DATA_HAS_TUSER=0,C_M_DATA_TDATA_WIDTH=56,C_M_DATA_TUSER_WIDTH=1,C_HAS_CONFIG_CHANNEL=0,C_CONFIG_SYNC_MODE=0,C_CONFIG_PACKET_SIZE=0,C_CONFIG_TDATA_WIDTH=1,C_RELOAD_TDATA_WIDTH=1}";
  attribute downgradeipidentifiedwarnings : string;
  attribute downgradeipidentifiedwarnings of decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix : entity is "yes";
end decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix;

architecture stub of decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix is
  attribute syn_black_box : boolean;
  attribute black_box_pad_pin : string;
  attribute syn_black_box of stub : architecture is true;
  attribute black_box_pad_pin of stub : architecture is "aresetn,aclk,s_axis_data_tvalid,s_axis_data_tready,s_axis_data_tdata[39:0],m_axis_data_tvalid,m_axis_data_tready,m_axis_data_tdata[55:0]";
  attribute x_interface_info : string;
  attribute x_interface_info of aresetn : signal is "xilinx.com:signal:reset:1.0 aresetn_intf RST";
  attribute x_interface_mode : string;
  attribute x_interface_mode of aresetn : signal is "slave aresetn_intf";
  attribute x_interface_parameter : string;
  attribute x_interface_parameter of aresetn : signal is "XIL_INTERFACENAME aresetn_intf, POLARITY ACTIVE_LOW, INSERT_VIP 0";
  attribute x_interface_info of aclk : signal is "xilinx.com:signal:clock:1.0 aclk_intf CLK";
  attribute x_interface_mode of aclk : signal is "slave aclk_intf";
  attribute x_interface_parameter of aclk : signal is "XIL_INTERFACENAME aclk_intf, ASSOCIATED_BUSIF S_AXIS_CONFIG:M_AXIS_DATA:S_AXIS_DATA:S_AXIS_RELOAD, ASSOCIATED_RESET aresetn, ASSOCIATED_CLKEN aclken, FREQ_HZ 100000000, FREQ_TOLERANCE_HZ 0, PHASE 0.0, INSERT_VIP 0";
  attribute x_interface_info of s_axis_data_tvalid : signal is "xilinx.com:interface:axis:1.0 S_AXIS_DATA TVALID";
  attribute x_interface_mode of s_axis_data_tvalid : signal is "slave S_AXIS_DATA";
  attribute x_interface_parameter of s_axis_data_tvalid : signal is "XIL_INTERFACENAME S_AXIS_DATA, TDATA_NUM_BYTES 5, TDEST_WIDTH 0, TID_WIDTH 0, TUSER_WIDTH 0, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 0, HAS_TLAST 0, FREQ_HZ 100000000, PHASE 0.0, LAYERED_METADATA undef, INSERT_VIP 0";
  attribute x_interface_info of s_axis_data_tready : signal is "xilinx.com:interface:axis:1.0 S_AXIS_DATA TREADY";
  attribute x_interface_info of s_axis_data_tdata : signal is "xilinx.com:interface:axis:1.0 S_AXIS_DATA TDATA";
  attribute x_interface_info of m_axis_data_tvalid : signal is "xilinx.com:interface:axis:1.0 M_AXIS_DATA TVALID";
  attribute x_interface_mode of m_axis_data_tvalid : signal is "master M_AXIS_DATA";
  attribute x_interface_parameter of m_axis_data_tvalid : signal is "XIL_INTERFACENAME M_AXIS_DATA, TDATA_NUM_BYTES 7, TDEST_WIDTH 0, TID_WIDTH 0, TUSER_WIDTH 0, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 0, HAS_TLAST 0, FREQ_HZ 100000000, PHASE 0.0, LAYERED_METADATA undef, INSERT_VIP 0";
  attribute x_interface_info of m_axis_data_tready : signal is "xilinx.com:interface:axis:1.0 M_AXIS_DATA TREADY";
  attribute x_interface_info of m_axis_data_tdata : signal is "xilinx.com:interface:axis:1.0 M_AXIS_DATA TDATA";
  attribute x_core_info : string;
  attribute x_core_info of stub : architecture is "fir_compiler_v7_2_23,Vivado 2024.2.1";
begin
end;
