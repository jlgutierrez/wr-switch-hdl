library ieee;
use ieee.std_logic_1164.all;

package swc_private_pkg is

  constant c_data_path_width      : integer                                        := 18;
  constant c_eof_marker           : std_logic_vector(c_data_path_width-1 downto 0) := "11XXXXXXXXXXXXXXXX";
  constant c_mpm_async_fifo_depth : integer                                        := 8;
  constant c_page_addr_width      : integer                                        := 12;

  type t_generic_slv_array is array (integer range <>, integer range <>) of std_logic;

  type t_mpm_write_in is record
    d        : std_logic_vector(c_data_path_width-1 downto 0);
    d_valid  : std_logic;
    d_eof    : std_logic;
    pg_addr  : std_logic_vector(c_page_addr_width-1 downto 0);
    pg_valid : std_logic;
  end record;

  type t_mpm_write_out is record
    d_req  : std_logic;
    pg_req : std_logic;
  end record;

  type t_mpm_write_in_array is array (integer range <>) of t_mpm_write_in;
  type t_mpm_write_out_array is array (integer range <>) of t_mpm_write_out;


  type t_mpm_read_out is record
    d       : std_logic_vector(c_data_path_width-1 downto 0);
    d_valid : std_logic;
    d_eof   : std_logic;
    pg_req  : std_logic;
  end record;

  type t_mpm_read_in is record
    pg_addr  : std_logic_vector(c_page_addr_width-1 downto 0);
    pg_valid : std_logic;
    d_req    : std_logic;
  end record;

  type t_mpm_read_in_array is array (integer range <>) of t_mpm_read_in;
  type t_mpm_read_out_array is array (integer range <>) of t_mpm_read_out;

  
  
  

end swc_private_pkg;
