library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity swc_block_allocator is
  generic (
    g_num_blocks      : integer := 2048;
    g_log2_num_blocks : integer := 13;
    g_usecount_bits   : integer := 4
    );

  port (
    clk_i   : in std_logic;
    rst_n_i : in std_logic;

    idle_o : out std_logic;

    alloc_rq_i        : in  std_logic;
    alloc_size_i      : in  std_logic_vector (7 downto 0);
    alloc_done_o      : out std_logic;
    alloc_nomem_o : out std_logic;
    alloc_use_count_i : in  std_logic_vector(g_usecount_bits-1 downto 0);
    alloc_addr_o      : out std_logic_vector (g_log2_num_blocks-1 downto 0);

    free_rq_i   : in  std_logic;
    free_addr_i : in  std_logic_vector(g_log2_num_blocks-1 downto 0);
    free_done_o : out std_logic
    );

end swc_block_allocator;

architecture syn of swc_block_allocator is

  constant c_l1_size : integer := g_num_blocks/32;

  signal l1_full : std_logic_vector(c_l1_size-1 downto 0);  -- 1 means block is
                                                            -- full

  signal l1_empty : std_logic_vector(c_l1_size-1 downto 0);  -- 1 means block is
                                                             -- empty

  type t_state is (IDLE, ALLOC_LOOKUP_L1);
begin  -- syn

  
  
  process (clk_i, rst_n_i)
  begin  -- process
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        l1_full  <= (others => '0');
        l1_empty <= (others => '1');
      else
        
      end if;
    end if;
  end process;

  


end syn;
