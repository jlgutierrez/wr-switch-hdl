-------------------------------------------------------------------------------
-- Title      : Generic platform-independent asychronous (2-stage) FIFO
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : generic_async_fifo_2stage.vhd
-- Author     : Tomasz Wlostowski
-- Company    : CERN BE-CO-HT
-- Created    : 2009-06-16
-- Last update: 2010-06-11
-- Platform   : 
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: Async FIFO design for Altera
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

entity generic_async_fifo_2stage is
  generic (
    g_width                : natural := 8;
    g_depth                : natural := 32;
    g_almostfull_bit_threshold : natural := 3
    );


  port
    (
      clear_i       : in  std_logic := '0';
      d_i           : in  std_logic_vector (g_width-1 downto 0);
      rd_clk_i      : in  std_logic;
      rd_req_i      : in  std_logic;
      wr_clk_i      : in  std_logic;
      wr_req_i      : in  std_logic;
      q_o           : out std_logic_vector (g_width-1 downto 0);
      rd_empty_o    : out std_logic;
      wr_full_o     : out std_logic;
      almost_full_o : out std_logic
      );

end generic_async_fifo_2stage;


architecture SYN of generic_async_fifo_2stage is

  function log2 (A : natural) return natural is
  begin
    for I in 1 to 64 loop               -- Works for up to 32 bits
      if (2**I > A) then
        return(I-1);
      end if;
    end loop;
    return(63);
  end function log2;


  constant c_mask_value  : std_logic_vector(g_almostfull_bit_threshold -1 downto 0) := (others => '1');

  signal sub_wire0  : std_logic;
  signal sub_wire1  : std_logic;
  signal sub_wire2  : std_logic_vector (g_width-1 downto 0);
  signal words_used : std_logic_vector(log2(g_depth)-1 downto 0);

  component dcfifo
    generic (
      intended_device_family : string;
      lpm_numwords           : natural;
      lpm_showahead          : string;
      lpm_type               : string;
      lpm_width              : natural;
      lpm_widthu             : natural;
      overflow_checking      : string;
      rdsync_delaypipe       : natural;
      underflow_checking     : string;
      use_eab                : string;
      write_aclr_synch       : string;
      wrsync_delaypipe       : natural
      );
    port (
      wrclk   : in  std_logic;
      rdempty : out std_logic;
      rdreq   : in  std_logic;
      aclr    : in  std_logic;
      wrfull  : out std_logic;
      rdclk   : in  std_logic;
      q       : out std_logic_vector (g_width-1 downto 0);
      wrreq   : in  std_logic;
      data    : in  std_logic_vector (g_width-1 downto 0);
      rdusedw : out std_logic_vector (log2(g_depth)-1 downto 0)
      );
  end component;

begin
  rd_empty_o <= sub_wire0;
  wr_full_o  <= sub_wire1;
  q_o        <= sub_wire2(g_width-1 downto 0);



  dcfifo_component : dcfifo
    generic map (
      intended_device_family => "Cyclone III",
      lpm_numwords           => g_depth,
      lpm_showahead          => "OFF",
      lpm_type               => "dcfifo",
      lpm_width              => g_width,
      lpm_widthu             => log2(g_depth),
      overflow_checking      => "OFF",
      rdsync_delaypipe       => 4,
      underflow_checking     => "OFF",
      use_eab                => "ON",
      write_aclr_synch       => "OFF",
      wrsync_delaypipe       => 4
      )
    port map (
      wrclk   => wr_clk_i,
      rdreq   => rd_req_i,
      aclr    => clear_i,
      rdclk   => rd_clk_i,
      wrreq   => wr_req_i,
      data    => d_i,
      rdempty => sub_wire0,
      wrfull  => sub_wire1,
      q       => sub_wire2,
      rdusedw => words_used
      );

  almost_full_check : process (wr_clk_i, clear_i)
  begin  -- process almost_full_check
    if clear_i = '1' then               -- asynchronous reset (active low)
      almost_full_o <= '0';
    elsif wr_clk_i'event and wr_clk_i = '1' then  -- rising clock edge
      if words_used(words_used'left downto words_used'left - g_almostfull_bit_threshold + 1) = c_mask_value then
        almost_full_o <= '1';
      else
        almost_full_o <= '0';
      end if;
    end if;
  end process almost_full_check;



end SYN;

