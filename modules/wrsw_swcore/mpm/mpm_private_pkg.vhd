library ieee;
use ieee.std_logic_1164.all;

package mpm_private_pkg is

  -----------------------------------------------------------------------------
  -- Components
  -----------------------------------------------------------------------------

  component mpm_pipelined_mux
    generic (
      g_width  : integer;
      g_inputs : integer);
    port (
      clk_i   : in  std_logic;
      rst_n_i : in  std_logic;
      d_i     : in  std_logic_vector(g_inputs * g_width-1 downto 0);
      q_o     : out std_logic_vector(g_width-1 downto 0);
      sel_i   : in  std_logic_vector(g_inputs-1 downto 0));
  end component;

  component mpm_async_grow_fifo
    generic (
      g_width          : integer;
      g_ratio          : integer;
      g_size           : integer;
      g_sideband_width : integer);
    port (
      rst_n_a_i    : in  std_logic;
      clk_wr_i     : in  std_logic;
      clk_rd_i     : in  std_logic;
      we_i         : in  std_logic;
      align_i      : in  std_logic;
      d_i          : in  std_logic_vector(g_width-1 downto 0);
      rd_i         : in  std_logic;
      q_o          : out std_logic_vector(g_width * g_ratio-1 downto 0);
      side_i       : in  std_logic_vector(g_sideband_width-1 downto 0);
      side_o       : out std_logic_vector(g_sideband_width-1 downto 0);
      full_o       : out std_logic;
      empty_o      : out std_logic);
  end component;

  component mpm_async_shrink_fifo
    generic (
      g_width          : integer;
      g_ratio          : integer;
      g_size           : integer;
      g_sideband_width : integer);
    port (
      rst_n_a_i : in  std_logic;
      clk_wr_i  : in  std_logic;
      clk_rd_i  : in  std_logic;
      we_i      : in  std_logic;
      d_i       : in  std_logic_vector(g_width*g_ratio-1 downto 0);
      rd_i      : in  std_logic;
      q_o       : out std_logic_vector(g_width-1 downto 0);
      side_i    : in  std_logic_vector(g_sideband_width-1 downto 0);
      side_o    : out std_logic_vector(g_sideband_width-1 downto 0);
      flush_i   : in  std_logic := '0';
      full_o    : out std_logic;
      empty_o   : out std_logic);
  end component;

  component mpm_async_fifo
    generic (
      g_width : integer;
      g_size  : integer);
    port (
      rst_n_a_i : in  std_logic;
      clk_wr_i  : in  std_logic;
      clk_rd_i  : in  std_logic;
      we_i      : in  std_logic;
      d_i       : in  std_logic_vector(g_width-1 downto 0);
      rd_i      : in  std_logic;
      q_o       : out std_logic_vector(g_width-1 downto 0);
      full_o    : out std_logic;
      empty_o   : out std_logic);
  end component;
  
  function f_slice (
    x     : std_logic_vector;
    index : integer;
    len   : integer) return std_logic_vector;

end mpm_private_pkg;

package body mpm_private_pkg is

  function f_slice (
    x     : std_logic_vector;
    index : integer;
    len   : integer) return std_logic_vector is
  begin
    return x((index + 1) * len - 1 downto index * len);
  end f_slice;


end mpm_private_pkg;
