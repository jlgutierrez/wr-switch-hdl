library ieee;
use ieee.std_logic_1164.all;

use work.wishbone_pkg.all;

entity xwrsw_pstats is
  generic(
    g_interface_mode      : t_wishbone_interface_mode      := PIPELINED;
    g_address_granularity : t_wishbone_address_granularity := BYTE;
    g_nports              : integer                        := 2;
    g_cnt_pp              : integer                        := 16;
    g_cnt_pw              : integer                        := 4);
  port(
    rst_n_i : in std_logic;
    clk_i   : in std_logic;

    events_i : in std_logic_vector(g_nports*g_cnt_pp-1 downto 0);

    wb_i : in  t_wishbone_slave_in;
    wb_o : out t_wishbone_slave_out);
end xwrsw_pstats;

architecture wrapper of xwrsw_pstats is

  component wrsw_pstats
    generic(
      g_nports : integer := 2;
      g_cnt_pp : integer := 16;
      g_cnt_pw : integer := 4);
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
  end component;


  signal wb_in  : t_wishbone_slave_in;
  signal wb_out : t_wishbone_slave_out;

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
      slave_i   => wb_i,
      slave_o   => wb_o,
      master_i  => wb_out,
      master_o  => wb_in);

  wb_out.err <= '0';
  wb_out.rty <= '0';

  U_Wrapped_PSTATS : wrsw_pstats
    generic map(
      g_nports => g_nports,
      g_cnt_pp => g_cnt_pp,
      g_cnt_pw => g_cnt_pw)
    port map(
      rst_n_i => rst_n_i,
      clk_i   => clk_i,

      events_i => events_i,

      wb_adr_i   => wb_in.adr(2 downto 0),
      wb_dat_i   => wb_in.dat,
      wb_dat_o   => wb_out.dat,
      wb_cyc_i   => wb_in.cyc,
      wb_sel_i   => wb_in.sel,
      wb_stb_i   => wb_in.stb,
      wb_we_i    => wb_in.we,
      wb_ack_o   => wb_out.ack,
      wb_stall_o => wb_out.stall);

end wrapper;
