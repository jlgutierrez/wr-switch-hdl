-------------------------------------------------------------------------------
-- Title      : IRQ RAM for Per-port statistics counters
-- Project    : White Rabbit Switch
-------------------------------------------------------------------------------
-- File       : irq_ram.vhd
-- Author     : Grzegorz Daniluk
-- Company    : CERN BE-CO-HT
-- Created    : 2013-02-27
-- Last update: 2013-07-24
-- Platform   : FPGA-generic
-- Standard   : VHDL
-------------------------------------------------------------------------------
-- Description:
-- Module stores irq flags from each counter of each port of WR Switch. Its
-- structure is simplified design of port_cntr module. IRQ flags are stored in
-- Block-RAM. Each 32-bit memory word can store up to 32 irq flags. IRQ events
-- comming from each port are first aligned so that each port's flags start
-- from a new word in memory to simplify reading FSM in top module.
-------------------------------------------------------------------------------
-- Copyright (c) 2013 Grzegorz Daniluk / CERN
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author          Description
-- 2013-02-27  0.1      greg.d          Created
-- 2013-07-24  0.2      greg.d          Optimized to save FPGA resources
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_misc.all;
use ieee.numeric_std.all;

library work;
use work.genram_pkg.all;
use work.wishbone_pkg.all;
use work.gencores_pkg.all;

entity irq_ram is
  generic(
    g_nports : integer := 8;
    g_cnt_pp : integer := 64;           --number of counters per port
    g_cnt_pw : integer := 32);          --number of counters per word
  port(
    rst_n_i : in std_logic;
    clk_i   : in std_logic;

    irq_i : in std_logic_vector(g_nports*g_cnt_pp-1 downto 0);

    --memory interface
    ext_cyc_i : in  std_logic  := '0';
    ext_adr_i : in  std_logic_vector(f_log2_size(g_nports*((g_cnt_pp+g_cnt_pw-1)/g_cnt_pw))-1 downto 0) := (others => '0');
    ext_we_i  : in  std_logic  := '0';
    ext_dat_i : in  std_logic_vector(31 downto 0) := (others => '0');
    ext_dat_o : out std_logic_vector(31 downto 0)

    --debug
    --dbg_evt_ov_o : out std_logic;
    --clr_flags_i  : in  std_logic := '0'
  );
end irq_ram;

architecture behav of irq_ram is

  constant c_rr_range     : integer := g_nports*((g_cnt_pp+g_cnt_pw-1)/g_cnt_pw);
  constant c_evt_range    : integer := c_rr_range*g_cnt_pw;
  constant c_mem_adr_sz   : integer := f_log2_size(c_rr_range);
  constant c_evt_align_sz : integer := ((g_cnt_pp+g_cnt_pw-1)/g_cnt_pw)*g_cnt_pw;

  type   t_cnt_st is (SEL, WRITE);
  signal cnt_state : t_cnt_st;

  signal mem_dat_in  : std_logic_vector(31 downto 0);
  signal mem_dat_out : std_logic_vector(31 downto 0);
  signal mem_adr     : integer range 0 to c_rr_range-1;
  signal mem_adr_d1  : integer range 0 to c_rr_range-1;
  signal mem_adr_lv  : std_logic_vector(c_mem_adr_sz-1 downto 0);
  signal mem_wr      : std_logic;

  signal events_reg     : std_logic_vector(c_evt_range-1 downto 0);
  signal events_aligned : std_logic_vector(c_evt_range-1 downto 0);
  signal events_clr     : std_logic_vector(c_evt_range-1 downto 0);
  signal events_sub     : std_logic_vector(g_cnt_pw-1 downto 0);
  signal events_ored    : std_logic_vector(c_rr_range-1 downto 0);
  signal events_preg    : std_logic_vector(c_rr_range-1 downto 0);
  signal events_grant   : std_logic_vector(c_rr_range-1 downto 0);
  signal events_presub  : std_logic_vector(g_cnt_pw-1 downto 0);

  signal wr_conflict : std_logic;

  function f_onehot_decode
    (x : std_logic_vector) return integer is
  begin
    for i in 0 to x'length-1 loop
      if(x(i) = '1') then
        return i;
      end if;
    end loop;
    return 0;
  end f_onehot_decode;

begin

  RAM_A1 : generic_dpram
    generic map(
      g_data_width               => 32,
      g_size                     => c_rr_range,
      g_with_byte_enable         => false,
      g_addr_conflict_resolution => "read_first",
      g_dual_clock               => false)   
    port map(
      rst_n_i => rst_n_i,

      clka_i => clk_i,
      bwea_i => (others => '1'),
      wea_i  => ext_we_i,
      aa_i   => ext_adr_i,
      da_i   => ext_dat_i,
      qa_o   => ext_dat_o,

      clkb_i => clk_i,
      bweb_i => (others => '1'),
      web_i  => mem_wr,
      ab_i   => mem_adr_lv,
      db_i   => mem_dat_in,
      qb_o   => mem_dat_out);

  mem_adr_lv <= std_logic_vector(to_unsigned(mem_adr, c_mem_adr_sz));


  --align events to 32-bit words
  GEN_ALIGN : for i in 0 to g_nports-1 generate
    events_aligned(i*c_evt_align_sz+g_cnt_pp-1 downto i*c_evt_align_sz) <=
      irq_i((i+1)*g_cnt_pp-1 downto i*g_cnt_pp);
    --zero padding for word aligning
    events_aligned((i+1)*c_evt_align_sz-1 downto i*c_evt_align_sz+g_cnt_pp) <= (others => '0');
  end generate;

  --store events into temp register, and clear those already counted
  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        events_reg   <= (others => '0');
        --dbg_evt_ov_o <= '0';
      else
        --clear counted events and store new events to be counted
        events_reg <= (events_reg xor events_clr) or events_aligned;

        --if(to_integer(unsigned((events_reg(g_cnt_pp-1 downto 0) xor events_clr(g_cnt_pp-1 downto 0))
        --  and events_aligned(g_cnt_pp-1 downto 0))) /= 0) then
        --    dbg_evt_ov_o <= '1';
        --end if;

        --if(clr_flags_i = '1') then
        --  dbg_evt_ov_o <= '0';
        --end if;
      end if;
    end if;
  end process;


  GEN_EVT_ORED : for i in 0 to c_rr_range-1 generate
    events_ored(i) <= or_reduce(events_reg((i+1)*g_cnt_pw-1 downto i*g_cnt_pw));
  end generate;

  events_presub <= events_reg((f_onehot_decode(events_grant)+1)*g_cnt_pw-1 downto f_onehot_decode(events_grant)*g_cnt_pw);

	GEN_EVT_CLR: for i in 0 to c_rr_range-1 generate
		events_clr((i+1)*g_cnt_pw-1 downto i*g_cnt_pw) <= events_presub when(cnt_state=WRITE and events_grant(i)='1') else
																											(others=>'0');
	end generate;

  mem_adr <= f_onehot_decode(events_grant);

  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        cnt_state   <= SEL;
        mem_wr      <= '0';
        events_sub  <= (others => '0');
        events_preg <= (others => '0');
        wr_conflict <= '0';
      else

        case(cnt_state) is
          when SEL =>
            --check each segment of events_i starting from the one pointed by round robin
            mem_wr      <= '0';
            wr_conflict <= '0';

            f_rr_arbitrate(events_ored, events_preg, events_grant);
            if(or_reduce(events_ored) = '1') then
              events_preg   <= events_grant;

              if(f_onehot_decode(events_grant) = to_integer(unsigned(ext_adr_i)) and ext_cyc_i = '1' and ext_we_i = '0') then
                wr_conflict <= '1';
              end if;
              cnt_state <= WRITE;
            end if;

          when WRITE =>
            events_sub    <= events_presub;
            if(std_logic_vector(to_unsigned(mem_adr, c_mem_adr_sz)) = ext_adr_i and ext_cyc_i = '1' and ext_we_i = '0') then
              mem_wr      <= '0';
              cnt_state   <= WRITE;
              wr_conflict <= '1';
            else
              mem_wr    <= '1';
              cnt_state <= SEL;
            end if;
        end case;
      end if;
    end if;
  end process;

  mem_dat_in <= mem_dat_out or events_sub;


end behav;
