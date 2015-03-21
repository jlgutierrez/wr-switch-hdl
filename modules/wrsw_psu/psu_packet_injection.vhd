-------------------------------------------------------------------------------
-- Title      : TX packet injection unit with pipelined WB I/F
-- Project    : White Rabbit
-------------------------------------------------------------------------------
-- File       : psu_packet_injection.vhd
-- Author     : Maciej Lipinski, Tomasz Wlostowski
-- Company    : CERN BE-CO-HT
-- Created    : 2012-11-01
-- Last update: 2015-03-18
-- Platform   : FPGA-generic
-- Standard   : VHDL'93
-------------------------------------------------------------------------------
-- Description: 
-- This packet injection unit is based on ep_tx_packet_injection.vhd but it
-- is adapted to speak pipelined WB
-- 
-- Asynchronously sends pre-defined packets upon a hardware request.
-- Packet contents are defined in a buffer accessible via Wishbone. The buffer
-- is shared with the TX VLAN unit and can contain templates of up to 8 packets
-- of up to 128 bytes of size. It is possible to replace a selected 16-bit word
-- within each template with a user-provided value.
-------------------------------------------------------------------------------
--
-- Copyright (c) 2012 CERN
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
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author          Description
-- 2012-11-01  1.0      twlostow          Created
-- 2013-03-12  1.1      mlipinsk          added empty-template protaciton 
--                                        prepared signals for RMON
-- 2015-03-18  2.0      mlipinsk          pipelined WB version
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.endpoint_private_pkg.all;

entity psu_packet_injection is

  port
    (
      clk_sys_i : in std_logic;
      rst_n_i   : in std_logic;


      src_i : in  t_wrf_source_in;
      src_o : out t_wrf_source_out;

      snk_i : in  t_wrf_sink_in;
      snk_o : out t_wrf_sink_out;

      inject_req_i        : in  std_logic;
      inject_ready_o      : out std_logic;
      inject_packet_sel_i : in  std_logic;
      inject_clockClass_i : in  std_logic_vector(15 downto 0);
      inject_port_index_i : in  std_logic_vector( 4 downto 0);
      
      mem_addr_o : out std_logic_vector(9 downto 0);
      mem_data_i : in  std_logic_vector(17 downto 0);
      mem_read_o : out std_logic
      );

end psu_packet_injection;

architecture rtl of psu_packet_injection is

  type t_state is (WAIT_IDLE, SOF, DO_INJECT, EOF);

  alias validData     : std_logic is mem_data_i(16);
  alias startOfPTP    : std_logic is mem_data_i(17);

  signal state        : t_state;
  signal counter      : unsigned(8 downto 0);
  signal announce_cnt : unsigned(6 downto 0);

  signal within_packet : std_logic;
  signal select_inject : std_logic;

  signal inj_src            : t_wrf_source_out;
  signal inj_stb            : std_logic;
  signal inject_req_latched : std_logic;
  signal inject_done        : std_logic; -- ML: indicates that requrested injection was successful
  
  signal cyc_d              : std_logic;
  signal rd_port_info_addr  : std_logic;
  signal def_status_reg : t_wrf_status_reg;
  
begin  -- rtl

  snk_o.stall                 <= '1' when (state = DO_INJECT)                 else src_i.stall;
  inject_done                 <= '1' when (state = EOF and src_i.stall = '0') else '0';
  within_packet               <= snk_i.cyc;

  def_status_reg.has_smac <= '1';
  def_status_reg.has_crc  <= '0';
  def_status_reg.error    <= '0';
  def_status_reg.is_hp    <= '0';

  p_injection_request_ready : process(clk_sys_i)
  begin
    if rising_edge(clk_sys_i) then
      if rst_n_i = '0' then
        inject_ready_o     <= '1';
        inject_req_latched <= '0';
      else
        if(inject_req_i = '1') then
          inject_ready_o     <= '0';
          inject_req_latched <= '1';
        elsif(state = EOF and src_i.stall = '0' ) then                     
          inject_ready_o     <= '1';
          inject_req_latched <= '0';
        end if;
      end if;
    end if;
  end process;

  p_injection_fsm : process(clk_sys_i)
  begin
    if rising_edge(clk_sys_i) then
      if rst_n_i = '0' then
        state             <= WAIT_IDLE;
        select_inject     <= '0';
        no_template_error <= '0';
        inj_src.cyc       <= '0';
        inj_stb           <= '0';
        inj_src.we        <= '0'; 
      else
        case state is
          when WAIT_IDLE =>
            inj_src.cyc       <= '0';
            inj_stb           <= '0';
            inj_src.we        <= '0';
            no_template_error <= '0';

            if(inject_req_i = '1') then --ML: we make sure that we remember the packet_sel_i 
                                        --    only when req_i HIGH
              counter(8)          <= inject_packet_sel_i;
              counter(7 downto 0) <= (others => '0');
              announce_cnt        <= (others => '0');
            end if;

            if(within_packet = '0' and inject_req_latched = '1' and no_template_error = '0') then
              state         <= SOF;
              select_inject <= '1';
            else
              select_inject <= '0';
            end if;

          when SOF =>
            if(src_i.stall = '0') then
              inj_src.cyc <= '1';
              state       <= TX_STATUS;
            end if;

          when TX_STATUS => 

            inj_src.adr     <= c_WRF_STATUS;
            if(inj_src.stall = '0') then
              inj_stb        <= '1';
              state          <= DO_INJECT_HEADERS;
            else
              inj_stb        <= '0';
            end if;

          when DO_INJECT_HEADERS =>

            if(inj_src.stall = '0') then
              inj_stb        <= '1';
              counter        <= counter + 1;
            else
              inj_stb         <= '0';
            end if;

            if(first_word = '1' and template_first = '0') then -- ML: first word read
              first_word <= '0';
            end if;

            if(validData = '1' and startOfPTP = '1') then
              announce_cnt   <= announce_cnt + 1;
              state          <= DO_INJECT_START_PTP
              rd_port_info_addr  <= '1';
            end if;

         when DO_INJECT_START_PTP =>

            if(inj_src.stall = '0') then
              inj_stb        <= '1';
              announce_cnt   <= announce_cnt + 1;
              counter        <= counter + 1;
            else
              inj_stb        <= '0';
            end if;

            if(announce_cnt = 4) then
              state              <=  DO_INJECT_PORT_STUFF;
            end if;

         when DO_INJECT_PORT_STUFF =>
            
            if(inj_src.stall = '0') then
              inj_stb            <= '1';
              rd_port_info_addr  <= '1';
              announce_cnt       <= announce_cnt + 1;
              counter            <= counter + 1;
            else
              inj_stb            <= '0';
            end if;

            if(announce_cnt = 6) then
              state              <=  DO_INJECT_REST;
            end if;

         when DO_INJECT_REST =>

            if(inj_src.stall = '0') then
              inj_stb        <= '1';
              counter        <= counter + 1;
              announce_cnt   <= announce_cnt + 1;
            else
              inj_src.stb    <= '0';
            end if;

            if(inj_stb = '1' and validData = '0') then
              inj_stb           <= '0';
              state             <= EOF;
            end if;
            
          when EOF =>
            inj_src.cyc       <= '0';
            inj_stb           <= '0';
            if(src_i.stall = '0') then
              state           <= WAIT_IDLE;
              select_inject   <= '0'; 
            end if;
        end case;
      end if;
    end if;
  end process;

  -- the last word cannot be user-defined as we use the user bit to indicate  odd size
  inj_src.sel(1) <= '1';--template_user when (template_last = '1' and first_word = '0') else '1';
  inj_src.sel(0) <= '1';
  inj_src.stb    <= inj_stb and validData;
  inj_src.dat    <= inject_clockClass_i               when (inj_src.adr   = c_WRF_DATA   and 
                                                            announce_cnt  = 19)           else
                 f_marshall_wrf_status(def_status_reg)when (inj_src.adr   = c_WRF_STATUS) else
                 mem_data_i(15 downto 0) ;
  
  src_o      <= inj_src when select_inject = '1' else snk_i;
  snk_o      <= inj_src when select_inject = '1' else src_i;

  mem_addr_o <= '1' & "000" & inject_port_index_i when (announce_cnt = 3 or announce_cnt = 4) else
                '0' & std_logic_vector(counter);
  mem_read_o <= '0' when (state = WAIT_IDLE) else '1';
end rtl;
