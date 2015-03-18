-------------------------------------------------------------------------------
-- Title      : PTP Support Unit Package
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : psu_private_pkg.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2015-03-17
-- Last update: 2015-03-17
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
--
-- Copyright (c) 2015 CERN / BE-CO-HT
--
-- This source file is free software; you can redistribute it
-- and/or modify it under the terms of the GNU Lesser General
-- Public License as published by the Free Software Foundation;
-- either version 2.1 of the License, or (at your option) any
-- later version.
--
-- This source is distributed in the hope that it will be
-- useful, but WITHOUT ANY WARRANTY; without even the implied
-- warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
-- PURPOSE.  See the GNU Lesser General Public License for more
-- details.
--
-- You should have received a copy of the GNU Lesser General
-- Public License along with this source; if not, download it
-- from http://www.gnu.org/licenses/lgpl-2.1.html
--
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2015-03-17  1.0      mlipinsk Created
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.CEIL;
use ieee.math_real.log2;

library work;
use work.wr_fabric_pkg.all;


package psu_pkg is

  type t_snoop_mode is (TX_SEQ_ID_MODE, RX_CLOCK_CLASS_MODE);
  function f_onehot_decode(x : std_logic_vector) return std_logic_vector;
  component psu_announce_snooper is
    generic(
      g_port_number   : integer := 18;
      g_snoop_mode    : t_snoop_mode := TX_SEQ_ID_MODE);
    port (
      clk_sys_i : in std_logic;
      rst_n_i   : in std_logic;
      snk_i                 : in  t_wrf_sink_in;
      src_i                 : in  t_wrf_source_in;
      rtu_dst_port_mask_i   : in std_logic_vector(g_port_number-1 downto 0);
      ptp_source_id_addr_o  : out std_logic_vector(7  downto 0); 
      ptp_source_id_data_i  :  in std_logic_vector(15 downto 0); 
      rxtx_detected_mask_o  : out std_logic_vector(g_port_number-1 downto 0);
      seq_id_o              : out std_logic_vector(15 downto 0);
      seq_id_valid_o        : out std_logic;
      clock_class_o         : out std_logic_vector(15 downto 0);
      clock_class_valid_o   : out std_logic;
      ignore_rx_port_id_i   :  in std_logic);
  end component;
  component psu_packet_injection is
    port (
      clk_sys_i : in std_logic;
      rst_n_i   : in std_logic;
      src_i : in  t_wrf_source_in;
      src_o : out t_wrf_source_out;
      snk_i : in  t_wrf_sink_in;
      snk_o : out t_wrf_sink_out;
      inject_req_i        : in  std_logic;
      inject_ready_o      : out std_logic;
      inject_packet_sel_i : in  std_logic_vector(2 downto 0);
      inject_user_value_i : in  std_logic_vector(15 downto 0);
      inject_mode_i       : in  std_logic_vector(1 downto 0);
      mem_addr_o : out std_logic_vector(9 downto 0);
      mem_data_i : in  std_logic_vector(17 downto 0));
  end component;

end psu_pkg;

package body psu_pkg is

  function f_onehot_decode(x : std_logic_vector) return std_logic_vector is
    variable tmp : std_logic_vector(2**x'length-1 downto 0);
  begin
    tmp                          := (others => '0');
    tmp(to_integer(unsigned(x))) := '1';

    return tmp;
  end function f_onehot_decode;


end psu_pkg;
