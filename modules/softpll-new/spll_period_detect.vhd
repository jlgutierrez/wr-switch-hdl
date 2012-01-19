-------------------------------------------------------------------------------
-- Title      : SoftPLL - linear frequency/period detector.
-- Project    : White Rabbit
-------------------------------------------------------------------------------
-- File       : softpll_period_detect.vhd
-- Author     : Tomasz Wlostowski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-06-14
-- Last update: 2012-01-17
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: Simple linear frequency detector with programmable error
-- setpoint and gating period. The measured clocks are: clk_ref_i and clk_fbck_i.
-- The error value is outputted every 2^(hpll_fbcr_fd_gate_i + 14) cycles on a
-- freq_err_o. A pulse is produced on freq_err_stb_p_o every time freq_err_o
-- is updated with a new value. freq_err_o value is:
-- - positive when clk_fbck_i is slower than selected frequency setpoint
-- - negative when clk_fbck_i is faster than selected frequency setpoint
-------------------------------------------------------------------------------
-- Copyright (c) 2010 Tomasz Wlostowski
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author          Description
-- 2010-06-14  1.0      twlostow        Created
-------------------------------------------------------------------------------

library ieee;

use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.gencores_pkg.all;

entity spll_period_detect is
  generic(
    g_num_ref_inputs : integer := 6);
  port (
-------------------------------------------------------------------------------
-- Clocks & resets
-------------------------------------------------------------------------------

-- reference clocks
    clk_ref_i : in std_logic_vector(g_num_ref_inputs-1 downto 0);

-- fed-back (VCO) clock
    clk_dmtd_i : in std_logic;

-- system clock (wishbone and I/O)
    clk_sys_i : in std_logic;

-- reset signals (the same reset synced to different clocks)
    rst_n_dmtdclk_i : in std_logic;
    rst_n_sysclk_i  : in std_logic;

-------------------------------------------------------------------------------
-- Outputs
-------------------------------------------------------------------------------    

-- frequency error value (signed)
    freq_err_o : out std_logic_vector(11 downto 0);

-- frequency error valid pulse    
    freq_err_stb_p_o : out std_logic;

    in_sel_i : in std_logic_vector(4 downto 0)
    );

end spll_period_detect;

architecture rtl of spll_period_detect is

  constant c_COUNTER_BITS  : integer := 19;
  constant c_GATING_PERIOD : integer := 1024;

-- frequency counters: feedback clock & gating counter
  signal in_muxed      : std_logic;
  signal in_sel_onehot : std_logic_vector(g_num_ref_inputs-1 downto 0);

  signal freq                                  : std_logic_vector(19 downto 0);
  signal freq_valid_dmtdclk, freq_valid_sysclk : std_logic;
  signal freq_valid_dmtdclk_d0, freq_valid_dmtdclk_pulse : std_logic;
  
begin  -- rtl


  gen_in_sel_mask : for i in 0 to g_num_ref_inputs-1 generate
    in_sel_onehot(i) <= '1' when i = to_integer(unsigned(in_sel_i)) else '0';
  end generate gen_in_sel_mask;  -- i 

  in_muxed <= '1' when unsigned(in_sel_onehot and clk_ref_i) /= 0 else '0';

  U_Freq_Meter : gc_frequency_meter
    generic map (
      g_with_internal_timebase => true,
      g_clk_sys_freq           => c_GATING_PERIOD,
      g_counter_bits           => 20)
    port map (
      clk_sys_i    => clk_dmtd_i,
      clk_in_i     => in_muxed,
      rst_n_i      => rst_n_dmtdclk_i,
      pps_p1_i     => '0',
      freq_o       => freq,
      freq_valid_o => freq_valid_dmtdclk);

  U_Pulse_Sync : gc_pulse_synchronizer
    port map (
      clk_in_i  => clk_dmtd_i,
      clk_out_i => clk_sys_i,
      rst_n_i   => rst_n_sysclk_i,
      d_p_i     => freq_valid_dmtdclk_pulse,
      q_p_o     => freq_valid_sysclk);

  p_edge_detect: process(clk_dmtd_i)
    begin
      if rising_edge(clk_dmtd_i) then
        freq_valid_dmtdclk_d0 <= freq_valid_dmtdclk;
      end if;
    end process;
  freq_valid_dmtdclk_pulse <= freq_valid_dmtdclk and not freq_valid_dmtdclk_d0;
    
  p_output : process(clk_sys_i)
  begin
    if rising_edge(clk_sys_i) then
      if rst_n_sysclk_i = '0' then
        freq_err_o       <= (others => '0');
        freq_err_stb_p_o <= '0';
      elsif(freq_valid_sysclk = '1') then
        freq_err_o       <= std_logic_vector(resize(unsigned(freq) - c_GATING_PERIOD, freq_err_o'length));
        freq_err_stb_p_o <= '1';
      else
        freq_err_stb_p_o <= '0';
      end if;
    end if;
  end process;
  
end rtl;
