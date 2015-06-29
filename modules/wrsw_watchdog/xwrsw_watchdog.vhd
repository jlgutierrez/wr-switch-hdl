library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.wr_fabric_pkg.all;

entity xwrsw_watchdog is
  generic(
    g_num_ports : integer := 18);
  port(
    rst_n_i : in  std_logic;
    clk_i   : in  std_logic;
    
    force_rst_i : in  std_logic;
    swc_nomem_i : in  std_logic;
    -- statistics to be exported by HWIU
    restart_cnt_o  : out std_logic_vector(31 downto 0);

    swcrst_n_o  : out std_logic;
    epstop_o    : out std_logic;

    rtu_ack_i   : in  std_logic_vector(g_num_ports-1 downto 0);
    rtu_ack_o   : out std_logic_vector(g_num_ports-1 downto 0);

    snk_i       : in  t_wrf_sink_in_array(g_num_ports-1 downto 0);
    snk_o       : out t_wrf_sink_out_array(g_num_ports-1 downto 0);
    src_o       : out t_wrf_source_out_array(g_num_ports-1 downto 0);
    src_i       : in  t_wrf_source_in_array(g_num_ports-1 downto 0));
end xwrsw_watchdog;

architecture behav of xwrsw_watchdog is
  constant c_RST_TIME    : integer := 128;
  constant c_SWCRST_TIME : integer := 8;
  constant c_NOMEM_THR   : integer := 10000; --62500000;

  signal nomem_cnt  : unsigned(25 downto 0);
  signal nomem_trig : std_logic;
  signal rst_cnt  : unsigned(7 downto 0);
  signal watchdog_cnt  : unsigned(31 downto 0);
  signal rst_trig : std_logic;
  signal rst_trig_d0 : std_logic;
  signal reset_mode : std_logic;
begin

  -- Hanging detection
  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i='0' or swc_nomem_i='0') then
        nomem_cnt   <= (others=>'0');
        nomem_trig  <= '0';
      elsif(swc_nomem_i='1' and nomem_cnt<c_NOMEM_THR) then
        nomem_trig <= '0';
        nomem_cnt <= nomem_cnt + 1;
      elsif(nomem_cnt = c_NOMEM_THR) then
        nomem_trig <= '1';
        nomem_cnt  <= (others=>'0');
      end if;
    end if;
  end process;

  rst_trig <= force_rst_i or nomem_trig;

  -- Resetting SwCore and Endpoints
  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if (rst_n_i = '0') then
        rst_cnt    <= (others=>'0');
        watchdog_cnt <= (others=>'0');
        rst_trig_d0   <= '0';
        reset_mode <= '0';
      else
        rst_trig_d0 <= rst_trig;
        if(rst_trig='1' and rst_trig_d0='0') then
          reset_mode <= '1';
          watchdog_cnt <= watchdog_cnt + 1;
        end if;

        if(reset_mode='1') then
          rst_cnt <= rst_cnt + 1;
          if(rst_cnt = c_RST_TIME) then
            reset_mode <= '0';
            rst_cnt <= (others=>'0');
          end if;
        end if;
      end if;
    end if;
  end process;
  restart_cnt_o <= std_logic_vector(watchdog_cnt);

  -- switching core we reset only for one clk cycle
  swcrst_n_o <= '0' when(reset_mode='1' and rst_cnt < c_SWCRST_TIME) else
                rst_n_i;

  -- the rest we keep longer in reset so that SWCore has time to initialize
  epstop_o <= '1' when (reset_mode = '1') else
              '0';

  rtu_ack_o <= (others=>'1') when (reset_mode = '1') else
               rtu_ack_i;

  GEN_FABTIC_RST: for I in 0 to g_num_ports-1 generate
    snk_o(I).stall <= '0' when (reset_mode='1') else
                      src_i(I).stall;
    snk_o(I).ack   <= '1' when (reset_mode='1') else
                      src_i(I).ack;
    snk_o(I).err   <= src_i(I).err;
    snk_o(I).rty   <= src_i(I).rty;

    src_o(I).cyc   <= '0' when (reset_mode='1') else
                      snk_i(I).cyc;
    src_o(I).stb   <= '0' when (reset_mode='1') else
                      snk_i(I).stb;
    src_o(I).we    <= snk_i(I).we;
    src_o(I).sel   <= snk_i(I).sel;
    src_o(I).adr   <= snk_i(I).adr;
    src_o(I).dat   <= snk_i(I).dat;
  end generate;



end behav;
