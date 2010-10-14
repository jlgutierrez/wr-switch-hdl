library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library lpm;
use lpm.all;

-------------------------------------------------------------------------------

package platform_specific is

  -----------------------------------------------------------------------------
  -- Component declarations
  -----------------------------------------------------------------------------
  component generic_async_fifo_2stage
    generic (
      g_width                    : natural;
      g_depth                    : natural;
      g_almostfull_bit_threshold : natural);
    port (
      clear_i       : in  std_logic := '0';
      d_i           : in  std_logic_vector (g_width-1 downto 0);
      rd_clk_i      : in  std_logic;
      rd_req_i      : in  std_logic;
      wr_clk_i      : in  std_logic;
      wr_req_i      : in  std_logic;
      q_o           : out std_logic_vector (g_width-1 downto 0);
      rd_empty_o    : out std_logic;
      wr_full_o     : out std_logic;
      almost_full_o : out std_logic);
  end component;

  component generic_ssram_dualport
    generic (
      g_width     : natural;
      g_addr_bits : natural;
      g_size      : natural);
    port (
      data_i    : in  std_logic_vector (g_width-1 downto 0);
      rd_addr_i : in  std_logic_vector (g_addr_bits-1 downto 0);
      rd_clk_i  : in  std_logic;
      wr_addr_i : in  std_logic_vector (g_addr_bits-1 downto 0);
      wr_clk_i  : in  std_logic;
      wr_en_i   : in  std_logic := '1';
      q_o       : out std_logic_vector (g_width-1 downto 0));
  end component;

  component generic_ssram_dualport_singleclock
    generic (
      g_width     : natural;
      g_addr_bits : natural;
      g_size      : natural;
      g_init_file : string := "UNUSED");
    port (
      data_i    : in  std_logic_vector (g_width-1 downto 0);
      clk_i     : in  std_logic;
      rd_addr_i : in  std_logic_vector (g_addr_bits-1 downto 0);
      wr_addr_i : in  std_logic_vector (g_addr_bits-1 downto 0);
      wr_en_i   : in  std_logic := '1';
      q_o       : out std_logic_vector (g_width-1 downto 0));
  end component;
  
  component alt_clock_divider
    port (
      inclk0 : in  std_logic := '0';
      c0     : out std_logic;
      c1     : out std_logic;
      locked : out std_logic);

    
  end component;

  component generic_pipelined_multiplier
    generic (
      g_width_a   : natural;
      g_width_b   : natural;
      g_width_out : natural;
      g_sign_mode : string);
    port (
      clk_i : in  std_logic;
      a_i   : in  std_logic_vector(g_width_a -1 downto 0);
      b_i   : in  std_logic_vector(g_width_b -1 downto 0);
      q_o   : out std_logic_vector(g_width_out-1 downto 0));
  end component;

end platform_specific;

-------------------------------------------------------------------------------
