library ieee;
use ieee.std_logic_1164.all;
use ieee.math_real.CEIL;
use ieee.math_real.log2;

package swc_swcore_pkg is


-- number of switch ports
  constant c_swc_num_ports       : integer := 11;
-- size of the packet memory in words (1 word = 1 ctrl + data sequence)
  constant c_swc_packet_mem_size : integer := 65536;

  constant c_swc_packet_mem_multiply : integer := 16;
  constant c_swc_data_width          : integer := 16;
  constant c_swc_ctrl_width          : integer := 16;
  constant c_swc_page_size           : integer := 64;


  -- 
  constant c_swc_packet_mem_num_pages  : integer := (c_swc_packet_mem_size / c_swc_page_size);
  constant c_swc_page_addr_width       : integer := integer(CEIL(LOG2(real(c_swc_packet_mem_num_pages-1))));
  constant c_swc_usecount_width        : integer := integer(CEIL(LOG2(real(c_swc_num_ports-1))));
  constant c_swc_page_offset_width     : integer := integer(CEIL(LOG2(real(c_swc_page_size / c_swc_packet_mem_multiply))));
  constant c_swc_packet_mem_addr_width : integer := c_swc_page_addr_width + c_swc_page_offset_width;
  constant c_swc_pump_width            : integer := c_swc_data_width + c_swc_ctrl_width;


  type t_slv_array is array(integer range <>, integer range <>) of std_logic;

-- type declarations for memory input/output registers in data pump
  subtype t_pump_entry is std_logic_vector(c_swc_pump_width-1 downto 0);
  type t_pump_reg is array (c_swc_packet_mem_multiply-1 downto 0) of t_pump_entry;

  component swc_prio_encoder
    generic (
      g_num_inputs  : integer range 2 to 64;
      g_output_bits : integer range 1 to 6);
    port (
      in_i     : in  std_logic_vector(g_num_inputs-1 downto 0);
      out_o    : out std_logic_vector(g_output_bits-1 downto 0);
      onehot_o : out std_logic_vector(g_num_inputs-1 downto 0);
      mask_o   : out std_logic_vector(g_num_inputs-1 downto 0);
      zero_o   : out std_logic);
  end component;

  component swc_page_allocator
    generic (
      g_num_pages      : integer;
      g_page_addr_bits : integer;
      g_use_count_bits : integer);
    port (
      clk_i          : in  std_logic;
      rst_n_i        : in  std_logic;
      alloc_i        : in  std_logic;
      free_i         : in  std_logic;
      usecnt_i       : in  std_logic_vector(g_use_count_bits-1 downto 0);
      pgaddr_i       : in  std_logic_vector(g_page_addr_bits -1 downto 0);
      pgaddr_o       : out std_logic_vector(g_page_addr_bits -1 downto 0);
      pgaddr_valid_o : out std_logic;
      idle_o         : out std_logic;
      done_o         : out std_logic;
      nomem_o        : out std_logic);
  end component;

  component swc_rr_arbiter
    generic (
      g_num_ports      : natural;
      g_num_ports_log2 : natural);
    port (
      rst_n_i       : in  std_logic;
      clk_i         : in  std_logic;
      next_i        : in  std_logic;
      request_i     : in  std_logic_vector(g_num_ports -1 downto 0);
      grant_o       : out std_logic_vector(g_num_ports_log2 - 1 downto 0);
      grant_valid_o : out std_logic);
  end component;

  component swc_packet_mem_write_pump
    port (
      clk_i    : in  std_logic;
      rst_n_i  : in  std_logic;
      pgaddr_i : in  std_logic_vector(c_swc_page_addr_width-1 downto 0);
      pgreq_i  : in  std_logic;
      pgend_o  : out std_logic;
      drdy_i   : in  std_logic;
      full_o   : out std_logic;
      flush_i  : in  std_logic;
      sync_i   : in  std_logic;
      addr_o   : out std_logic_vector(c_swc_packet_mem_addr_width -1 downto 0);
      d_i      : in  std_logic_vector(c_swc_pump_width -1 downto 0);
      q_o      : out std_logic_vector(c_swc_pump_width * c_swc_packet_mem_multiply - 1 downto 0);
      we_o     : out std_logic);
  end component;

  component swc_packet_mem_read_pump
    port (
      clk_i    : in  std_logic;
      rst_n_i  : in  std_logic;
      pgreq_i  : in  std_logic;
      pgaddr_i : in  std_logic_vector(c_swc_page_addr_width - 1 downto 0);
      pgend_o  : out std_logic;
      drdy_o   : out std_logic;
      dreq_i   : in  std_logic;
      sync_i   : in  std_logic;
      d_o      : out std_logic_vector(c_swc_pump_width - 1 downto 0);
      addr_o   : out std_logic_vector(c_swc_packet_mem_addr_width - 1 downto 0);
      q_i      : in  std_logic_vector(c_swc_pump_width * c_swc_packet_mem_multiply -1 downto 0));
  end component;
  
end swc_swcore_pkg;

package body swc_swcore_pkg is




end swc_swcore_pkg;
