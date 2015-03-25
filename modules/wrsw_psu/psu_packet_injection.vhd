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
use work.psu_pkg.all;
use work.wr_fabric_pkg.all;
-- use work.endpoint_private_pkg.all;

entity psu_packet_injection is
  generic(
    g_port_number      : integer:=18
  );
  port
    (
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
      
      -- keep valid when injecting
      inject_clockClass_i : in  std_logic_vector(15 downto 0);
      inject_port_mask_i  : in  std_logic_vector(g_port_number-1 downto 0);
      inject_pck_prio_i   : in  std_logic_vector( 2 downto 0);
      
      rd_ram_data_i       : in  std_logic_vector(17 downto 0)
      );

end psu_packet_injection;

architecture rtl of psu_packet_injection is

  type t_state is (WAIT_IDLE, TX_STATUS, SOF, DO_INJECT, EOF);

  alias validData     : std_logic is rd_ram_data_i(16);
  alias clockClass    : std_logic is rd_ram_data_i(17);

  signal state        : t_state;

  signal within_packet : std_logic;
  signal select_inject : std_logic;

  signal inj_src            : t_wrf_source_out;
  signal inj_snk            : t_wrf_sink_out;
  signal inj_stb            : std_logic;
  signal inject_req_latched : std_logic;
  signal inject_done        : std_logic; -- ML: indicates that requrested injection was successful

  signal def_status_reg     : t_wrf_status_reg;
  signal def_status_word    : std_logic_vector(15 downto 0);

  signal rtu_rsp_valid      : std_logic;
  
begin  -- rtl

  def_status_reg.has_smac <= '1';
  def_status_reg.has_crc  <= '0';
  def_status_reg.error    <= '0';
  def_status_reg.is_hp    <= '0';
  
  def_status_word         <=  f_marshall_wrf_status(def_status_reg);

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
        inj_src.cyc       <= '0';
        inj_stb           <= '0';
        inj_src.we        <= '0'; 
        rtu_rsp_valid     <= '0'; 
        inj_src.adr       <= (others =>'0');
      else

          if(state = WAIT_IDLE and within_packet = '0' and inject_req_latched = '1') then
            rtu_rsp_valid <= '1'; 
          elsif (rtu_rsp_valid = '1' and select_inject = '1' and rtu_rsp_ack_i = '1') then
              rtu_rsp_valid <= '0'; 
          end if; 

        case state is

          when WAIT_IDLE =>
            inj_src.cyc       <= '0';
            inj_stb           <= '0';
            inj_src.we        <= '0';

            if(within_packet = '0' and inject_req_latched = '1') then
              state         <= SOF;
              select_inject <= '1';
              inj_src.cyc   <= '1';
              inj_src.we    <= '1';
            else
              select_inject <= '0';
            end if;

          when SOF =>
            if(src_i.stall = '0') then
              inj_stb        <= '1';
              state          <= TX_STATUS;
              inj_src.adr    <= c_WRF_STATUS;
            end if;

          when TX_STATUS => 

            if(src_i.stall = '0') then
              state          <= DO_INJECT;
              inj_src.adr    <= c_WRF_DATA;
            else
              inj_stb        <= '0';
            end if;

         when DO_INJECT =>

            if(src_i.stall = '0') then
              inj_stb        <= '1';
            else
              inj_stb        <= '0';
            end if;

            if(inj_stb = '1' and validData = '0') then
              inj_stb           <= '0';
              state             <= EOF;
            end if;

          when EOF =>
            inj_src.cyc       <= '0';
            inj_src.we        <= '0';
            inj_stb           <= '0';
            if(src_i.stall = '0') then
              state           <= WAIT_IDLE;
              select_inject   <= '0'; 
            end if;
        end case;
      end if;
    end if;
  end process;

  inj_src.sel(1) <= '1';
  inj_src.sel(0) <= '1';
  inj_src.stb    <= '1' when (inj_stb = '1' and validData = '1') else '0';
  inj_src.dat    <= inject_clockClass_i when (inj_src.adr = c_WRF_DATA and clockClass = '1') else
                    def_status_word     when (inj_src.adr = c_WRF_STATUS)                    else
                    rd_ram_data_i(15 downto 0) ;
  
  
  inject_done         <= '1' when (state = EOF and src_i.stall = '0') else '0';
  within_packet       <= snk_i.cyc;

  inj_snk.ack         <= '0';
  inj_snk.stall       <= '1'                 when select_inject = '1' else src_i.stall;
  inj_snk.err         <= '0';
  inj_snk.rty         <= '0';

  src_o               <= inj_src             when select_inject = '1' else snk_i;
  snk_o               <= inj_snk             when select_inject = '1' else src_i;
  rtu_dst_port_mask_o <= inject_port_mask_i  when select_inject = '1' else rtu_dst_port_mask_i;
  rtu_prio_o          <= inject_pck_prio_i   when select_inject = '1' else rtu_prio_i;
  rtu_drop_o          <= '0'                 when select_inject = '1' else rtu_drop_i;
  rtu_rsp_valid_o     <= rtu_rsp_valid       when select_inject = '1' else rtu_rsp_valid_i;
  rtu_rsp_ack_o       <= rtu_rsp_ack_i;

--   mem_addr_o <= '1' & "000" & inject_port_index_i when (announce_cnt = 3 or announce_cnt = 4) else
--                 '0' & std_logic_vector(counter);
--   mem_read_o <= '0' when (state = WAIT_IDLE) else '1';
end rtl;
