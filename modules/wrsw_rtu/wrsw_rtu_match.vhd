-------------------------------------------------------------------------------
-- Title      : Routing Table Unit's Matching Component (RTU_MATCH)
-- Project    : White Rabbit Switch
-------------------------------------------------------------------------------
-- File       : wrsw_rtu_match.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-05-08
-- Last update: 2012-01-26
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
-- Copyright (c) 2010 Maciej Lipinski / CERN
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
use work.wrsw_rtu_private_pkg.all;
use work.genram_pkg.all;


entity wrsw_rtu_match is
  
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
    rq_fifo_input_i : in std_logic_vector(c_rtu_num_ports +  -- request port ID
                                          c_wrsw_mac_addr_width +  -- destination MAC
                                          c_wrsw_mac_addr_width +  -- source MAC
                                          c_wrsw_vid_width +       -- VLAN ID
                                          c_wrsw_prio_width +      -- PRIORITY 
                                          1 +                -- has_prio    
                                          1 - 1 downto 0);   -- has vid

    -------------------------------------------------------------------------------
    -- output response
    -------------------------------------------------------------------------------

    -- write data to response FIFO
    rsp_fifo_write_o : out std_logic;

    -- response FIFO is full
    rsp_fifo_full_i   : in  std_logic;
    -- ouput response (to response FIFO):    
    rsp_fifo_output_o : out std_logic_vector(c_rtu_num_ports +  -- request port ID
                                             c_wrsw_num_ports +  -- forward port mask  
                                             c_wrsw_prio_width +  -- priority
                                             1 - 1 downto 0);   -- drop

    htab_start_o : out std_logic;
    -- htab_idle_i: in std_logic;
    htab_ack_o   : out std_logic;
    htab_found_i : in  std_logic;
    htab_hash_o  : out std_logic_vector(c_wrsw_hash_width - 1 downto 0);
    htab_mac_o   : out std_logic_vector(c_wrsw_mac_addr_width -1 downto 0);
    htab_fid_o   : out std_logic_vector(c_wrsw_fid_width - 1 downto 0);
    htab_drdy_i  : in  std_logic;
--    htab_valid_i : in  std_logic;

    htab_entry_i : in t_rtu_htab_entry;

    -------------------------------------------------------------------------------
    -- Unrecongized FIFO (operated by WB)
    -------------------------------------------------------------------------------  
    -- FIFO write request
    rtu_ufifo_wr_req_o : out std_logic;

    -- FIFO full flag
    rtu_ufifo_wr_full_i : in std_logic;

    -- FIFO empty flag
    rtu_ufifo_wr_empty_i : in  std_logic;
    rtu_ufifo_dmac_lo_o  : out std_logic_vector(31 downto 0);
    rtu_ufifo_dmac_hi_o  : out std_logic_vector(15 downto 0);
    rtu_ufifo_smac_lo_o  : out std_logic_vector(31 downto 0);
    rtu_ufifo_smac_hi_o  : out std_logic_vector(15 downto 0);
    rtu_ufifo_vid_o      : out std_logic_vector(c_wrsw_vid_width - 1 downto 0);
    rtu_ufifo_prio_o     : out std_logic_vector(2 downto 0);
    rtu_ufifo_pid_o      : out std_logic_vector(3 downto 0);
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

    -- Port for std_logic_vector field: 'Aging register value' in reg: 'Aging register for HCAM'
    rtu_agr_hcam_i      : in  std_logic_vector(31 downto 0);
    rtu_agr_hcam_o      : out std_logic_vector(31 downto 0);
    rtu_agr_hcam_load_i : in  std_logic;

    -------------------------------------------------------------------------------
    -- VLAN TABLE
    -------------------------------------------------------------------------------   

    rtu_vlan_tab_addr_o : out std_logic_vector(c_wrsw_vid_width - 1 downto 0);
    rtu_vlan_tab_data_i : in  std_logic_vector(31 downto 0);
    rtu_vlan_tab_rd_o   : out std_logic;

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
    rtu_pcr_pass_all_i : in std_logic_vector(c_rtu_num_ports - 1 downto 0);

    -- LEARN_EN : Learning enable
    -- 1: enables learning process on this port. Unrecognized requests will be put into UFIFO
    -- 0: disables learning. Unrecognized requests will be either broadcast or dropped. 
    rtu_pcr_learn_en_i : in std_logic_vector(c_rtu_num_ports - 1 downto 0);

    -- PASS_BPDU : Pass BPDUs
    -- 1: BPDU packets (with dst MAC 01:80:c2:00:00:00) are passed according to RT rules. This setting overrides PASS_ALL.
    -- 0: BPDU packets are dropped. 
    rtu_pcr_pass_bpdu_i : in std_logic_vector(c_rtu_num_ports - 1 downto 0);

    -- [TODO implemented] B_UNREC : Unrecognized request behaviour
    -- Sets the port behaviour for all unrecognized requests:
    -- 0: packet is dropped
    -- 1: packet is broadcast     
    rtu_pcr_b_unrec_i : in std_logic_vector(c_rtu_num_ports - 1 downto 0);

    -------------------------------------------------------------------------------
    -- HASH based on CRC
    -------------------------------------------------------------------------------   
    rtu_crc_poly_i : in std_logic_vector(c_wrsw_crc_width - 1 downto 0)

    );

end wrsw_rtu_match;

architecture behavioral of wrsw_rtu_match is

-------------------------------------------------------------------------------------------------------------------------
--| Register bit aliases
-------------------------------------------------------------------------------------------------------------------------
  -- identifies port number: rtu_port_id = (2^port_number)
  -- so the port number equals the number of shift_left
  alias a_rtu_port_id : std_logic_vector(c_rtu_num_ports - 1 downto 0) is rq_fifo_input_i(c_rtu_num_ports - 1 downto 0);
  
  alias a_rq_smac : std_logic_vector(c_wrsw_mac_addr_width - 1 downto 0) is rq_fifo_input_i(c_rtu_num_ports +
                                                                                            c_wrsw_mac_addr_width - 1 downto c_rtu_num_ports);

  alias a_rq_dmac : std_logic_vector(c_wrsw_mac_addr_width - 1 downto 0) is rq_fifo_input_i(c_rtu_num_ports +
                                                                                            2*c_wrsw_mac_addr_width - 1 downto c_rtu_num_ports +
                                                                                            c_wrsw_mac_addr_width);
  alias a_rq_vid : std_logic_vector(c_wrsw_vid_width - 1 downto 0) is rq_fifo_input_i(c_rtu_num_ports +
                                                                                      2*c_wrsw_mac_addr_width +
                                                                                      c_wrsw_vid_width - 1 downto c_rtu_num_ports +
                                                                                      2*c_wrsw_mac_addr_width);

  alias a_rq_prio : std_logic_vector(c_wrsw_prio_width - 1 downto 0) is rq_fifo_input_i(c_rtu_num_ports +
                                                                                        2*c_wrsw_mac_addr_width +
                                                                                        c_wrsw_vid_width +
                                                                                        c_wrsw_prio_width - 1 downto c_rtu_num_ports +
                                                                                        2*c_wrsw_mac_addr_width +
                                                                                        c_wrsw_vid_width);

  alias a_rq_has_vid : std_logic is rq_fifo_input_i(c_rtu_num_ports +
                                                    2*c_wrsw_mac_addr_width +
                                                    c_wrsw_vid_width +
                                                    c_wrsw_prio_width);

  alias a_rq_has_prio : std_logic is rq_fifo_input_i(c_rtu_num_ports +
                                                     2*c_wrsw_mac_addr_width +
                                                     c_wrsw_vid_width +
                                                     c_wrsw_prio_width + 1);  

-------------------------------------------------------------------------------------------------------------------------
--| RTU FSM states
-------------------------------------------------------------------------------------------------------------------------
  type t_rtu_match_states is (s_idle, s_rd_vlan_table_0, s_rd_vlan_table_1, s_calculate_hash, s_search_src_htab,
                              s_search_src_htab_rsp, s_learn_src, s_finished_src_or_dst, s_response);
  signal s_rtu_mach_state : t_rtu_match_states;

-------------------------------------------------------------------------------------------------------------------------
--| signals
-------------------------------------------------------------------------------------------------------------------------
-- ack for the htab_lookup module that the provided data has been read
  signal s_htab_rd_data_ack : std_logic;

-- addr derived from the hash, suplied to htab_lookup
  signal s_htab_rd_addr : std_logic_vector(c_wrsw_hash_width - 1 downto 0);
  signal s_htab_mac     : std_logic_vector(c_wrsw_mac_addr_width -1 downto 0);

-- registers to store request data
  signal s_port_id      : std_logic_vector(c_rtu_num_ports - 1 downto 0);
  signal s_port_zero    : std_logic_vector(c_rtu_num_ports - 1 downto 0);
  signal s_rq_smac      : std_logic_vector(c_wrsw_mac_addr_width - 1 downto 0);
  signal s_rq_dmac      : std_logic_vector(c_wrsw_mac_addr_width - 1 downto 0);
  signal s_rq_vid       : std_logic_vector(c_wrsw_vid_width - 1 downto 0);
  signal s_rq_has_vid   : std_logic;
  signal s_rq_prio      : std_logic_vector(c_wrsw_prio_width - 1 downto 0);
  signal s_rq_has_prio  : std_logic;
  signal s_rq_fifo_read : std_logic;

-- registers to store response data
  signal s_rsp_dst_port_mask : std_logic_vector(c_wrsw_num_ports-1 downto 0);
  signal s_rsp_drop          : std_logic;
  signal s_rsp_prio          : std_logic_vector (c_wrsw_prio_width-1 downto 0);

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
  signal s_vlan_port_mask     : std_logic_vector(c_wrsw_num_ports - 1 downto 0);
  signal s_vlan_fid           : std_logic_vector(c_wrsw_fid_width - 1 downto 0);
  signal s_vlan_prio          : std_logic_vector(c_wrsw_prio_width - 1 downto 0);
  signal s_vlan_has_prio      : std_logic;
  signal s_vlan_prio_override : std_logic;

--|registers used to store data of SOURCE ENTRY 
  signal s_src_entry_bucket_cnt               : std_logic_vector(5 downto 0);
  signal s_src_entry_port_mask_src            : std_logic_vector(c_wrsw_num_ports - 1 downto 0);
  signal s_src_entry_drop_unmatched_src_ports : std_logic;
  signal s_src_entry_prio_src                 : std_logic_vector(c_wrsw_prio_width - 1 downto 0);
  signal s_src_entry_has_prio_src             : std_logic;
  signal s_src_entry_prio_override_src        : std_logic;
  signal s_src_entry_cam_addr                 : std_logic_vector(c_wrsw_cam_addr_width -1 downto 0);

--|registers used to store data of DESTINATION ENTRY 
  signal s_dst_entry_is_bpdu           : std_logic;
  signal s_dst_entry_port_mask_dst     : std_logic_vector(c_wrsw_num_ports - 1 downto 0);
  signal s_dst_entry_prio_dst          : std_logic_vector(c_wrsw_prio_width - 1 downto 0);
  signal s_dst_entry_has_prio_dst      : std_logic;
  signal s_dst_entry_prio_override_dst : std_logic;

--|AGING for htab
  signal s_aram_main_addr           : std_logic_vector(c_wrsw_hash_width-3-1 downto 0);
  signal s_aram_main_data_o         : std_logic_vector(31 downto 0);
  signal s_aram_main_data_o_delayed : std_logic_vector(31 downto 0);
  signal s_aram_main_rd             : std_logic;
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


  signal s_agr_hcam_reg : std_logic_vector(31 downto 0);

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


  signal s_rtu_ufifo_wr_req : std_logic;

-------------------------------------------------------------------------------------------------------------------------
--| Address outs and flag generation and 
-------------------------------------------------------------------------------------------------------------------------
begin
  s_port_zero <= (others => '0');
  -----------------------------------------------------------------------------------------------------------------------
  --| Hash calculation
  -----------------------------------------------------------------------------------------------------------------------

  -- the sooner we have feed, the sooner the hash function (asynch) 
  -- will start calculating hash (which takes time)
  s_hash_input_fid <= rtu_vlan_tab_data_i(16 + c_wrsw_fid_width - 1 downto 16);

  --source hash calculate
  rtu_match_hash_src : wrsw_rtu_crc
    port map(
      mac_addr_i => s_rq_smac,
      fid_i      => s_hash_input_fid,
      crc_poly_i => rtu_crc_poly_i,     --x"8408",
      hash_o     => s_hash_src
      );
  --destination hash calculate    
  rtu_match_hash_dst : wrsw_rtu_crc
    port map(
      mac_addr_i => s_rq_dmac,
      fid_i      => s_hash_input_fid,
      crc_poly_i => rtu_crc_poly_i,     --x"8408",
      hash_o     => s_hash_dst
      );

  -----------------------------------------------------------------------------------------------------------------------
  --| Shift Left calculation
  -----------------------------------------------------------------------------------------------------------------------
  shift_left : for i in 0 to 31 generate
    shifted_left(i) <= '1' when(i = to_integer(unsigned(s_to_shift_left))) else '0';
  end generate;

  -----------------------------------------------------------------------------------------------------------------------
  --| Calculate port number = log2(port_id)
  -----------------------------------------------------------------------------------------------------------------------

  s_port_id_vector(c_rtu_num_ports - 1 downto 0) <= rq_fifo_input_i(c_rtu_num_ports - 1 downto 0);
  s_port_id_vector(31 downto c_rtu_num_ports)    <= (others => '0');

  with s_port_id_vector select
    s_port_number_tmp <= x"00" when "00000000000000000000000000000000", -- should not ther be 1? 
    x"01"                      when "00000000000000000000000000000010",
    x"02"                      when "00000000000000000000000000000100",
    x"03"                      when "00000000000000000000000000001000",
    x"04"                      when "00000000000000000000000000010000",
    x"05"                      when "00000000000000000000000000100000",
    x"06"                      when "00000000000000000000000001000000",
    x"07"                      when "00000000000000000000000010000000",
    x"08"                      when "00000000000000000000000100000000",
    x"09"                      when "00000000000000000000001000000000",
    x"0a"                      when "00000000000000000000010000000000",
    x"0b"                      when "00000000000000000000100000000000",
    x"0c"                      when "00000000000000000001000000000000",
    x"0d"                      when "00000000000000000010000000000000",
    x"0e"                      when "00000000000000000100000000000000",
    x"0f"                      when "00000000000000001000000000000000",
    x"10"                      when "00000000000000010000000000000000",
    x"11"                      when "00000000000000100000000000000000",
    x"12"                      when "00000000000001000000000000000000",
    x"13"                      when "00000000000010000000000000000000",
    x"14"                      when "00000000000100000000000000000000",
    x"15"                      when "00000000001000000000000000000000",
    x"16"                      when "00000000010000000000000000000000",
    x"17"                      when "00000000100000000000000000000000",
    x"18"                      when "00000001000000000000000000000000",
    x"19"                      when "00000010000000000000000000000000",
    x"1a"                      when "00000100000000000000000000000000",
    x"1b"                      when "00001000000000000000000000000000",
    x"1c"                      when "00010000000000000000000000000000",
    x"1d"                      when "00100000000000000000000000000000",
    x"1e"                      when "01000000000000000000000000000000",
    x"1f"                      when "10000000000000000000000000000000",
    x"00"                      when others;


  -------------------------------------------------------------------------------------------------------------------------
  --| Begining of RTU MATCH FSM
  --| (state transitions)       
  -------------------------------------------------------------------------------------------------------------------------
  rtu_match_state : process(clk_i)

    --ML: variable v_test_data_correctness: std_logic_vector(31 downto 0);

  begin
    if rising_edge(clk_i) then
      
      if(rst_n_i = '0') then
        --do reset
        s_rsp_dst_port_mask <= (others => '0');
        s_rsp_drop          <= '0';
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


        s_aram_main_rd <= '0';
        -- CAM

        s_src_dst_sel <= '0';

        s_vlan_tab_addr <= (others => '0');

        s_vlan_tab_rd <= '0';

        s_rq_learned_reg <= '0';

        s_rtu_ufifo_wr_req <= '0';

        s_rq_fifo_read <= '0';

      else
        -- FSM
        case s_rtu_mach_state is
          ------------------------------------------------------------------------------------------------------------------
          --| IDLE: Check input FIFO, if it's not empty, go ahead and work !!! [SRC/DST]
          ------------------------------------------------------------------------------------------------------------------
          when s_idle =>


            --| if the FIFO is not empty we have work to do !
            
            s_rsp_dst_port_mask <= (others => '0');
            s_rsp_drop          <= '0';
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

            s_aram_main_rd  <= '0';
            s_aram_main_wr  <= '0';
            s_to_shift_left <= (others => '0');
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
                (((a_rtu_port_id and rtu_pcr_pass_all_i) = a_rtu_port_id) or ((a_rtu_port_id and rtu_pcr_pass_bpdu_i) = a_rtu_port_id)) then

                s_rtu_mach_state <= s_rd_vlan_table_0;

                -- remember request [provided show ahead in request fifo is ON]
                s_port_id    <= a_rtu_port_id;
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

                if((a_rtu_port_id and rtu_pcr_pass_all_i) = a_rtu_port_id) then
                  s_rtu_pcr_pass_all <= '1';
                end if;


                if((a_rtu_port_id and rtu_pcr_learn_en_i) = a_rtu_port_id) then
                  s_rtu_pcr_learn_en <= '1';
                end if;

                if((a_rtu_port_id and rtu_pcr_pass_bpdu_i) = a_rtu_port_id) then
                  s_rtu_pcr_pass_bpdu <= '1';
                end if;

                if((a_rtu_port_id and rtu_pcr_b_unrec_i) = a_rtu_port_id) then
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
                s_port_id <= a_rtu_port_id;

                s_rsp_drop          <= '1';
                s_rsp_dst_port_mask <= (others => '0');
                s_rsp_prio          <= (others => '0');
                s_rtu_mach_state    <= s_response;
                

              end if;
            end if;  -- if(rq_fifo_empty_i = '0') then

            ------------------------------------------------------------------------------------------------------------------
            --| READ VLAN TABLE: output addr [ONLY SRC]
            ------------------------------------------------------------------------------------------------------------------
          when s_rd_vlan_table_0 =>

            s_rtu_mach_state <= s_rd_vlan_table_1;
            s_vlan_tab_rd    <= '1';
            -- stop reading request from rq_fifo
            s_rq_fifo_read   <= '0';
            ------------------------------------------------------------------------------------------------------------------
            --| READ VLAN TABLE: read vlan data [ONLY SRC]
            ------------------------------------------------------------------------------------------------------------------
          when s_rd_vlan_table_1 =>


            -- port mask (max 16 bits)
            s_vlan_port_mask(c_wrsw_num_ports - 1 downto 0) <= rtu_vlan_tab_data_i(c_wrsw_num_ports - 1 downto 0);

            -- fid can be max 10 bits,                 
            s_vlan_fid(c_wrsw_fid_width - 1 downto 0) <= rtu_vlan_tab_data_i(16 + c_wrsw_fid_width - 1 downto 16);

            -- has priority
            s_vlan_has_prio <= rtu_vlan_tab_data_i(26);

            if (rtu_vlan_tab_data_i(26) = '1') then  -- equals:  if ( s_vlan_has_prio ) then
              s_vlan_prio (c_wrsw_prio_width - 1 downto 0) <= rtu_vlan_tab_data_i(16 + 10 + 1 + c_wrsw_prio_width - 1 downto 16 + 10 + 1);
              s_vlan_prio_override                         <= rtu_vlan_tab_data_i(16 + 10 + 1 + 3);
            else
              s_vlan_prio (c_wrsw_prio_width - 1 downto 0) <= (others => '0');
              s_vlan_prio_override                         <= '0';
            end if;

            -------------------------------------------       
            -- drop reqeust from VLAN config
            -------------------------------------------            
            if(rtu_vlan_tab_data_i(31) = '1') then  -- if(s_vlan_drop = '1')

              -- RETURN
              s_rsp_drop       <= '1';
              s_rtu_mach_state <= s_response;
              s_vlan_tab_rd    <= '0';

              -------------------------------------------       
              -- VLAN config allows to process data
              -------------------------------------------                  
            else
              
              s_rtu_mach_state <= s_calculate_hash;
              s_vlan_tab_rd    <= '1';
              s_htab_mac       <= s_rq_smac;
              
            end if;

            ------------------------------------------------------------------------------------------------------------------
            --| CALCULATE HASH
            ------------------------------------------------------------------------------------------------------------------
          when s_calculate_hash =>

            -- remember hash for destination MAC
            -- entry search
            s_hash_dst_reg <= s_hash_dst;

            -- address to read for source search
            -- based on hash
            s_htab_rd_addr <= s_hash_src;

            -- just in case we find entry, read appropriate word from aging aram
            -- the addrss is based on hash
            s_aram_main_addr <= s_hash_src(c_wrsw_hash_width -1 downto 3);

            -- the rest of hash goes to the "shift" function
            s_to_shift_left(4 downto 2) <= s_hash_src(2 downto 0);

            -- this part we don't know yet, it depends on 
            -- the bucket in which we will find the entry
            s_to_shift_left(1 downto 0) <= (others => '0');

            -- read aging aram  
            s_aram_main_rd <= '1';

            s_rtu_mach_state <= s_search_src_htab;

            -- keep reading VLAN (don't remember why:()
            s_vlan_tab_rd <= '1';

            ------------------------------------------------------------------------------------------------------------------
            --| LOOK FOR THE ENTRY IN THE HASH TABLE (ZBT SRAM) [SRC/DST]
            ------------------------------------------------------------------------------------------------------------------
          when s_search_src_htab =>

            -- as soon as possible supply the mising aging info to shift function
            -- so that we can update aging aram if needed
            s_to_shift_left(1 downto 0) <= htab_entry_i.bucket_entry;

            -- in the first clock of being in this state
            -- we can stop  reading aram
            if (s_aram_main_rd = '1') then
              s_aram_main_rd <= '0';
            end if;

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
                s_aram_main_data_o <= shifted_left or rtu_aram_main_data_i;
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
                    s_rsp_dst_port_mask <= (others => '0');
                    s_rsp_prio          <= (others => '0');
                    s_rtu_mach_state    <= s_response;

                    -------------------------------------------       
                    -- source MAC is not blocked, go ahead
                    -------------------------------------------                           
                  else
                    
                    
                    s_rtu_mach_state <= s_finished_src_or_dst;

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
                    s_rsp_dst_port_mask <= (others => '0');
                    s_rsp_prio          <= (others => '0');
                    s_rtu_mach_state    <= s_response;


                    -------------------------------------------       
                    -- source MAC is not blocked, go ahead
                    -------------------------------------------                         
                  else

                    s_rtu_mach_state <= s_finished_src_or_dst;

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
--                  s_rtu_mach_state <= s_search_src_cam;


                  -------------------------------------------       
                  -- MAC entry definitelly not found
                  -- neither in htab nor in hcam
                  ------------------------------------------- 
                else

                  ----------------------------------------------------------------------------
                  --  SOURCE MAC ENTRY SEARCH 
                  ----------------------------------------------------------------------------                      
                  if(s_src_dst_sel = '0') then
                    
                    
                    s_src_entry_port_mask_src            <= (others => '1');  -- changed
                    s_src_entry_drop_unmatched_src_ports <= '0';

                    ----------------------------------------------------------------------------
                    --  DESTINATION MAC ENTRY SEARCH
                    ----------------------------------------------------------------------------                      
                  else
                    
                    s_dst_entry_port_mask_dst <= (others => '1');
                    s_dst_entry_is_bpdu       <= '0';  -- changed
                  end if;  -- if( s_src_dst_sel = '0') then            

                  -------------------------------------------       
                  -- Learning enabled, there is place in 
                  -- learning fifo, and we have not yet
                  -- stored info about this request
                  -------------------------------------------
                  if((rtu_ufifo_wr_full_i = '0') and (s_rtu_pcr_learn_en = '1') and (s_rq_learned_reg = '0')) then

                    s_rtu_mach_state   <= s_learn_src;
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
                      s_rsp_dst_port_mask <= (others => '0');
                      s_rsp_prio          <= (others => '0');
                      s_rtu_mach_state    <= s_response;
                      
                    else

                      s_rtu_mach_state <= s_finished_src_or_dst;
                      
                      
                    end if;  --if( s_rtu_pcr_b_unrec = '0' and s_src_dst_sel = '1') then  
                  end if;  --  if( (rtu_ufifo_wr_full_i = '0') and (s_rtu_pcr_learn_en = '1') and (s_rq_learned_reg = '0')) then
                end if;  --if(htab_entry_i.go_to_cam_i = '1') then
              end if;  -- if(htab_rd_found_entry_i = '1') then
            end if;  --if(htab_entry_i.ready_i = '1') then

            -- acknolwdge data reception



            ------------------------------------------------------------------------------------------------------------------
            --| LEARN: [SRC/DST]
            ------------------------------------------------------------------------------------------------------------------
          when s_learn_src =>

            -- remembers that we've already
            -- learned this request
            -- this is to prevent pushing
            -- into learing queue the same
            -- request two times
            s_rq_learned_reg <= '1';

            s_rtu_ufifo_wr_req <= '0';

            s_rtu_mach_state <= s_finished_src_or_dst;


            if(s_htab_rd_data_ack = '1') then
              -- reset acknoledge pulse
              s_htab_rd_data_ack <= '0';
            end if;

            ----------------------------------------------------------------------------
            --  SOURCE MAC ENTRY SEARCH
            ----------------------------------------------------------------------------     
            if(s_src_dst_sel = '0') then
              
              s_src_entry_port_mask_src            <= (others => '1');
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
                s_dst_entry_port_mask_dst <= (others => '1');

                -------------------------------------------       
                -- not broadcast unrecognized requests = drop
                -------------------------------------------                       
              else
                -- unrecongized behaviour of
                -- unrecognized request is set to 0
                -- so we drop
                
                s_rsp_drop          <= '1';
                s_rsp_dst_port_mask <= (others => '0');
                s_rsp_prio          <= (others => '0');
                s_rtu_mach_state    <= s_response;

              end if;
              
            end if;  --if( s_src_dst_sel = '0') then

            ------------------------------------------------------------------------------------------------------------------
            --| SOURCE or DESTINATION ENTRY SEARCH FINISHED : if source search finished, start again with destination search
            --                                                if destination search finished, output response and exit
            ------------------------------------------------------------------------------------------------------------------
          when s_finished_src_or_dst =>
            
            
            
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
              if ((s_port_id and s_src_entry_port_mask_src(c_rtu_num_ports - 1 downto 0)) = s_port_zero(c_rtu_num_ports - 1 downto 0)) then

                -------------------------------------------       
                -- if the MAC address is locked to 
                -- source port, drop the paket
                ------------------------------------------- 
                if (s_src_entry_drop_unmatched_src_ports = '1') then

                  -- RETURN
                  s_rsp_drop       <= '1';
                  s_rtu_mach_state <= s_response;

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
                    
                    s_src_entry_port_mask_src            <= (others => '1');
                    s_src_entry_drop_unmatched_src_ports <= '0';
                    ----------------------------------------------------------------------------
                    --  DESTINATION MAC ENTRY SEARCH
                    ----------------------------------------------------------------------------  
                  else
                    
                    s_dst_entry_is_bpdu       <= '0';
                    s_dst_entry_port_mask_dst <= (others => '1');
                    
                  end if;


                  -------------------------------------------       
                  -- Learning enabled, there is place in 
                  -- learning fifo, and we have not yet
                  -- stored info about this request
                  -------------------------------------------                    
                  if((rtu_ufifo_wr_full_i = '0') and (s_rtu_pcr_learn_en = '1') and (s_rq_learned_reg = '0')) then
                    
                    s_rtu_mach_state   <= s_learn_src;
                    s_rtu_ufifo_wr_req <= '1';

                    -------------------------------------------       
                    -- for some reasons we don't want to learn
                    -- things below are normally done
                    -- in s_learn_src state
                    -------------------------------------------                        
                  else

                    -- change address to destination MAC search
                    s_htab_rd_addr              <= s_hash_dst_reg;  --s_hash_dst;--s_hash_dst_reg;
                    -- MAC to look for
                    s_htab_mac                  <= s_rq_dmac;
                    -- now, search for destination entry
                    s_rtu_mach_state            <= s_search_src_htab;
                    -- now, go for destination search
                    s_src_dst_sel               <= '1';
                    s_aram_main_addr            <= s_hash_dst_reg(c_wrsw_hash_width -1 downto 3);
                    s_to_shift_left(4 downto 2) <= s_hash_dst_reg(2 downto 0);
                    s_to_shift_left(1 downto 0) <= (others => '0');  -- at the beginning the bucket number always  is 0x0                  
                    s_aram_main_rd              <= '1';
                    
                  end if;
                  
                end if;  --if ( s_src_entry_drop_unmatched_src_ports = '1') then

                -------------------------------------------       
                --  the packet with given
                --  source MAC can come from this port.    
                -------------------------------------------                    
              else

                -- change address to destination MAC search
                s_htab_rd_addr              <= s_hash_dst_reg;   --s_hash_dst;
                -- MAC to look for
                s_htab_mac                  <= s_rq_dmac;
                -- now, search for destination entry
                s_rtu_mach_state            <= s_search_src_htab;
                -- now, go for destination search
                s_src_dst_sel               <= '1';
                s_aram_main_addr            <= s_hash_dst_reg(c_wrsw_hash_width -1 downto 3);
                s_to_shift_left(4 downto 2) <= s_hash_dst_reg(2 downto 0);
                s_to_shift_left(1 downto 0) <= (others => '0');  -- at the beginning the bucket number always  is 0x0 
                s_aram_main_rd              <= '1';
                
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
              s_rtu_mach_state <= s_response;
              
            end if;



            ------------------------------------------------------------------------------------------------------------------
            --| RESPONSE: Say the World that the response is ready and keep the information available to the outside World [SRC/CST]
            ------------------------------------------------------------------------------------------------------------------
          when s_response =>

            -- stop reading request from rq_fifo (if RTU/port disabled, 
            -- the FSM goes here from idle state)
            
            s_rq_fifo_read <= '0';
            if(s_htab_rd_data_ack = '1') then

              -- reset acknoledge pulse
              s_htab_rd_data_ack <= '0';
              
            end if;

            s_rtu_mach_state <= s_idle;
            s_vlan_tab_rd    <= '0';
            s_aram_main_wr   <= '0';
            ------------------------------------------------------------------------------------------------------------------
            --| UPS, SHOULD NOT COME HERE: In case it happens
            ------------------------------------------------------------------------------------------------------------------
          when others =>
            --|don't know what to do, go to the beginnig :)
            s_rtu_mach_state <= s_idle;
            s_vlan_tab_rd    <= '0';
            s_aram_main_wr   <= '0';
        end case;

      end if;
    end if;
  end process rtu_match_state;




  rtu_vlan_tab_addr_o <= s_vlan_tab_addr;
  rtu_vlan_tab_rd_o   <= s_vlan_tab_rd;

  htab_mac_o <= s_htab_mac;
  htab_fid_o <= s_vlan_fid;

  htab_hash_o <= s_htab_rd_addr;
  htab_ack_o  <= s_htab_rd_data_ack;

  rtu_aram_main_rd_o   <= s_aram_main_rd;
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
  rtu_ufifo_pid_o <= s_ufifo_pid(3 downto 0);


  rtu_ufifo_has_vid_o  <= s_rq_has_vid;
  rtu_ufifo_has_prio_o <= s_rq_has_prio;

  rq_fifo_read_o <= s_rq_fifo_read;

  -- requests to search modules
  htab_start_o <= '1' when (s_rtu_mach_state = s_search_src_htab) else '0';

  rtu_ufifo_wr_req_o                              <= s_rtu_ufifo_wr_req;
  rsp_fifo_write_o                                <= '1' when s_rtu_mach_state = s_response else '0';
  -- response strobe
  rsp_fifo_output_o(c_rtu_num_ports - 1 downto 0) <= s_port_id;

  rsp_fifo_output_o(c_rtu_num_ports +
                    c_wrsw_num_ports - 1 downto c_rtu_num_ports) <= s_rsp_dst_port_mask;

  rsp_fifo_output_o(c_rtu_num_ports +
                    c_wrsw_num_ports +
                    c_wrsw_prio_width - 1 downto c_rtu_num_ports +
                    c_wrsw_num_ports) <= s_rsp_prio;
  rsp_fifo_output_o(c_rtu_num_ports +
                    c_wrsw_num_ports +
                    c_wrsw_prio_width) <=  s_rsp_drop ;

  s_agr_hcam_reg <= (others => '0');
  rtu_agr_hcam_o <= s_agr_hcam_reg;     -- x"F0123456";
  
end architecture;  --wrsw_rtu_match
