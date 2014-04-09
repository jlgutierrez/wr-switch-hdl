-------------------------------------------------------------------------------
-- Title      : Per-port statistics counters
-- Project    : White Rabbit Switch
-------------------------------------------------------------------------------
-- File       : wrsw_pstats.vhd
-- Author     : Grzegorz Daniluk
-- Company    : CERN BE-CO-HT
-- Created    : 2013-01-11
-- Last update: 2013-03-04
-- Platform   : FPGA-generic
-- Standard   : VHDL
-------------------------------------------------------------------------------
-- Description:
-- Module implements the set of statistic counters for each port of WR Switch.
-- It is fully generic so that the number of ports, number of counters per port
-- and number of counters stored in a single 32-bit memory word can be
-- configured. It consists of two layers of counters. L1 is made of g_nports
-- instances of port_cntrs while L2 collects overlow events from all L1
-- port_cntrs to one port_cntrs component. The module can also generate an
-- interrupt when any of the counters (in any port) overflows. IRQ_RAM component
-- provides the information to the software saying which counters have
-- overflowed.
-------------------------------------------------------------------------------
--
-- Copyright (c) 2013 CERN / BE-CO-HT
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
-- 2013-01-11  0.1      greg.d          Created
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_misc.all;
use ieee.numeric_std.all;

library work;
use work.genram_pkg.all;
use work.pstats_wbgen2_pkg.all;

entity wrsw_pstats is
  generic(
    g_nports    : integer := 2;
    g_cnt_pp    : integer := 16;
    g_cnt_pw    : integer := 4;
    --Layer 2
    g_L2_cnt_pw : integer := 4;
    g_keep_ov   : integer := 1);
  port(
    rst_n_i : in std_logic;
    clk_i   : in std_logic;

    events_i : in std_logic_vector(g_nports*g_cnt_pp-1 downto 0);

    wb_adr_i   : in  std_logic_vector(3 downto 0);
    wb_dat_i   : in  std_logic_vector(31 downto 0);
    wb_dat_o   : out std_logic_vector(31 downto 0);
    wb_cyc_i   : in  std_logic;
    wb_sel_i   : in  std_logic_vector(3 downto 0);
    wb_stb_i   : in  std_logic;
    wb_we_i    : in  std_logic;
    wb_ack_o   : out std_logic;
    wb_stall_o : out std_logic;
    wb_int_o   : out std_logic);
end wrsw_pstats;

architecture behav of wrsw_pstats is

  component pstats_wishbone_slave
    port (
      rst_n_i          : in  std_logic;
      clk_sys_i        : in  std_logic;
      wb_adr_i         : in  std_logic_vector(3 downto 0);
      wb_dat_i         : in  std_logic_vector(31 downto 0);
      wb_dat_o         : out std_logic_vector(31 downto 0);
      wb_cyc_i         : in  std_logic;
      wb_sel_i         : in  std_logic_vector(3 downto 0);
      wb_stb_i         : in  std_logic;
      wb_we_i          : in  std_logic;
      wb_ack_o         : out std_logic;
      wb_stall_o       : out std_logic;
      wb_int_o         : out std_logic;
      irq_port0_i      : in  std_logic;
      irq_port0_ack_o  : out std_logic;
      irq_port1_i      : in  std_logic;
      irq_port1_ack_o  : out std_logic;
      irq_port2_i      : in  std_logic;
      irq_port2_ack_o  : out std_logic;
      irq_port3_i      : in  std_logic;
      irq_port3_ack_o  : out std_logic;
      irq_port4_i      : in  std_logic;
      irq_port4_ack_o  : out std_logic;
      irq_port5_i      : in  std_logic;
      irq_port5_ack_o  : out std_logic;
      irq_port6_i      : in  std_logic;
      irq_port6_ack_o  : out std_logic;
      irq_port7_i      : in  std_logic;
      irq_port7_ack_o  : out std_logic;
      irq_port8_i      : in  std_logic;
      irq_port8_ack_o  : out std_logic;
      irq_port9_i      : in  std_logic;
      irq_port9_ack_o  : out std_logic;
      irq_port10_i     : in  std_logic;
      irq_port10_ack_o : out std_logic;
      irq_port11_i     : in  std_logic;
      irq_port11_ack_o : out std_logic;
      irq_port12_i     : in  std_logic;
      irq_port12_ack_o : out std_logic;
      irq_port13_i     : in  std_logic;
      irq_port13_ack_o : out std_logic;
      irq_port14_i     : in  std_logic;
      irq_port14_ack_o : out std_logic;
      irq_port15_i     : in  std_logic;
      irq_port15_ack_o : out std_logic;
      irq_port16_i     : in  std_logic;
      irq_port16_ack_o : out std_logic;
      irq_port17_i     : in  std_logic;
      irq_port17_ack_o : out std_logic;
      regs_i           : in  t_pstats_in_registers;
      regs_o           : out t_pstats_out_registers);
  end component;

  component port_cntr
    generic(
      g_cnt_pp  : integer;
      g_cnt_pw  : integer;
      g_keep_ov : integer);
    port(
      rst_n_i   : in std_logic;
      clk_i     : in std_logic;
      events_i  : in  std_logic_vector(g_cnt_pp-1 downto 0);
      ext_adr_i : in  std_logic_vector(f_log2_size((g_cnt_pp+g_cnt_pw-1)/g_cnt_pw)-1 downto 0);
      ext_dat_o : out std_logic_vector(31 downto 0);
      ov_cnt_o  : out
			std_logic_vector(((g_cnt_pp+g_cnt_pw-1)/g_cnt_pw)*g_cnt_pw-1 downto 0));  --c_evt_range
  end component;

  component irq_ram
    generic(
      g_nports : integer := 8;
      g_cnt_pp : integer := 64;
      g_cnt_pw : integer := 32);
    port(
      rst_n_i      : in std_logic;
      clk_i        : in std_logic;
      irq_i        : in std_logic_vector(g_nports*g_cnt_pp-1 downto 0);
      ext_cyc_i    : in  std_logic := '0';
      ext_adr_i    : in  std_logic_vector(f_log2_size(g_nports*((g_cnt_pp+g_cnt_pw-1)/g_cnt_pw))-1 downto 0) := (others => '0');
      ext_we_i     : in  std_logic := '0';
      ext_dat_i    : in  std_logic_vector(31 downto 0) := (others => '0');
      ext_dat_o    : out std_logic_vector(31 downto 0));
  end component;

  ----------------------------------------------------------
  ----------------------------------------------------------

  constant c_adr_mem_sz     : integer := f_log2_size((g_cnt_pp+g_cnt_pw-1)/g_cnt_pw);
  constant c_adr_psel_sz    : integer := f_log2_size(g_nports);
  constant c_portirq_sz     : integer := (g_cnt_pp+g_cnt_pw-1)/g_cnt_pw;
  constant c_L2_event_sz    : integer := c_portirq_sz*g_cnt_pw;
  constant c_L2_adr_mem_sz  : integer := f_log2_size((g_nports*g_cnt_pp+g_L2_cnt_pw-1)/g_L2_cnt_pw);
  constant c_IRQ_pw         : integer := 32;
  constant c_IRQ_adr_mem_sz : integer := f_log2_size(g_nports*((g_cnt_pp+c_IRQ_pw-1)/c_IRQ_pw));

  ----------------------------------------------------------

  --for wishbone interface
  signal wb_regs_in  : t_pstats_in_registers;
  signal wb_regs_out : t_pstats_out_registers;

  --for wb_gen wishbone interface
  signal rd_port : std_logic_vector(c_adr_psel_sz-1 downto 0);
  signal rd_val  : std_logic_vector(31 downto 0);
  signal rd_en   : std_logic;

  --for ports' ext mem interfaces
  type t_ext_dat_array is array(natural range <>) of std_logic_vector(31 downto 0);
  signal p_dat_out : t_ext_dat_array(g_nports-1 downto 0);

  type   t_rd_st is (IDLE, READ_LS, READ_MS, WRITE_LS, WRITE_MS);
  signal rd_state : t_rd_st;
  signal rd_irq   : std_logic;

  signal irq    : std_logic_vector(g_nports*g_cnt_pp-1 downto 0);
  --signal evt_ov : std_logic_vector(g_nports-1 downto 0);

  --Layer 2
  signal L2_events  : std_logic_vector(g_nports*c_L2_event_sz-1 downto 0);
  signal L2_adr     : std_logic_vector(c_L2_adr_mem_sz-1 downto 0);
  signal L2_dat_out : std_logic_vector(31 downto 0);
  signal L2_rd_val  : std_logic_vector(31 downto 0);

  --Layer 3 (a.k.a. IRQ)
  signal L3_events    : std_logic_vector(g_nports*c_L2_event_sz-1 downto 0);
  signal IRQ_cyc      : std_logic;
  signal IRQ_port_adr : unsigned(c_IRQ_adr_mem_sz-1 downto 0);
  signal IRQ_adr      : std_logic_vector(c_IRQ_adr_mem_sz-1 downto 0);
  signal IRQ_we       : std_logic;
  signal IRQ_dat_out  : std_logic_vector(31 downto 0);

  signal port_irq     : std_logic_vector(17 downto 0);
  signal port_irq_ack : std_logic_vector(17 downto 0);
  signal port_irq_reg : std_logic_vector(17 downto 0);

begin
  
  U_WB_Slave : pstats_wishbone_slave
    port map (
      rst_n_i          => rst_n_i,
      clk_sys_i        => clk_i,
      wb_adr_i         => wb_adr_i,
      wb_dat_i         => wb_dat_i,
      wb_dat_o         => wb_dat_o,
      wb_cyc_i         => wb_cyc_i,
      wb_sel_i         => wb_sel_i,
      wb_stb_i         => wb_stb_i,
      wb_we_i          => wb_we_i,
      wb_ack_o         => wb_ack_o,
      wb_stall_o       => wb_stall_o,
      wb_int_o         => wb_int_o,
      irq_port0_i      => port_irq_reg(0),
      irq_port0_ack_o  => port_irq_ack(0),
      irq_port1_i      => port_irq_reg(1),
      irq_port1_ack_o  => port_irq_ack(1),
      irq_port2_i      => port_irq_reg(2),
      irq_port2_ack_o  => port_irq_ack(2),
      irq_port3_i      => port_irq_reg(3),
      irq_port3_ack_o  => port_irq_ack(3),
      irq_port4_i      => port_irq_reg(4),
      irq_port4_ack_o  => port_irq_ack(4),
      irq_port5_i      => port_irq_reg(5),
      irq_port5_ack_o  => port_irq_ack(5),
      irq_port6_i      => port_irq_reg(6),
      irq_port6_ack_o  => port_irq_ack(6),
      irq_port7_i      => port_irq_reg(7),
      irq_port7_ack_o  => port_irq_ack(7),
      irq_port8_i      => port_irq_reg(8),
      irq_port8_ack_o  => port_irq_ack(8),
      irq_port9_i      => port_irq_reg(9),
      irq_port9_ack_o  => port_irq_ack(9),
      irq_port10_i     => port_irq_reg(10),
      irq_port10_ack_o => port_irq_ack(10),
      irq_port11_i     => port_irq_reg(11),
      irq_port11_ack_o => port_irq_ack(11),
      irq_port12_i     => port_irq_reg(12),
      irq_port12_ack_o => port_irq_ack(12),
      irq_port13_i     => port_irq_reg(13),
      irq_port13_ack_o => port_irq_ack(13),
      irq_port14_i     => port_irq_reg(14),
      irq_port14_ack_o => port_irq_ack(14),
      irq_port15_i     => port_irq_reg(15),
      irq_port15_ack_o => port_irq_ack(15),
      irq_port16_i     => port_irq_reg(16),
      irq_port16_ack_o => port_irq_ack(16),
      irq_port17_i     => port_irq_reg(17),
      irq_port17_ack_o => port_irq_ack(17),
      regs_i           => wb_regs_in,
      regs_o           => wb_regs_out
    );

  wb_regs_in.cr_rd_en_i   <= rd_en;
  wb_regs_in.l1_cnt_val_i <= rd_val;
  wb_regs_in.l2_cnt_val_i <= L2_rd_val;
  rd_port                 <= wb_regs_out.cr_port_o(c_adr_psel_sz-1 downto 0);


  -------------------------------------------------------------
  -------------------------------------------------------------
  --  LAYER 1
  -------------------------------------------------------------

  --wb_regs_in.dbg_evt_ov_i(g_nports-1 downto 0) <= evt_ov(g_nports-1 downto 0);
  --connect rest of the evt_ov_i to '0' if synthesized for less than 18 ports
  --GEN_NUSED_EVTOV: if g_nports < 18 generate
  --  wb_regs_in.dbg_evt_ov_i(17 downto g_nports) <= (others=>'0');
  --end generate;

  GEN_PCNT : for i in 0 to g_nports-1 generate

    PER_PORT_CNT : port_cntr
      generic map(
        g_cnt_pp  => g_cnt_pp,
        g_cnt_pw  => g_cnt_pw,
        g_keep_ov => 0)
      port map(
        rst_n_i => rst_n_i,
        clk_i   => clk_i,

        events_i => events_i((i+1)*g_cnt_pp-1 downto i*g_cnt_pp),

        ext_adr_i => wb_regs_out.cr_addr_o(c_adr_mem_sz-1 downto 0),
        ext_dat_o => p_dat_out(i),

        ov_cnt_o     => L2_events((i+1)*c_L2_event_sz-1 downto i*c_L2_event_sz));
        --dbg_evt_ov_o => evt_ov(i),
        --clr_flags_i  => wb_regs_out.dbg_clr_o);

  end generate;

  -------------------------------------------------------------
  -------------------------------------------------------------
  -- LAYER 2
  -------------------------------------------------------------

  L2_CNT : port_cntr
    generic map(
      g_cnt_pp  => g_nports*c_L2_event_sz,
      g_cnt_pw  => g_L2_cnt_pw,
      g_keep_ov => 0)
    port map(
      rst_n_i => rst_n_i,
      clk_i   => clk_i,

      events_i => L2_events,

      ext_adr_i => L2_adr,
      ext_dat_o => L2_dat_out,

      ov_cnt_o     => L3_events);
      --dbg_evt_ov_o => wb_regs_in.dbg_l2_evt_ov_i,
      --clr_flags_i  => wb_regs_out.dbg_l2_clr_o);

  L2_adr <= std_logic_vector(to_unsigned(to_integer(unsigned(rd_port))*c_portirq_sz +
                        to_integer(unsigned(wb_regs_out.cr_addr_o(c_adr_mem_sz-1 downto 0))),
                        c_L2_adr_mem_sz));

  -------------------------------------------------------------
  -------------------------------------------------------------
  -- LAYER IRQ
  -------------------------------------------------------------
  --select only the events from active counters
  GEN_IRQS : for i in 0 to g_nports-1 generate
    irq((i+1)*g_cnt_pp-1 downto i*g_cnt_pp) <= L3_events(i*c_L2_event_sz+g_cnt_pp-1 downto i*c_L2_event_sz);
    port_irq(i) <= or_reduce(L3_events(i*c_L2_event_sz+g_cnt_pp-1 downto i*c_L2_event_sz));
  end generate;

  GEN_NUSED_IRQS : if g_nports < 18 generate
    port_irq(17 downto g_nports) <= (others => '0');
  end generate;

  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        port_irq_reg <= (others => '0');
      else
        port_irq_reg <= (port_irq_reg xor port_irq_ack) or port_irq;
      end if;
    end if;
  end process;

  CNTRS_IRQ : irq_ram
    generic map(
      g_nports => g_nports,
      g_cnt_pp => g_cnt_pp,
      g_cnt_pw => c_IRQ_pw)
    port map(
      rst_n_i => rst_n_i,
      clk_i   => clk_i,
      irq_i   => irq,

      ext_cyc_i => IRQ_cyc,
      ext_adr_i => IRQ_adr,
      ext_we_i  => IRQ_we,
      ext_dat_i => (others => '0'),
      ext_dat_o => IRQ_dat_out);

  -------------------------------------------------------------
  -------------------------------------------------------------
  --rd_port translated into the address in IRQ mem, based on g_cnt_pp
  IRQ_port_adr <= to_unsigned(to_integer(unsigned(rd_port))*((g_cnt_pp+c_IRQ_pw-1)/c_IRQ_pw), c_IRQ_adr_mem_sz);
  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        rd_state  <= IDLE;
        rd_val    <= (others => '0');
        L2_rd_val <= (others => '0');
        IRQ_cyc   <= '0';
        IRQ_we    <= '0';
        IRQ_adr   <= std_logic_vector(IRQ_port_adr);
        rd_irq    <= '0';
        rd_en     <= '0';
      else
        case(rd_state) is
          when IDLE =>
            IRQ_cyc <= '0';
            IRQ_we  <= '0';
            rd_irq  <= '0';
            IRQ_adr <= std_logic_vector(IRQ_port_adr);
            if(wb_regs_out.cr_rd_en_load_o = '1' and wb_regs_out.cr_rd_en_o = '1') then
              rd_en    <= '1';
              rd_state <= READ_LS;
            elsif(wb_regs_out.cr_rd_irq_load_o = '1' and wb_regs_out.cr_rd_irq_o = '1') then
              rd_irq   <= '1';
              rd_en    <= '1';
              rd_state <= READ_LS;
            end if;

          when READ_LS =>
            rd_en   <= '1';
            IRQ_we  <= '0';
            IRQ_adr <= std_logic_vector(IRQ_port_adr);
            if(rd_irq = '0') then
              IRQ_cyc  <= '0';
              rd_state <= WRITE_LS;
            elsif(rd_irq = '1' and g_cnt_pp > c_IRQ_pw) then
              --for irq read second word or clear the one already read
              IRQ_cyc  <= '1';
              rd_STATE <= READ_MS;
            else
              IRQ_cyc  <= '1';
              rd_state <= WRITE_LS;
            end if;

          when READ_MS =>
            rd_en    <= '1';
            IRQ_we   <= '0';
            IRQ_cyc  <= '1';
            IRQ_adr  <= std_logic_vector(IRQ_port_adr+1);
            rd_val   <= IRQ_dat_out;
            rd_state <= WRITE_LS;

          when WRITE_LS =>
            rd_en   <= '0';
            IRQ_adr <= std_logic_vector(IRQ_port_adr);
            if(rd_irq = '0') then
              rd_val    <= p_dat_out(to_integer(unsigned(rd_port)));
              L2_rd_val <= L2_dat_out;
              rd_state  <= IDLE;
            elsif(rd_irq = '1' and g_cnt_pp > c_IRQ_pw) then
              L2_rd_val <= IRQ_dat_out;
              IRQ_we    <= '1';
              rd_state  <= WRITE_MS;
            else
              rd_val    <= IRQ_dat_out;
              L2_rd_val <= (others => '0');
              IRQ_we    <= '1';
              rd_state  <= IDLE;
            end if;

          when WRITE_MS =>
            rd_en    <= '0';
            IRQ_adr  <= std_logic_vector(IRQ_port_adr+1);
            IRQ_we   <= '1';
            rd_state <= IDLE;
        end case;
      end if;
    end if;
  end process;

end behav;
