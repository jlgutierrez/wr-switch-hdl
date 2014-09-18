-------------------------------------------------------------------------------
-- Title      : WR Switch bare sdb package
-- Project    : White Rabbit Switch
-------------------------------------------------------------------------------
-- File       : wrs_sdb_pkg.vhd
-- Author     : Grzegorz Daniluk
-- Company    : CERN BE-CO-HT
-- Created    : 2014-09-16
-- Last update: 2014-09-16
-- Platform   : FPGA-generic
-- Standard   : VHDL
-------------------------------------------------------------------------------
-- Description:
-- Wishbone SDB package for WR Switch bare top
-------------------------------------------------------------------------------
--
-- Copyright (c) 2014 CERN / BE-CO-HT
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

use work.wishbone_pkg.all;
use work.wrcore_pkg.all;
use work.endpoint_pkg.all;
use work.synthesis_descriptor.all;

package wrs_sdb_pkg is

  -- missing descriptors here
  constant c_xwb_tics_sdb : t_sdb_device := (
    abi_class     => x"0000",
    abi_ver_major => x"01",
    abi_ver_minor => x"01",
    wbd_endian    => c_sdb_endian_big,
    wbd_width     => x"7",
    sdb_component => (
      addr_first  => x"0000000000000000",
      addr_last   => x"00000000000000ff",
      product     => (
        vendor_id => x"000000000000CE42",  -- CERN
        device_id => x"57494266",          -- echo -n "xwb_tics" | md5sum - | cut -c1-8
        version   => x"00000001",
        date      => x"20140916",
        name      => "WB Simple Timer    ")));

  constant c_xwrsw_nic_sdb : t_sdb_device := (
    abi_class => x"0000",
    abi_ver_major => x"01",
    abi_ver_minor => x"01",
    wbd_endian    => c_sdb_endian_big,
    wbd_width     => x"7",
    sdb_component => (
      addr_first  => x"0000000000000000",
      addr_last   => x"000000000000ffff",
      product     => (
        vendor_id => x"000000000000CE42",  -- CERN
        device_id => x"ba07b9d3",          -- echo -n "xwrsw_nic" | md5sum - | cut -c1-8
        version   => x"00000001",
        date      => x"20140916",
        name      => "WRSW NIC           ")));

  constant c_xwrsw_txtsu_sdb : t_sdb_device := (
    abi_class => x"0000",
    abi_ver_major => x"01",
    abi_ver_minor => x"01",
    wbd_endian    => c_sdb_endian_big,
    wbd_width     => x"7",
    sdb_component => (
      addr_first  => x"0000000000000000",
      addr_last   => x"00000000000000ff",
      product     => (
        vendor_id => x"000000000000CE42",  -- CERN
        device_id => x"a027fd6e",          -- echo -n "xwrsw_txtsu" | md5sum - | cut -c1-8
        version   => x"00000001",
        date      => x"20140916",
        name      => "WR Tx Tstamp Unit  ")));

  constant c_xwrsw_rtu_sdb : t_sdb_device := (
    abi_class => x"0000",
    abi_ver_major => x"01",
    abi_ver_minor => x"01",
    wbd_endian    => c_sdb_endian_big,
    wbd_width     => x"7",
    sdb_component => (
      addr_first  => x"0000000000000000",
      addr_last   => x"000000000000ffff",
      product     => (
        vendor_id => x"000000000000CE42",  -- CERN
        device_id => x"2e8524c7",          -- echo -n "xwrsw_rtu" | md5sum - | cut -c1-8
        version   => x"00000001",
        date      => x"20140916",
        name      => "WRSW RTU           ")));

  constant c_xwb_simple_pwm_sdb : t_sdb_device := (
    abi_class => x"0000",
    abi_ver_major => x"01",
    abi_ver_minor => x"01",
    wbd_endian    => c_sdb_endian_big,
    wbd_width     => x"7",
    sdb_component => (
      addr_first  => x"0000000000000000",
      addr_last   => x"00000000000000ff",
      product     => (
        vendor_id => x"000000000000CE42",  -- CERN
        device_id => x"91446863",          -- echo -n "xwb_simple_pwm" | md5sum - | cut -c1-8
        version   => x"00000001",
        date      => x"20140916",
        name      => "WB Simple PWM      ")));

  constant c_xwrsw_tru_sdb : t_sdb_device := (
    abi_class => x"0000",
    abi_ver_major => x"01",
    abi_ver_minor => x"01",
    wbd_endian    => c_sdb_endian_big,
    wbd_width     => x"7",
    sdb_component => (
      addr_first  => x"0000000000000000",
      addr_last   => x"00000000000000ff",
      product     => (
        vendor_id => x"000000000000CE42",  -- CERN
        device_id => x"53bf6e6f",          -- echo -n "xwrsw_tru" | md5sum - | cut -c1-8
        version   => x"00000001",
        date      => x"20140916",
        name      => "WRSW TRU           ")));

  constant c_xwrsw_tatsu_sdb : t_sdb_device := (
    abi_class => x"0000",
    abi_ver_major => x"01",
    abi_ver_minor => x"01",
    wbd_endian    => c_sdb_endian_big,
    wbd_width     => x"7",
    sdb_component => (
      addr_first  => x"0000000000000000",
      addr_last   => x"00000000000000ff",
      product     => (
        vendor_id => x"000000000000CE42",  -- CERN
        device_id => x"0c0a9cc1",          -- echo -n "xwrsw_tatsu" | md5sum - | cut -c1-8
        version   => x"00000001",
        date      => x"20140916",
        name      => "WRSW TATSU         ")));

  constant c_xwrsw_pstats_sdb : t_sdb_device := (
    abi_class => x"0000",
    abi_ver_major => x"01",
    abi_ver_minor => x"01",
    wbd_endian    => c_sdb_endian_big,
    wbd_width     => x"7",
    sdb_component => (
      addr_first  => x"0000000000000000",
      addr_last   => x"00000000000000ff",
      product     => (
        vendor_id => x"000000000000CE42",  -- CERN
        device_id => x"6c21e54e",          -- echo -n "xwrsw_pstats" | md5sum - | cut -c1-8
        version   => x"00000001",
        date      => x"20140916",
        name      => "WRSW PSTATS        ")));

  constant c_xwrsw_hwiu_sdb : t_sdb_device := (
    abi_class => x"0000",
    abi_ver_major => x"01",
    abi_ver_minor => x"01",
    wbd_endian    => c_sdb_endian_big,
    wbd_width     => x"7",
    sdb_component => (
      addr_first  => x"0000000000000000",
      addr_last   => x"00000000000000ff",
      product     => (
        vendor_id => x"000000000000CE42",  -- CERN
        device_id => x"11f10474",          -- echo -n "xwrsw_hwiu" | md5sum - | cut -c1-8
        version   => x"00000001",
        date      => x"20140916",
        name      => "WRSW HWIU          ")));

  -- RT subsystem crossbar
  constant c_rtbar_layout : t_sdb_record_array(6 downto 0) :=
    (0 => f_sdb_embed_device(f_xwb_dpram(16384),   x"00000000"),
     1 => f_sdb_embed_device(c_wrc_periph1_sdb,    x"00010000"), --UART
     2 => f_sdb_embed_device(c_xwr_softpll_ng_sdb, x"00010100"), --SoftPLL
     3 => f_sdb_embed_device(c_xwb_spi_sdb,        x"00010200"), --SPI
     4 => f_sdb_embed_device(c_xwb_gpio_port_sdb,  x"00010300"), --GPIO
     5 => f_sdb_embed_device(c_xwb_tics_sdb,       x"00010400"), --TICS
     6 => f_sdb_embed_device(c_xwr_pps_gen_sdb,    x"00010500"));--PPSgen
  constant c_rtbar_sdb_address : t_wishbone_address := x"00010600";
  constant c_rtbar_bridge_sdb : t_sdb_bridge :=
    f_xwb_bridge_layout_sdb(true, c_rtbar_layout, c_rtbar_sdb_address);

  -- EP crossbar
  constant c_epbar_layout : t_sdb_record_array(17 downto 0) :=
    (0  => f_sdb_embed_device(c_xwr_endpoint_sdb, x"00000000"),
     1  => f_sdb_embed_device(c_xwr_endpoint_sdb, x"00000400"),
     2  => f_sdb_embed_device(c_xwr_endpoint_sdb, x"00000800"),
     3  => f_sdb_embed_device(c_xwr_endpoint_sdb, x"00000c00"),
     4  => f_sdb_embed_device(c_xwr_endpoint_sdb, x"00001000"),
     5  => f_sdb_embed_device(c_xwr_endpoint_sdb, x"00001400"),
     6  => f_sdb_embed_device(c_xwr_endpoint_sdb, x"00001800"),
     7  => f_sdb_embed_device(c_xwr_endpoint_sdb, x"00001c00"),
     8  => f_sdb_embed_device(c_xwr_endpoint_sdb, x"00002000"),
     9  => f_sdb_embed_device(c_xwr_endpoint_sdb, x"00002400"),
     10 => f_sdb_embed_device(c_xwr_endpoint_sdb, x"00002800"),
     11 => f_sdb_embed_device(c_xwr_endpoint_sdb, x"00002c00"),
     12 => f_sdb_embed_device(c_xwr_endpoint_sdb, x"00003000"),
     13 => f_sdb_embed_device(c_xwr_endpoint_sdb, x"00003400"),
     14 => f_sdb_embed_device(c_xwr_endpoint_sdb, x"00003800"),
     15 => f_sdb_embed_device(c_xwr_endpoint_sdb, x"00003c00"),
     16 => f_sdb_embed_device(c_xwr_endpoint_sdb, x"00004000"),
     17 => f_sdb_embed_device(c_xwr_endpoint_sdb, x"00004400"));
  constant c_epbar_sdb_address : t_wishbone_address := x"00004800";
  constant c_epbar_bridge_sdb : t_sdb_bridge :=
    f_xwb_bridge_layout_sdb(true, c_epbar_layout, c_epbar_sdb_address);

  -- WRS main crossbar
  constant c_layout : t_sdb_record_array(12+4 downto 0) :=
    (0  => f_sdb_embed_bridge(c_rtbar_bridge_sdb,   x"00000000"), --RT subsystem
     1  => f_sdb_embed_device(c_xwrsw_nic_sdb,      x"00020000"), --NIC
     2  => f_sdb_embed_bridge(c_epbar_bridge_sdb,   x"00030000"), --Endpoints
     3  => f_sdb_embed_device(c_xwb_vic_sdb,        x"00050000"), --VIC
     4  => f_sdb_embed_device(c_xwrsw_txtsu_sdb,    x"00051000"), --Txtsu
     5  => f_sdb_embed_device(c_xwrsw_rtu_sdb,      x"00060000"), --RTU
     6  => f_sdb_embed_device(c_xwb_gpio_port_sdb,  x"00053000"), --GPIO
     7  => f_sdb_embed_device(c_xwb_i2c_master_sdb, x"00054000"), --I2C
     8  => f_sdb_embed_device(c_xwb_simple_pwm_sdb, x"00055000"), --PWM
     9  => f_sdb_embed_device(c_xwrsw_tru_sdb,      x"00056000"), --TRU
     10 => f_sdb_embed_device(c_xwrsw_tatsu_sdb,    x"00057000"), --TATSU
     11 => f_sdb_embed_device(c_xwrsw_pstats_sdb,   x"00058000"), --PSTATS
     12 => f_sdb_embed_device(c_xwrsw_hwiu_sdb,     x"00059000"), --HWIU
     13 => f_sdb_embed_repo_url(c_sdb_repo_url),
     14 => f_sdb_embed_synthesis(c_sdb_top_syn_info),
     15 => f_sdb_embed_synthesis(c_sdb_general_cores_syn_info),
     16 => f_sdb_embed_synthesis(c_sdb_wr_cores_syn_info));
  constant c_sdb_address  : t_wishbone_address := x"00070000";

end wrs_sdb_pkg;
