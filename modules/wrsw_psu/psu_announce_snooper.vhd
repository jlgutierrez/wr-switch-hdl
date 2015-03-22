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
-- 
-- Where            | what      |  offset  16bit words   | value
---------------------------------------------------------------------------------------------
-- Ethernet header  | EtherType | 6 from start of header       | 0x88F7 (PTP), 0x8100 (VLAN), 0x0800 (IP), 
-- VLAN tag         | EtherType | 2 from EtherType             | 0x88F7 (PTP), 0x0800 (IP)
-- IP header v4     | ProtoType | 5 from EtherType raw/tagged  | ?? bits [7:0] = 0x11 (UDP) 
-- UDP header       | DstPort   | 7 from IPv4 ProtoType        | 0x0140 (320 -> general message)
-- PTP header       | MsgType   | 1 from EtherType raw/tagged  | [3:0]=0x2 (PTPv2) and  [11:8]=0xB (announce)
-- PTP header       | MsgType   | 3 from EtherType UDP dstPort | [3:0]=0x2 (PTPv2) and  [11:8]=0xB (announce)
-- PTP header       | PortID    |10 from MsgType               | 5 words to check 
-- PTP header       | SeqID     | 1 from PortID end            | remember
-- PTP header       | SeqID     |15 from MsgType               | remember
-- PTP Announce     | ClkClass  | 9 from SeqID                 | remember
-- 
-- 
-- TODO:
-- - check which octect of the word is IPv4 ProtoType
-- - check IHL options for IP
--   http://en.wikipedia.org/wiki/IPv4#Options
-- - check whcih octect for the word of PTP msg type
-- - 
-- 
-- 
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
use work.gencores_pkg.all;

entity psu_announce_snooper is
  generic(
    g_port_number       : integer := 18;
    g_port_number_width : integer := 5;
    g_snoop_mode        : t_snoop_mode := TX_SEQ_ID_MODE);
  port (
    clk_sys_i : in std_logic;
    rst_n_i   : in std_logic;

    -- interface with NIC
    snk_i                 : in  t_wrf_sink_in;
    snk_o                 : out t_wrf_sink_out;
    
    src_i                 : in  t_wrf_source_in;
    src_o                 : out t_wrf_source_out;

    rtu_dst_port_mask_i   : in  std_logic_vector(g_port_number-1 downto 0);
    
    -- ctrl: tell which ports to snoop, ignore others
    snoop_ports_mask_i    : in  std_logic_vector(g_port_number-1 downto 0);
    
    holdover_on_i         : in std_logic;
    -- indicates the snooped announce clock class
    holdover_clk_class_i  : in std_logic_vector(15 downto 0);

    -- internal stuff

    -- indicates that an annouunce message was detected, all the below information about
    -- the announce shouldb e ealuated when detect_announce pulse is high
    detected_announce_o   : out std_logic;

    -- vector which indicates what was the destination port (on tx) or source port (on rx)
    -- of the announce
    srcdst_port_mask_o    : out std_logic_vector(g_port_number-1 downto 0);

    -- indicates that the sourcePortID matches the announce messages snooped previously on this
    -- port (we learn from what is sent)
    sourcePortID_match_o  : out std_logic;
    
    -- indicates that the clock class of the message matches the one we are looking for
    clockClass_match_o    : out std_logic;
    
    -- it indicats that an announce with the same sequence ID as the previous one has been 
    -- detected
    announce_duplicate_o  : out std_logic;
    
    -- it indicates that sequence number of the snooped announce is not 1 greater than the 
    -- previous announce
    sequenceID_wrong_o    : out std_logic;

    -- access to the RAM that stores snooped announce frames and information about
    -- portID + seqID per port.
    wr_ram_ena_o          : out std_logic;
    wr_ram_data_o         : out std_logic_vector(17 downto 0);
    wr_ram_addr_o         : out std_logic_vector(9 downto 0); 

    wr_ram_sel_o          : out std_logic;
    
    rd_ram_data_i         : in std_logic_vector(17 downto 0);
    rd_ram_addr_o         : out std_logic_vector( 9 downto 0);    
    rd_ram_sel_o          : out std_logic
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
    SOURCE_CLOCK_ID,
    SOURCE_PORT_NUMBER,
    SEQ_ID,
    WAIT_CLOCK_CLASS,
    EVALUATE_TX,
    CLOCK_CLASS,
    WAIT_EOF
    );

   signal data               : std_logic_vector(15 downto 0);
   signal addr               : std_logic_vector( 1 downto 0);
   signal stb                : std_logic;
   signal oob_valid          : std_logic;
   signal data_valid         : std_logic;
   signal word_cnt           : unsigned(7 downto 0); -- just enough of cnt to detect interestng stuff
   signal word_rd            : unsigned(7 downto 0);
   signal next_offset        : unsigned(7 downto 0); -- just enough of cnt to detect interestng stuff
   signal state              : t_fsm_state;
   signal cyc_d              : std_logic;
   signal rd_ram_addr        : unsigned(7  downto 0); 
   signal port_mask          : std_logic_vector(g_port_number-1 downto 0);
   signal detect_mask        : std_logic_vector(31 downto 0); -- for port id from OOB of 5 bits
   signal wr_port_info_addr  : std_logic; 
   signal rd_port_info_addr  : std_logic; 
   signal wr_ram_ena         : std_logic;
   signal sel                : std_logic; -- current wr mem bank
   signal port_index         : std_logic_vector(g_port_number_width-1 downto 0);
   
   signal sourcePortIDmatch  : std_logic;
   signal clockClassMatch    : std_logic;
   signal duplicate          : std_logic; -- the same sequence second time
   signal seqIdWrong         : std_logic; -- not 1 greater than previous
   signal dropAnnounce       : std_logic;
   signal zeros              : std_logic_vector(g_port_number-1 downto 0);
begin   
   zeros <=(others =>'0');
   -- data stored in "data" is being acked by snk | data cnt is incremented
   data_valid <= '1'       when (snk_i.cyc = '1' and snk_i.stb = '1' and src_i.stall = '0' and snk_i.adr="00") else '0';
   oob_valid  <= '1'       when (snk_i.cyc = '1' and snk_i.stb = '1' and src_i.stall = '0' and snk_i.adr="01") else '0';
   data       <= snk_i.dat when (snk_i.cyc = '1' and snk_i.stb = '1' and src_i.stall = '0')                    else (others => '0');
   port_index <= f_onehot_decode(port_mask,g_port_number_width);

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
        elsif(data_valid = '1') then
           word_cnt <= word_cnt + 1;
        end if;
      end if;
    end if;
   end process;

   detect_stuff: process(clk_sys_i,rst_n_i)
   begin
    if rising_edge(clk_sys_i) then
      if rst_n_i = '0' then
        sourcePortIDmatch <= '0';
        clockClassMatch   <= '0';
        duplicate         <= '0';
        seqIdWrong        <= '0';
      else

        if(state = WAIT_SOURCE_PORT_ID) then
          sourcePortIDmatch <= '1';
        elsif(state = SOURCE_CLOCK_ID and data_valid = '1' and rd_ram_data_i(15 downto 0) /= data) then
          sourcePortIDmatch <= '0';
        elsif(state = SOURCE_PORT_NUMBER and data_valid = '1' and rd_ram_data_i(15 downto 0) /= data) then
          sourcePortIDmatch <= '0';
        elsif(state = WAIT_SOF) then
          sourcePortIDmatch <= '0';
        end if;
        
        if(state = CLOCK_CLASS and data_valid = '1' and data = holdover_clk_class_i) then
          clockClassMatch <= '1';
        elsif(state = WAIT_SOF) then
          clockClassMatch <= '0';
        end if;
        
        if(state = SEQ_ID and data_valid = '1' and std_logic_vector(unsigned(data)+1) = rd_ram_data_i(15 downto 0)) then
          duplicate <= '1';
        elsif(state = WAIT_SOF) then
          duplicate <= '0';
        end if;

        if(state = SEQ_ID and data_valid = '1') then
          if(data = rd_ram_data_i(15 downto 0)) then
            seqIdWrong <= '0';
          else
            seqIdWrong <= '1';
          end if;
        elsif(state = WAIT_SOF) then
          seqIdWrong <= '0';
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
         rd_ram_addr          <= (others=>'0');
         port_mask            <= (others=>'0');
         detect_mask          <= (others=>'0');
         sel                  <= '0';
         rd_port_info_addr    <= '0';
         wr_port_info_addr    <= '0';
         detected_announce_o  <= '0';
         dropAnnounce         <= '0';
       else
         case state is

           when WAIT_SOF =>
             detected_announce_o  <= '0';
             
             if(cyc_d = '0' and snk_i.cyc ='1') then
               if(g_snoop_mode = TX_SEQ_ID_MODE and (snoop_ports_mask_i & rtu_dst_port_mask_i) = zeros) then
                 state                <= WAIT_SOF;
               else
                 state                <= WAIT_DATA; 
                 next_offset          <= (others=>'0');
                 rd_ram_addr          <= (others=>'0');
                 port_mask            <= rtu_dst_port_mask_i;
                 detect_mask          <= (others=>'0');
                 rd_port_info_addr    <= '0';
                 wr_port_info_addr    <= '0';
                 dropAnnounce         <= '0';
               end if;
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
                 next_offset    <= next_offset + 5; 
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
                 next_offset    <= next_offset + 5;
               else
                 state          <= WAIT_SOF; -- we are done, it's not announce
               end if;
             end if;

           when WAIT_UDP_PROTO =>

             if(data_valid = '1' and word_cnt = next_offset) then
               if(data(7 downto 0) = x"11") then -- 17 is the UDP protocol
                 state          <= WAIT_PTP_PORT;
                 next_offset    <= next_offset + 7;
               else
                 state <= WAIT_SOF; -- we are done, it's not announce
               end if;
             end if;

           when WAIT_PTP_PORT =>

             if(data_valid = '1' and word_cnt = next_offset) then
               if(data = x"0140") then 
                 state          <= WAIT_MSG_TYPE;
                 next_offset    <= next_offset + 3;
               else
                 state          <= WAIT_SOF; -- we are done, it's not announce
               end if;
             end if;

           when WAIT_MSG_TYPE =>

             if(data_valid = '1' and word_cnt = next_offset) then
               if(data(11 downto 8) = x"B" and data(3 downto 0) = x"2") then --Announce of PTPv2
                 state          <= WAIT_SOURCE_PORT_ID;
                 next_offset    <= next_offset + 9;
               else 
                 state          <= WAIT_SOF; -- we are done, it's not announce
               end if;
             end if;

           when WAIT_SOURCE_PORT_ID => 

             if(data_valid = '1' and word_cnt = next_offset) then
               state                 <= SOURCE_CLOCK_ID;
               rd_port_info_addr    <= '0';
               wr_port_info_addr    <= '0';
               next_offset           <= next_offset + 4;
             end if;

           when SOURCE_CLOCK_ID =>

             if(data_valid = '1') then
               if(word_cnt = next_offset) then
                 state               <= SOURCE_PORT_NUMBER;
                 next_offset         <= next_offset + 1;
                 rd_port_info_addr    <= '1';
                 wr_port_info_addr    <= '0';
               end if;
             end if;

           when SOURCE_PORT_NUMBER =>

             if(data_valid = '1') then
               if(word_cnt = next_offset) then
                 state               <= SEQ_ID;
                 next_offset         <= next_offset + 1;
                 rd_port_info_addr    <= '1';
                 wr_port_info_addr    <= '1';
               end if;
             end if;

           when SEQ_ID =>

             if(data_valid = '1' and word_cnt = next_offset) then
               state                 <= WAIT_CLOCK_CLASS;
               next_offset           <= next_offset + 8;
             end if;

           when WAIT_CLOCK_CLASS=>

             if(data_valid = '1' and word_cnt = next_offset) then
               state                 <= CLOCK_CLASS;
               next_offset           <= next_offset + 1;
             end if;


           when CLOCK_CLASS=>

             if(data_valid = '1' and word_cnt = next_offset) then
               if(g_snoop_mode = TX_SEQ_ID_MODE) then
                 state               <= EVALUATE_TX;
               else
                 state               <= WAIT_EOF;
               end if;
             end if;

	    when EVALUATE_TX =>
             if(holdover_on_i = '1' and (clockClassMatch ='0' or duplicate = '1' or seqIdWrong ='1')) then
               dropAnnounce         <= '1';
             end if;
             state                <= WAIT_EOF;
           when WAIT_EOF =>

             if(oob_valid = '1' or (cyc_d = '1' and snk_i.cyc = '0' )) then -- 1st OOB word
               state                 <= WAIT_SOF;
               dropAnnounce          <= '0';
               if(dropAnnounce = '0') then 
                 sel                   <= not sel;
                 detected_announce_o   <= '1';
                 if(oob_valid = '1'  and g_snoop_mode = RX_CLOCK_CLASS_MODE) then
                   detect_mask           <= f_onehot_encode(data(4 downto 0));
                 elsif(g_snoop_mode = TX_SEQ_ID_MODE) then
                   detect_mask(g_port_number-1 downto 0)             <= port_mask;
                   detect_mask(31              downto g_port_number) <= (others =>'0');
                 end if;
               end if;
             end if;

           when others => null;

         end case;
       end if;
     end if;    
   end process;
  word_rd                    <= word_cnt +1;
  
  rd_ram_addr_o              <= '1' &     sel & "00" & port_index & rd_port_info_addr  when ((word_cnt = next_offset and state = SOURCE_CLOCK_ID) or state = SOURCE_PORT_NUMBER) else
                                '0' &     sel & std_logic_vector(word_rd);
  wr_ram_addr_o              <= '1' & not sel & "00" & port_index & wr_port_info_addr  when (state = SOURCE_PORT_NUMBER or state = SEQ_ID) else
                                '0' & not sel & std_logic_vector(word_cnt);
  wr_ram_data_o(15 downto 0) <=  std_logic_vector(unsigned(data) + 1) when (data_valid = '1' and state = SEQ_ID) else
                                 data                                 when (data_valid = '1') else 
                                 (others =>'0');
  
  wr_ram_data_o(17) <= '1' when (state = CLOCK_CLASS) else '0';
  -- start of PTP announce msg
--   wr_ram_data_o(17) <= '1' when (state             = WAIT_MSG_TYPE and 
--                                  data_valid        = '1'           and 
--                                  word_cnt          = next_offset   and
--                                  data(11 downto 8) = x"B"   and 
--                                  data(3 downto 0)  = x"2") else
--                        '0';
  -- valid data (to somehow pass info when the frame finishes (without having to register)
  wr_ram_data_o(16)           <= data_valid; 
  
  wr_ram_ena_o                <= data_valid;


  srcdst_port_mask_o       <= detect_mask(g_port_number-1 downto 0);

  wr_ram_sel_o               <= sel;
  rd_ram_sel_o               <= not sel;
  
  src_o.adr   <= snk_i.adr;
  src_o.dat   <= snk_i.dat when (dropAnnounce = '0') else (others =>'0');
  src_o.cyc   <= snk_i.cyc;
  src_o.stb   <= snk_i.stb when (dropAnnounce = '0') else '0';
  src_o.we    <= snk_i.we;
  src_o.sel   <= snk_i.sel;
  
  snk_o.ack   <= src_i.ack when (dropAnnounce = '0') else '1';
  snk_o.stall <= src_i.stall;
  snk_o.err   <= src_i.err;
  snk_o.rty   <= src_i.rty; 
  
end behavioral;

