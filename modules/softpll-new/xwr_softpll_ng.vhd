library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.gencores_pkg.all;
use work.wishbone_pkg.all;

entity xwr_softpll_ng is
  generic(
    g_tag_bits                 : integer;
    g_interface_mode           : t_wishbone_interface_mode      := CLASSIC;
    g_address_granularity      : t_wishbone_address_granularity := WORD;
    g_num_ref_inputs           : integer;
    g_num_outputs              : integer;
    g_period_detector_ref_mask : std_logic_vector(31 downto 0)  := x"ffffffff"
    );

  port(
    clk_sys_i : in std_logic;
    rst_n_i   : in std_logic;


-- Reference inputs (i.e. the RX clocks recovered by the PHYs)
    clk_ref_i  : in std_logic_vector(g_num_ref_inputs-1 downto 0);
-- Feedback clocks (i.e. the outputs of the main or aux oscillator)
    clk_fb_i   : in std_logic_vector(g_num_outputs-1 downto 0);
-- DMTD Offset clock
    clk_dmtd_i : in std_logic;

-- DMTD oscillator drive
    dac_dmtd_data_o : out std_logic_vector(15 downto 0);
    dac_dmtd_load_o : out std_logic;

-- Output channel DAC value
    dac_out_data_o : out std_logic_vector(15 downto 0);
-- Output channel select (0 = channel 0, etc. )
    dac_out_sel_o  : out std_logic_vector(3 downto 0);
    dac_out_load_o : out std_logic;

    out_enable_i : in  std_logic_vector(g_num_outputs-1 downto 0);
    out_locked_o : out std_logic_vector(g_num_outputs-1 downto 0);

    slave_i : in  t_wishbone_slave_in;
    slave_o : out t_wishbone_slave_out;

    debug_o : out std_logic_vector(3 downto 0)
    );

end xwr_softpll_ng;

architecture wrapper of xwr_softpll_ng is
  component wr_softpll_ng
    generic (
      g_tag_bits                 : integer;
      g_interface_mode           : t_wishbone_interface_mode;
      g_address_granularity      : t_wishbone_address_granularity;
      g_num_ref_inputs           : integer;
      g_num_outputs              : integer--;
--      g_period_detector_ref_mask : std_logic_vector(31 downto 0) := x"ffffffff"
      );
    port (
      clk_sys_i       : in  std_logic;
      rst_n_i         : in  std_logic;
      clk_ref_i       : in  std_logic_vector(g_num_ref_inputs-1 downto 0);
      clk_fb_i        : in  std_logic_vector(g_num_outputs-1 downto 0);
      clk_dmtd_i      : in  std_logic;
      dac_dmtd_data_o : out std_logic_vector(15 downto 0);
      dac_dmtd_load_o : out std_logic;
      dac_out_data_o  : out std_logic_vector(15 downto 0);
      dac_out_sel_o   : out std_logic_vector(3 downto 0);
      dac_out_load_o  : out std_logic;
      out_enable_i    : in  std_logic_vector(g_num_outputs-1 downto 0);
      out_locked_o    : out std_logic_vector(g_num_outputs-1 downto 0);
      wb_adr_i        : in  std_logic_vector(6 downto 0);
      wb_dat_i        : in  std_logic_vector(31 downto 0);
      wb_dat_o        : out std_logic_vector(31 downto 0);
      wb_cyc_i        : in  std_logic;
      wb_sel_i        : in  std_logic_vector(3 downto 0);
      wb_stb_i        : in  std_logic;
      wb_we_i         : in  std_logic;
      wb_ack_o        : out std_logic;
      wb_stall_o      : out std_logic;
      wb_irq_o        : out std_logic;
      debug_o         : out std_logic_vector(3 downto 0));
  end component;
  
begin  -- behavioral

  U_Wrapped_Softpll : wr_softpll_ng
    generic map (
      g_tag_bits            => g_tag_bits,
      g_interface_mode      => g_interface_mode,
      g_address_granularity => g_address_granularity,
      g_num_ref_inputs      => g_num_ref_inputs,
      g_num_outputs         => g_num_outputs)
--      g_period_detector_ref_mask => g_period_detector_ref_mask)
    port map (
      clk_sys_i       => clk_sys_i,
      rst_n_i         => rst_n_i,
      clk_ref_i       => clk_ref_i,
      clk_fb_i        => clk_fb_i,
      clk_dmtd_i      => clk_dmtd_i,
      dac_dmtd_data_o => dac_dmtd_data_o,
      dac_dmtd_load_o => dac_dmtd_load_o,
      dac_out_data_o  => dac_out_data_o,
      dac_out_sel_o   => dac_out_sel_o,
      dac_out_load_o  => dac_out_load_o,
      out_enable_i    => out_enable_i,
      out_locked_o    => out_locked_o,
      wb_adr_i        => slave_i.adr(6 downto 0),
      wb_dat_i        => slave_i.dat,
      wb_dat_o        => slave_o.dat,
      wb_cyc_i        => slave_i.cyc,
      wb_sel_i        => slave_i.sel,
      wb_stb_i        => slave_i.stb,
      wb_we_i         => slave_i.we,
      wb_ack_o        => slave_o.ack,
      wb_stall_o      => slave_o.stall,
      wb_irq_o        => slave_o.int,
      debug_o         => debug_o);

end wrapper;
