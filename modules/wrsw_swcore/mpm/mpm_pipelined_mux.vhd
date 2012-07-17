-------------------------------------------------------------------------------
-- Title        : 2-stage pipelined multiplexer 
-- Project      : White Rabbit Switch
-------------------------------------------------------------------------------
-- File         : mpm_pipelined_mux.vhd
-- Author       : Tomasz Włostowski
-- Company      : CERN BE-CO-HT
-- Created      : 2012-01-30
-- Last update  : 2012-01-30
-- Platform     : FPGA-generic
-- Standard     : VHDL'93
-- Dependencies : 
-------------------------------------------------------------------------------
-- Description: 2-stage pipelined multiplexer. Input is selected by one-hot
-- encoded sel_i signal. Introduces (d_i, sel_i -> q_o) delay of 2 clk_i cycles.
-------------------------------------------------------------------------------
--
-- Copyright (c) 2012 CERN
--
-- This source file is free software; you can redistribute it   
-- and/or modify it under the terms of the GNU Lesser General   
-- Public License as published by the Free Software Foundation; 
-- either version 2.1 of the License, or (at your option) any   
-- later version.                                               
--
-- This source is distributed in the hope that it will be       
-- useful, but WITHOUT ANY WARRANTY; without even the implied   
-- warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR      
-- PURPOSE.  See the GNU Lesser General Public License for more 
-- details.                                                     
--
-- You should have received a copy of the GNU Lesser General    
-- Public License along with this source; if not, download it   
-- from http://www.gnu.org/licenses/lgpl-2.1.html
--
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author          Description
-- 2012-01-30  1.0      twlostow        Created
-------------------------------------------------------------------------------

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
  constant c_num_inputs_floor3 : integer := ((g_inputs+2)/3) * 3;

  signal first_stage : t_generic_slv_array(0 to c_first_stage_muxes-1, g_width-1 downto 0);



  signal d_extended   : std_logic_vector(c_num_inputs_floor3 * g_width - 1 downto 0);
  signal sel_extended : std_logic_vector(c_num_inputs_floor3 - 1 downto 0) := (others => '0');

  function f_deXize(x : std_logic_vector) return std_logic_vector is
    variable tmp : std_logic_vector(x'length-1 downto 0);
  begin
    for i in 0 to x'length-1 loop
      if(x(i) = '0' or x(i) = '1') then
        tmp(i) := x(i);
      else
        tmp(i) := '0';
      end if;
    end loop;  -- i

    return tmp;
    
  end f_deXize;
  
begin  -- rtl

  d_extended (d_i'left downto 0)     <= d_i;
  sel_extended (sel_i'left downto 0) <= sel_i;


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
            if(sel_extended(3*i + 2 downto 3*i) = "001") then
              first_stage(i, j) <= d_extended(i * 3 * g_width + j);
            elsif (sel_extended(3*i + 2 downto 3*i) = "010") then
              first_stage(i, j) <= d_extended(i * 3 * g_width + g_width + j);
            elsif (sel_extended(3*i + 2 downto 3*i) = "100") then
              first_stage(i, j) <= d_extended(i * 3 * g_width + 2*g_width + j);
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

          if(unsigned(f_deXize(row)) = 0) then
            q_o(j) <= '0';
          else
            q_o(j) <= '1';
          end if;
        end if;
      end loop;  -- j in 0 to g_width-1 loop
    end if;
  end process;
  
  
end rtl;
