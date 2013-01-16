-------------------------------------------------------------------------------
-- Title      : One port statistics counter
-- Project    : White Rabbit Switch
-------------------------------------------------------------------------------
-- File       : port_cntr.vhd
-- Author     : Grzegorz Daniluk
-- Company    : CERN BE-CO-HT
-- Created    : 2012-12-20
-- Last update: 2013-01-16
-- Platform   : FPGA-generic
-- Standard   : VHDL
-------------------------------------------------------------------------------
-- Description: 

-------------------------------------------------------------------------------
-- Copyright (c) 2012 Grzegorz Daniluk
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author          Description
-- 2012-12-20  0.1      greg.d          Created
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.genram_pkg.all;
use work.wishbone_pkg.all;

entity port_cntr is
  generic(
    g_cnt_pp : integer := 64;           --number of counters per port
    g_cnt_pw : integer := 8);           --number of counters per word
  port(
    rst_n_i : in std_logic;
    clk_i   : in std_logic;

    events_i : in std_logic_vector(g_cnt_pp-1 downto 0);

    --memory interface
    ext_cyc_i : in  std_logic                                                                := '0';
    ext_adr_i : in  std_logic_vector(f_log2_size((g_cnt_pp+g_cnt_pw-1)/g_cnt_pw)-1 downto 0) := (others => '0');
    ext_we_i  : in  std_logic                                                                := '0';
    ext_dat_i : in  std_logic_vector(31 downto 0)                                            := (others => '0');
    ext_dat_o : out std_logic_vector(31 downto 0)
  );
end port_cntr;

architecture behav of port_cntr is

  constant c_rr_range   : integer := (g_cnt_pp+g_cnt_pw-1)/g_cnt_pw;
  constant c_evt_range  : integer := c_rr_range*g_cnt_pw;
  constant c_cnt_width  : integer := c_wishbone_data_width/g_cnt_pw;
  constant c_mem_adr_sz : integer := f_log2_size(c_rr_range);

  type   t_cnt_st is (SEL, WRITE);
  signal cnt_state : t_cnt_st;

  signal mem_dat_in  : std_logic_vector(31 downto 0);
  signal mem_dat_out : std_logic_vector(31 downto 0);
  signal mem_adr     : integer range 0 to c_rr_range-1;
  signal mem_adr_lv  : std_logic_vector(c_mem_adr_sz-1 downto 0);
  signal mem_wr      : std_logic;

  signal events_reg : std_logic_vector(c_evt_range-1 downto 0);
  signal events_clr : std_logic_vector(c_evt_range-1 downto 0);
  signal events_sub : std_logic_vector(g_cnt_pw-1 downto 0);

  signal rr_select    : integer range 0 to c_rr_range-1 := 0;
  signal evt_overflow : std_logic;
  signal wr_conflict  : std_logic;

  function evt_sel(i, rr_select : integer) return integer is
    variable sel : integer range 0 to (g_cnt_pp+g_cnt_pw-1)/g_cnt_pw-1;  --c_rr_range-1;
  begin
    if(i+rr_select > (g_cnt_pp+g_cnt_pw-1)/g_cnt_pw-1) then   --c_rr_range-1
      sel := i+rr_select - ((g_cnt_pp+g_cnt_pw-1)/g_cnt_pw);  --c_rr_range
    else
      sel := i+rr_select;
    end if;
    return sel;
  end function;

  function evt_subset(events : std_logic_vector; i, rr_select : integer) return std_logic_vector is
    variable sel : integer range 0 to (g_cnt_pp+g_cnt_pw-1)/g_cnt_pw-1;  --c_rr_range-1;
  begin
    sel := evt_sel(i, rr_select);
    return events((sel+1)*g_cnt_pw-1 downto sel*g_cnt_pw);
  end function;

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
      wea_i  => '0', --ext_we_i,
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

  --store events into temp register, and clear those already counted
  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        events_reg   <= (others => '0');
        evt_overflow <= '0';
      else
        --clear counted events and store new events to be counted
        events_reg(g_cnt_pp-1 downto 0) <= (events_reg(g_cnt_pp-1 downto 0) xor
          events_clr(g_cnt_pp-1 downto 0)) or events_i(g_cnt_pp-1 downto 0);

        if(to_integer(unsigned((events_reg(g_cnt_pp-1 downto 0) xor events_clr(g_cnt_pp-1 downto 0))
          and events_i(g_cnt_pp-1 downto 0))) /= 0) then
            evt_overflow <= '1';
        end if;
      end if;
    end if;
  end process;

  process(clk_i)
    variable i : integer range 0 to c_rr_range-1 := 0;
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        events_clr(g_cnt_pp-1 downto 0) <= (others => '0');
        rr_select                       <= 0;
        cnt_state                       <= SEL;
        mem_adr                         <= 0;
        mem_wr                          <= '0';
        events_sub                      <= (others => '0');
        wr_conflict                     <= '0';
      else

        case(cnt_state) is
          when SEL =>
            --check each segment of events_i starting from the one pointed by round robin
            events_clr <= (others => '0');
            mem_wr     <= '0';
            wr_conflict <= '0';
            for i in 0 to c_rr_range-1 loop
              if(to_integer(unsigned(evt_subset(events_reg, i, rr_select))) /= 0) then
                mem_adr     <= evt_sel(i, rr_select);
                cnt_state   <= WRITE;
                events_sub  <= events_reg((evt_sel(i, rr_select)+1)*g_cnt_pw-1 downto evt_sel(i, rr_select)*g_cnt_pw);
                events_clr((evt_sel(i, rr_select)+1)*g_cnt_pw-1 downto evt_sel(i, rr_select)*g_cnt_pw) <=
                  events_reg((evt_sel(i, rr_select)+1)*g_cnt_pw-1 downto evt_sel(i, rr_select)*g_cnt_pw);  --events_sub
                exit;
              end if;
            end loop;
            --update round-robin
            if(rr_select = c_rr_range-1) then
              rr_select <= 0;
            else
              rr_select <= rr_select + 1;
            end if;

          when WRITE =>
            events_clr <= (others => '0');
            if(std_logic_vector(to_unsigned(mem_adr, c_mem_adr_sz)) = ext_adr_i and ext_cyc_i = '1' and ext_we_i = '0') then
              mem_wr    <= '0';
              cnt_state <= WRITE;
              wr_conflict <= '0'; --'1';
            else
              mem_wr    <= '1';
              cnt_state <= SEL;
            end if;
        end case;


      end if;
    end if;
  end process;

  GEN_INCR : for i in 0 to g_cnt_pw-1 generate
    mem_dat_in((i+1)*c_cnt_width-1 downto i*c_cnt_width) <= --if processor has accessed counter, it has cleared it for sure
                                                            std_logic_vector(to_unsigned(1, c_cnt_width)) when(wr_conflict='1' and events_sub(i)='1') else    
                                                            --if processor has accessed counter,but there is no event for it, just write there '0', since mem_dat_out still holds old value
                                                            std_logic_vector(to_unsigned(0, c_cnt_width)) when(wr_conflict='1' and events_sub(i)='0') else
                                                            --otherwise, normal situation, just increment
                                                            std_logic_vector(unsigned(mem_dat_out((i+1)*c_cnt_width-1 downto i*c_cnt_width)) + 1) when events_sub(i)='1' else
                                                            --no change
                                                            mem_dat_out((i+1)*c_cnt_width-1 downto i*c_cnt_width);
  end generate;

end behav;
