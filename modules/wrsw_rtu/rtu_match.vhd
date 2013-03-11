-------------------------------------------------------------------------------
-- Title      : Routing Table Unit's Matching Component (RTU_MATCH)
-- Project    : White Rabbit Switch
-------------------------------------------------------------------------------
-- File       : rtu_match.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-05-08
-- Last update: 2012-07-17
-- Platform   : FPGA-generic
-- Standard   : VHDL
-------------------------------------------------------------------------------
-- RTU_MATCH is RTU's engine which is shared among ports, it:
-- - reads request from FIFO
-- - processes request (looks in hast table and (if necessary) CAM
-- - writes respons to response FIFO
--
-------------------------------------------------------------------------------
--
-- Copyright (c) 2010z Maciej Lipinski / CERN
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
-- 2010-05-08  1.0      lipinskimm          Created
-- 2010-05-22  1.1      lipinskimm          revised, developed further
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.genram_pkg.all;
use work.pack_unpack_pkg.all;
use work.wrsw_shared_types_pkg.all;
use work.rtu_private_pkg.all;

entity rtu_match is
  generic (
    g_num_ports : integer);
  port(

    -----------------------------------------------------------------
    --| General IOs
    -----------------------------------------------------------------
    -- clock (62.5 MHz refclk/2)
    clk_i   : in std_logic;
    -- reset (synchronous, active low)
    rst_n_i : in std_logic;

    -------------------------------------------------------------------------------
    -- input request
    -------------------------------------------------------------------------------

    -- read request FIFO.
    rq_fifo_read_o : out std_logic;

    -- request FIFO is empty - there is no work for us:(
    rq_fifo_empty_i : in std_logic;

    -- input from request FIFO
    rq_fifo_input_i : in std_logic_vector(g_num_ports + c_PACKED_REQUEST_WIDTH - 1 downto 0);

    -------------------------------------------------------------------------------
    -- output response
    -------------------------------------------------------------------------------

    -- write data to response FIFO
    rsp_fifo_write_o  : out std_logic;
    rsp_fifo_full_i   : in  std_logic;
    rsp_fifo_output_o : out std_logic_vector(g_num_ports + c_PACKED_RESPONSE_WIDTH - 1 downto 0);


    htab_start_o : out std_logic;
    htab_ack_o   : out std_logic;
    htab_found_i : in  std_logic;
    htab_hash_o  : out std_logic_vector(c_wrsw_hash_width - 1 downto 0);
    htab_mac_o   : out std_logic_vector(c_wrsw_mac_addr_width -1 downto 0);
    htab_fid_o   : out std_logic_vector(c_wrsw_fid_width - 1 downto 0);
    htab_drdy_i  : in  std_logic;
    htab_entry_i : in  t_rtu_htab_entry;

    -------------------------------------------------------------------------------
    -- Unrecongized FIFO (operated by WB)
    -------------------------------------------------------------------------------  

    rtu_ufifo_wr_req_o   : out std_logic;
    rtu_ufifo_wr_full_i  : in  std_logic;
    rtu_ufifo_wr_empty_i : in  std_logic;
    rtu_ufifo_dmac_lo_o  : out std_logic_vector(31 downto 0);
    rtu_ufifo_dmac_hi_o  : out std_logic_vector(15 downto 0);
    rtu_ufifo_smac_lo_o  : out std_logic_vector(31 downto 0);
    rtu_ufifo_smac_hi_o  : out std_logic_vector(15 downto 0);
    rtu_ufifo_vid_o      : out std_logic_vector(c_wrsw_vid_width - 1 downto 0);
    rtu_ufifo_prio_o     : out std_logic_vector(2 downto 0);
    rtu_ufifo_pid_o      : out std_logic_vector(7 downto 0);
    rtu_ufifo_has_vid_o  : out std_logic;
    rtu_ufifo_has_prio_o : out std_logic;


    -------------------------------------------------------------------------------
    -- Aging registers(operated by WB)
    ------------------------------------------------------------------------------- 
    -- Ports for RAM: Aging bitmap for main hashtable
    rtu_aram_main_addr_o : out std_logic_vector(7 downto 0);

    -- Read data output
    rtu_aram_main_data_i : in std_logic_vector(31 downto 0);

    -- Read strobe input (active high)
    rtu_aram_main_rd_o : out std_logic;

    -- Write data input
    rtu_aram_main_data_o : out std_logic_vector(31 downto 0);

    -- Write strobe (active high)
    rtu_aram_main_wr_o : out std_logic;


    -------------------------------------------------------------------------------
    -- VLAN TABLE
    -------------------------------------------------------------------------------   

    vlan_tab_addr_o : out std_logic_vector(c_wrsw_vid_width - 1 downto 0);
    vlan_tab_entry_i : in t_rtu_vlan_tab_entry;

    -------------------------------------------------------------------------------
    -- CTRL registers
    ------------------------------------------------------------------------------- 
    -- RTU Global Enable : Global RTU enable bit. Overrides all port settings. 
    --   0: RTU is disabled. All packets are dropped.
    ---  1: RTU is enabled.
    rtu_gcr_g_ena_i : in std_logic;

    -- PASS_ALL [read/write]: Pass all packets
    -- 1: all packets are passed (depending on the rules in RT table).
    -- 0: all packets are dropped on this port. 
    rtu_pcr_pass_all_i : in std_logic_vector(g_num_ports - 1 downto 0);

    -- LEARN_EN : Learning enable
    -- 1: enables learning process on this port. Unrecognized requests will be put into UFIFO
    -- 0: disables learning. Unrecognized requests will be either broadcast or dropped. 
    rtu_pcr_learn_en_i : in std_logic_vector(g_num_ports - 1 downto 0);

    -- PASS_BPDU : Pass BPDUs
    -- 1: BPDU packets (with dst MAC 01:80:c2:00:00:00) are passed according to RT rules. This setting overrides PASS_ALL.
    -- 0: BPDU packets are dropped. 
    rtu_pcr_pass_bpdu_i : in std_logic_vector(g_num_ports - 1 downto 0);

    -- [TODO implemented] B_UNREC : Unrecognized request behaviour
    -- Sets the port behaviour for all unrecognized requests:
    -- 0: packet is dropped
    -- 1: packet is broadcast     
    rtu_pcr_b_unrec_i : in std_logic_vector(g_num_ports - 1 downto 0);

    -- 
    rtu_b_unrec_fw_cpu_i : in std_logic;
    rtu_cpu_mask_i       : in std_logic_vector(c_RTU_MAX_PORTS-1 downto 0);
    -------------------------------------------------------------------------------
    -- HASH based on CRC
    -------------------------------------------------------------------------------   
    rtu_crc_poly_i : in std_logic_vector(c_wrsw_crc_width - 1 downto 0)

    );

end rtu_match;

architecture behavioral of rtu_match is

  signal a_rq_smac, a_rq_dmac        : std_logic_vector(c_wrsw_mac_addr_width-1 downto 0);
  signal a_rq_vid                    : std_logic_vector(c_wrsw_vid_width-1 downto 0);
  signal a_rq_has_vid, a_rq_has_prio : std_logic;
  signal a_rq_prio                   : std_logic_vector(c_wrsw_prio_width-1 downto 0);

-------------------------------------------------------------------------------------------------------------------------
--| RTU FSM states
-------------------------------------------------------------------------------------------------------------------------
  type t_rtu_match_states is (IDLE, RD_VLAN_TABLE_0, RD_VLAN_TABLE1, CALCULATE_HASH, SEARCH_HTAB,
                              LEARN_SRC, LOOKUP_DONE, OUTPUT_RESPONSE);
  signal mstate : t_rtu_match_states;

-------------------------------------------------------------------------------------------------------------------------
--| signals
-------------------------------------------------------------------------------------------------------------------------
-- ack for the htab_lookup module that the provided data has been read
  signal s_htab_rd_data_ack : std_logic;

-- registers to store request data
  signal s_port_id      : std_logic_vector(g_num_ports - 1 downto 0);
  signal s_rq_smac      : std_logic_vector(c_wrsw_mac_addr_width - 1 downto 0);
  signal s_rq_dmac      : std_logic_vector(c_wrsw_mac_addr_width - 1 downto 0);
  signal s_rq_vid       : std_logic_vector(c_wrsw_vid_width - 1 downto 0);
  signal s_rq_has_vid   : std_logic;
  signal s_rq_prio      : std_logic_vector(c_wrsw_prio_width - 1 downto 0);
  signal s_rq_has_prio  : std_logic;
  signal s_rq_fifo_read : std_logic;

-- registers to store response data
  signal s_rsp_dst_port_mask : std_logic_vector(c_RTU_MAX_PORTS-1 downto 0);
  signal s_rsp_drop          : std_logic;
  signal s_rsp_prio          : std_logic_vector (c_wrsw_prio_width-1 downto 0);
  signal s_rsp_bpdu          : std_logic; -- ML (oct 2012)
--|manage input fifo
--ML: signal s_rd_input_req_fifo  : std_logic;
--ML: signal s_input_fifo_full    : std_logic;
--ML: signal s_usedw              : std_logic_vector(7 downto 0);

--|i/o signals to hash module
  signal s_hash_input_fid : std_logic_vector(c_wrsw_fid_width - 1 downto 0);
  signal s_hash_dst       : std_logic_vector(c_wrsw_hash_width - 1 downto 0);
  signal s_hash_src       : std_logic_vector(c_wrsw_hash_width - 1 downto 0);

-- register to store dst has
  signal s_hash_dst_reg : std_logic_vector(c_wrsw_hash_width - 1 downto 0);

--|VLAN 
--ML: signal s_fid_dst            : std_logic_vector(c_wrsw_fid_width -1 downto 0);
--ML: signal s_fid_src            : std_logic_vector(c_wrsw_fid_width -1 downto 0);

--|VLAN ctrl
  signal s_vlan_tab_addr      : std_logic_vector(c_wrsw_vid_width - 1 downto 0);
  signal s_vlan_tab_data      : std_logic_vector(31 downto 0);
  signal s_vlan_tab_rd        : std_logic;
--|VLAN data
  signal s_vlan_port_mask     : std_logic_vector(c_RTU_MAX_PORTS - 1 downto 0);
  signal s_vlan_fid           : std_logic_vector(c_wrsw_fid_width - 1 downto 0);
  signal s_vlan_prio          : std_logic_vector(c_wrsw_prio_width - 1 downto 0);
  signal s_vlan_has_prio      : std_logic;
  signal s_vlan_prio_override : std_logic;

--|registers used to store data of SOURCE ENTRY 
  signal s_src_entry_bucket_cnt               : std_logic_vector(5 downto 0);
  signal s_src_entry_port_mask_src            : std_logic_vector(c_RTU_MAX_PORTS - 1 downto 0);
  signal s_src_entry_drop_unmatched_src_ports : std_logic;
  signal s_src_entry_prio_src                 : std_logic_vector(c_wrsw_prio_width - 1 downto 0);
  signal s_src_entry_has_prio_src             : std_logic;
  signal s_src_entry_prio_override_src        : std_logic;
  signal s_src_entry_cam_addr                 : std_logic_vector(c_wrsw_cam_addr_width -1 downto 0);

--|registers used to store data of DESTINATION ENTRY 
  signal s_dst_entry_is_bpdu           : std_logic;
  signal s_dst_entry_port_mask_dst     : std_logic_vector(c_RTU_MAX_PORTS - 1 downto 0);
  signal s_dst_entry_prio_dst          : std_logic_vector(c_wrsw_prio_width - 1 downto 0);
  signal s_dst_entry_has_prio_dst      : std_logic;
  signal s_dst_entry_prio_override_dst : std_logic;

--|AGING for htab
  signal s_aram_main_addr           : std_logic_vector(c_wrsw_hash_width-3-1 downto 0);
  signal s_aram_main_data_o         : std_logic_vector(31 downto 0);
  signal s_aram_main_data_o_delayed : std_logic_vector(31 downto 0);
  signal s_aram_main_wr             : std_logic;


--| used for determining the aging bit to be writen for a given hash_addr:
-- shift count
  signal s_to_shift_left : std_logic_vector(4 downto 0);

-- shift outcome
  signal shifted_left : std_logic_vector(31 downto 0);


--| learning queue
  signal s_ufifo_dmac_lo  : std_logic_vector(31 downto 0);
  signal s_ufifo_dmac_hi  : std_logic_vector(15 downto 0);
  signal s_ufifo_smac_lo  : std_logic_vector(31 downto 0);
  signal s_ufifo_smac_hi  : std_logic_vector(15 downto 0);
  signal s_ufifo_vid      : std_logic_vector(11 downto 0);
  signal s_ufifo_prio     : std_logic_vector(2 downto 0);
  signal s_ufifo_pid      : std_logic_vector(7 downto 0);
  signal s_ufifo_has_vid  : std_logic;
  signal s_ufifo_has_prio : std_logic;

--| says whether we look for 
--| destination/source entry
-- '0' - src mac entry search
-- '1' - dst mac entry search
  signal s_src_dst_sel : std_logic;



-- we remenber taht we learned request, not to send it
-- second time to learning queue
  signal s_rq_learned_reg : std_logic;

-- nasty translation from one pid coding to another
  signal s_port_id_vector  : std_logic_vector(31 downto 0);
  signal s_port_number_tmp : std_logic_vector(7 downto 0);

-- control regs
  signal s_rtu_pcr_pass_all  : std_logic;
  signal s_rtu_pcr_learn_en  : std_logic;
  signal s_rtu_pcr_pass_bpdu : std_logic;
  signal s_rtu_pcr_b_unrec   : std_logic;
  signal s_aram_bitsel_msb : std_logic_vector(2 downto 0);

  signal s_rtu_ufifo_wr_req : std_logic;

  function f_onehot_decode (
    x : std_logic_vector) return integer is
  begin
    for i in 0 to x'length-1 loop
      if x(i) = '1' then
        return i;
      end if;
    end loop;  -- i
    return 0;
  end f_onehot_decode;


  function f_onehot_encode (x : integer; size : integer) return std_logic_vector is
    variable rv : std_logic_vector(size-1 downto 0);
  begin
    rv    := (others => '0');
    rv(x) := '1';
    return rv;
  end f_onehot_encode;

  signal requesting_port       : std_logic_vector(g_num_ports-1 downto 0);
  signal s_urec_broadcast_mask : std_logic_vector(c_RTU_MAX_PORTS-1 downto 0);  
-------------------------------------------------------------------------------------------------------------------------
--| Address outs and flag generation and 
-------------------------------------------------------------------------------------------------------------------------
begin

  -- mask used for broadcasting unrecognizd traffic. such a broadcast should avoid
  -- sending frames to NIC (CPU) which is port number g_num_ports - this coused switch's CPU
  -- to get almost stuck. however, normal broadcast has to be forwarded to NIC so that
  -- ARP and other protocols could work on it
  -- 
--   UREC_MASK: for i in 0 to c_RTU_MAX_PORTS-1 generate
--       s_urec_broadcast_mask(i) <= '1' when (i < g_num_ports) else '0';
--   end generate;

  -- if forward of unrecognized frames to CPU is disabled (LOW), then we use
  -- the cpu_mask to forward everywhere but to CPU, otherwise we do on all ports
  s_urec_broadcast_mask <= (not rtu_cpu_mask_i) when (rtu_b_unrec_fw_cpu_i = '0') else
                           (others =>'1');
  -----------------------------------------------------------------------------------------------------------------------
  --| Hash calculation
  -----------------------------------------------------------------------------------------------------------------------

  -- the sooner we have feed, the sooner the hash function (asynch) 
  -- will start calculating hash (which takes time)
  s_hash_input_fid <= vlan_tab_entry_i.fid;

  --source hash calculate
  U_rtu_match_hash_src : rtu_crc
    port map(
      mac_addr_i => s_rq_smac,
      fid_i      => s_hash_input_fid,
      crc_poly_i => rtu_crc_poly_i,     --x"8408",
      hash_o     => s_hash_src
      );
  --destination hash calculate    
  U_rtu_match_hash_dst : rtu_crc
    port map(
      mac_addr_i => s_rq_dmac,
      fid_i      => s_hash_input_fid,
      crc_poly_i => rtu_crc_poly_i,     --x"8408",
      hash_o     => s_hash_dst
      );

  -- unpack request and decode requesting port number (from 1-hot to binary)
  f_unpack7(
    rq_fifo_input_i,
    requesting_port,
    a_rq_has_vid,
    a_rq_prio,
    a_rq_has_prio,
    a_rq_vid,
    a_rq_dmac,
    a_rq_smac
    );

  s_port_number_tmp <= std_logic_vector(to_unsigned(f_onehot_decode(requesting_port), 8));


  --------------------------------------
  -- Begining of RTU MATCH FSM
  --------------------------------------

  rtu_match_state : process(clk_i)
  begin
    if rising_edge(clk_i) then
      
      if(rst_n_i = '0') then
        --do reset
        s_rsp_dst_port_mask <= (others => '0');
        s_rsp_drop          <= '0';
        s_rsp_bpdu          <= '0';
        s_rsp_prio          <= (others => '0');
        s_htab_rd_data_ack  <= '0';

        s_src_entry_port_mask_src            <= (others => '0');
        s_src_entry_drop_unmatched_src_ports <= '0';
        s_src_entry_prio_src                 <= (others => '0');
        s_src_entry_has_prio_src             <= '0';
        s_src_entry_prio_override_src        <= '0';

        s_dst_entry_is_bpdu           <= '0';
        s_dst_entry_port_mask_dst     <= (others => '0');
        s_dst_entry_prio_dst          <= (others => '0');
        s_dst_entry_has_prio_dst      <= '0';
        s_dst_entry_prio_override_dst <= '0';


        rtu_aram_main_rd_o <= '0';
        -- CAM

        s_src_dst_sel <= '0';

        s_vlan_tab_addr <= (others => '0');

        s_vlan_tab_rd <= '0';

        s_rq_learned_reg <= '0';

        s_rtu_ufifo_wr_req <= '0';

        s_rq_fifo_read <= '0';

      else
        -- FSM
        case mstate is
          ------------------------------------------------------------------------------------------------------------------
          --| IDLE: Check input FIFO, if it's not empty, go ahead and work !!! [SRC/DST]
          ------------------------------------------------------------------------------------------------------------------
          when IDLE =>


            --| if the FIFO is not empty we have work to do !
            
            s_rsp_dst_port_mask <= (others => '0');
            s_rsp_drop          <= '0';
            s_rsp_bpdu          <= '0';
            s_rsp_prio          <= (others => '0');
            s_htab_rd_data_ack  <= '0';

            s_src_entry_port_mask_src            <= (others => '0');
            s_src_entry_drop_unmatched_src_ports <= '0';
            s_src_entry_prio_src                 <= (others => '0');
            s_src_entry_has_prio_src             <= '0';
            s_src_entry_prio_override_src        <= '0';
            s_src_entry_cam_addr                 <= (others => '0');

            s_dst_entry_is_bpdu           <= '0';
            s_dst_entry_port_mask_dst     <= (others => '0');
            s_dst_entry_prio_dst          <= (others => '0');
            s_dst_entry_has_prio_dst      <= '0';
            s_dst_entry_prio_override_dst <= '0';

            rtu_aram_main_rd_o <= '0';
            s_aram_main_wr     <= '0';
            -- CAM            

            s_src_dst_sel <= '0';

            s_vlan_tab_addr <= (others => '0');

            s_rq_learned_reg <= '0';

            s_rtu_ufifo_wr_req <= '0';

            s_rtu_pcr_learn_en  <= '0';
            s_rtu_pcr_pass_bpdu <= '0';
            s_rtu_pcr_b_unrec   <= '0';


            -------------------------------------------       
            -- there is a request to be handled
            -------------------------------------------              
            if(rq_fifo_empty_i = '0') then

              -- read the request from rq_fifo
              s_rq_fifo_read <= '1';

              -------------------------------------------       
              -- RTU enabled, port enabled or 
              -- in pass_only_bpdu packages state
              -------------------------------------------              
              if ((rtu_gcr_g_ena_i = '1'))
                and
                (((requesting_port and rtu_pcr_pass_all_i) = requesting_port) or ((requesting_port and rtu_pcr_pass_bpdu_i) = requesting_port)) then

                mstate <= RD_VLAN_TABLE_0;

                -- remember request [provided show ahead in request fifo is ON]
                s_port_id    <= requesting_port;
                s_rq_smac    <= a_rq_smac;
                s_rq_dmac    <= a_rq_dmac;
                s_rq_vid     <= a_rq_vid;
                s_rq_has_vid <= a_rq_has_vid;

                --ML new-------------------------------------
                if(a_rq_has_prio = '1') then
                  s_rq_prio <= a_rq_prio;
                else
                  s_rq_prio <= (others => '0');
                end if;
                ---------------------------------------
                s_rq_has_prio <= a_rq_has_prio;
                s_ufifo_pid   <= s_port_number_tmp;

                s_rtu_pcr_pass_all  <= '0';
                s_rtu_pcr_learn_en  <= '0';
                s_rtu_pcr_pass_bpdu <= '0';
                s_rtu_pcr_b_unrec   <= '0';

                -- check the configuration data for a given port 
                -- for which the match is performed

                if((requesting_port and rtu_pcr_pass_all_i) = requesting_port) then
                  s_rtu_pcr_pass_all <= '1';
                end if;


                if((requesting_port and rtu_pcr_learn_en_i) = requesting_port) then
                  s_rtu_pcr_learn_en <= '1';
                end if;

                if((requesting_port and rtu_pcr_pass_bpdu_i) = requesting_port) then
                  s_rtu_pcr_pass_bpdu <= '1';
                end if;

                if((requesting_port and rtu_pcr_b_unrec_i) = requesting_port) then
                  s_rtu_pcr_b_unrec <= '1';
                end if;


                -- ctrl vlan
                s_vlan_tab_rd <= '1';

                if(a_rq_has_vid = '1') then
                  s_vlan_tab_addr <= a_rq_vid;
                else
                  s_vlan_tab_addr <= (others => '0');
                end if;

                -------------------------------------------       
                -- RTU disabled or port disabled and 
                -- not in pass_only_bpdu packages state
                -------------------------------------------                 
              else

                -- drop package, RTU or port disabled
                s_port_id <= requesting_port;

                s_rsp_drop          <= '1';
                s_rsp_bpdu          <= '0';
                s_rsp_dst_port_mask <= (others => '0');
                s_rsp_prio          <= (others => '0');
                mstate              <= OUTPUT_RESPONSE;
                

              end if;
            end if;  -- if(rq_fifo_empty_i = '0') then

            ------------------------------------------------------------------------------------------------------------------
            --| READ VLAN TABLE: output addr [ONLY SRC]
            ------------------------------------------------------------------------------------------------------------------
          when RD_VLAN_TABLE_0 =>

            mstate         <= RD_VLAN_TABLE1;
            s_vlan_tab_rd  <= '1';
            -- stop reading request from rq_fifo
            s_rq_fifo_read <= '0';
            ------------------------------------------------------------------------------------------------------------------
            --| READ VLAN TABLE: read vlan data [ONLY SRC]
            ------------------------------------------------------------------------------------------------------------------
          when RD_VLAN_TABLE1 =>


            -- port mask (max 16 bits)
            s_vlan_port_mask(vlan_tab_entry_i.port_mask'length - 1 downto 0) <=
              vlan_tab_entry_i.port_mask;

            -- fid can be max 10 bits,                 
            htab_fid_o <= vlan_tab_entry_i.fid;
            
            -- has priority
            s_vlan_has_prio <= vlan_tab_entry_i.has_prio;

            if (vlan_tab_entry_i.has_prio = '1') then  -- equals:  if ( s_vlan_has_prio ) then
              s_vlan_prio (c_wrsw_prio_width - 1 downto 0) <= vlan_tab_entry_i.prio;
              s_vlan_prio_override                         <= vlan_tab_entry_i.prio_override;
            else
              s_vlan_prio (c_wrsw_prio_width - 1 downto 0) <= (others => '0');
              s_vlan_prio_override                         <= '0';
            end if;

            -------------------------------------------       
            -- drop reqeust from VLAN config
            -------------------------------------------            
            if(vlan_tab_entry_i.drop = '1') then  -- if(s_vlan_drop = '1')

              -- RETURN
              s_rsp_drop    <= '1';
              s_rsp_bpdu    <= '0';
              mstate        <= OUTPUT_RESPONSE;
              s_vlan_tab_rd <= '0';

              -------------------------------------------       
              -- VLAN config allows to process data
              -------------------------------------------                  
            else
              
              mstate        <= CALCULATE_HASH;
              s_vlan_tab_rd <= '1';
              htab_mac_o    <= s_rq_smac;
              
            end if;

            ------------------------------------------------------------------------------------------------------------------
            --| CALCULATE HASH
            ------------------------------------------------------------------------------------------------------------------
          when CALCULATE_HASH =>

            -- remember hash for destination MAC
            -- entry search
            s_hash_dst_reg <= s_hash_dst;

            -- address to read for source search
            -- based on hash
            htab_hash_o <= s_hash_src;

            -- just in case we find entry, read appropriate word from aging aram
            -- the addrss is based on hash
            s_aram_main_addr <= s_hash_src(c_wrsw_hash_width -1 downto 3);

            -- the rest of hash goes to the "shift" function
            s_aram_bitsel_msb <= s_hash_src(2 downto 0);
 
            -- read aging aram  
            rtu_aram_main_rd_o <= '1';

            mstate <= SEARCH_HTAB;

            -- keep reading VLAN (don't remember why:()
            s_vlan_tab_rd <= '1';

            ------------------------------------------------------------------------------------------------------------------
            --| LOOK FOR THE ENTRY IN THE HASH TABLE (ZBT SRAM) [SRC/DST]
            ------------------------------------------------------------------------------------------------------------------
          when SEARCH_HTAB =>

            -- as soon as possible supply the mising aging info to shift function
            -- so that we can update aging aram if needed

            -- in the first clock of being in this state
            -- we can stop  reading aram
            rtu_aram_main_rd_o <= '0';

            -------------------------------------------       
            -- htab_lookup finished the search, we can
            -- read the outcome
            -------------------------------------------
            if(htab_drdy_i = '1') then

              -- ack to htab_lookup 
              -- that the data has been read
              s_htab_rd_data_ack <= '1';


              -------------------------------------------       
              -- so we are luckz, mac entry found
              -- read the outcome
              -------------------------------------------
              if(htab_found_i = '1') then

                -- update aging aram (in any case that entry was found,
                -- even if dropped later, we update aging aram
                s_aram_main_data_o <= rtu_aram_main_data_i or f_onehot_encode(to_integer(unsigned(std_logic_vector'(s_aram_bitsel_msb & htab_entry_i.bucket_entry))), 32);
                -- strange hack do to t_mac_array of std_logic_vector declaration
                -- solution taken from :http://www.velocityreviews.com/forums/t639905-ambiguous-type-in-infix-expression.html
                s_aram_main_wr     <= '1';

                ----------------------------------------------------------------------------
                --  SOURCE MAC ENTRY SEARCH 
                ----------------------------------------------------------------------------                      
                if(s_src_dst_sel = '0') then

                  -------------------------------------------       
                  -- source MAC address is blocked? - 
                  -- drop the package
                  -------------------------------------------                    
                  if(htab_entry_i.drop_when_src = '1') then

                    -- RETURN
                    s_rsp_drop          <= '1';
                    s_rsp_bpdu          <= '0';
                    s_rsp_dst_port_mask <= (others => '0');
                    s_rsp_prio          <= (others => '0');
                    mstate              <= OUTPUT_RESPONSE;

                    -------------------------------------------       
                    -- source MAC is not blocked, go ahead
                    -------------------------------------------                           
                  else
                    
                    
                    mstate <= LOOKUP_DONE;

                    -- remember destination MAC entry data
                    s_src_entry_port_mask_src            <= htab_entry_i.port_mask_src;
                    s_src_entry_drop_unmatched_src_ports <= htab_entry_i.drop_unmatched_src_ports;
                    s_src_entry_has_prio_src             <= htab_entry_i.has_prio_src;

                    if (htab_entry_i.has_prio_src = '1') then
                      s_src_entry_prio_src          <= htab_entry_i.prio_src;
                      s_src_entry_prio_override_src <= htab_entry_i.prio_override_src;
                    else
                      s_src_entry_prio_src          <= (others => '0');
                      s_src_entry_prio_override_src <= '0';
                    end if;
                    

                  end if;  -- if( htab_entry_i.drop_when_source_i = '1') then


                  ----------------------------------------------------------------------------
                  --  DESTINATION MAC ENTRY SEARCH
                  ---------------------------------------------------------------------------- 
                else

                  -------------------------------------------       
                  -- destination address is  blocked
                  ------------------------------------------- 
                  if(htab_entry_i.drop_when_dst = '1') then

                    -- RETURN
                    s_rsp_drop          <= '1';
                    s_rsp_bpdu          <= '0';
                    s_rsp_dst_port_mask <= (others => '0');
                    s_rsp_prio          <= (others => '0');
                    mstate              <= OUTPUT_RESPONSE;


                    -------------------------------------------       
                    -- source MAC is not blocked, go ahead
                    -------------------------------------------                         
                  else

                    mstate <= LOOKUP_DONE;

                    s_dst_entry_is_bpdu       <= htab_entry_i.is_bpdu;
                    s_dst_entry_port_mask_dst <= htab_entry_i.port_mask_dst;
                    s_dst_entry_has_prio_dst  <= htab_entry_i.has_prio_dst;

                    if(htab_entry_i.has_prio_dst = '1') then
                      s_dst_entry_prio_dst          <= htab_entry_i.prio_dst;
                      s_dst_entry_prio_override_dst <= htab_entry_i.prio_override_dst;
                    else
                      s_dst_entry_prio_dst          <= (others => '0');
                      s_dst_entry_prio_override_dst <= '0';
                    end if;


                  end if;  --if( htab_entry_i.drop_when_dst = '1') then
                end if;  --if( s_src_dst_sel = '0') then


                -------------------------------------------       
                -- no luck, MAC entry not found
                -------------------------------------------    
              else

                -------------------------------------------       
                -- but there is hope the entry is in CAM
                -- go looking in hcam
                -------------------------------------------  
                if(htab_entry_i.go_to_cam = '1') then

                  -- remember cam addresses stored in htab
--                  s_src_entry_cam_addr <= htab_entry_i.cam_addr;

                  -- lookup in CAM
--                  mstate <= s_search_src_cam;


                  -------------------------------------------       
                  -- MAC entry definitelly not found
                  -- neither in htab nor in hcam
                  ------------------------------------------- 
                else

                  ----------------------------------------------------------------------------
                  --  SOURCE MAC ENTRY SEARCH 
                  ----------------------------------------------------------------------------                      
                  if(s_src_dst_sel = '0') then
                    
                    
                    s_src_entry_port_mask_src            <= s_urec_broadcast_mask; --ML changed (mar2013) again, to avoid broadast to NIC, old:
                                                                                   --(others => '1');  -- changed
                    s_src_entry_drop_unmatched_src_ports <= '0';

                    ----------------------------------------------------------------------------
                    --  DESTINATION MAC ENTRY SEARCH
                    ----------------------------------------------------------------------------                      
                  else
                    
                    s_dst_entry_port_mask_dst <= s_urec_broadcast_mask; --ML changed (mar2013) to avoid broadcast to NIC, old:(others => '1');
                    s_dst_entry_is_bpdu       <= '0';  -- changed
                  end if;  -- if( s_src_dst_sel = '0') then            

                  -------------------------------------------       
                  -- Learning enabled, there is place in 
                  -- learning fifo, and we have not yet
                  -- stored info about this request
                  -------------------------------------------
                  if((rtu_ufifo_wr_full_i = '0') and (s_rtu_pcr_learn_en = '1') and (s_rq_learned_reg = '0')) then

                    mstate             <= LEARN_SRC;
                    s_rtu_ufifo_wr_req <= '1';

                    -------------------------------------------       
                    -- for some reasons we don't want to learn
                    -------------------------------------------                        
                  else
                    -- 
                    if(s_rtu_pcr_b_unrec = '0' and s_src_dst_sel = '1') then
                      -- only in case of destination mac search
                      -- unrecongized behaviour of
                      -- unrecognized request is set to 0
                      -- so we drop
                      
                      s_rsp_drop          <= '1';
                      s_rsp_bpdu          <= '0';
                      s_rsp_dst_port_mask <= (others => '0');
                      s_rsp_prio          <= (others => '0');
                      mstate              <= OUTPUT_RESPONSE;
                      
                    else

                      mstate <= LOOKUP_DONE;
                      
                      
                    end if;  --if( s_rtu_pcr_b_unrec = '0' and s_src_dst_sel = '1') then  
                  end if;  --  if( (rtu_ufifo_wr_full_i = '0') and (s_rtu_pcr_learn_en = '1') and (s_rq_learned_reg = '0')) then
                end if;  --if(htab_entry_i.go_to_cam_i = '1') then
              end if;  -- if(htab_rd_found_entry_i = '1') then
            end if;  --if(htab_entry_i.ready_i = '1') then

            -- acknolwdge data reception



            ------------------------------------------------------------------------------------------------------------------
            --| LEARN: [SRC/DST]
            ------------------------------------------------------------------------------------------------------------------
          when LEARN_SRC =>

            -- remembers that we've already
            -- learned this request
            -- this is to prevent pushing
            -- into learing queue the same
            -- request two times
            s_rq_learned_reg <= '1';

            s_rtu_ufifo_wr_req <= '0';

            mstate <= LOOKUP_DONE;


            if(s_htab_rd_data_ack = '1') then
              -- reset acknoledge pulse
              s_htab_rd_data_ack <= '0';
            end if;

            ----------------------------------------------------------------------------
            --  SOURCE MAC ENTRY SEARCH
            ----------------------------------------------------------------------------     
            if(s_src_dst_sel = '0') then
              
              s_src_entry_port_mask_src            <= s_urec_broadcast_mask; --ML changed (mar2013) to avoid broadcast to NIC, old: (others => '1');
              s_src_entry_drop_unmatched_src_ports <= '0';
              ----------------------------------------------------------------------------
              --  DESTINATION MAC ENTRY SEARCH
              ----------------------------------------------------------------------------  
            else

              -------------------------------------------       
              -- broadcast unrecognized requests
              -------------------------------------------                       
              if(s_rtu_pcr_b_unrec = '1') then
                -- unrecongized behaviour of
                -- unrecognized request is set to 1
                -- so we broardcast
                
                s_dst_entry_is_bpdu       <= '0';
                s_dst_entry_port_mask_dst <= s_urec_broadcast_mask; --ML changed (mar2013) to avoid broadcast to NIC, old: (others => '1');

                -------------------------------------------       
                -- not broadcast unrecognized requests = drop
                -------------------------------------------                       
              else
                -- unrecongized behaviour of
                -- unrecognized request is set to 0
                -- so we drop
                
                s_rsp_drop          <= '1';
                s_rsp_bpdu          <= '0';
                s_rsp_dst_port_mask <= (others => '0');
                s_rsp_prio          <= (others => '0');
                mstate              <= OUTPUT_RESPONSE;

              end if;
              
            end if;  --if( s_src_dst_sel = '0') then

            ------------------------------------------------------------------------------------------------------------------
            --| SOURCE or DESTINATION ENTRY SEARCH FINISHED : if source search finished, start again with destination search
            --                                                if destination search finished, output response and exit
            ------------------------------------------------------------------------------------------------------------------
          when LOOKUP_DONE =>
            
            
            
            if(s_htab_rd_data_ack = '1') then
              -- reset acknoledge pulse
              s_htab_rd_data_ack <= '0';
            end if;


            s_aram_main_wr <= '0';
            ----------------------------------------------------------------------------
            --  SOURCE MAC ENTRY SEARCH
            ----------------------------------------------------------------------------     
            if(s_src_dst_sel = '0') then

              -------------------------------------------       
              --  check if the packet with given
              --  source MAC can come from this port.    
              -------------------------------------------        
              if unsigned(s_port_id and s_src_entry_port_mask_src(g_num_ports - 1 downto 0)) = 0 then

                -------------------------------------------       
                -- if the MAC address is locked to 
                -- source port, drop the paket
                ------------------------------------------- 
                if (s_src_entry_drop_unmatched_src_ports = '1') then

                  -- RETURN
                  s_rsp_drop <= '1';
                  s_rsp_bpdu <= '0';
                  mstate     <= OUTPUT_RESPONSE;

                  -------------------------------------------       
                  -- MAC address is not locked to 
                  -- source port, go aheac
                  -------------------------------------------                   
                else

                  -- otherwise add it to the learning queue - perhaps device has been reconnected 
                  -- to another port and topology info needs to be updated

                  -- learning, even if the queue is full, or we've already learned the request
                  -- we set appropriately masks, etc

                  ----------------------------------------------------------------------------
                  --  SOURCE MAC ENTRY SEARCH
                  ----------------------------------------------------------------------------     
                  if(s_src_dst_sel = '0') then
                    
                    s_src_entry_port_mask_src            <= s_urec_broadcast_mask; --ML changed (mar2013) to avoid broadcast to NIC, old:(others => '1');
                    s_src_entry_drop_unmatched_src_ports <= '0';
                    ----------------------------------------------------------------------------
                    --  DESTINATION MAC ENTRY SEARCH
                    ----------------------------------------------------------------------------  
                  else
                    
                    s_dst_entry_is_bpdu       <= '0';
                    s_dst_entry_port_mask_dst <= s_urec_broadcast_mask; --ML changed (mar2013) to avoid broadcast to NIC, old:(others => '1');
                    
                  end if;


                  -------------------------------------------       
                  -- Learning enabled, there is place in 
                  -- learning fifo, and we have not yet
                  -- stored info about this request
                  -------------------------------------------                    
                  if((rtu_ufifo_wr_full_i = '0') and (s_rtu_pcr_learn_en = '1') and (s_rq_learned_reg = '0')) then
                    
                    mstate             <= LEARN_SRC;
                    s_rtu_ufifo_wr_req <= '1';

                    -------------------------------------------       
                    -- for some reasons we don't want to learn
                    -- things below are normally done
                    -- in LEARN_SRC state
                    -------------------------------------------                        
                  else

                    -- change address to destination MAC search
                    htab_hash_o                 <= s_hash_dst_reg;  --s_hash_dst;--s_hash_dst_reg;
                    -- MAC to look for
                    htab_mac_o                  <= s_rq_dmac;
                    -- now, search for destination entry
                    mstate                      <= SEARCH_HTAB;
                    -- now, go for destination search
                    s_src_dst_sel               <= '1';
                    s_aram_main_addr            <= s_hash_dst_reg(c_wrsw_hash_width -1 downto 3);
                    s_aram_bitsel_msb <= s_hash_dst_reg(2 downto 0);
                    rtu_aram_main_rd_o          <= '1';
                    
                  end if;
                  
                end if;  --if ( s_src_entry_drop_unmatched_src_ports = '1') then

                -------------------------------------------       
                --  the packet with given
                --  source MAC can come from this port.    
                -------------------------------------------                    
              else

                -- change address to destination MAC search
                htab_hash_o                 <= s_hash_dst_reg;   --s_hash_dst;
                -- MAC to look for
                htab_mac_o                  <= s_rq_dmac;
                -- now, search for destination entry
                mstate                      <= SEARCH_HTAB;
                -- now, go for destination search
                s_src_dst_sel               <= '1';
                s_aram_main_addr            <= s_hash_dst_reg(c_wrsw_hash_width -1 downto 3);

                s_aram_bitsel_msb <= s_hash_dst_reg(2 downto 0);
                rtu_aram_main_rd_o          <= '1';
                
              end if;



              ----------------------------------------------------------------------------
              --  DESTINATION MAC ENTRY SEARCH
              ----------------------------------------------------------------------------     
            else


              -------------------------------------------       
              --  if we are in pass_bpdu, and the dst
              -- entry is not bpdu, drop  
              -------------------------------------------    
              if((s_rtu_pcr_pass_bpdu = '1') and (s_dst_entry_is_bpdu = '0')) then

                -- RETURN
                s_rsp_drop          <= '1';
                s_rsp_bpdu          <= '0';
                s_rsp_dst_port_mask <= (others => '0');
                s_rsp_prio          <= (others => '0');

                -------------------------------------------       
                -- don't have to do bpdu-related drop
                -- compose response
                -------------------------------------------                    
              else

                -- generate the final port mask by anding the MAC-assigned destination ports with ports
                -- registered in current VLAN
                --tmp

                -------------------------------------------       
                -- set response PORT MASK
                ------------------------------------------- 
                s_rsp_dst_port_mask <= s_vlan_port_mask and s_dst_entry_port_mask_dst;


                --evaluate the final priority of the packet
                s_rsp_drop <= '0';
                s_rsp_bpdu <= s_dst_entry_is_bpdu; --- ML (oct2012 - new, to be verified)
                -------------------------------------------       
                -- set response PRIORITY
                ------------------------------------------- 
                if (s_src_entry_prio_override_src = '1') then
                  -- take source priority
                  s_rsp_prio <= s_src_entry_prio_src;
                elsif (s_dst_entry_prio_override_dst = '1') then
                  -- take destinaion priority
                  s_rsp_prio <= s_dst_entry_prio_dst;
                elsif (s_vlan_prio_override = '1') then
                  -- take vlan priority
                  s_rsp_prio <= s_vlan_prio;
                else
                  -- no overriding,
                  if (s_src_entry_has_prio_src = '1') then
                    -- take source priority
                    s_rsp_prio <= s_src_entry_prio_src;
                  elsif (s_dst_entry_has_prio_dst = '1') then
                    -- take destination priority
                    s_rsp_prio <= s_dst_entry_prio_dst;
                  elsif (s_vlan_has_prio = '1') then
                    -- take vlan priority
                    s_rsp_prio <= s_vlan_prio;
                  elsif (s_rq_has_prio = '1') then
                    -- take port priority
                    s_rsp_prio <= s_rq_prio;
                  else
                    -- nothning matching
                    s_rsp_prio <= (others => '0');
                  end if;  -- if ( s_src_entry_prio_src = '1' ) then         
                end if;  -- if (s_src_entry_prio_override_src > x"0" ) then
              end if;  -- if( (s_rtu_pcr_pass_bpdu = '1') and (s_dst_entry_is_bpdu = '0')) then

              -- finished searching (both src and dst)
              mstate <= OUTPUT_RESPONSE;
              
            end if;



            ------------------------------------------------------------------------------------------------------------------
            --| RESPONSE: Say the World that the response is ready and keep the information available to the outside World [SRC/CST]
            ------------------------------------------------------------------------------------------------------------------
          when OUTPUT_RESPONSE =>

            -- stop reading request from rq_fifo (if RTU/port disabled, 
            -- the FSM goes here from idle state)
            
            s_rq_fifo_read <= '0';
            if(s_htab_rd_data_ack = '1') then

              -- reset acknoledge pulse
              s_htab_rd_data_ack <= '0';
              
            end if;

            mstate         <= IDLE;
            s_vlan_tab_rd  <= '0';
            s_aram_main_wr <= '0';
            ------------------------------------------------------------------------------------------------------------------
            --| UPS, SHOULD NOT COME HERE: In case it happens
            ------------------------------------------------------------------------------------------------------------------
          when others =>
            --|don't know what to do, go to the beginnig :)
            mstate         <= IDLE;
            s_vlan_tab_rd  <= '0';
            s_aram_main_wr <= '0';
        end case;

      end if;
    end if;
  end process rtu_match_state;


  vlan_tab_addr_o <= s_vlan_tab_addr;

  htab_ack_o <= s_htab_rd_data_ack;

  rtu_aram_main_addr_o <= "00" & s_aram_main_addr;
  rtu_aram_main_data_o <= s_aram_main_data_o;
  rtu_aram_main_wr_o   <= s_aram_main_wr;

  rtu_ufifo_dmac_lo_o <= s_rq_dmac(31 downto 0);
  rtu_ufifo_dmac_hi_o <= s_rq_dmac(47 downto 32);
  rtu_ufifo_smac_lo_o <= s_rq_smac(31 downto 0);
  rtu_ufifo_smac_hi_o <= s_rq_smac(47 downto 32);
  rtu_ufifo_vid_o     <= s_rq_vid(c_wrsw_vid_width -1 downto 0);
  rtu_ufifo_prio_o    <= s_rq_prio(2 downto 0);

  -- TODO:
  rtu_ufifo_pid_o <= s_ufifo_pid(7 downto 0);

  rtu_ufifo_has_vid_o  <= s_rq_has_vid;
  rtu_ufifo_has_prio_o <= s_rq_has_prio;

  rq_fifo_read_o <= s_rq_fifo_read;

  -- requests to search modules
  htab_start_o <= '1' when (mstate = SEARCH_HTAB) else '0';

  rtu_ufifo_wr_req_o <= s_rtu_ufifo_wr_req;
  rsp_fifo_write_o   <= '1' when mstate = OUTPUT_RESPONSE else '0';
  -- response strobe

 rsp_fifo_output_o <= s_rsp_bpdu & s_rsp_dst_port_mask & s_rsp_drop & s_rsp_prio & s_port_id;

end architecture;

