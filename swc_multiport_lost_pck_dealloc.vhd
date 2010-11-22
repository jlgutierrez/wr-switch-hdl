-------------------------------------------------------------------------------
-- Title      : multiport lost pck deallocator
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : swc_multiport_plost_pck_dealloc.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-11-13
-- Last update: 2010-11-13
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
--
-- Copyright (c) 2010 Maciej Lipinski / CERN
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
-- 2010-11-13  1.0      mlipinsk Created
-------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.swc_swcore_pkg.all;
use work.platform_specific.all;



entity swc_multiport_lost_pck_dealloc is
  port (
    clk_i   : in std_logic;
    rst_n_i : in std_logic;

    ib_force_free_i         : in  std_logic_vector(c_swc_num_ports-1 downto 0);
    ib_force_free_done_o    : out std_logic_vector(c_swc_num_ports-1 downto 0);
    ib_force_free_pgaddr_i  : in  std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);

    ob_force_free_i         : in  std_logic_vector(c_swc_num_ports-1 downto 0);
    ob_force_free_done_o    : out std_logic_vector(c_swc_num_ports-1 downto 0);
    ob_force_free_pgaddr_i  : in  std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
    
    ll_read_addr_o          : out std_logic_vector(c_swc_num_ports * c_swc_page_addr_width -1 downto 0);
    --ll_read_data_i          : in  std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
    ll_read_data_i          : in  std_logic_vector(c_swc_page_addr_width - 1 downto 0);
    ll_read_req_o           : out std_logic_vector(c_swc_num_ports-1 downto 0);
    ll_read_valid_data_i    : in  std_logic_vector(c_swc_num_ports-1 downto 0);
    
    mmu_force_free_o        : out std_logic_vector(c_swc_num_ports-1 downto 0);
    mmu_force_free_done_i   : in  std_logic_vector(c_swc_num_ports-1 downto 0);
    mmu_force_free_pgaddr_o : out std_logic_vector(c_swc_num_ports * c_swc_page_addr_width -1 downto 0)
    );

end swc_multiport_lost_pck_dealloc;

architecture syn of swc_multiport_lost_pck_dealloc is

  
begin  -- syn 



  lpd_gen : for i in 0 to c_swc_num_ports-1 generate
  
    LPD:  swc_lost_pck_dealloc 
    port map(
      clk_i                   => clk_i,
      rst_n_i                 => rst_n_i,

      ib_force_free_i         => ib_force_free_i(i),
      ib_force_free_done_o    => ib_force_free_done_o(i),
      ib_force_free_pgaddr_i  => ib_force_free_pgaddr_i((i+1)*c_swc_page_addr_width - 1 downto i * c_swc_page_addr_width),
  
      ob_force_free_i         => ob_force_free_i(i),
      ob_force_free_done_o    => ob_force_free_done_o(i),
      ob_force_free_pgaddr_i  => ob_force_free_pgaddr_i((i+1)*c_swc_page_addr_width - 1 downto i * c_swc_page_addr_width),
      
      ll_read_addr_o          => ll_read_addr_o((i+1)*c_swc_page_addr_width - 1 downto i * c_swc_page_addr_width),
      --ll_read_data_i          => ll_read_data_i((i+1)*c_swc_num_ports - 1 downto i * c_swc_num_ports),
      ll_read_data_i          => ll_read_data_i,
      ll_read_req_o           => ll_read_req_o(i),
      ll_read_valid_data_i    => ll_read_valid_data_i(i),
      
      mmu_force_free_o        => mmu_force_free_o(i),
      mmu_force_free_done_i   => mmu_force_free_done_i(i),
      mmu_force_free_pgaddr_o => mmu_force_free_pgaddr_o((i+1)*c_swc_page_addr_width - 1 downto i * c_swc_page_addr_width)
  
         
      );

  end generate lpd_gen;
  
  
end syn;
