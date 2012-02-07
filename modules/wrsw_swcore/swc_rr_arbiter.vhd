-------------------------------------------------------------------------------
-- Title      : Round Robin Arbiter
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : swc_rr_arbiter.vhd
-- Author     : Tomasz Wlostowski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-04-08
-- Last update: 2010-04-08
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
--
-- Copyright (c) 2010 Tomasz Wlostowski, Maciej Lipinski / CERN
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
-- Date        Version  Author   Description
-- 2010-04-08  1.0      twlostow Created
-------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.swc_swcore_pkg.all;

entity swc_rr_arbiter is
  
  generic (
    g_num_ports      : natural := 22;
    g_num_ports_log2 : natural := 5

    );

  port (
    rst_n_i       : in  std_logic;
    clk_i         : in  std_logic;
    next_i        : in  std_logic;
    request_i     : in  std_logic_vector(g_num_ports -1 downto 0);
    grant_o       : out std_logic_vector(g_num_ports_log2 - 1 downto 0);
    grant_valid_o : out std_logic
    );

end swc_rr_arbiter;

architecture syn of swc_rr_arbiter is

  signal request_mask       : std_logic_vector(g_num_ports -1 downto 0);
  signal request_mask_saved : std_logic_vector(g_num_ports -1 downto 0);
  signal request_vec_masked : std_logic_vector(g_num_ports -1 downto 0);

  type t_state is (WAIT_REQUEST, HANDLE_REQUEST);

  signal state : t_state;

  signal rq_decoded      : std_logic_vector(g_num_ports_log2-1 downto 0);
  signal rq_decoded_mask : std_logic_vector(g_num_ports-1 downto 0);
  signal rq_zero         : std_logic;
  signal rq_wait_next    : std_logic;
begin  -- syn


  ENC : swc_prio_encoder
    generic map (
      g_num_inputs  => g_num_ports,
      g_output_bits => g_num_ports_log2)
    port map (
      in_i   => request_vec_masked,
      out_o  => rq_decoded,
      mask_o => rq_decoded_mask,
      zero_o => rq_zero);



  arbitrate : process (clk_i, rst_n_i)
  begin  -- process arbitrate
    if rising_edge (clk_i) then
      if(rst_n_i = '0') then
        request_mask       <= (others => '1');
        request_vec_masked <= (others => '0');
        grant_o            <= (others => '0');
        grant_valid_o      <= '0';
        rq_wait_next       <= '0';
      else
        
        if(rq_wait_next = '1') then

          if(next_i = '1') then
            request_vec_masked <= request_i and request_mask;
            rq_wait_next       <= '0';
            grant_valid_o      <= '0';
          end if;

        else
          if(rq_zero = '0') then
            grant_o            <= rq_decoded;
            request_mask       <= rq_decoded_mask;
            request_vec_masked <= request_i and request_mask;
            grant_valid_o      <= '1';
            rq_wait_next       <= '1';
            
          else

            grant_valid_o      <= '0';
            request_mask       <= (others => '1');
            request_vec_masked <= request_i;
            rq_wait_next       <= '0';

          end if;
        end if;
      end if;
    end if;
  end process arbitrate;

end syn;
