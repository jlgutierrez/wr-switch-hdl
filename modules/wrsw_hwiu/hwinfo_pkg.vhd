-------------------------------------------------------------------------------
-- Title      : Hardware Info Unit package
-- Project    : White Rabbit Switch
-------------------------------------------------------------------------------
-- File       : hwinfo_pkg.vhd
-- Author     : Grzegorz Daniluk
-- Company    : CERN BE-CO-HT
-- Created    : 2013-03-26
-- Last update: 2014-02-05
-- Platform   : FPGA-generic
-- Standard   : VHDL
-------------------------------------------------------------------------------
--
-- Copyright (c) 2013 - 2014 CERN / BE-CO-HT
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

library ieee;
use ieee.std_logic_1164.all;
use work.wishbone_pkg.all;

package hwinfo_pkg is

  constant c_str_ver : integer := 1;
  constant c_info_words  : integer := 4;

  type t_words is array (natural range <>) of std_logic_vector(31 downto 0);

  type t_hwinfo_struct is record
    struct_ver  : std_logic_vector(7 downto 0);
    nwords  : std_logic_vector(7 downto 0);
    gw_ver  : std_logic_vector(15 downto 0);
    w       : t_words(0 to c_info_words-1);
  end record;

  -- w(0) : date [Day(1B) Month(1B) Year(1B) Build(1B)]
  -- w(1) : wr-switch-hdl hash
  -- w(2) : general-cores hash
  -- w(3) : wr-cores hash
  
  function f_pack_info_header (hw : t_hwinfo_struct) return std_logic_vector;

  component xwrsw_hwiu
    generic (
      g_interface_mode      : t_wishbone_interface_mode      := PIPELINED;
      g_address_granularity : t_wishbone_address_granularity := BYTE;
      g_ndbg_regs           : integer                        := 1;
      g_ver_major           : integer;
      g_ver_minor           : integer;
      g_build               : integer                        := 0);
    port(
      rst_n_i : in std_logic;
      clk_i   : in std_logic;
  
      dbg_regs_i    : in std_logic_vector(g_ndbg_regs*32-1 downto 0) := (others=>'0');
      dbg_chps_id_o : out std_logic_vector(7 downto 0);
  
      wb_i : in  t_wishbone_slave_in;
      wb_o : out t_wishbone_slave_out);
  end component;


end package;

package body hwinfo_pkg is

  function f_pack_info_header (hw : t_hwinfo_struct) return std_logic_vector is
    variable word : std_logic_vector(31 downto 0);
  begin
    word(31 downto 24) := hw.struct_ver;
    word(23 downto 16) := hw.nwords;
    word(15 downto 0)  := hw.gw_ver;
    return word;
  end function;

end hwinfo_pkg;
