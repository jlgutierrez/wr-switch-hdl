library ieee;
use ieee.std_logic_1164.all;
use work.genram_pkg.all;


entity showahead_fifo is

  generic (
    g_data_width : natural;
    g_size       : natural);

  port (
    rst_n_i : in  std_logic := '1';
    clk_i   : in  std_logic;
    d_i     : in  std_logic_vector(g_data_width-1 downto 0);
    we_i    : in  std_logic;
    q_o     : out std_logic_vector(g_data_width-1 downto 0);
    rd_i    : in  std_logic;
    empty_o : out std_logic;
    full_o  : out std_logic);

end showahead_fifo;

architecture rtl of showahead_fifo is

  signal empty, rd : std_logic;
  signal q_valid : std_logic;
  

    
  
begin  -- rtl


  U_Fifo : generic_sync_fifo
    generic map (
      g_data_width => g_data_width,
      g_size       => g_size)
    port map (
      rst_n_i => rst_n_i,
      clk_i   => clk_i,
      d_i     => d_i,
      we_i    => we_i,
      q_o     => q_o,
      rd_i    => rd,
      empty_o => empty,
      full_o  => full_o);

  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if rst_n_i = '0' then
        empty <= '1';
      else
        if(empty = '0') then
          rd <= '1';
          q_valid <= rd;
        end if;
      end if;
    end if;
  end process;
  
  
  

end rtl;




