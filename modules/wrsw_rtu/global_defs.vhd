-------------------------------------------------------------------------------
-- Title      : Global definitions
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : global_defs.vhd
-- Author     : Tomasz Wlostowski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-04-27
-- Last update: 2011-07-15
-- Platform   : FPGA-generic
-- Standard   : VHDL
-------------------------------------------------------------------------------
-- Description: Definitions (mostly constants) global for whole switch design.
-------------------------------------------------------------------------------
-- Copyright (c) 2010 Tomasz Wlostowski
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author          Description
-- 2010-04-27  1.0      twlostow        Created
-------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;

package global_defs is

-- Number of switch ports (including NIC)
  constant c_wrsw_num_ports : integer := 11;

-- MAC address size
  constant c_wrsw_mac_addr_width : integer := 48;

-- VID (VLAN Id) size
  constant c_wrsw_vid_width : integer := 12;

-- Priority vector size
  constant c_wrsw_prio_width : integer := 3;

-- Number of internal priority levels
  constant c_wrsw_prio_levels : integer := 8;

-- Number of RTU ports (number of switch ports - 1x NIC which doesn't use RTU)
  constant c_rtu_num_ports : integer := 10;  --c_wrsw_num_ports - 1;

-- RX error code bus width
  constant c_ep_rx_error_code_size : integer := 3;

-- TX error code bus width
  constant c_ep_tx_error_code_size : integer := 3;

-- Size of fabric control bus
  constant c_wrsw_ctrl_size : integer := 4;

-- Size of TX OOB frame identifier
  constant c_wrsw_oob_frame_id_size : integer := 16;

-- Size of rising-edge timestamp (the main one)
  constant c_wrsw_timestamp_size_r : integer := 28;

-- Size of falling-edge timestamp (the error-checking one)
  constant c_wrsw_timestamp_size_f : integer := 4;

-- empty control field (such as empty source MAC address) left by the sender to
-- be filled by the endpoint.
  constant c_wrsw_ctrl_none : std_logic_vector(c_wrsw_ctrl_size - 1 downto 0) := x"0";

  constant c_wrsw_ctrl_dst_mac   : std_logic_vector(c_wrsw_ctrl_size - 1 downto 0) := x"1";
  constant c_wrsw_ctrl_src_mac   : std_logic_vector(c_wrsw_ctrl_size - 1 downto 0) := x"2";
  constant c_wrsw_ctrl_ethertype : std_logic_vector(c_wrsw_ctrl_size - 1 downto 0) := x"3";
  constant c_wrsw_ctrl_vid_prio  : std_logic_vector(c_wrsw_ctrl_size - 1 downto 0) := x"4";
  constant c_wrsw_ctrl_tx_oob    : std_logic_vector(c_wrsw_ctrl_size - 1 downto 0) := x"5";
  constant c_wrsw_ctrl_rx_oob    : std_logic_vector(c_wrsw_ctrl_size - 1 downto 0) := x"6";
  constant c_wrsw_ctrl_payload   : std_logic_vector(c_wrsw_ctrl_size - 1 downto 0) := x"7";
  constant c_wrsw_ctrl_fcs       : std_logic_vector(c_wrsw_ctrl_size - 1 downto 0) := x"8";


-- Size of Filetering Idetifier, 801.2Q-2005, p77:range of fid=<1-4096>
  constant c_wrsw_fid_width : integer := 8;

-- Size of hash - works as address of filtering database
  constant c_wrsw_hash_width : integer := 9;

-- Size of CRC
  constant c_wrsw_crc_width : integer := 16;

-- Size of CAM address - works as part of the filtering database (-limit by ZBT space to 15 bits)
  constant c_wrsw_cam_addr_width : integer := 8;

-- Number of words in one entry (5) [actually there is 6 elements in the mFIFO, because addrress is
-- also put into fifo, this is why in the code there is '>'. so acually the mFIFO is started to be
-- read when there are 6 elements, at least]
  constant c_wrsw_entry_words_number : std_logic_vector(5 downto 0) := "000101";

-- '1' -  enable debugging
-- '0' - disable debugging
-- debugging concerns recording to FIFOs what is read from ZBT SRAM and CAM
  constant c_wrsw_rtu_debugging : std_logic := '0';

  constant c_default_hash_poly : std_logic_vector(16 - 1 downto 0) := x"1021";

end global_defs;

