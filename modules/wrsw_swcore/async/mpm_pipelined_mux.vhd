
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.genram_pkg.all;
use work.mpm_private_pkg.all;

entity mpm_pipelined_mux is
  
  generic (
    g_width  : integer := 16;
    g_inputs : integer := 18);

  port (
    clk_i   : in std_logic;
    rst_n_i : in std_logic;

    d_i : in  std_logic_vector(g_inputs * g_width-1 downto 0);
    q_o : out std_logic_vector(g_width-1 downto 0);

    -- select input (one hot encoded)
    sel_i : in std_logic_vector(g_inputs-1 downto 0)
    );

end mpm_pipelined_mux;

architecture rtl of mpm_pipelined_mux is

  type t_generic_slv_array is array (integer range <>, integer range <>) of std_logic;

  constant c_first_stage_muxes : integer := (g_inputs+2)/3;

  signal first_stage : t_generic_slv_array(0 to c_first_stage_muxes-1, g_width-1 downto 0);

begin  -- rtl

  -- 1st stage, optimized for 5-input LUTs: mux each 3-input groups or 0
  -- if (sel == 11)
  gen_1st_stage : for i in 0 to c_first_stage_muxes-1 generate
    gen_each_bit : for j in 0 to g_width-1 generate
      p_mux_or : process(clk_i)
      begin
        if rising_edge(clk_i) then
          if rst_n_i = '0' then
            first_stage(i, j) <= '0';
          else
            if(sel_i(3*i + 2 downto 3*i) = "001") then
              first_stage(i, j) <= d_i(i * 3 * g_width + j);
            elsif (sel_i(3*i + 2 downto 3*i) = "010") then
              first_stage(i, j) <= d_i(i * 3 * g_width + g_width + j);
            elsif (sel_i(3*i + 2 downto 3*i) = "100") then
              first_stage(i, j) <= d_i(i * 3 * g_width + 2*g_width + j);
            else
              first_stage(i, j) <= '0';
            end if;
          end if;
        end if;
      end process;
    end generate gen_each_bit;
  end generate gen_1st_stage;

  -- 2nd stage: simply OR together the results of the 1st stage
  p_2nd_stage : process(clk_i)
    variable row : std_logic_vector(c_first_stage_muxes-1 downto 0);
  begin
    if rising_edge(clk_i) then
      for j in 0 to g_width-1 loop
        if rst_n_i = '0' then
          q_o(j) <= '0';
        else
          for i in 0 to c_first_stage_muxes-1 loop
            row(i) := first_stage(i, j);
          end loop;  -- i

          if(unsigned(row) = 0) then
            q_o(j) <= '0';
          else
            q_o(j) <= '1';
          end if;
        end if;
      end loop;  -- j in 0 to g_width-1 loop
    end if;
  end process;
  
  
end rtl;
