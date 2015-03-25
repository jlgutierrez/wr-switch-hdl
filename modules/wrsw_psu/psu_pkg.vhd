-------------------------------------------------------------------------------
-- Title      : PTP Support Unit Package
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : psu_private_pkg.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2015-03-17
-- Last update: 2015-03-17
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
--
-- Copyright (c) 2015 CERN / BE-CO-HT
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
-- 2015-03-17  1.0      mlipinsk Created
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.CEIL;
use ieee.math_real.log2;

library work;
use work.wr_fabric_pkg.all;
use work.psu_wbgen2_pkg.all;


package psu_pkg is

  type t_snoop_mode is (TX_SEQ_ID_MODE, RX_CLOCK_CLASS_MODE);

  type t_snooper_config is record
    seqID_duplicate_det : std_logic;
    seqID_wrong_det     : std_logic;
    clkCl_mismatch_det  : std_logic;
    prtID_mismatch_det  : std_logic;

    holdover_clk_class   : std_logic_vector(7 downto 0);
    snoop_ports_mask     : std_logic_vector(31 downto 0);
  end record;

  component psu_announce_snooper is
    generic(
      g_port_number   : integer := 18;
      g_snoop_mode    : t_snoop_mode := TX_SEQ_ID_MODE);
    port (
    clk_sys_i : in std_logic;
    rst_n_i   : in std_logic;

    snk_i                 : in  t_wrf_sink_in;
    snk_o                 : out t_wrf_sink_out;

    src_i                 : in  t_wrf_source_in;
    src_o                 : out t_wrf_source_out;

    rtu_dst_port_mask_i   : in  std_logic_vector(g_port_number-1 downto 0);
    holdover_on_i         : in std_logic;

    detected_announce_o   : out std_logic;
    detected_port_mask_o  : out std_logic_vector(g_port_number-1 downto 0);

    wr_ram_ena_o          : out std_logic;
    wr_ram_data_o         : out std_logic_vector(17 downto 0);
    wr_ram_addr_o         : out std_logic_vector(9 downto 0); 

    rd_ram_data_i         : in std_logic_vector(17 downto 0);
    rd_ram_ena_o          : out std_logic;
    rd_ram_addr_o         : out std_logic_vector( 9 downto 0);    
    config_i              : in t_snooper_config);
  end component;
  component psu_packet_injection is
    generic(
      g_port_number      : integer:=18
    );
    port (
      clk_sys_i : in std_logic;
      rst_n_i   : in std_logic;


      src_i : in  t_wrf_source_in;
      src_o : out t_wrf_source_out;
      snk_i : in  t_wrf_sink_in;
      snk_o : out t_wrf_sink_out;
      rtu_dst_port_mask_o : out std_logic_vector(g_port_number-1 downto 0);
      rtu_prio_o          : out std_logic_vector(2 downto 0);
      rtu_drop_o          : out std_logic;
      rtu_rsp_valid_o     : out std_logic;
      rtu_rsp_ack_i       : in  std_logic;
      rtu_dst_port_mask_i : in  std_logic_vector(g_port_number-1 downto 0);
      rtu_prio_i          : in  std_logic_vector(2 downto 0);
      rtu_drop_i          : in  std_logic;
      rtu_rsp_valid_i     : in  std_logic;
      rtu_rsp_ack_o       : out std_logic;
      inject_req_i        : in  std_logic;
      inject_ready_o      : out std_logic;
      inject_clockClass_i : in  std_logic_vector(7 downto 0);
      inject_port_mask_i  : in  std_logic_vector(g_port_number-1 downto 0);
      inject_pck_prio_i   : in  std_logic_vector( 2 downto 0);
      
      rd_ram_data_i       : in  std_logic_vector(17 downto 0)
);
  end component;

  component psu_tx_ctrl is
    generic(
      g_port_number       : integer := 18);
    port (
      clk_sys_i           : in std_logic;
      rst_n_i             : in std_logic;
      inject_req_o        : out std_logic;
      inject_ready_i      : in  std_logic;
      inject_port_mask_o  : out std_logic_vector(g_port_number-1 downto 0);
      tx_port_mask_i      : in std_logic_vector(g_port_number-1 downto 0); 
      tx_ann_detect_mask_i : in std_logic_vector(g_port_number-1 downto 0); 
      holdover_on_i       : in  std_logic;
      holdover_on_o       : out std_logic);
   end component;


  component psu_wishbone_controller is
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
      regs_i                                   : in     t_psu_in_registers;
      regs_o                                   : out    t_psu_out_registers
   );
 end component;

end psu_pkg;

package body psu_pkg is



end psu_pkg;
