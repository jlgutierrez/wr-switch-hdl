-------------------------------------------------------------------------------
-- Title        : Asynchronous Multi Port Memory - write path
-- Project      : White Rabbit Switch
-------------------------------------------------------------------------------
-- File         : mpm_write_path.vhd
-- Author       : Tomasz Włostowski
-- Company      : CERN BE-CO-HT
-- Created      : 2012-01-30
-- Last update  : 2013-11-07
-- Platform     : FPGA-generic
-- Standard     : VHDL'93
-- Dependencies : genram_pkg, gencores_pkg, mpm_async_grow_fifo, mpm_pipelined_mux,
--                mpm_private_pkg.
-------------------------------------------------------------------------------
-- Description: N-port MPM write path.
-------------------------------------------------------------------------------
--
-- Copyright (c) 2012 - 2013 CERN / BE-CO-HT
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
-- 2012-01-30  1.0      twlostow        Created
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.mpm_private_pkg.all;

use work.gencores_pkg.all;              -- for f_rr_arbitrate
use work.genram_pkg.all;                -- for f_log2_size

entity mpm_write_path is
  
  generic (
    g_data_width           : integer := 8;
    g_ratio                : integer := 6;
    g_page_size            : integer := 66;
    g_num_pages            : integer := 2048;
    g_num_ports            : integer := 19;
    g_fifo_size            : integer := 8;
    g_page_addr_width      : integer := 11;
    g_partial_select_width : integer := 1
    );

  port(
    -- I/O ports clock (slow)
    clk_io_i   : in std_logic;
    -- Memory/Core clock (fast)
    clk_core_i : in std_logic;

    rst_n_io_i   : in std_logic;
    rst_n_core_i : in std_logic;

-- read-write ports I/F (streaming)
    wport_d_i       : in  std_logic_vector (g_num_ports * g_data_width -1 downto 0);
    wport_dvalid_i  : in  std_logic_vector (g_num_ports-1 downto 0);
    wport_dlast_i   : in  std_logic_vector (g_num_ports-1 downto 0);

    wport_pg_addr_i : in  std_logic_vector (g_num_ports * g_page_addr_width -1 downto 0);
    wport_pg_req_o  : out std_logic_vector(g_num_ports -1 downto 0);
    wport_dreq_o    : out std_logic_vector (g_num_ports-1 downto 0);

-- F. B. Memory output
    fbm_addr_o : out std_logic_vector(f_log2_size(g_num_pages * g_page_size / g_ratio)-1 downto 0);
    fbm_data_o : out std_logic_vector(g_ratio * g_data_width -1 downto 0);
    fbm_we_o   : out std_logic
    );

end mpm_write_path;

architecture rtl of mpm_write_path is

  constant c_line_size_width     : integer := f_log2_size(g_page_size / g_ratio);
  constant c_fbm_data_width      : integer := g_ratio * g_data_width;
  constant c_fbm_entries         : integer := g_num_pages * g_page_size / g_ratio;
  constant c_fbm_addr_width      : integer := f_log2_size(c_fbm_entries);
  constant c_fifo_sideband_width : integer := c_fbm_addr_width;

  type t_mpm_write_port is record
    -- data input
    d       : std_logic_vector(g_data_width-1 downto 0);
    -- 1: got valid data word on d
    d_valid : std_logic;
    -- 1: end-of-packet
    d_last  : std_logic;
    -- address of the page to be written to (important only on the 1st write to
    -- the page)
    pg_addr : std_logic_vector(g_page_addr_width-1 downto 0);
    pg_req  : std_logic;
    dreq    : std_logic;
  end record;


  type t_wport_state is record
    -- clk_io_i domain
    pg_addr     : unsigned(g_page_addr_width-1 downto 0);
    pg_offset   : unsigned(c_line_size_width-1 downto 0);
    word_count  : unsigned(f_log2_size(g_ratio)-1 downto 0);
    fbm_addr_in : unsigned(c_fbm_addr_width-1 downto 0);
    fifo_full   : std_logic;
    fifo_we     : std_logic;
    fifo_align  : std_logic;

    -- clk_core_i domain
    fifo_rd      : std_logic;
    fifo_empty   : std_logic;
    fifo_q       : std_logic_vector(c_fbm_data_width -1 downto 0);
    fbm_addr_out : std_logic_vector(c_fbm_addr_width-1 downto 0);
    grant_d      : std_logic_vector(3 downto 0);
  end record;

  type t_mpm_write_port_array is array (integer range <>) of t_mpm_write_port;
  type t_wport_state_array is array(integer range <>) of t_wport_state;

  signal wstate : t_wport_state_array(g_num_ports-1 downto 0);
  signal wport  : t_mpm_write_port_array(g_num_ports-1 downto 0);


  signal arb_req, arb_grant, arb_grant_sreg : std_logic_vector(g_num_ports-1 downto 0);

  signal wr_mux_a_in : std_logic_vector(g_num_ports * c_fbm_addr_width -1 downto 0);
  signal wr_mux_d_in : std_logic_vector(g_num_ports * c_fbm_data_width -1 downto 0);
  signal fbm_we_d    : std_logic_vector(2 downto 0);

  signal wr_mux_sel : std_logic_vector(g_num_ports-1 downto 0);




  
begin  -- rtl

-- I/O structure serialization/deserialization
  gen_serialize_ios : for i in 0 to g_num_ports-1 generate
    wport(i).d        <= f_slice(wport_d_i, i, g_data_width);
    wport(i).d_valid  <= wport_dvalid_i(i);
    wport(i).d_last   <= wport_dlast_i(i);
    wport(i).pg_addr  <= f_slice(wport_pg_addr_i, i, g_page_addr_width);
    wport_dreq_o(i)   <= wport(i).dreq;
    wport_pg_req_o(i) <= wport(i).pg_req;
  end generate gen_serialize_ios;

  -----------------------------------------------------------------------------
  -- Write side logic
  -----------------------------------------------------------------------------
  -----------------------------------------------------------------------------
  gen_input_arbiter_ios : for i in 0 to g_num_ports-1 generate

    -- arbiter request vector generation: If there is any data in the input
    -- FIFOs, it's request line becomes active. Another requst from the same
    -- port can be served 3 cycles later (pipeline delay)
    arb_req(i) <= not wstate(i).fifo_empty and not (wstate(i).grant_d(0) or wstate(i).grant_d(1) or wstate(i).grant_d(2));

    wstate(i).grant_d(0) <= arb_grant(i);

    -- Delay the grant signal to generate enables for each pipeline stage
    process(clk_core_i)
    begin
      if rising_edge(clk_core_i) then
        if rst_n_core_i = '0' then
          wstate(i).grant_d(3 downto 1) <= (others => '0');
        else
          wstate(i).grant_d(3) <= wstate(i).grant_d(2);
          wstate(i).grant_d(2) <= wstate(i).grant_d(1);
          wstate(i).grant_d(1) <= wstate(i).grant_d(0);
        end if;
      end if;
    end process;
  end generate gen_input_arbiter_ios;


--   U_RR_Arbiter: gc_rr_arbiter
--     generic map (
--       g_size => g_num_ports)
--     port map (
--       clk_i    => clk_core_i,
--       rst_n_i  => rst_n_core_i,
--       req_i    => arb_req,
--       grant_o  => arb_grant);
--   
     -- The actual round-robin arbiter.
--     p_input_arbiter : process(clk_core_i)
--     begin
--      if rising_edge(clk_core_i) then
--        if rst_n_core_i = '0' then
--          arb_grant <= (others => '0');
--        else
--          f_rr_arbitrate(arb_req, arb_grant, arb_grant);
--        end if;
--      end if;
--     end process;


  p_input_arbiter : process(clk_core_i)
  begin
   if rising_edge(clk_core_i) then
     if rst_n_core_i = '0' then
       arb_grant                              <= (others => '0');
       arb_grant_sreg(g_num_ports-1 downto 1) <= (others => '0');
       arb_grant_sreg(0)                      <= '1';
     else
       -- spartan arbieter
       arb_grant_sreg <= arb_grant_sreg(g_num_ports-2 downto 0) & arb_grant_sreg(g_num_ports-1); -- shift
       arb_grant      <= arb_grant_sreg and arb_req;
     end if;
   end if;
  end process;
  


  -- write side address counter. Calculates the address of the entry in the F.B. Memory
  -- the incoming data shall be written to.
  -- It contains two nested counters:
  -- - word_count, which counts the number of words in the line of the FBM currently
  --   being written. Each line contains g_ratio words of g_data_width.
  -- - pg_offset, which counts up every time the previous counter overflow,
  --   addressing subsequent cells of the FBM.
  -- When we reach the end of the current page, both counters are reset, so we
  -- can proceed with the next page.

  gen_input_addr_counters : for i in 0 to g_num_ports-1 generate
    process(clk_io_i)
    begin
      if rising_edge(clk_io_i) then
-- Reset or last data transfer in the frame? Go to the beginning of the page.
        if (rst_n_io_i = '0') or (wport(i).d_valid = '1' and wport(i).d_last = '1') then
          wstate(i).pg_offset  <= (others => '0');
          wstate(i).word_count <= (others => '0');
        else
          if(wport(i).d_valid = '1') then
            if(wstate(i).word_count = g_ratio-1) then
              wstate(i).word_count <= (others => '0');

              -- end-of-page?
              if(wstate(i).pg_offset = g_page_size / g_ratio - 1) then
                wstate(i).pg_offset <= (others => '0');
              else
                wstate(i).pg_offset <= wstate(i).pg_offset + 1;
              end if;
            else
              wstate(i).word_count <= wstate(i).word_count + 1;
            end if;
          end if;
        end if;
      end if;
    end process;

    -- Generate a page request signal on the last word of the current page.
    -- This way, the source won't have to keep track of the words written per
    -- each page and so will save some resources.
    wport(i).pg_req <= '1' when (wport(i).d_valid = '1'
                                 and wstate(i).pg_offset = g_page_size/g_ratio-1
                                 and wstate(i).word_count = g_ratio -1)
                       else '0';

    -- combine the current page address and page-internal offset into final
    -- FBM address
    wstate(i).fbm_addr_in <= resize(unsigned(wport(i).pg_addr) * (g_page_size/g_ratio) + wstate(i).pg_offset, c_fbm_addr_width);
  end generate gen_input_addr_counters;


  -- Input FIFO blocks
  gen_input_fifos : for i in 0 to g_num_ports-1 generate

    -- Dual-clock "growing" FIFO. Takes N bit words in clk_io_i clock domain and outputs (N*M)
    -- parallelized words in clk_core_i domain. This allows for significant
    -- reduction of the size of multipumped memory input registers, but a
    -- higher core clock frequency is required. In our case N = g_data_width
    -- and M = g_ratio.
    --
    -- The FIFO also provides a "sideband" channel working
    -- synchronously with the wide port and used to pass FBM addresses. Thanks
    -- to that, the fast clock domain only does the multiplexing.

    U_Input_FIFOx : mpm_async_grow_fifo
      generic map (
        g_width          => g_data_width,
        g_ratio          => g_ratio,
        g_size           => g_fifo_size,
        g_sideband_width => c_fifo_sideband_width)
      port map (
        rst_n_a_i => rst_n_core_i,
        clk_wr_i  => clk_io_i,
        clk_rd_i  => clk_core_i,

        we_i    => wstate(i).fifo_we,
        align_i => wstate(i).fifo_align,
        d_i     => wport(i).d,

        side_i => std_logic_vector(wstate(i).fbm_addr_in),
        side_o => wstate(i).fbm_addr_out,

        rd_i    => wstate(i).fifo_rd,
        q_o     => wstate(i).fifo_q,
        full_o  => wstate(i).fifo_full,
        empty_o => wstate(i).fifo_empty);


    wport(i).dreq        <= not wstate(i).fifo_full;
    wstate(i).fifo_we    <= wport(i).d_valid;
    wstate(i).fifo_align <= wport(i).d_last;
    wstate(i).fifo_rd    <= wstate(i).grant_d(0);  -- and not wstate(i).grant_d(1);
  end generate gen_input_fifos;


  gen_mux_inputs : for i in 0 to g_num_ports-1 generate
    wr_mux_d_in(c_fbm_data_width * (i + 1) - 1 downto c_fbm_data_width * i) <= wstate(i).fifo_q;
    wr_mux_a_in(c_fbm_addr_width * (i + 1) - 1 downto c_fbm_addr_width * i) <= wstate(i).fbm_addr_out;
    wr_mux_sel(i)                                                           <= wstate(i).grant_d(1);
  end generate gen_mux_inputs;

  U_Data_Mux : mpm_pipelined_mux
    generic map (
      g_width  => c_fbm_data_width,
      g_inputs => g_num_ports)
    port map (
      clk_i   => clk_core_i,
      rst_n_i => rst_n_core_i,
      d_i     => wr_mux_d_in,
      q_o     => fbm_data_o,
      sel_i   => wr_mux_sel);

  U_WR_Address_Mux : mpm_pipelined_mux
    generic map (
      g_width  => c_fbm_addr_width,
      g_inputs => g_num_ports)
    port map (
      clk_i   => clk_core_i,
      rst_n_i => rst_n_core_i,
      d_i     => wr_mux_a_in,
      q_o     => fbm_addr_o,
      sel_i   => wr_mux_sel);

  
  p_write_pipe : process(clk_core_i)
  begin
    if rising_edge(clk_core_i) then
      if rst_n_core_i = '0' then
        fbm_we_d <= (others => '0');
      else
        if(unsigned(wr_mux_sel) /= 0) then
          fbm_we_d(0) <= '1';
        else
          fbm_we_d(0) <= '0';
        end if;
        fbm_we_d(1) <= fbm_we_d(0);
        fbm_we_d(2) <= fbm_we_d(1);
      end if;
    end if;
  end process;


  fbm_we_o <= fbm_we_d(1);
  

end rtl;
