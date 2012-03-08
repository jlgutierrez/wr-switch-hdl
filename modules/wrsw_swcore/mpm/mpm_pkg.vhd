-------------------------------------------------------------------------------
-- Title      : Multiport Memory Package
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : mpm_pkg.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-02-14
-- Last update: 2012-02-14
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
-- 2012-02-14  1.0      mlipinsk created
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.math_real.CEIL;
use ieee.math_real.log2;

package mpm_pkg is

  component mpm_top is
  generic (
    g_data_width           : integer := 18;
    g_ratio                : integer := 2;
    g_page_size            : integer := 64;
    g_num_pages            : integer := 2048;
    g_num_ports            : integer := 8;
    g_fifo_size            : integer := 4;
    g_page_addr_width      : integer := 11;
    g_partial_select_width : integer := 1;
    g_max_oob_size         : integer := 3;
    g_max_packet_size      : integer := 10000;
    g_ll_data_width        : integer := 15
    );

  port(
    clk_io_i   : in std_logic;
    clk_core_i : in std_logic;
    rst_n_i    : in std_logic;

    wport_d_i       : in  std_logic_vector (g_num_ports * g_data_width -1 downto 0);
    wport_dvalid_i  : in  std_logic_vector (g_num_ports-1 downto 0);
    wport_dlast_i   : in  std_logic_vector (g_num_ports-1 downto 0);
    wport_pg_addr_i : in  std_logic_vector (g_num_ports * g_page_addr_width -1 downto 0);
    wport_pg_req_o  : out std_logic_vector(g_num_ports -1 downto 0);
    wport_dreq_o    : out std_logic_vector (g_num_ports-1 downto 0);

    rport_d_o        : out std_logic_vector (g_num_ports * g_data_width -1 downto 0);
    rport_dvalid_o   : out std_logic_vector (g_num_ports-1 downto 0);
    rport_dlast_o    : out std_logic_vector (g_num_ports-1 downto 0);
    rport_dsel_o     : out std_logic_vector (g_num_ports * g_partial_select_width -1 downto 0);
    rport_dreq_i     : in  std_logic_vector (g_num_ports-1 downto 0);
    rport_abort_i    : in  std_logic_vector (g_num_ports-1 downto 0);
    rport_pg_addr_i  : in  std_logic_vector (g_num_ports * g_page_addr_width -1 downto 0);
    rport_pg_valid_i : in  std_logic_vector (g_num_ports-1 downto 0);
    rport_pg_req_o   : out std_logic_vector (g_num_ports-1 downto 0);

    ll_addr_o : out std_logic_vector(g_page_addr_width-1 downto 0);
    ll_data_i : in  std_logic_vector(g_ll_data_width  -1 downto 0)
    );
   end component; 

end mpm_pkg;

package body mpm_pkg is

end mpm_pkg;
