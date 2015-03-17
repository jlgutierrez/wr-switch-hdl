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
      clock_class_valid_o   : out std_logic);
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
