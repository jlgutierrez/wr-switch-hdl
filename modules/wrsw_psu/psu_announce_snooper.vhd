-------------------------------------------------------------------------------
-- Title      : A module to snoop on PTP announce messaeges
-- Project    : White Rabbit
-------------------------------------------------------------------------------
-- File       : psu_announce_snooper.vhd
-- Author     : Maciej Lip0inski
-- Company    : CERN BE-CO-HT
-- Created    : 2015-03-17
-- Last update: 2015-03-17
-- Platform   : FPGA-generic
-- Standard   : VHDL'93
-------------------------------------------------------------------------------
-- Description: this module recognizes PTP Announce messages (over 802.3 Ethernet
-- and UDP) and extracts from them required info on the fly, i.e. sequence ID and
-- clock class)
-- useful: http://wiki.hevs.ch/uit/index.php5/Standards/Ethernet_PTP/frames
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
-- FIXME:
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author          Description
-- 2015-03-17  1.0      mlipinsk	    Created
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.psu_pkg.all;
use work.wr_fabric_pkg.all;

entity psu_announce_snooper is
  generic(
    g_port_number   : integer := 18;
    g_snoop_mode    : t_snoop_mode := TX_SEQ_ID_MODE);
  port (
    clk_sys_i : in std_logic;
    rst_n_i   : in std_logic;

    -- interface with NIC
    snk_i                 : in  t_wrf_sink_in;
    src_i                 : in  t_wrf_source_in;
    rtu_dst_port_mask_i   : in  std_logic_vector(g_port_number-1 downto 0);
    -- internal stuff

    -- access to BRAM with stored sourceClockIdentity, needed for recognision if the
    -- announce is frmo our current parent
    ptp_source_id_addr_o  : out std_logic_vector(7  downto 0); 
    ptp_source_id_data_i  :  in std_logic_vector(15 downto 0); 

    -- vector which indicates that announce msg was detected, it indicates on which port
    -- (if tx, it says to which port the frame was being sent, if rx, it says on which port
    -- the message was received)
    rxtx_detected_mask_o  : out std_logic_vector(g_port_number-1 downto 0);

    -- indicates the snooped announce seq_id (tx)
    seq_id_o              : out std_logic_vector(15 downto 0);
    seq_id_valid_o        : out std_logic;

    -- indicates the snooped clock_class (rx)
    clock_class_o         : out std_logic_vector(15 downto 0);
    clock_class_valid_o   : out std_logic
    );


end psu_announce_snooper;

architecture behavioral of psu_announce_snooper is

   type t_fsm_state is (
    WAIT_SOF,
    WAIT_DATA, 
    WAIT_ETHERTYPE,
    HAS_VTAG,
    WAIT_UDP_PROTO,
    WAIT_PTP_PORT,
    WAIT_MSG_TYPE,
    WAIT_SOURCE_PORT_ID,
    CHECK_SOURCE_PORT_ID,
    SEQ_ID,
    WAIT_CLOCK_CLASS,
    WAIT_OOB
    );

   signal data               : std_logic_vector(15 downto 0);
   signal addr               : std_logic_vector( 1 downto 0);
   signal stb                : std_logic;
   signal data_valid         : std_logic;
   signal word_cnt           : unsigned(7 downto 0); -- just enough of cnt to detect interestng stuff
   signal next_offset        : unsigned(7 downto 0); -- just enough of cnt to detect interestng stuff
   signal state              : t_fsm_state;
   signal cyc_d              : std_logic;
   signal ptp_source_id_addr : unsigned(7  downto 0); 
   signal port_mask          : std_logic_vector(g_port_number-1 downto 0);

begin   
   -- data stored in "data" is being acked by snk | data cnt is incremented
   data_valid <= '1'       when (snk_i.cyc = '1' and snk_i.stb = '1' and src_i.stall = '0') else '0';
   data       <= snk_i.dat when (snk_i.cyc = '1' and snk_i.stb = '1' and src_i.stall = '0') else (others => '0');

   process_data: process(clk_sys_i,rst_n_i)
   begin
    if rising_edge(clk_sys_i) then
      if rst_n_i = '0' then
        word_cnt   <= (others =>'0');
        cyc_d      <= '0';
      else

        cyc_d <= snk_i.cyc;

        if(snk_i.cyc = '0') then
           word_cnt   <= (others =>'0');
        elsif(snk_i.cyc = '1' and snk_i.stb = '1' and src_i.stall = '0' and snk_i.adr = "00") then
           word_cnt <= word_cnt + 1;
        end if;

      end if;
    end if;
   end process;


   fsm: process(clk_sys_i,rst_n_i)
   begin
   
     if rising_edge(clk_sys_i) then
       if rst_n_i = '0' then
         next_offset          <= (others=>'0');
         state                <= WAIT_SOF;
         ptp_source_id_addr   <= (others=>'0');
         seq_id_o             <= (others=>'0');
         seq_id_valid_o       <= '0';
         clock_class_o        <= (others=>'0');
         clock_class_valid_o  <= '0';
         port_mask            <= (others=>'0');
         rxtx_detected_mask_o <= (others=>'0');
         
       else
         case state is

           when WAIT_SOF =>

             if(cyc_d = '0' and snk_i.cyc ='1') then
               state                <= WAIT_DATA; 
               next_offset          <= (others=>'0');
               ptp_source_id_addr   <= (others=>'0');
               seq_id_o             <= (others=>'0');
               seq_id_valid_o       <=  '0';
               clock_class_o        <= (others=>'0');
               clock_class_valid_o  <=  '0';
               port_mask            <= rtu_dst_port_mask_i;
               rxtx_detected_mask_o <= (others=>'0');

             end if;

           when WAIT_DATA =>

             if (word_cnt = 0 and data_valid = '1') then
               state       <= WAIT_ETHERTYPE;
               next_offset <= to_unsigned(6, next_offset'length);
             end if;

           when WAIT_ETHERTYPE =>

             if(data_valid = '1' and word_cnt = next_offset) then
               if(data    = x"88F7") then -- PTP raw ethernet frame
                 state          <= WAIT_MSG_TYPE;
                 next_offset    <= next_offset + 1; -- th word
               elsif(data = x"8100") then -- VLAN tag
                 state          <= HAS_VTAG;
                 next_offset      <= next_offset + 2; 
               elsif(data = x"0800") then -- IP frame
                 state          <= WAIT_UDP_PROTO;
                 next_offset    <= next_offset + 6; 
               else
                 state          <= WAIT_SOF; -- we are done, it's not announce
               end if;
             end if;

           when HAS_VTAG =>

             if(data_valid = '1' and word_cnt = next_offset) then

               if(data = x"88F7") then -- PTP raw ethernet frame
                 state          <= WAIT_MSG_TYPE;
                 next_offset    <= next_offset + 1;
               elsif(data = x"0800") then -- IP frame
                 state          <= WAIT_UDP_PROTO;
                 next_offset    <= next_offset + 6;
               else
                 state          <= WAIT_SOF; -- we are done, it's not announce
               end if;
             end if;

           when WAIT_UDP_PROTO =>

             if(data_valid = '1' and word_cnt = next_offset) then
               if(data(7 downto 0) = x"11") then -- 17 is the UDP protocol
                 state          <= WAIT_PTP_PORT;
                 next_offset    <= next_offset + 15;
               else
                 state <= WAIT_SOF; -- we are done, it's not announce
               end if;
             end if;

           when WAIT_PTP_PORT =>

             if(data_valid = '1' and word_cnt = next_offset) then
               if(data = x"013F") then 
                 state          <= WAIT_MSG_TYPE;
                 next_offset    <= next_offset + 4;
               else
                 state          <= WAIT_SOF; -- we are done, it's not announce
               end if;
             end if;

           when WAIT_MSG_TYPE =>

             if(data_valid = '1' and word_cnt = next_offset) then
               if(data(11 downto 8) = x"B" and data(3 downto 0) = x"2") then --Announce of PTPv2
                 state          <= WAIT_SOURCE_PORT_ID;
                 next_offset    <= next_offset + 10;
               else 
                 state          <= WAIT_SOF; -- we are done, it's not announce
               end if;
             end if;

           when WAIT_SOURCE_PORT_ID => 

             if(data_valid = '1' and word_cnt = next_offset) then

               if(g_snoop_mode = TX_SEQ_ID_MODE) then
                 state                 <= SEQ_ID;
                 next_offset           <= next_offset + 5;
               else
                 state                 <= CHECK_SOURCE_PORT_ID;
                 ptp_source_id_addr    <= ptp_source_id_addr + 1;
                 next_offset           <= next_offset + 4;
               end if;
             end if;

           when CHECK_SOURCE_PORT_ID =>

             if(data_valid = '1') then
               if(ptp_source_id_data_i = data) then
                 if(word_cnt = next_offset) then
                   state               <= SEQ_ID;
                   next_offset         <= next_offset + 1;
                 else
                   state               <= CHECK_SOURCE_PORT_ID;
                   ptp_source_id_addr  <= ptp_source_id_addr + 1;
                 end if;
               else
                 state                 <= WAIT_SOF; -- we are done, it's not announce
               end if;
             end if;

           when SEQ_ID =>

             if(data_valid = '1' and word_cnt = next_offset) then
               state                 <= CHECK_SOURCE_PORT_ID;
               seq_id_o              <= data;
               seq_id_valid_o        <= '1';
               if(g_snoop_mode = TX_SEQ_ID_MODE) then
                 state               <= WAIT_SOF;
                 rxtx_detected_mask_o<= port_mask;
               elsif(g_snoop_mode = RX_CLOCK_CLASS_MODE) then
                   state               <= WAIT_CLOCK_CLASS;
                   next_offset         <= next_offset + 8;
               end if;
             end if;

           when WAIT_CLOCK_CLASS=>

             if(data_valid = '1' and word_cnt = next_offset) then
               state                 <= WAIT_OOB;
               clock_class_o         <= data(15 downto 0);
               clock_class_valid_o   <= '1';
             end if;

           when WAIT_OOB =>

             if(snk_i.adr = "01" and data_valid = '1') then -- 1st OOB word
               rxtx_detected_mask_o  <= f_onehot_decode(data(4 downto 0));
               state                 <= WAIT_SOF;
             end if;

           when others => null;

         end case;
       end if;
     end if;    
   end process;

  ptp_source_id_addr_o <=std_logic_vector(ptp_source_id_addr);

end behavioral;

