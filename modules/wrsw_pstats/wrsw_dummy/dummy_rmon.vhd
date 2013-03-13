library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.dummy_wbgen2_pkg.all;
use work.wishbone_pkg.all;

entity dummy_rmon is
  generic(
    g_interface_mode      : t_wishbone_interface_mode      := PIPELINED;
    g_address_granularity : t_wishbone_address_granularity := BYTE;
    g_nports  : integer := 8;
    g_cnt_pp  : integer := 2);
  port(
    rst_n_i : in std_logic;
    clk_i   : in std_logic;
    events_i  : in std_logic_vector(g_nports*g_cnt_pp-1 downto 0);

    wb_i : in  t_wishbone_slave_in;
    wb_o : out t_wishbone_slave_out);
end dummy_rmon;

architecture behav of dummy_rmon is

  component dummy_wishbone_slave
    port (
      rst_n_i                                  : in     std_logic;
      clk_sys_i                                : in     std_logic;
      wb_adr_i                                 : in     std_logic_vector(4 downto 0);
      wb_dat_i                                 : in     std_logic_vector(31 downto 0);
      wb_dat_o                                 : out    std_logic_vector(31 downto 0);
      wb_cyc_i                                 : in     std_logic;
      wb_sel_i                                 : in     std_logic_vector(3 downto 0);
      wb_stb_i                                 : in     std_logic;
      wb_we_i                                  : in     std_logic;
      wb_ack_o                                 : out    std_logic;
      wb_stall_o                               : out    std_logic;
      regs_i                                   : in     t_dummy_in_registers;
      regs_o                                   : out    t_dummy_out_registers
    );
  end component;

  signal wb_in  : t_wishbone_slave_in;
  signal wb_out : t_wishbone_slave_out;
  signal wb_regs_in : t_dummy_in_registers;
  signal wb_regs_out : t_dummy_out_registers;

  type t_rmon_reg is array(natural range <>) of std_logic_vector(31 downto 0);
  signal regs : t_rmon_reg(g_nports*g_cnt_pp-1 downto 0);


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

  U_WB_if: dummy_wishbone_slave
    port map(
      rst_n_i    => rst_n_i,
      clk_sys_i  => clk_i,
      wb_adr_i   => wb_in.adr(4 downto 0),
      wb_dat_i   => wb_in.dat,
      wb_dat_o   => wb_out.dat,
      wb_cyc_i   => wb_in.cyc,
      wb_sel_i   => wb_in.sel,
      wb_stb_i   => wb_in.stb,
      wb_we_i    => wb_in.we,
      wb_ack_o   => wb_out.ack,
      wb_stall_o => wb_out.stall,
      regs_i     => wb_regs_in,
      regs_o     => wb_regs_out
    );

  wb_regs_in.p0_tx_i <= regs(0);
  wb_regs_in.p0_rx_i <= regs(1);
  wb_regs_in.p1_tx_i <= regs(2);
  wb_regs_in.p1_rx_i <= regs(3);
  wb_regs_in.p2_tx_i <= regs(4);
  wb_regs_in.p2_rx_i <= regs(5);
  wb_regs_in.p3_tx_i <= regs(6);
  wb_regs_in.p3_rx_i <= regs(7);
  wb_regs_in.p4_tx_i <= regs(8);
  wb_regs_in.p4_rx_i <= regs(9);
  wb_regs_in.p5_tx_i <= regs(10);
  wb_regs_in.p5_rx_i <= regs(11);
  wb_regs_in.p6_tx_i <= regs(12);
  wb_regs_in.p6_rx_i <= regs(13);
  wb_regs_in.p7_tx_i <= regs(14);
  wb_regs_in.p7_rx_i <= regs(15);

  GEN_REGS: for i in 0 to g_nports*g_cnt_pp-1 generate
    process(clk_i)
    begin
      if rising_edge(clk_i) then
        if(rst_n_i='0' or wb_regs_out.cr_rst_o='1') then
          regs(i) <= (others=>'0');
        elsif(events_i(i) = '1') then
          regs(i) <= std_logic_vector(unsigned(regs(i)) + 1);
        end if;
      end if;
    end process;
  end generate;
end behav;
