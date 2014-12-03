-------------------------------------------------------------------------------
-- Title      : Auxiliary clock generation (10MHz by default)
-- Project    : White Rabbit Switch
-------------------------------------------------------------------------------
-- File       : xwrsw_gen_10mhz.vhd
-- Author     : Grzegorz Daniluk
-- Company    : CERN BE-CO-HT
-- Created    : 2014-12-01
-- Last update: 2014-12-01
-- Platform   : FPGA-generic
-- Standard   : VHDL
-------------------------------------------------------------------------------
-- Description:
-- Module used to generate aux clock of configured frequency and phase. It can
-- be used with WRS hardware >= 3.4. The clk_aux_p/n_o is there wired to CLK2
-- SMC connector on the front panel. By default 10MHz signal is generated.
-------------------------------------------------------------------------------
--
-- Copyright (c) 2014 CERN / BE-CO-HT
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
-- 2014-12-01  1.0      greg.d          Created
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.wishbone_pkg.all;
use work.gen10_wbgen2_pkg.all;

library UNISIM;
use UNISIM.vcomponents.all;

entity xwrsw_gen_10mhz is
  generic (
    g_interface_mode      : t_wishbone_interface_mode      := PIPELINED;
    g_address_granularity : t_wishbone_address_granularity := WORD);
  port (
    rst_n_i     : in std_logic;
    clk_i       : in std_logic;
    pps_i       : in std_logic;
    pps_valid_i : in std_logic;

    clk_aux_p_o  : out std_logic;
    clk_aux_n_o  : out std_logic;

    slave_i   : in  t_wishbone_slave_in := cc_dummy_slave_in;
    slave_o   : out t_wishbone_slave_out);
  attribute maxdelay : string;
  attribute maxdelay of pps_i : signal is "500 ps";
end xwrsw_gen_10mhz;

architecture behav of xwrsw_gen_10mhz is

  component gen10_wishbone_slave is
    port (
      rst_n_i    : in     std_logic;
      clk_sys_i  : in     std_logic;
      wb_adr_i   : in     std_logic_vector(1 downto 0);
      wb_dat_i   : in     std_logic_vector(31 downto 0);
      wb_dat_o   : out    std_logic_vector(31 downto 0);
      wb_cyc_i   : in     std_logic;
      wb_sel_i   : in     std_logic_vector(3 downto 0);
      wb_stb_i   : in     std_logic;
      wb_we_i    : in     std_logic;
      wb_ack_o   : out    std_logic;
      wb_stall_o : out    std_logic;
      regs_i     : in     t_gen10_in_registers;
      regs_o     : out    t_gen10_out_registers);
  end component;

  component pll_62_5_500mhz is
    port(
      clk_ref_i  : in  std_logic;
      clk_500_o  : out std_logic;
      CLKFB_IN   : in  std_logic;
      CLKFB_OUT  : out std_logic;
      RESET      : in  std_logic;
      LOCKED     : out std_logic);
  end component;
  
  component oserdes_8_to_1 is
    generic(
      sys_w : integer := 1;
      dev_w : integer := 8); 
    port(
      DATA_OUT_FROM_DEVICE : in  std_logic_vector(dev_w-1 downto 0); 
      DATA_OUT_TO_PINS_P   : out std_logic_vector(sys_w-1 downto 0); 
      DATA_OUT_TO_PINS_N   : out std_logic_vector(sys_w-1 downto 0); 

      DELAY_RESET    : in  std_logic;
      DELAY_DATA_CE  : in  std_logic_vector(sys_w -1 downto 0);
      DELAY_DATA_INC : in  std_logic_vector(sys_w -1 downto 0);
      DELAY_TAP_IN   : in  std_logic_vector(5*sys_w -1 downto 0);
      DELAY_TAP_OUT  : out std_logic_vector(5*sys_w -1 downto 0);
      DELAY_LOCKED   : out std_logic;
      REF_CLOCK      : in  std_logic;

      CLK_IN     : in std_logic;
      CLK_DIV_IN : in std_logic;
      IO_RESET   : in std_logic);
  end component;

  constant c_DATA_W : integer := 8; -- parallel data width going to serdes
  constant c_HALF   : integer := 25;-- default high/low width for 10MHz

  signal clk_500    : std_logic;
  signal clk_fb     : std_logic;
  signal clk_fb_buf : std_logic;
  signal rst        : std_logic;
  signal pll_locked : std_logic;
  signal sd_out_p   : std_logic_vector(0 downto 0);
  signal sd_out_n   : std_logic_vector(0 downto 0);

  signal sd_data : std_logic_vector(c_DATA_W-1 downto 0);

  signal wb_in  : t_wishbone_slave_in;
  signal wb_out : t_wishbone_slave_out;
  signal aux_half_high: unsigned(15 downto 0);
  signal aux_half_low : unsigned(15 downto 0);
  signal aux_shift    : unsigned(15 downto 0);
  signal pps_valid_d  : std_logic;
  signal clk_realign  : std_logic;
  signal new_freq     : std_logic;

  signal wb_regs_in  : t_gen10_in_registers;
  signal wb_regs_out : t_gen10_out_registers;

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
      slave_i   => slave_i,
      slave_o   => slave_o,
      master_i  => wb_out,
      master_o  => wb_in);

  U_WB_IF: gen10_wishbone_slave
    port map (
      rst_n_i   => rst_n_i,
      clk_sys_i => clk_i,
      wb_adr_i  => wb_in.adr(1 downto 0),
      wb_dat_i  => wb_in.dat,
      wb_dat_o  => wb_out.dat,
      wb_cyc_i  => wb_in.cyc,
      wb_sel_i  => wb_in.sel,
      wb_stb_i  => wb_in.stb,
      wb_we_i   => wb_in.we,
      wb_ack_o  => wb_out.ack,
      wb_stall_o=> wb_out.stall,
      regs_i    => wb_regs_in,
      regs_o    => wb_regs_out);

  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if (rst_n_i = '0') then
        aux_half_high <= to_unsigned(c_HALF, aux_half_high'length);
        aux_half_low  <= to_unsigned(c_HALF, aux_half_low'length);
        aux_shift     <= (others=>'0');
        new_freq      <= '0';
      elsif wb_regs_out.pr_hp_width_wr_o = '1' then
        aux_half_high <= unsigned(wb_regs_out.pr_hp_width_o);
        aux_half_low  <= unsigned(wb_regs_out.pr_hp_width_o);
        new_freq      <= '1';
      elsif wb_regs_out.dcr_low_width_wr_o = '1' then
        aux_half_low  <= unsigned(wb_regs_out.dcr_low_width_o);
        new_freq      <= '1';
      elsif wb_regs_out.csr_wr_o = '1' then
        aux_shift <= unsigned(wb_regs_out.csr_o);
        new_freq  <= '1';
      else
        new_freq <= '0';
      end if;
    end if;
  end process;

  rst <= not rst_n_i;

  U_PLL_500: pll_62_5_500mhz
  port map (
    clk_ref_i => clk_i,
    clk_500_o => clk_500,
    CLKFB_IN  => clk_fb_buf,
    CLKFB_OUT => clk_fb,
    RESET     => rst,
    LOCKED    => pll_locked);

  U_BUFG: BUFG
  port map(
    O => clk_fb_buf,
    I => clk_fb);

  U_10MHZ_SERDES: oserdes_8_to_1
  generic map(
    dev_w => c_DATA_W)
  port map(
    DATA_OUT_FROM_DEVICE => sd_data,
    DATA_OUT_TO_PINS_P   => sd_out_p,
    DATA_OUT_TO_PINS_N   => sd_out_n,
    DELAY_RESET          => wb_regs_out.psr_set_val_wr_o,
    DELAY_DATA_CE        => (others=>'0'),
    DELAY_DATA_INC       => (others=>'0'),
    DELAY_TAP_IN         => wb_regs_out.psr_set_val_o,
    DELAY_TAP_OUT        => wb_regs_in.psr_cur_val_i,
    DELAY_LOCKED         => wb_regs_in.psr_lck_i,
    REF_CLOCK            => clk_i,
    CLK_IN               => clk_500,
    CLK_DIV_IN           => clk_i,
    IO_RESET             => rst);

  clk_aux_p_o  <= sd_out_p(0);
  clk_aux_n_o  <= sd_out_n(0);

  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if(rst = '1' or new_freq = '1' or pll_locked = '0') then  -- if new_freq or pll lost lock,
                                                -- force alignment to next PPS
        pps_valid_d <= '0';
      elsif(pps_i = '1') then
        pps_valid_d <= pps_valid_i;
      end if;
    end if;
  end process;
  clk_realign <= (not pps_valid_d) and pps_valid_i and pps_i;

  process(clk_i)
    variable rest  : integer range 0 to 65535;
    variable v_bit : std_logic;
  begin
    if rising_edge(clk_i) then
      if (rst='1' or pll_locked='0' or clk_realign='1') then
        if(aux_shift <= aux_half_high) then
          rest := to_integer(aux_half_high - aux_shift);
          v_bit := '1';
        else
          rest := to_integer(aux_half_low + aux_half_high - aux_shift);
          v_bit := '0';
        end if;
      else
        for i in 0 to c_DATA_W-1 loop
          if(rest /= 0) then
            sd_data(i) <= v_bit;
            rest := rest - 1;
          elsif(v_bit = '1') then
            sd_data(i) <= '0';
            v_bit := '0';
            rest := to_integer(aux_half_low-1); -- because here we already wrote first bit
                                    -- from this group
          elsif(v_bit = '0') then
            sd_data(i) <= '1';
            v_bit := '1';
            rest := to_integer(aux_half_high-1);
          end if;
        end loop;

      end if;
    end if;
  end process;

end behav;
