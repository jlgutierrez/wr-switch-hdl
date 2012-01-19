-------------------------------------------------------------------------------
-- Title      : WR NIC - constants package
-- Project    : WhiteRabbit Switch
-------------------------------------------------------------------------------
-- File       : nic_constants_pkg.vhd
-- Author     : Tomasz Wlostowski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-11-24
-- Last update: 2010-11-27
-- Platform   : FPGA-generic
-- Standard   : VHDL
-------------------------------------------------------------------------------
-- Description: Package with  global NIC constants
-------------------------------------------------------------------------------
-- Copyright (c) 2010 Tomasz Wlostowski
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author          Description
-- 2010-11-24  1.0      twlostow        Created
-------------------------------------------------------------------------------

library IEEE;

use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;


package nic_constants_pkg is

  -- number of TX descriptors. Must be a power of 2.
  constant c_nic_num_tx_descriptors : integer := 8;

  -- log2(c_nic_num_tx_descriptors)
  constant c_nic_num_tx_descriptors_log2 : integer := 3;

  -- number of RX descriptors. Must be a power of 2.
  constant c_nic_num_rx_descriptors : integer := 8;

  -- log2(c_nic_num_rx_descriptors)
  constant c_nic_num_rx_descriptors_log2 : integer := 3;
  
  -- endianess of the packet buffer
  constant c_nic_buf_little_endian : boolean := true;

  -- log2(size of the packet buffer)
  constant c_nic_buf_size_log2 : integer := 15;
  
end package nic_constants_pkg;

