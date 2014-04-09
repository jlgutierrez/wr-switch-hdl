-------------------------------------------------------------------------------
-- Title      : Hardware Info Unit wrapper
-- Project    : White Rabbit Switch
-------------------------------------------------------------------------------
-- File       : xwrsw_hwiu.vhd
-- Author     : Grzegorz Daniluk
-- Company    : CERN BE-CO-HT
-- Created    : 2013-03-26
-- Last update: 2014-02-05
-- Platform   : FPGA-generic
-- Standard   : VHDL
-------------------------------------------------------------------------------
-- Description:
-- Debugging module, allows reading the content of selected registers inside 
-- WR Switch GW through Wishbone interface.
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
-- Revisions  :
-- Date        Version  Author          Description
-- 2013-03-26  0.1      greg.d          Created
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.wishbone_pkg.all;
use work.hwiu_wbgen2_pkg.all;
use work.hwinfo_pkg.all;
use work.hwver_pkg.all;

entity xwrsw_hwiu is
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

    dbg_regs_i    : in std_logic_vector(g_ndbg_regs*32-1 downto 0) := (others => '0');
    dbg_chps_id_o : out std_logic_vector(7 downto 0);

    wb_i : in  t_wishbone_slave_in;
    wb_o : out t_wishbone_slave_out);
end xwrsw_hwiu;

architecture behav of xwrsw_hwiu is

  component hwiu_wishbone_slave
    port (
      rst_n_i    : in  std_logic;
      clk_sys_i  : in  std_logic;
      wb_adr_i   : in  std_logic_vector(1 downto 0);
      wb_dat_i   : in  std_logic_vector(31 downto 0);
      wb_dat_o   : out std_logic_vector(31 downto 0);
      wb_cyc_i   : in  std_logic;
      wb_sel_i   : in  std_logic_vector(3 downto 0);
      wb_stb_i   : in  std_logic;
      wb_we_i    : in  std_logic;
      wb_ack_o   : out std_logic;
      wb_stall_o : out std_logic;
      regs_i     : in  t_hwiu_in_registers;
      regs_o     : out t_hwiu_out_registers
    );
  end component;

  signal wb_in  : t_wishbone_slave_in;
  signal wb_out : t_wishbone_slave_out;

  signal wb_regs_in  : t_hwiu_in_registers;
  signal wb_regs_out : t_hwiu_out_registers;

  type   t_rd_st is (IDLE, READ);
  signal rd_state : t_rd_st;

  signal rd_val        : std_logic_vector(31 downto 0);
  signal rd_err, rd_en : std_logic;

  constant c_dat_wrds : integer := c_info_words+1 +  -- HW Info
                                   g_ndbg_regs;      -- Debug registers
  --signal data : std_logic_vector( c_dat_wrds*32-1 downto 0);
  signal data : t_words(0 to c_info_words+g_ndbg_regs);

  -- regs for storing HW version info
  signal hwinfo : t_hwinfo_struct;

begin

  U_Adapter : wb_slave_adapter
    generic map (
      g_master_use_struct  => true,
      g_master_mode        => CLASSIC,
      g_master_granularity => WORD,
      g_slave_use_struct   => true,
      g_slave_mode         => g_interface_mode,
      g_slave_granularity  => g_address_granularity)
    port map (
      clk_sys_i => clk_i,
      rst_n_i   => rst_n_i,
      slave_i   => wb_i,
      slave_o   => wb_o,
      master_i  => wb_out,
      master_o  => wb_in);

  wb_out.err <= '0';
  wb_out.rty <= '0';
  wb_out.int <= '0';

  U_WB_Slave : hwiu_wishbone_slave
    port map(
      rst_n_i    => rst_n_i,
      clk_sys_i  => clk_i,
      wb_adr_i   => wb_in.adr(1 downto 0),
      wb_dat_i   => wb_in.dat,
      wb_dat_o   => wb_out.dat,
      wb_cyc_i   => wb_in.cyc,
      wb_sel_i   => wb_in.sel,
      wb_stb_i   => wb_in.stb,
      wb_we_i    => wb_in.we,
      wb_ack_o   => wb_out.ack,
      wb_stall_o => wb_out.stall,
      regs_i     => wb_regs_in,
      regs_o     => wb_regs_out
    );

  -- fill HW Info regs
  hwinfo.struct_ver          <= std_logic_vector(to_unsigned(c_str_ver, 8));
  hwinfo.nwords              <= std_logic_vector(to_unsigned(c_info_words, 8));
  hwinfo.gw_ver(15 downto 8) <= std_logic_vector(to_unsigned(g_ver_major, 8));
  hwinfo.gw_ver(7 downto 0)  <= std_logic_vector(to_unsigned(g_ver_minor, 8));

  hwinfo.w(0) <= c_build_date(31 downto 8) & std_logic_vector(to_unsigned(g_build, 8));
  hwinfo.w(1) <= c_switch_hdl_ver;
  hwinfo.w(2) <= c_gencores_ver;
  hwinfo.w(3) <= c_wrcores_ver;

  -- fill data available through HW info
  data(0) <= f_pack_info_header(hwinfo);
  GEN_HWINFO : for i in 0 to c_info_words-1 generate
    data(i+1) <= hwinfo.w(i);
  end generate;

  GEN_DBGREGS : for i in 0 to g_ndbg_regs-1 generate
    data(i+c_info_words+1) <= dbg_regs_i((i+1)*32-1 downto i*32);
  end generate;

  wb_regs_in.reg_val_i   <= rd_val;
  wb_regs_in.cr_rd_err_i <= rd_err;
  wb_regs_in.cr_rd_en_i  <= rd_en;

  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        rd_state <= IDLE;
        rd_en    <= '0';
        rd_err   <= '0';
      else
        case(rd_state) is
          when IDLE =>
            if(wb_regs_out.cr_rd_en_o = '1' and wb_regs_out.cr_rd_en_load_o = '1') then
              rd_en    <= '1';
              rd_state <= READ;
            end if;
          when READ =>
            rd_en    <= '0';
            rd_state <= IDLE;
            if(to_integer(unsigned(wb_regs_out.cr_adr_o)) > c_dat_wrds-1) then
              rd_err <= '1';
            else
              rd_err <= '0';
              --get part of dbg_regs input vector
              rd_val <= data(to_integer(unsigned(wb_regs_out.cr_adr_o)));
            end if;

          when others =>
            rd_state <= IDLE;
        end case;
      end if;
    end if;
  end process;

 dbg_chps_id_o <= wb_regs_out.chps_id_o;

end behav;
