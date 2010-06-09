
library ieee;
use ieee.std_logic_1164.all;

library altera_mf;
use altera_mf.all;

entity generic_ssram_dualport is
  generic (
    g_width     : natural := 8;
    g_addr_bits : natural := 10;
    g_size      : natural := 1024);
  port
    (
      data_i    : in  std_logic_vector (g_width-1 downto 0);
      rd_addr_i : in  std_logic_vector (g_addr_bits-1 downto 0);
      rd_clk_i  : in  std_logic;
      wr_addr_i : in  std_logic_vector (g_addr_bits-1 downto 0);
      wr_clk_i  : in  std_logic;
      wr_en_i   : in  std_logic := '1';
      q_o       : out std_logic_vector (g_width-1 downto 0)
      );
end generic_ssram_dualport;


architecture SYN of generic_ssram_dualport is

  signal sub_wire0 : std_logic_vector (g_width-1 downto 0);


  component altsyncram
    generic (
      address_aclr_b         : string;
      address_reg_b          : string;
      clock_enable_input_a   : string;
      clock_enable_input_b   : string;
      clock_enable_output_b  : string;
      intended_device_family : string;
      lpm_type               : string;
      numwords_a             : natural;
      numwords_b             : natural;
      operation_mode         : string;
      outdata_aclr_b         : string;
      outdata_reg_b          : string;
      power_up_uninitialized : string;
      widthad_a              : natural;
      widthad_b              : natural;
      width_a                : natural;
      width_b                : natural;
      width_byteena_a        : natural
      );
    port (
      wren_a    : in  std_logic;
      clock0    : in  std_logic;
      clock1    : in  std_logic;
      address_a : in  std_logic_vector (g_addr_bits-1 downto 0);
      address_b : in  std_logic_vector (g_addr_bits-1 downto 0);
      q_b       : out std_logic_vector (g_width-1 downto 0);
      data_a    : in  std_logic_vector (g_width-1 downto 0)
      );
  end component;

begin
  q_o <= sub_wire0(g_width-1 downto 0);

  altsyncram_component : altsyncram
    generic map (
      address_aclr_b         => "NONE",
      address_reg_b          => "CLOCK1",
      clock_enable_input_a   => "BYPASS",
      clock_enable_input_b   => "BYPASS",
      clock_enable_output_b  => "BYPASS",
      intended_device_family => "Cyclone III",
      lpm_type               => "altsyncram",
      numwords_a             => g_size,
      numwords_b             => g_size,
      operation_mode         => "DUAL_PORT",
      outdata_aclr_b         => "NONE",
      outdata_reg_b          => "CLOCK1",
      power_up_uninitialized => "FALSE",
      widthad_a              => g_addr_bits,
      widthad_b              => g_addr_bits,
      width_a                => g_width,
      width_b                => g_width,
      width_byteena_a        => 1
      )
    port map (
      wren_a    => wr_en_i,
      clock0    => wr_clk_i,
      clock1    => rd_clk_i,
      address_a => wr_addr_i,
      address_b => rd_addr_i,
      data_a    => data_i,
      q_b       => sub_wire0
      );



end SYN;

