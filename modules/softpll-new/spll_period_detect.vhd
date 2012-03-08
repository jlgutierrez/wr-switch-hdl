-------------------------------------------------------------------------------
-- Title      : SoftPLL - linear frequency/period detector.
-- Project    : White Rabbit
-------------------------------------------------------------------------------
-- File       : softpll_period_detect.vhd
-- Author     : Tomasz Wlostowski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-06-14
-- Last update: 2012-01-23
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

  constant c_GATING_PERIOD_LOG2 : integer := 17;

  subtype t_counter is unsigned(c_GATING_PERIOD_LOG2+1 downto 0);
  type    t_counter_array is array(integer range <>) of t_counter;

  signal freq_valid_sysclk : std_logic;

  signal gate_counter         : t_counter;
  signal gate_pulse_dmtdclk   : std_logic;
  signal gate_pulse_synced    : std_logic_vector(g_num_ref_inputs-1 downto 0);
  signal fb_counters, fb_freq : t_counter_array(g_num_ref_inputs-1 downto 0);
  signal fb_muxpipe           : t_counter_array(2 downto 0);
  
  
begin  -- rtl

  p_gate_counter : process(clk_dmtd_i)
  begin
    if rising_edge(clk_dmtd_i) then
      if rst_n_dmtdclk_i = '0' then
        gate_counter <= to_unsigned(1, gate_counter'length);
      else
        if(gate_counter(c_GATING_PERIOD_LOG2) = '1') then
          gate_counter <= to_unsigned(1, gate_counter'length);
        else
          gate_counter <= gate_counter + 1;
        end if;
      end if;
    end if;
  end process;

  gate_pulse_dmtdclk <= gate_counter(c_GATING_PERIOD_LOG2);

  gen_feedback_counters : for i in 0 to g_num_ref_inputs-1 generate
    
    U_Gate_Sync : gc_pulse_synchronizer
      port map (
        clk_in_i  => clk_dmtd_i,
        clk_out_i => clk_ref_i(i),
        rst_n_i   => rst_n_sysclk_i,
        d_p_i     => gate_pulse_dmtdclk,
        q_p_o     => gate_pulse_synced(i));

    p_feedback_counter : process(clk_ref_i(i))
    begin
      if rst_n_sysclk_i = '0' then
        fb_counters(i) <= to_unsigned(1, c_GATING_PERIOD_LOG2+2);
      elsif rising_edge(clk_ref_i(i)) then

        if(gate_pulse_synced(i) = '1') then
          fb_freq(i)     <= fb_counters(i);
          fb_counters(i) <= to_unsigned(0, c_GATING_PERIOD_LOG2+2);
        else
          fb_counters(i) <= fb_counters(i) + 1;
        end if;
      end if;
    end process;
  end generate gen_feedback_counters;

  U_Sync_Gate : gc_sync_ffs
    generic map (
      g_sync_edge => "positive")
    port map (
      clk_i    => clk_sys_i,
      rst_n_i  => rst_n_sysclk_i,
      data_i   => std_logic(gate_counter(c_GATING_PERIOD_LOG2-1)),
      ppulse_o => freq_valid_sysclk);

  p_mux_counters : process(clk_sys_i)
  begin
    if rising_edge(clk_sys_i) then
      fb_muxpipe(0) <= fb_freq(to_integer(unsigned(in_sel_i)));
      for i in 1 to fb_muxpipe'length-1 loop
        fb_muxpipe(i) <= fb_muxpipe(i-1);
      end loop;  -- i
    end if;
  end process;

  p_output : process(clk_sys_i)
  begin
    if rising_edge(clk_sys_i) then
      if rst_n_sysclk_i = '0' then
        freq_err_o       <= (others => '0');
        freq_err_stb_p_o <= '0';
      elsif(freq_valid_sysclk = '1') then
        freq_err_o       <= std_logic_vector(resize(fb_muxpipe(fb_muxpipe'length-1) - (2 ** c_GATING_PERIOD_LOG2), freq_err_o'length));
        freq_err_stb_p_o <= '1';
      else
        freq_err_stb_p_o <= '0';
      end if;
    end if;
  end process;

end rtl;
