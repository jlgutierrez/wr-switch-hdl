-------------------------------------------------------------------------------
-- Title        : Multiport Memory - Read Path Core
-- Project      : White Rabbit Switch
-------------------------------------------------------------------------------
-- File         : mpm_rpath_core_block.vhd
-- Author       : Tomasz Włostowski
-- Company      : CERN BE-CO-HT
-- Created      : 2012-02-12
-- Last update  : 2012-02-12
-- Platform     : FPGA-generic
-- Standard     : VHDL'93
-------------------------------------------------------------------------------
--
-- Copyright (c) 2012 CERN / BE-CO-HT
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

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.gencores_pkg.all;
use work.genram_pkg.all;

entity mpm_rpath_core_block is
  
  generic (
    g_num_pages       : integer;
    g_data_width      : integer;
    g_page_addr_width : integer;
    g_page_size       : integer;
    g_ratio           : integer
    );

  port(
    clk_core_i   : in std_logic;
    rst_n_core_i : in std_logic;

    -- F. B. Memory I/F
    fbm_req_o   : out std_logic;
    fbm_grant_i : in  std_logic;
    fbm_addr_o  : out std_logic_vector(f_log2_size(g_num_pages * g_page_size / g_ratio)-1 downto 0);

    df_full_i : in  std_logic;
    df_we_o   : out std_logic;

    pf_fbm_addr_i : in std_logic_vector(f_log2_size(g_num_pages * g_page_size / g_ratio) - 1 downto 0);
    pf_pg_lines_i : in std_logic_vector(f_log2_size(g_page_size / g_ratio + 1)-1 downto 0);
    pf_empty_i : in  std_logic;
    pf_rd_o    : out std_logic
    );
end mpm_rpath_core_block;

architecture behavioral of mpm_rpath_core_block is

  constant c_lines_per_page   : integer := g_page_size/g_ratio;
  constant c_page_lines_width : integer := f_log2_size(c_lines_per_page + 1);
  constant c_page_size_width  : integer := f_log2_size(g_page_size + 1);
  constant c_fbm_entries         : integer := g_num_pages * g_page_size / g_ratio;
  constant c_fbm_addr_width      : integer := f_log2_size(c_fbm_entries);

  -- fbm_grant_d timing:
  -- 0: mux_sel = our block, increase line counter, check ovf
  -- 1: if ovf, increase page counter, read next page
  -- 2: fbm_data = our data, fifo_we = 1

  type t_core_state is (IDLE, GET_ADDR, READ_PAGE);

  signal fbm_grant_d : std_logic_vector(4 downto 0);
  signal state       : t_core_state;

  signal fbm_addr            : unsigned(c_fbm_addr_width-1 downto 0);
  signal fbm_remaining_lines : unsigned(c_page_lines_width-1 downto 0);
  signal page_read           : std_logic;
  signal fbm_req_int         : std_logic;
  
  
begin  -- behavioral


  fbm_grant_d(0) <= fbm_grant_i;
  
  p_delay_grant : process(clk_core_i)
  begin
    if rising_edge(clk_core_i) then
      if rst_n_core_i = '0' then
        fbm_grant_d (fbm_grant_d'left downto 1) <= (others => '0');
      else
        fbm_grant_d (fbm_grant_d'left downto 1) <= fbm_grant_d(fbm_grant_d'left-1 downto 0) ;
      end if;
    end if;
  end process;

  p_fsm : process(clk_core_i)
  begin
    if rising_edge(clk_core_i) then
      if rst_n_core_i = '0' then
        state       <= IDLE;
        fbm_req_int <= '0';
        page_read   <= '0';
        df_we_o <= '0';
      else
        case state is
          when IDLE =>
            if(pf_empty_i = '0') then
              state <= GET_ADDR;
            end if;

          when GET_ADDR =>
            fbm_addr            <= unsigned(pf_fbm_addr_i);
            fbm_remaining_lines <= unsigned(pf_pg_lines_i);
            state               <= READ_PAGE;

          when READ_PAGE =>

            if(unsigned(fbm_grant_d) = 0 and df_full_i = '0') then
              fbm_addr_o  <= std_logic_vector(fbm_addr);
              fbm_req_int <= '1';
            else
              fbm_req_int <= '0';
            end if;

            if(fbm_grant_d(0) = '1') then
              fbm_addr         <= fbm_addr + 1;
              fbm_remaining_lines <= fbm_remaining_lines - 1;
            end if;


          if(fbm_grant_d(3) = '1') then
            df_we_o <= '1';
            else
              df_we_o <='0';
            end if;
            
            if(fbm_grant_d(4) = '1' and fbm_remaining_lines = 0) then
              state <= IDLE;
            end if;
        end case;
      end if;
    end if;
  end process;

  fbm_req_o <= fbm_req_int and not (fbm_grant_d(0) or fbm_grant_d(1) or fbm_grant_d(2));
--  fbm_addr_o <= std_logic_vector(fbm_addr);
  pf_rd_o <= '1' when (state = IDLE and pf_empty_i = '0') else '0';
--  df_we_o <= fbm_grant_d(4);
  
end behavioral;



