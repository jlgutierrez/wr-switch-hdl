-------------------------------------------------------------------------------
-- Title      : Per-port statistics counters
-- Project    : White Rabbit Switch
-------------------------------------------------------------------------------
-- File       : wrsw_pstats.vhd
-- Author     : Grzegorz Daniluk
-- Company    : CERN BE-CO-HT
-- Created    : 2013-01-11
-- Last update: 2013-01-16
-- Platform   : FPGA-generic
-- Standard   : VHDL
-------------------------------------------------------------------------------
-- Description: 

-------------------------------------------------------------------------------
-- Copyright (c) 2013 Grzegorz Daniluk
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author          Description
-- 2013-01-11  0.1      greg.d          Created
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.genram_pkg.all;
use work.pstats_wbgen2_pkg.all;

entity wrsw_pstats is
  generic(
    g_nports : integer := 2;
    g_cnt_pp : integer := 16;
    g_cnt_pw : integer := 4);
  port(
    rst_n_i : in std_logic;
    clk_i   : in std_logic;

    events_i : in std_logic_vector(g_nports*g_cnt_pp-1 downto 0);

    wb_adr_i   : in  std_logic_vector(0 downto 0);
    wb_dat_i   : in  std_logic_vector(31 downto 0);
    wb_dat_o   : out std_logic_vector(31 downto 0);
    wb_cyc_i   : in  std_logic;
    wb_sel_i   : in  std_logic_vector(3 downto 0);
    wb_stb_i   : in  std_logic;
    wb_we_i    : in  std_logic;
    wb_ack_o   : out std_logic;
    wb_stall_o : out std_logic);
end wrsw_pstats;

architecture behav of wrsw_pstats is

  component pstats_wishbone_slave
    port (
      rst_n_i    : in  std_logic;
      clk_sys_i  : in  std_logic;
      wb_adr_i   : in  std_logic_vector(0 downto 0);
      wb_dat_i   : in  std_logic_vector(31 downto 0);
      wb_dat_o   : out std_logic_vector(31 downto 0);
      wb_cyc_i   : in  std_logic;
      wb_sel_i   : in  std_logic_vector(3 downto 0);
      wb_stb_i   : in  std_logic;
      wb_we_i    : in  std_logic;
      wb_ack_o   : out std_logic;
      wb_stall_o : out std_logic;
      regs_i     : in  t_pstats_in_registers;
      regs_o     : out t_pstats_out_registers
    );
  end component;

  component port_cntr
    generic(
      g_cnt_pp : integer;
      g_cnt_pw : integer);
    port(
      rst_n_i : in std_logic;
      clk_i   : in std_logic;

      events_i : in std_logic_vector(g_cnt_pp-1 downto 0);

      ext_cyc_i : in  std_logic;
      ext_adr_i : in  std_logic_vector(f_log2_size((g_cnt_pp+g_cnt_pw-1)/g_cnt_pw)-1 downto 0);
      ext_we_i  : in  std_logic;
      ext_dat_i : in  std_logic_vector(31 downto 0);
      ext_dat_o : out std_logic_vector(31 downto 0));
  end component;

  constant c_adr_mem_sz  : integer := f_log2_size((g_cnt_pp+g_cnt_pw-1)/g_cnt_pw);
  constant c_adr_psel_sz : integer := f_log2_size(g_nports);

  --for wishbone interface
  signal wb_regs_in  : t_pstats_in_registers;
  signal wb_regs_out : t_pstats_out_registers;

  --for wb_gen wishbone interface
  signal rd_port : std_logic_vector(c_adr_psel_sz-1 downto 0);
  signal rd_val  : std_logic_vector(31 downto 0);
  signal rd_en   : std_logic;

  --for ports' ext mem interfaces
  type t_ext_adr_array is array(natural range <>) of std_logic_vector(c_adr_mem_sz-1 downto 0);
  type t_ext_dat_array is array(natural range <>) of std_logic_vector(31 downto 0);

  signal p_cyc     : std_logic_vector(g_nports-1 downto 0);
  signal p_we      : std_logic_vector(g_nports-1 downto 0);
  signal p_adr     : t_ext_adr_array(g_nports-1 downto 0);
  signal p_dat_out : t_ext_dat_array(g_nports-1 downto 0);

  type   t_rd_st is (IDLE, READ, WRITE);
  signal rd_state : t_rd_st;

begin
  
  U_WB_Slave : pstats_wishbone_slave
    port map (
      rst_n_i    => rst_n_i,
      clk_sys_i  => clk_i,
      wb_adr_i   => wb_adr_i,
      wb_dat_i   => wb_dat_i,
      wb_dat_o   => wb_dat_o,
      wb_cyc_i   => wb_cyc_i,
      wb_sel_i   => wb_sel_i,
      wb_stb_i   => wb_stb_i,
      wb_we_i    => wb_we_i,
      wb_ack_o   => wb_ack_o,
      wb_stall_o => wb_stall_o,
      regs_i     => wb_regs_in,
      regs_o     => wb_regs_out
    );

  wb_regs_in.cr_rd_en_i <= rd_en;
  wb_regs_in.cnt_val_i  <= rd_val;
  rd_port               <= wb_regs_out.cr_port_o(c_adr_psel_sz-1 downto 0);


  GEN_PCNT : for i in 0 to g_nports-1 generate

    PER_PORT_CNT : port_cntr
      generic map(
        g_cnt_pp => g_cnt_pp,
        g_cnt_pw => g_cnt_pw)
      port map(
        rst_n_i => rst_n_i,
        clk_i   => clk_i,

        events_i => events_i((i+1)*g_cnt_pp-1 downto i*g_cnt_pp),

        ext_cyc_i => p_cyc(i),
        ext_adr_i => wb_regs_out.cr_addr_o(c_adr_mem_sz-1 downto 0),
        ext_we_i  => p_we(i),
        ext_dat_i => (others => '0'),
        ext_dat_o => p_dat_out(i));

  end generate;

  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        rd_state <= IDLE;
        p_cyc    <= (others => '0');
        p_we     <= (others => '0');
        rd_val   <= (others => '0');
        rd_en    <= '0';
      else
        case(rd_state) is
          when IDLE =>
            p_cyc <= (others => '0');
            p_we  <= (others => '0');
            if(wb_regs_out.cr_rd_en_load_o = '1' and wb_regs_out.cr_rd_en_o = '1') then
              rd_en    <= '1';
              rd_state <= READ;
            end if;
          when READ =>
            p_cyc(to_integer(unsigned(rd_port))) <= '1';
            p_we                                 <= (others => '0');
            rd_en                                <= '1';
            rd_state                             <= WRITE;
          when WRITE =>
            p_cyc(to_integer(unsigned(rd_port))) <= '1';
            rd_val                               <= p_dat_out(to_integer(unsigned(rd_port)));
            p_we(to_integer(unsigned(rd_port)))  <= '1';
            rd_en                                <= '0';
            rd_state                             <= IDLE;
        end case;
      end if;
    end if;
  end process;
  
end behav;
