-------------------------------------------------------------------------------
-- Title      : Generic platform-independent sychronous FIFO
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : generic_sync_fifo.vhd
-- Author     : Tomasz Wlostowski
-- Company    : CERN BE-CO-HT
-- Created    : 2009-06-16
-- Last update: 2010-06-11
-- Platform   : 
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: Sync FIFO design for Altera  FPGAs
-------------------------------------------------------------------------------
-- Copyright (c) 2009 
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author  Description
-- 2009-06-16  1.0      slayer  Created
-------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;

library altera_mf;
use altera_mf.all;

entity generic_sync_fifo is
  generic (
    g_width      : natural := 8;
    g_depth      : natural := 32;
    g_depth_log2 : natural := 5
    );

  port
    (
      clk_i   : in std_logic;
      clear_i : in std_logic := '0';

      wr_req_i : in std_logic;
      d_i      : in std_logic_vector (g_width-1 downto 0);

      rd_req_i : in  std_logic;
      q_o      : out std_logic_vector (g_width-1 downto 0);

      empty_o : out std_logic;
      full_o  : out std_logic;
      usedw_o : out std_logic_vector(g_depth_log2-1 downto 0)
      );

end generic_sync_fifo;


architecture SYN of generic_sync_fifo is

  component scfifo
    generic (
      add_ram_output_register : string;
      intended_device_family  : string;
      lpm_numwords            : natural;
      lpm_showahead           : string;
      lpm_type                : string;
      lpm_width               : natural;
      lpm_widthu              : natural;
      overflow_checking       : string;
      underflow_checking      : string;
      use_eab                 : string
      );
    port (
      usedw : out std_logic_vector (g_depth_log2-1 downto 0);
      rdreq : in  std_logic;
      sclr  : in  std_logic;
      empty : out std_logic;
      clock : in  std_logic;
      q     : out std_logic_vector (g_width-1 downto 0);
      wrreq : in  std_logic;
      data  : in  std_logic_vector (g_width-1 downto 0);
      full  : out std_logic
      );
  end component;


begin

  scfifo_component : scfifo
    generic map (
      add_ram_output_register => "OFF",
      intended_device_family  => "Cyclone III",
      lpm_numwords            => g_depth,
      lpm_showahead           => "OFF",
      lpm_type                => "scfifo",
      lpm_width               => g_width,
      lpm_widthu              => g_depth_log2,
      overflow_checking       => "ON",
      underflow_checking      => "ON",
      use_eab                 => "ON")
    port map (
      rdreq   => rd_req_i,
      sclr    => clear_i,
      clock   => clk_i,
      wrreq   => wr_req_i,
      data    => d_i,
      usedw => usedw_o,
      empty   => empty_o,
      q       => q_o,
      full    => full_o);


end SYN;

