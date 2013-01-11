-------------------------------------------------------------------------------
-- Title      : 
-- Project    : White Rabbit Switch
-------------------------------------------------------------------------------
-- File       : wrsw_rmon.vhd
-- Author     : Grzegorz Daniluk
-- Company    : CERN BE-Co-HT
-- Created    : 2012-12-20
-- Last update: 2013-01-11
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

entity wrsw_rmon is
  generic(
    g_cnt_pp : integer := 64;           --number of counters per port
    g_cnt_pw : integer := 8);           --number of counters per word
  port(
    rst_n_i : in std_logic;
    clk_i   : in std_logic;

    events_i : in  std_logic_vector(g_cnt_pp-1 downto 0);
    wb_i     : in  t_wishbone_slave_in := cc_dummy_slave_in;
    wb_o     : out t_wishbone_slave_out
  );
end wrsw_rmon;

architecture behav of wrsw_rmon is

  constant c_rr_range   : integer := (g_cnt_pp+g_cnt_pw-1)/g_cnt_pw;
  constant c_evt_range  : integer := c_rr_range*g_cnt_pw;
  constant c_cnt_width  : integer := c_wishbone_data_width/g_cnt_pw;
  constant c_mem_adr_sz : integer := f_log2_size(g_cnt_pp/g_cnt_pw);

  type   t_cnt_st is (SEL, WRITE);
  signal cnt_state  : t_cnt_st;
  signal real_state : t_cnt_st;

  signal mem_wb_in   : t_wishbone_slave_in;
  signal mem_wb_out  : t_wishbone_slave_out;
  signal mem_dat_in  : std_logic_vector(31 downto 0);
  signal mem_dat_out : std_logic_vector(31 downto 0);
  signal mem_adr     : integer range 0 to c_rr_range-1;
  signal mem_wr      : std_logic;

  signal events_reg : std_logic_vector(c_evt_range-1 downto 0);
  signal events_clr : std_logic_vector(c_evt_range-1 downto 0);
  signal events_sub : std_logic_vector(g_cnt_pw-1 downto 0);

  signal rr_select    : integer range 0 to c_rr_range-1 := 0;
  signal evt_overflow : std_logic;

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

  RAM_A1 : xwb_dpram
    generic map(
      g_size                  => (g_cnt_pp + g_cnt_pw-1)/g_cnt_pw,
      g_must_have_init_file   => false,
      g_slave1_interface_mode => PIPELINED,
      g_slave2_interface_mode => PIPELINED,
      g_slave1_granularity    => WORD,
      g_slave2_granularity    => WORD)
    port map(
      clk_sys_i => clk_i,
      rst_n_i   => rst_n_i,

      slave1_i => wb_i,
      slave1_o => wb_o,
      slave2_i => mem_wb_in,
      slave2_o => mem_wb_out);

  mem_wb_in.cyc                          <= '1';
  mem_wb_in.stb                          <= '1';
  mem_wb_in.adr(c_mem_adr_sz-1 downto 0) <= std_logic_vector(to_unsigned(mem_adr, c_mem_adr_sz));
  mem_wb_in.sel                          <= "1111";
  mem_wb_in.we                           <= mem_wr;
  mem_wb_in.dat                          <= mem_dat_in;
  mem_dat_out                            <= mem_wb_out.dat;

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
      else

        
        case(cnt_state) is
          when SEL =>
            real_state <= SEL;
            --check each segment of events_i starting from the one pointed by round robin
            events_clr <= (others => '0');
            --events_sub <= (others=>'0');
            mem_wr     <= '0';
            for i in 0 to c_rr_range-1 loop
              --report "SEL " & integer'image(i) & " " & integer'image(rr_select);
              if(to_integer(unsigned(evt_subset(events_reg, i, rr_select))) /= 0) then
                mem_adr         <= evt_sel(i, rr_select);
                cnt_state       <= WRITE;
                events_sub      <= events_reg((evt_sel(i, rr_select)+1)*g_cnt_pw-1 downto evt_sel(i, rr_select)*g_cnt_pw);
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
            real_state <= WRITE;
            mem_wr     <= '1';
            events_clr <= (others => '0');
            cnt_state  <= SEL;
        end case;


      end if;
    end if;
  end process;

  GEN_INCR : for i in 0 to g_cnt_pw-1 generate
    mem_dat_in((i+1)*c_cnt_width-1 downto i*c_cnt_width) <= std_logic_vector(unsigned(mem_dat_out((i+1)*c_cnt_width-1 downto i*c_cnt_width)) + 1) when events_sub(i) = '1' else
                                        mem_dat_out((i+1)*c_cnt_width-1 downto i*c_cnt_width);
  end generate;

end behav;
