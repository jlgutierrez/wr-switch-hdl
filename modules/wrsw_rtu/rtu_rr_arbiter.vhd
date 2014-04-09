-------------------------------------------------------------------------------
-- Title      : Round Robin Arbiter
-- Project    : White Rabbit Switch
-------------------------------------------------------------------------------
-- File       : wrsw_rr_arbiter.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-05-09
-- Last update: 2012-01-25
-- Platform   : FPGA-generic
-- Standard   : VHDL
-------------------------------------------------------------------------------
-- Implements parametrized Round Robin Arbiter :
-- - a slave requests access by settin HIGH on his request line
-- - HIGH state should be as long as the slave needs - it measn that the next
--   request is served when the currently requestes slave sets his request line
--   to LOW
-- - used this side as reference: 
--   http://un.codiert.org/2009/04/round-robin-arbiter-vhdl/
--
-------------------------------------------------------------------------------
--
-- Copyright (c) 2010 - 2012 CERN / BE-CO-HT
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
-- 2010-05-09  1.0      lipinskimm	    Created
-------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.rtu_private_pkg.all;


entity rtu_rr_arbiter is
    generic (
        g_width          : natural :=4 );
    port (
        clk_i,  rst_n_i  :in  std_logic;
        req_i            :in  std_logic_vector(g_width - 1 downto 0);
        gnt_o            :out std_logic_vector(g_width - 1 downto 0)
        
    );
end entity;
architecture behavior of rtu_rr_arbiter is

    ----------------Internal Registers-----------------
    signal s_reqs      :std_logic_vector(g_width - 1 downto 0);
    signal s_gnts      :std_logic_vector(g_width - 1 downto 0);
    signal s_gnt       :std_logic_vector(g_width - 1 downto 0);
    signal s_gntM      :std_logic_vector(g_width - 1 downto 0);
    signal s_pre_gnt   :std_logic_vector(g_width - 1 downto 0);
    signal s_zeros     :std_logic_vector(g_width - 1 downto 0);
    
begin

    s_zeros <= (others => '0');
    
    main: process (clk_i) begin
		if (rising_edge(clk_i)) then  -- evaluate on rising edge
          if (rst_n_i = '0') then     -- synch reset
		    gnt_o         <= (others => '0');
            s_pre_gnt     <= (others => '0');
          else    
            -- if the current request has been served
            if((req_i AND s_pre_gnt) = s_zeros) then
              gnt_o         <= s_gntM;
              s_pre_gnt     <= s_gntM; -- remember current grant vector, for the next operation
            end if;
          end if;
        end if;
    end process main;

    -- bit twiddling magic :
    s_gnt  <= req_i    and std_logic_vector(unsigned(not req_i) + 1);
    s_reqs <= req_i    and not (std_logic_vector(unsigned(s_pre_gnt ) - 1) or s_pre_gnt);
    s_gnts <= s_reqs   and std_logic_vector(unsigned(not s_reqs)+1);
    s_gntM <= s_gnt    when s_reqs = s_zeros else s_gnts;


end architecture;

