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
    g_cnt_pw : integer := 4;
    --Layer 2
    g_L2_cnt_pw : integer := 4;
    g_keep_ov: integer := 1);
  port(
    rst_n_i : in std_logic;
    clk_i   : in std_logic;

    events_i : in std_logic_vector(g_nports*g_cnt_pp-1 downto 0);

    wb_adr_i   : in  std_logic_vector(2 downto 0);
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
      wb_adr_i   : in  std_logic_vector(2 downto 0);
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
      g_cnt_pw : integer;
      g_keep_ov: integer);
    port(
      rst_n_i : in std_logic;
      clk_i   : in std_logic;

      events_i : in  std_logic_vector(g_cnt_pp-1 downto 0);
      irq_o    : out std_logic_vector((g_cnt_pp+g_cnt_pw-1)/g_cnt_pw-1 downto 0);

      ext_adr_i : in  std_logic_vector(f_log2_size((g_cnt_pp+g_cnt_pw-1)/g_cnt_pw)-1 downto 0);
      ext_dat_o : out std_logic_vector(31 downto 0);

      ov_cnt_o    : out std_logic_vector( ((g_cnt_pp+g_cnt_pw-1)/g_cnt_pw)*g_cnt_pw-1 downto 0); --c_evt_range

      dbg_evt_ov_o  : out std_logic;
      clr_flags_i   : in  std_logic);
  end component;

  constant c_adr_mem_sz  : integer := f_log2_size((g_cnt_pp+g_cnt_pw-1)/g_cnt_pw);
  constant c_adr_psel_sz : integer := f_log2_size(g_nports);
  constant c_portirq_sz  : integer := (g_cnt_pp+g_cnt_pw-1)/g_cnt_pw;
  constant c_L2_event_sz : integer := c_portirq_sz*g_cnt_pw;

  constant c_L2_adr_mem_sz : integer := f_log2_size((g_nports*g_cnt_pp+g_L2_cnt_pw-1)/g_L2_cnt_pw);

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

  signal p_dat_out : t_ext_dat_array(g_nports-1 downto 0);

  type   t_rd_st is (IDLE, READ, WRITE);
  signal rd_state : t_rd_st;

  signal irq  : std_logic_vector(g_nports*c_portirq_sz-1 downto 0);
  signal evt_ov : std_logic_vector(g_nports-1 downto 0);
  signal cnt_ov : std_logic_vector(g_nports-1 downto 0);

  type t_L1_ov_cnt is array(natural range <>) of std_logic_vector(c_portirq_sz*g_cnt_pw-1 downto 0);
  signal L1_ov_cnt : t_L1_ov_cnt(g_nports-1 downto 0);

  --Layer 2
  signal L2_events : std_logic_vector(g_nports*c_L2_event_sz-1 downto 0);
  --signal L2_events : std_logic_vector(g_nports*g_cnt_pp-1 downto 0);
  signal L2_adr : std_logic_vector(c_L2_adr_mem_sz-1 downto 0);
  signal L2_dat_out : std_logic_vector(31 downto 0);
  signal L2_rd_val  : std_logic_vector(31 downto 0);

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
  wb_regs_in.l1_cnt_val_i  <= rd_val;
  wb_regs_in.l2_cnt_val_i  <= L2_rd_val;
  rd_port               <= wb_regs_out.cr_port_o(c_adr_psel_sz-1 downto 0);


  -------------------------------------------------------------
  -------------------------------------------------------------
  --  LAYER 1
  -------------------------------------------------------------

  --TODO: change this for 18-port version
  wb_regs_in.dbg_evt_ov_i <= evt_ov(7 downto 0);
  wb_regs_in.dbg_cnt_ov_i <= cnt_ov(7 downto 0);

  GEN_PCNT : for i in 0 to g_nports-1 generate

    PER_PORT_CNT : port_cntr
      generic map(
        g_cnt_pp => g_cnt_pp,
        g_cnt_pw => g_cnt_pw,
        g_keep_ov=> 0)
      port map(
        rst_n_i => rst_n_i,
        clk_i   => clk_i,

        events_i => events_i((i+1)*g_cnt_pp-1 downto i*g_cnt_pp),

        ext_adr_i => wb_regs_out.cr_addr_o(c_adr_mem_sz-1 downto 0),
        ext_dat_i => (others => '0'),
        ext_dat_o => p_dat_out(i),
        ov_cnt_o  => L2_events((i+1)*c_L2_event_sz-1 downto i*c_L2_event_sz), --L1_ov_cnt(i),
        --ov_cnt_o     => L1_ov_cnt(i),
        dbg_evt_ov_o => evt_ov(i),
        clr_flags_i  => wb_regs_out.dbg_clr_o);

      --L2_events((i+1)*g_cnt_pp-1 downto i*g_cnt_pp) <= L1_ov_cnt(i)(g_cnt_pp-1 downto 0);
  end generate;

  -------------------------------------------------------------
  -------------------------------------------------------------
  -- LAYER 2
  -------------------------------------------------------------

  L2_CNT: port_cntr
    generic map(
      g_cnt_pp => g_nports*c_L2_event_sz,
      g_cnt_pw => g_L2_cnt_pw,
      g_keep_ov=> g_keep_ov)
    port map(
      rst_n_i => rst_n_i,
      clk_i   => clk_i,

      events_i => L2_events,

      ext_adr_i => L2_adr,
      ext_dat_i => (others => '0'),
      ext_dat_o => L2_dat_out,
      dbg_evt_ov_o => wb_regs_in.dbg_l2_evt_ov_i,
      clr_flags_i  => wb_regs_out.dbg_l2_clr_o);

  L2_adr <= std_logic_vector(to_unsigned(to_integer(unsigned(rd_port))*c_portirq_sz + 
                        to_integer(unsigned(wb_regs_out.cr_addr_o(c_adr_mem_sz-1 downto 0))),
                        c_L2_adr_mem_sz));

  -------------------------------------------------------------
  -------------------------------------------------------------

  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        rd_state <= IDLE;
        rd_val   <= (others => '0');
        L2_rd_val<= (others => '0');
        rd_en    <= '0';
      else
        case(rd_state) is
          when IDLE =>
            if(wb_regs_out.cr_rd_en_load_o = '1' and wb_regs_out.cr_rd_en_o = '1') then
              rd_en    <= '1';
              rd_state <= READ;
            end if;
          when READ =>
            rd_en                                <= '1';
            rd_state                             <= WRITE;
          when WRITE =>
            rd_val                               <= p_dat_out(to_integer(unsigned(rd_port)));
            rd_en                                <= '0';
            L2_rd_val <= L2_dat_out;
            rd_state                             <= IDLE;
        end case;
      end if;
    end if;
  end process;


end behav;
