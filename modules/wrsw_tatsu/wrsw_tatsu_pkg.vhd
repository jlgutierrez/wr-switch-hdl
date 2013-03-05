-------------------------------------------------------------------------------
-- Title      : Time-Aware Traffic Shaper Unit: package
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : wrsw_tatsu_pkg.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-CO-HT
-- Created    : 2013-03-01
-- Last update: 2012-03-01
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: Package with records, function, constants and components
-- declarations for TATSU module
--
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -
-- 
-- 
-- 
-- 
-------------------------------------------------------------------------------
--
-- Copyright (c) 2013 Maciej Lipinski / CERN
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
-- 2012-03-01  1.0      mlipinsk Created
-------------------------------------------------------------------------------
library ieee;
use ieee.STD_LOGIC_1164.all;

library work;
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.CEIL;
use ieee.math_real.log2;
use work.wrsw_shared_types_pkg.all; 
use work.tatsu_wbgen2_pkg.all;
use work.wishbone_pkg.all;         -- wishbone_{interface_mode,address_granularity}

package wrsw_tatsu_pkg is


  type t_tatsu_config is record
    start_tm_tai           : std_logic_vector(39 downto 0);
    start_tm_cycles        : std_logic_vector(27 downto 0);
    repeat_cycles          : std_logic_vector(27 downto 0);
    window_quanta          : std_logic_vector(15 downto 0);
    ports_mask             : std_logic_vector(31 downto 0);
    prio_mask              : std_logic_vector(7  downto 0);
  end record;


  component tatsu_wishbone_controller is
  port (
    rst_n_i                                  : in     std_logic;
    clk_sys_i                                : in     std_logic;
    wb_adr_i                                 : in     std_logic_vector(2 downto 0);
    wb_dat_i                                 : in     std_logic_vector(31 downto 0);
    wb_dat_o                                 : out    std_logic_vector(31 downto 0);
    wb_cyc_i                                 : in     std_logic;
    wb_sel_i                                 : in     std_logic_vector(3 downto 0);
    wb_stb_i                                 : in     std_logic;
    wb_we_i                                  : in     std_logic;
    wb_ack_o                                 : out    std_logic;
    wb_stall_o                               : out    std_logic;
    regs_i                                   : in     t_tatsu_in_registers;
    regs_o                                   : out    t_tatsu_out_registers
  );
  end component;
  
  component xwrsw_tatsu is
  generic(     
     g_num_ports          : integer := 6;  
     g_interface_mode     : t_wishbone_interface_mode      := PIPELINED;
     g_simulation         : boolean := false;
     g_address_granularity: t_wishbone_address_granularity := BYTE
     );
  port (
    clk_sys_i                 : in std_logic;
    clk_ref_i                 : in std_logic;

    rst_n_i                   : in std_logic;

    shaper_request_o          : out t_global_pause_request ;
    shaper_drop_at_hp_ena_o   : out std_logic;    

    tm_utc_i                  : in  std_logic_vector(39 downto 0);
    tm_cycles_i               : in  std_logic_vector(27 downto 0);
    tm_time_valid_i           : in  std_logic;

    wb_i                      : in  t_wishbone_slave_in;
    wb_o                      : out t_wishbone_slave_out          
    );
  end component; 

  function f_pick (
    cond     : boolean;
    if_true  : integer;
    if_false : integer
    ) return integer;


end wrsw_tatsu_pkg;

package body wrsw_tatsu_pkg is

  function f_pick (
    cond     : boolean;
    if_true  : integer;
    if_false : integer
    ) return integer is
  begin
    if(cond) then
      return if_true;
    else
      return if_false;
    end if;
  end f_pick;

end wrsw_tatsu_pkg;

