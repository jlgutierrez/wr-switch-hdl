-------------------------------------------------------------------------------
-- Title      : Output Block
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : swc_output_block.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-11-03
-- Last update: 2012-03-16
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: 
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
-- Date        Version  Author   Description
-- 2010-11-09  1.0      mlipinsk created
-- 2012-01-19  2.0      mlipinsk wisbonized (pipelined WB)
-- 2012-01-19  2.0      twlostow added buffer-FIFO
-- 2012-02-02  3.0      mlipinsk generic-azed
-- 2012-02-16  4.0      mlipinsk adapted to the new (async) MPM
-- 2012-04-19  4.1      mlipinsk adapted to muti-resource MMU implementation
-- 2012-04-20  4.2      mlipinsk added dropping of frames from queues which are full
-------------------------------------------------------------------------------
-- TODO:
-- 1) mpm_dsel_i - needs to be made it generic
-- 2) mpm_abort_o - implement
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.CEIL;
use ieee.math_real.log2;

library work;
use work.swc_swcore_pkg.all;
use work.genram_pkg.all;
use work.wr_fabric_pkg.all;
use work.endpoint_private_pkg.all;      -- Tom
use work.ep_wbgen2_pkg.all;             -- tom

entity xswc_output_block_new is
  generic (

    g_max_pck_size_width              : integer;  --:= c_swc_max_pck_size_width  
    g_output_block_per_queue_fifo_size : integer;  --:= c_swc_output_fifo_size
    g_queue_num_width                 : integer;  --
    g_queue_num                       : integer;  --
    g_prio_num_width                  : integer;  --                      
    g_mpm_page_addr_width             : integer;  --:= c_swc_page_addr_width;
    g_mpm_data_width                  : integer;  --:= c_swc_page_addr_width;
    g_mpm_partial_select_width        : integer;
    g_mpm_fetch_next_pg_in_advance    : boolean := false;
    g_mmu_resource_num_width          : integer;
    g_wb_data_width                   : integer;
    g_wb_addr_width                   : integer;
    g_wb_sel_width                    : integer;
    g_hwdu_output_block_width         : integer := 8;
    g_wb_ob_ignore_ack                : boolean := true;
    g_drop_outqueue_head_on_full      : boolean := true
    );
  port (
    clk_i   : in std_logic;
    rst_n_i : in std_logic;

-------------------------------------------------------------------------------
-- I/F with Pck Transfer Arbiter
-------------------------------------------------------------------------------

    pta_transfer_data_valid_i : in  std_logic;
    pta_pageaddr_i            : in  std_logic_vector(g_mpm_page_addr_width    - 1 downto 0);
    pta_prio_i                : in  std_logic_vector(g_prio_num_width         - 1 downto 0);
    pta_hp_i                  : in  std_logic;
--     pta_resource_i            : in  std_logic_vector(g_mmu_resource_num_width - 1 downto 0);
    pta_transfer_data_ack_o   : out std_logic;

-------------------------------------------------------------------------------
-- I/F with Multiport Memory's Read Pump (MMP)
-------------------------------------------------------------------------------

    mpm_d_i            : in  std_logic_vector (g_mpm_data_width -1 downto 0);
    mpm_dvalid_i       : in  std_logic;
    mpm_dlast_i        : in  std_logic;
--dsel--    mpm_dsel_i         : in  std_logic_vector (g_mpm_partial_select_width -1 downto 0);
    mpm_dreq_o         : out std_logic;
    mpm_abort_o        : out std_logic;
    mpm_pg_addr_o      : out std_logic_vector (g_mpm_page_addr_width -1 downto 0);
    mpm_pg_valid_o     : out std_logic;
    mpm_pg_req_i       : in  std_logic;
-------------------------------------------------------------------------------
-- I/F with Pck's Pages Free Module(PPFM)
-------------------------------------------------------------------------------      
    -- correctly read pck
    ppfm_free_o        : out std_logic;
    ppfm_free_done_i   : in  std_logic;
    ppfm_free_pgaddr_o : out std_logic_vector(g_mpm_page_addr_width - 1 downto 0);

-------------------------------------------------------------------------------
--: output traffic shaper (PAUSE + time-aware-shaper)
-------------------------------------------------------------------------------  
    ots_output_mask_i : in  std_logic_vector(7 downto 0) := "00000000"; -- '1' bit indicate
                                                          -- that queue shall be PAUSED
    ots_output_drop_at_rx_hp_i : in std_logic := '0';  -- if '1' the currently transmitted non-HP frame
                                             -- is dropped (stop transmision) if HP is scheduled
-------------------------------------------------------------------------------
-- pWB : output (goes to the Endpoint)
-------------------------------------------------------------------------------  

    src_i : in  t_wrf_source_in;
    src_o : out t_wrf_source_out;

-------------------------------------------------------------------------------
-- debugging
-------------------------------------------------------------------------------  
    dbg_hwdu_o : out std_logic_vector(g_hwdu_output_block_width -1 downto 0);
    tap_out_o : out std_logic_vector(15 downto 0)
    );
end xswc_output_block_new;

architecture behavoural of xswc_output_block_new is
  
  constant c_per_queue_fifo_size_width : integer := integer(CEIL(LOG2(real(g_output_block_per_queue_fifo_size-1))));  -- c_swc_output_fifo_addr_width

  signal pta_transfer_data_ack : std_logic;

  signal wr_addr : std_logic_vector(g_queue_num_width + c_per_queue_fifo_size_width -1 downto 0);
  signal rd_addr : std_logic_vector(g_queue_num_width + c_per_queue_fifo_size_width -1 downto 0);

-- drop_imp:  
  signal dp_addr             : std_logic_vector(g_queue_num_width + c_per_queue_fifo_size_width -1 downto 0);
  signal ram_rd_addr           : std_logic_vector(g_queue_num_width + c_per_queue_fifo_size_width -1 downto 0);
  signal drop_index            : std_logic_vector(g_queue_num_width - 1 downto 0);
  signal drop_array            : std_logic_vector(g_queue_num       - 1 downto 0);

  signal write_index        : std_logic_vector(g_queue_num_width - 1 downto 0);
  signal read_index        : std_logic_vector(g_queue_num_width - 1 downto 0);
  signal not_full_array  : std_logic_vector(g_queue_num - 1 downto 0);
  signal full_array      : std_logic_vector(g_queue_num - 1 downto 0);
  signal not_empty_array : std_logic_vector(g_queue_num - 1 downto 0);
  signal not_empty_and_shaped_array: std_logic_vector(g_queue_num - 1 downto 0);
  signal read_array      : std_logic_vector(g_queue_num - 1 downto 0);
  signal read            : std_logic_vector(g_queue_num - 1 downto 0);
  signal rd_array            : std_logic_vector(g_queue_num - 1 downto 0);
  signal write_array     : std_logic_vector(g_queue_num - 1 downto 0);
  signal write           : std_logic_vector(g_queue_num - 1 downto 0);
  signal zeros           : std_logic_vector(g_queue_num - 1 downto 0);

  subtype t_head_and_head is std_logic_vector(c_per_queue_fifo_size_width - 1 downto 0);

  type t_addr_array is array (g_queue_num - 1 downto 0) of t_head_and_head;

  signal wr_addr_array : t_addr_array;
  signal rd_addr_array : t_addr_array;

  type t_prep_to_send is (S_IDLE,
                          S_NEWPCK_PAGE_READY,
                          S_NEWPCK_PAGE_SET_IN_ADVANCE,
                          S_NEWPCK_PAGE_USED,
                          S_RETRY_PREPARE,
                          S_RETRY_READY
                          );
  type t_send_pck is (S_IDLE,
                      S_DATA,
                      S_FLUSH_STALL,
                      S_FINISH_CYCLE,
                      S_EOF,
                      S_RETRY,
                      S_WAIT_FREE_PCK
                      );

--   function f_prepstate_2_slv (arg : t_prep_to_send) return std_logic_vector is
--   begin
--     case arg is
--       when S_IDLE                       => return "000";
--       when S_NEWPCK_PAGE_READY          => return "001";
--       when S_NEWPCK_PAGE_SET_IN_ADVANCE => return "010";
--       when S_NEWPCK_PAGE_USED           => return "011";
--       when S_RETRY_PREPARE              => return "100";
--       when S_RETRY_READY                => return "101";
--       when others                       => return "111";
--     end case;
--     return "111";
--   end f_prepstate_2_slv;
-- 
--   function f_sendstate_2_slv (arg : t_send_pck) return std_logic_vector is
--   begin
--     case arg is
--       when S_IDLE          => return "000";
--       when S_DATA          => return "001";
--       when S_FLUSH_STALL   => return "010";
--       when S_FINISH_CYCLE  => return "011";
--       when S_EOF           => return "100";
--       when S_RETRY         => return "101";
--       when S_WAIT_FREE_PCK => return "110";
--     end case;
--     return "111";
--   end f_sendstate_2_slv;


  signal s_send_pck     : t_send_pck;
  signal s_prep_to_send : t_prep_to_send;

  signal wr_data    : std_logic_vector(g_mpm_page_addr_width - 1 downto 0);
  signal rd_data    : std_logic_vector(g_mpm_page_addr_width - 1 downto 0);
 

  signal ppfm_free        : std_logic;
  signal ppfm_free_pgaddr : std_logic_vector(g_mpm_page_addr_width - 1 downto 0);

  signal pck_start_pgaddr : std_logic_vector(g_mpm_page_addr_width - 1 downto 0);

  signal free_sent_pck_addr : std_logic_vector(g_mpm_page_addr_width - 1 downto 0);
  signal free_sent_pck_req  : std_logic;

  signal free_dped_pck_addr : std_logic_vector(g_mpm_page_addr_width - 1 downto 0);
  signal free_dped_pck_req  : std_logic;

  signal ram_zeros : std_logic_vector(g_mpm_page_addr_width- 1 downto 0);
  signal ram_ones  : std_logic_vector((g_mpm_page_addr_width+7)/8 - 1 downto 0);

  signal request_retry : std_logic;
  signal out_dat_err   : std_logic;

  signal mpm_pg_addr_memorized       : std_logic_vector(g_mpm_page_addr_width -1 downto 0);
  signal mpm_pg_addr_memorized_valid : std_logic;

  signal mpm_dreq     : std_logic;
  signal mpm_abort    : std_logic;
  signal mpm_pg_addr  : std_logic_vector (g_mpm_page_addr_width -1 downto 0);
  signal mpm_pg_valid : std_logic;

  signal mpm2wb_dat_int, mpm2wb_dat_int_pre  : std_logic_vector (g_wb_data_width -1 downto 0); --dsel--
  signal mpm2wb_sel_int : std_logic_vector (g_wb_sel_width -1 downto 0);
  signal mpm2wb_adr_int, mpm2wb_adr_int_pre : std_logic_vector (g_wb_addr_width -1 downto 0); --dsel--

  signal src_out_int : t_wrf_source_out;
  signal tmp_sel     : std_logic_vector(g_wb_sel_width - 1 downto 0);
  signal tmp_dat     : std_logic_vector(g_wb_data_width - 1 downto 0);
  signal tmp_adr     : std_logic_vector(g_wb_addr_width - 1 downto 0);

  signal ack_count : unsigned(3 downto 0);

  signal set_next_rd_addr     : std_logic;

  signal wr_en       : std_logic;
  signal wr_en_reg   : std_logic;
  signal wr_addr_reg : std_logic_vector(g_queue_num_width + c_per_queue_fifo_size_width -1 downto 0);
  signal wr_data_reg : std_logic_vector(g_mpm_page_addr_width - 1 downto 0);

  signal rdy_for_rd_addr : std_logic;
  signal set_next_mem_addr : std_logic;
  signal set_next_dp_addr : std_logic;
  signal rd_valid          : std_logic; 
  signal allow_next_newpck_set : std_logic; 
  signal dp_valid         : std_logic;

  signal ppfm_free_sent   : std_logic;
  signal ppfm_free_dropped: std_logic;
  
  signal mm_valid         : std_logic;

  signal cycle_frozen     : std_logic;
  signal cycle_frozen_cnt : unsigned(5 downto 0);

  signal current_tx_prio : std_logic_vector(g_queue_num - 1 downto 0);
  
  signal hp_prio_mask    : std_logic_vector(g_queue_num - 1 downto 0);
  signal zero_prio_mask  : std_logic_vector(g_queue_num - 1 downto 0);
  
  signal hp_in_queuing   : std_logic;
  signal non_hp_txing    : std_logic;
  signal abord_tx_at_hp  : std_logic;
  signal drop_at_hp      : std_logic;
  
  signal wrf_status_err  : t_wrf_status_reg;
  
  signal page_set_in_advance: std_logic; 
  
  signal ifg_count : unsigned(3 downto 0);
  signal cyc_d0    : std_logic;
  signal drop_at_retry : std_logic; -- 

  signal send_FSM : std_logic_vector(3 downto 0);
  signal prep_FSM : std_logic_vector(3 downto 0);

  -- In theory stall is making sure the proper gap is there,but in case... two cycles
  -- are needed between falling and rising edge of cyc output signal in order for EP
  -- to prepare for new frame. actually, it is :
  -- * one cycle  for odd 
  -- * two cycles for even - we make artificially gap more by one, so things work the same
  --   for odd and even (the same gap between)
  constant tx_interframe_gap      : unsigned(3 downto 0) := x"1";-- x"2"; !!!! changed it on 8-Nov-2013, brave thing to change something that almost works
  
  -- if TRUE,  any time a retry request is received from EP (most probably PCS), the request
  -- will be ignored and frame dumped 
  --    NOTE: usually, such retry requets comes because there is a problem on input (e.g.: PAUSE
  --          and a "hole" in memory is created, PCS stops receiving data (unacceptable) so it 
  --          gets lost -> tries again to send out the frame. usually in ends up in infinite
  --          retry of sending the same frame
  --    
  -- if FALSE, when a retry requsts comes from EP, it will be handled only if output queues are free
  constant c_always_drop_at_retry : boolean := true;
  
begin  --  behavoural

  wrf_status_err.is_hp       <= '0';
  wrf_status_err.has_smac    <= '0';
  wrf_status_err.has_crc     <= '0';
  wrf_status_err.error       <= '1';
  wrf_status_err.tag_me      <= '0';
  wrf_status_err.match_class <= (others =>'0');

  zero_prio_mask   <= (others => '0');
    
  --tap_out_o <= f_slv_resize(mpm_d_i & mpm_dvalid_i & mpm_dlast_i & mpm_dreq & mpm_pg_valid & mpm_pg_addr & ppfm_free_pgaddr & ppfm_free
  --  & f_prepstate_2_slv(s_prep_to_send) & f_sendstate_2_slv(s_send_pck) & cycle_frozen & std_logic_vector(ack_count) & pta_pageaddr_i & pta_transfer_data_ack & pta_transfer_data_valid_i, 80);

  tap_out_o <= f_slv_resize(mpm_dvalid_i & mpm_dlast_i & mpm_dreq & cycle_frozen & pta_pageaddr_i & pta_transfer_data_ack & pta_transfer_data_valid_i, 16);

  p_detect_frozen : process(clk_i)
  begin
    if rising_edge(clk_i) then
      if rst_n_i = '0' then
        cycle_frozen     <= '0';
        cycle_frozen_cnt <= (others => '0');
      else
        if(src_out_int.cyc = '1') then
          if(src_out_int.stb = '1') then
            cycle_frozen_cnt <= (others => '0');
          else
            cycle_frozen_cnt <= cycle_frozen_cnt + 1;
            if(cycle_frozen_cnt = "111111") then
              cycle_frozen <= '1';
            end if;
          end if;
        end if;
      end if;
    end if;
  end process;


  zeros     <= (others => '0');
  ram_zeros <= (others => '0');
  ram_ones  <= (others => '1');
  
  -- here we map the RTU+resource info into output queues
  write_index     <= f_map_rtu_rsp_and_mmu_res_to_out_queue(pta_prio_i,
                                                            pta_hp_i,
                                                            full_array,
                                                            g_queue_num);

  -- manage writing to output queues
  write_array     <= f_onehot_decode(write_index);
  wr_data         <= pta_pageaddr_i;
  wr_addr         <= write_index & wr_addr_array(to_integer(unsigned(write_index)));
  wr_en           <= write(to_integer(unsigned(write_index)));

  -- create potential address from which the next frame can be read (if there is anything in 
  -- any queue)
  rd_addr         <= read_index  & rd_addr_array(to_integer(unsigned(read_index)));

  -- create potential address from which frame shall be dropped (if any queue full)
  dp_addr         <= drop_index  & rd_addr_array(to_integer(unsigned(drop_index)));

  -- here we decide when we start next MPM access (and whether it is "in advance"
  -- TODO: change to do it faster
  rdy_for_rd_addr <= '1' when (mpm_pg_req_i                = '1'    and 
                               allow_next_newpck_set       = '1'    and 
--                               s_send_pck                  = S_IDLE and 
                               s_prep_to_send              = S_IDLE
                                                                    )else -- here we decide whether 
                     '0';                                                -- we allocate in advance

  -- indicates that next frame is ready and should be read from an output queue
  set_next_rd_addr<= '1' when (read_array                 /= zeros  and 
                               mpm_pg_addr_memorized_valid = '0'    and
                               rd_valid                    = '0'    and -- to make it a strope (1 cyc)
                               dp_valid                    = '0'    and -- cannot read when we are dropping, 
                               rdy_for_rd_addr             = '1'   )else 
                     '0';

  set_next_mem_addr<='1' when (mpm_pg_addr_memorized_valid = '1'    and
                               rdy_for_rd_addr             = '1'   )else 
                     '0';
  -- indicates that a frame should be dropped from the output queue
  set_next_dp_addr<= '1' when (set_next_rd_addr            = '0'    and
                               drop_array                 /= zeros  and
                               dp_valid                    = '0'    and -- to make it a strope (1 cyc)
                               rd_valid                    = '0'    and -- cannot drop when we are reading (would drop the same address)
                               free_dped_pck_req           = '0' ) else
                     '0';
  
  -- indicates the address from which next frame should be read/dropped (both operations translate
  -- into reading from the ram (output queues)
  ram_rd_addr     <= rd_addr when (set_next_rd_addr = '1') else 
                     dp_addr when (set_next_dp_addr = '1') else
                     rd_addr;
  -- generate ack (if not empty, the queue can accommodate next entry)    
  pta_transfer_data_ack_o <= pta_transfer_data_ack;
  pta_transfer_data_ack   <= not_full_array(to_integer(unsigned(write_index)));

  --allow_next_newpck_set   <= '1' when (mpm_pg_req_i = '1') else '0';
  
  -- we make sure that the read-from-ram (for reading=sending or dropping frame from the output 
  -- queue) is atomic (single cycle). 
  rd_or_dp_valid : process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
           
        rd_valid           <= '0';
        dp_valid           <= '0';
        free_dped_pck_req  <= '0';
        free_dped_pck_addr <= (others =>'0');
        mm_valid           <= '0';
        
      else

        rd_valid <= '0';
        rd_array <= (others => '0');
        dp_valid <= '0';

        -- first part of atomic operation: remember from which queue the data is pop-ed
        if(set_next_rd_addr = '1') then
          rd_array <= read_array;
          rd_valid <= '1';
        elsif(set_next_dp_addr = '1') then
          rd_array <= drop_array;
          dp_valid <= '1';
        end if;        
                     
        if(dp_valid = '1') then
          free_dped_pck_req  <= '1';
          free_dped_pck_addr <= rd_data(g_mpm_page_addr_width - 1 downto 0);
        elsif(free_dped_pck_req = '1' and ppfm_free_dropped = '1') then
          free_dped_pck_req  <= '0';
        end if;
        
        mm_valid <= set_next_mem_addr;

      end if;
    end if;
  end process;  

  -- here we instantiate a module responsible for output queue scheduling (policy)
  OUTPUT_SCHEDULER: swc_output_queue_scheduler
    generic map (
      g_queue_num       => g_queue_num,
      g_queue_num_width => g_queue_num_width)
    port map (
      clk_i               => clk_i,
      rst_n_i             => rst_n_i,
      not_empty_array_i   => not_empty_and_shaped_array, -- vector with '1' corresponding to non_empty queue
      read_queue_index_o  => read_index,      -- decision which queue read now (unsigned)
      read_queue_onehot_o => read_array,      -- the above decision in vector form
      full_array_i        => full_array,      -- indicates which queue(s) is full (vector)
      drop_queue_index_o  => drop_index,      -- indicate from from which queue the oldest entry 
                                              -- shall be dropped (unsinged)
      drop_queue_onehot_o => drop_array       -- the above in vector form
      );

  not_empty_and_shaped_array <= (not ots_output_mask_i) and not_empty_array;
  --------------------------------------------------------------------------------------------------
  --  generating control for each output queue
  --------------------------------------------------------------------------------------------------
  queue_ctrl : for i in 0 to g_queue_num - 1 generate
  --------------------------------------------------------------------------------------------------  
    write(i) <= write_array(i) and not_full_array(i) and pta_transfer_data_valid_i;
    read(i)  <= rd_array(i)    and (rd_valid or dp_valid);

    QUEUE_CTRL : swc_ob_prio_queue
      generic map(
        g_per_queue_fifo_size_width => c_per_queue_fifo_size_width  -- c_swc_output_fifo_addr_width
        )
      port map (
        clk_i       => clk_i,
        rst_n_i     => rst_n_i,
        write_i     => write(i),          -- strobe to indicate we wrote one entry (increment head)
        read_i      => read(i),           -- strobe to indicate we read  one entry (increment tail)
        not_full_o  => not_full_array(i), -- indicates we can add entries (tail < head-1
        not_empty_o => not_empty_array(i),-- tail != head
        wr_en_o     => open,              -- wr_en_array(i),
        wr_addr_o   => wr_addr_array(i),  -- head (used to create addresse to which we write in RAM)
        rd_addr_o   => rd_addr_array(i)   -- tail (used to create addresse from which we read RAM) 
        );
    full_array(i) <= not not_full_array(i);
  --------------------------------------------------------------------------------------------------
  end generate queue_ctrl ;
  --------------------------------------------------------------------------------------------------

  PRIO_QUEUE: swc_rd_wr_ram
    generic map (
      g_data_width => g_mpm_page_addr_width,  -- + g_max_pck_size_width,
      g_size       => (g_queue_num * g_output_block_per_queue_fifo_size))
    port map (
      clk_i => clk_i,
      we_i  => wr_en_reg,
      wa_i  => wr_addr_reg,
      wd_i  => wr_data_reg,
      ra_i  => ram_rd_addr,
      rd_o  => rd_data);
    
  wr_ram : process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        wr_en_reg   <= '0';
        wr_addr_reg <= (others => '0');
        wr_data_reg <= (others => '0');
      else
        wr_en_reg   <= wr_en;
        wr_addr_reg <= wr_addr;
        wr_data_reg <= wr_data;
      end if;
    end if;
  end process wr_ram;

  -- learning which queues are HP 
  -- this is defined in RTU config, based on the config
  -- RTU provides info which packet is HP. In theory, more queues can be 
  -- defined as HP 
  p_learn_hp_mask: process(clk_i)
  begin
    if rising_edge(clk_i) then
      if rst_n_i = '0' then
        hp_prio_mask <= (others => '0');
      else
        if(pta_transfer_data_valid_i = '1' and pta_hp_i = '1') then
          hp_prio_mask <= hp_prio_mask or write_array ; -- add to mask
        elsif(pta_transfer_data_valid_i = '1' and pta_hp_i = '0') then
          if((hp_prio_mask and  write_array) /= zeros) then -- we recognzie nonHP queu as HP
                                                              -- remove from hp_prio_mask
            hp_prio_mask <= hp_prio_mask and (not write_array);
          end if;
        end if;
      end if;
    end if;
  end process;
-- for testing: set HP vector
--   hp_prio_mask(g_queue_num-2 downto 0) <= (others =>'0');
--   hp_prio_mask(g_queue_num-1)            <= '1'; -- HP

  -- remember info about currently processed prio of the frame. this is needed to
  -- decide whether the currently tx-ed frame shall be dropped when HP frame is queued
  p_track_tx_prio: process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        current_tx_prio <= (others => '0');
      else
        if(rd_valid = '1') then
          current_tx_prio <= read_array;
        elsif((s_send_pck = S_EOF) and (s_prep_to_send = S_IDLE)) then
          current_tx_prio <= (others => '0');
        end if;
      end if;
    end if;
  end process p_track_tx_prio;
  
  -- deciding whether to drop currently tx-ed frame
  hp_in_queuing  <= '1' when ((read_array      and      hp_prio_mask)  /= zero_prio_mask) else '0';
  non_hp_txing   <= '1' when ((current_tx_prio and (not hp_prio_mask)) /= zero_prio_mask) else '0';
                             
  abord_tx_at_hp <= non_hp_txing  and   -- we are currently sending frame which is not HP
                    hp_in_queuing and   -- we have frame which is in HP output queue
                    drop_at_hp    and   -- the configuration enable dropping at HP
                    (not mpm_pg_req_i); -- we chack that we are not at the end of sending 
                                        -- the non-HP frame. There is no sense in dropping
                                        -- frame which is almost completely sent
  
  drop_at_hp      <= ots_output_drop_at_rx_hp_i;
  --==================================================================================================
  -- FSM to prepare next pck to be send
  --==================================================================================================
  -- This state machine takes data (if available) from the output queue. The data is only the 
  -- pckfirst_page address (this is all we need).
  -- It then makes the page available for the MPM, once it's set to the MPM, the FSM waits until
  -- the MPM is ready to set pckstart_page for the next pck (in current implementation, this can
  -- happen when reading the last word). The pckstart_page is made available to the MPM, and 
  -- so again and again...
  -- The fun starts when the Endpoint requests retry of sending. we need to abort the current 
  -- MPM readout (currently not implemented in the MPM) and set again the same pckstart_page
  -- (this requires that we need to put aside and remember the page which we've already read from the 
  -- output queue, if any). once, done, we need to come to the rememberd pckstart_page.
  -- 
  -- REMARK:
  -- we don't want to get a new pckpage_start from the output queue as soon as it has been 
  -- set to MPM, this is becuase, during the transmission of the current pck, a higher 
  -- priority frame can be transfered.... so doing so at the end of pck sending should be better
  -- 
  p_prep_to_send_fsm : process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        --========================================
        s_prep_to_send              <= S_IDLE;
        mpm_abort                   <= '0';
        mpm_pg_addr                 <= (others => '0');
        mpm_pg_valid                <= '0';
        mpm_pg_addr_memorized_valid <= '0';
        mpm_pg_addr_memorized       <= (others => '0');
        allow_next_newpck_set       <= '0';
        --========================================
      else

        -- default values       
        mpm_abort     <= '0';      
        mpm_pg_valid  <= '0';      
        
        case s_prep_to_send is
          --===========================================================================================
          when S_IDLE =>
          --===========================================================================================   
            if(rd_valid = '1') then
              mpm_pg_valid     <= '1';
              mpm_pg_addr      <= rd_data(g_mpm_page_addr_width - 1 downto 0);
              if(s_send_pck = S_DATA or s_send_pck = S_FLUSH_STALL) then
                s_prep_to_send <= S_NEWPCK_PAGE_SET_IN_ADVANCE;
              else
                s_prep_to_send <= S_NEWPCK_PAGE_READY;
              end if;
            elsif(mm_valid = '1') then
              mpm_pg_addr_memorized_valid <= '0';
              mpm_pg_addr      <= mpm_pg_addr_memorized;   
              mpm_pg_valid     <= '1';       
              if(s_send_pck = S_DATA or s_send_pck = S_FLUSH_STALL) then
                s_prep_to_send <= S_NEWPCK_PAGE_SET_IN_ADVANCE;
              else
                s_prep_to_send <= S_NEWPCK_PAGE_READY;
              end if;
            elsif(request_retry = '1') then
              -- if retry happens here we don't need to remember the address becasue a new one 
              -- has not been pop-ed from the queue
              mpm_abort      <= '1'; 
              s_prep_to_send <= S_RETRY_PREPARE;
            end if;
          --===========================================================================================
          when S_NEWPCK_PAGE_SET_IN_ADVANCE =>
          --===========================================================================================        
            if(request_retry = '1') then
              mpm_abort                   <= '1';
              s_prep_to_send              <= S_RETRY_PREPARE;
              mpm_pg_addr_memorized_valid <= '1';
              mpm_pg_addr_memorized       <= mpm_pg_addr;
            --elsif(mpm_dlast_i = '1') then
            elsif(s_send_pck = S_EOF) then
              s_prep_to_send <= S_NEWPCK_PAGE_READY;
            end if;
          --===========================================================================================
          when S_NEWPCK_PAGE_READY =>
          --=========================================================================================== 
            if(request_retry = '1') then
              -- we don't have to remember address here, this is because if we are in thsi state
              -- it means that we are on the verge of sending new data. request_retry should not 
              -- happen here, but if it does (basically at the very beginning of new data
              -- that we need to retry sending new address which is stored in mpm_pg_addr and  
              -- pck_start_pgaddr
              mpm_abort      <= '1';
              s_prep_to_send <= S_RETRY_PREPARE;
            elsif(s_send_pck = S_DATA) then
              s_prep_to_send <= S_NEWPCK_PAGE_USED;
            end if;
          --===========================================================================================
          when S_NEWPCK_PAGE_USED =>
          --=========================================================================================== 
            if(request_retry = '1') then
              -- don't need to remember the address -- 
              mpm_abort      <= '1';
              s_prep_to_send <= S_RETRY_PREPARE;
            elsif(abord_tx_at_hp = '1' and mpm_pg_req_i = '0') then 
              mpm_abort      <= '1';
              s_prep_to_send <= S_IDLE;
            elsif(mpm_pg_req_i = '1') then 
                s_prep_to_send <= S_IDLE;
            end if;
          --===========================================================================================
          when S_RETRY_PREPARE =>
          --=========================================================================================== 
            if(mpm_pg_req_i = '1') then
              mpm_pg_addr    <= pck_start_pgaddr;
              mpm_pg_valid   <= '1';
              s_prep_to_send <= S_RETRY_READY;
            end if;
          --===========================================================================================
          when S_RETRY_READY =>
          --=========================================================================================== 
            if(request_retry = '1') then
              mpm_abort      <= '1';
              s_prep_to_send <= S_RETRY_PREPARE;
            elsif(s_send_pck = S_DATA) then
              s_prep_to_send <= S_NEWPCK_PAGE_USED;
            end if;
          --===========================================================================================
          when others =>
          --=========================================================================================== 
            s_prep_to_send <= S_IDLE;
        end case;

        if(s_prep_to_send = S_NEWPCK_PAGE_READY ) then
          allow_next_newpck_set <= '0';        
        --elsif(mpm_dlast_i = '1' or s_send_pck = S_IDLE ) then
        elsif(mpm_pg_req_i = '1') then
          allow_next_newpck_set <= '1';
        end if; 

      end if;
    end if;
  end process p_prep_to_send_fsm;
     
  --==================================================================================================
  -- FSM send pck with pWB I/F
  --==================================================================================================
  -- Forwarding pck read from MPM to pWB interface.
  -- 1) we make a 1 cycle or greater gap between pWB cycles (S_EOF)
  -- 2) when the transfer is finished, we request freeing (decrementing usecnt) the page
  --    (this is done by separate module)
  -- 3) if freeing from the previously sent pck has not finished when we reached the end 
  --    (or error/retry happend) of the current pck, we wait patiently. This should not happen
  -- 4) We re-try sending the same pck if asked for (not implemented yet in the MPM)
  -- 
  p_send_pck_fsm : process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        --========================================
        s_send_pck          <= S_IDLE;
        src_out_int.stb     <= '0';
        src_out_int.we      <= '1';
        src_out_int.adr     <= c_WRF_DATA;
        src_out_int.dat     <= (others => '0');
        src_out_int.cyc     <= '0';
        src_out_int.sel     <= (others => '0');
        free_sent_pck_req      <= '0';
        free_sent_pck_addr <= (others => '0');
        tmp_adr             <= (others => '0');
        tmp_dat             <= (others => '0');
        tmp_sel             <= (others => '0');
        page_set_in_advance <= '0';
        --========================================
      else
        -- default values
        if(free_sent_pck_req = '1' and ppfm_free_sent = '1') then
          free_sent_pck_req <= '0';
        end if;
        request_retry  <= '0';

        case s_send_pck is
          --===========================================================================================
          when S_IDLE =>
          --===========================================================================================   

            if(s_prep_to_send = S_NEWPCK_PAGE_READY and src_i.err = '0' and src_i.stall = '0' and ifg_count = x"0") then
              src_out_int.cyc  <= '1';
              s_send_pck       <= S_DATA;
              pck_start_pgaddr <= mpm_pg_addr;
            end if;

            --===========================================================================================
          when S_DATA =>
            --===========================================================================================        
            if(src_i.stall = '0') then
              if(mpm_dvalid_i = '1') then  -- a avoid copying crap (i.e. XXX)
                src_out_int.adr <= mpm2wb_adr_int;
                src_out_int.dat <= mpm2wb_dat_int;
                src_out_int.sel <= mpm2wb_sel_int;
              end if;
              src_out_int.stb <= mpm_dvalid_i;
            end if;

            if(src_i.err = '1' or drop_at_retry = '1') then
              s_send_pck      <= S_EOF;      -- we free page in EOF
              src_out_int.cyc <= '0';
              src_out_int.stb <= '0';
            elsif(out_dat_err = '1') then
              s_send_pck <= S_FINISH_CYCLE;  -- to make sure that the error word was sent
            elsif(src_i.rty = '1') then
              src_out_int.cyc <= '0';
              src_out_int.stb <= '0';
              request_retry   <= '1';
              s_send_pck      <= S_RETRY;
            elsif(abord_tx_at_hp = '1' and mpm_dlast_i = '0') then -- drop at HP in the outqueue
              s_send_pck      <= S_FINISH_CYCLE;      -- we free page in EOF
              src_out_int.adr <= c_WRF_STATUS;
              src_out_int.dat <= f_marshall_wrf_status(wrf_status_err);
              src_out_int.sel <= (others => '1'); 
              src_out_int.stb <= '1';                           
            elsif(src_i.stall = '1' and mpm_dvalid_i = '1') then
              s_send_pck <= S_FLUSH_STALL;
            end if;

            if(mpm_dlast_i = '1')then
              s_send_pck <= S_FINISH_CYCLE;  -- we free page in EOF
            end if;
            if(mpm_dvalid_i = '1') then  -- only when dvalid to avoid copying crap (i.e. XXX)
              tmp_adr <= mpm2wb_adr_int;
              tmp_dat <= mpm2wb_dat_int;
              tmp_sel <= mpm2wb_sel_int;
            end if;
            
            if(s_prep_to_send = S_NEWPCK_PAGE_SET_IN_ADVANCE) then
              page_set_in_advance <= '1';
            else
              page_set_in_advance <= '0';
            end if;
            --===========================================================================================
          when S_FLUSH_STALL =>
            --===========================================================================================        
            if(src_i.err = '1') then
              s_send_pck      <= S_EOF;  -- we free page in EOF
              src_out_int.cyc <= '0';
              src_out_int.stb <= '0';
            elsif(src_i.stall = '0') then
              src_out_int.dat <= tmp_dat;
              src_out_int.adr <= tmp_adr;
              src_out_int.stb <= '1';
              src_out_int.sel <= tmp_sel;
              s_send_pck      <= S_DATA;
            end if;
            --===========================================================================================
          when S_FINISH_CYCLE =>
            --===========================================================================================        
            if(src_i.stall = '0') then
              src_out_int.stb <= '0';
            end if;

            -- making the CYCLE signal to go faster down... optimizing (hopefully not breaking)
            if(g_wb_ob_ignore_ack and src_out_int.stb = '0') then
              src_out_int.cyc <= '0';
              s_send_pck      <= S_EOF;  -- we free page in EOF
            elsif(ack_count = 1 and src_i.ack = '1' and not (src_out_int.stb = '1' and src_i.stall = '0')) then
              src_out_int.cyc <= '0';
              s_send_pck      <= S_EOF;  -- we free page in EOF
            end if;

            --===========================================================================================
          when S_EOF =>
            --===========================================================================================        
            if(ppfm_free = '0') then
              free_sent_pck_req      <= '1';
              free_sent_pck_addr <= pck_start_pgaddr;

              if(s_prep_to_send = S_NEWPCK_PAGE_READY and src_i.err = '0'  and src_i.stall = '0') then -- stall bug
                src_out_int.cyc  <= '1';
                s_send_pck       <= S_DATA;
                pck_start_pgaddr <= mpm_pg_addr;
              else
                s_send_pck <= S_IDLE;
              end if;
            else
              s_send_pck <= S_WAIT_FREE_PCK;
            end if;
            --===========================================================================================
          when S_RETRY =>
            --===========================================================================================        
            if(s_prep_to_send = S_RETRY_READY and src_i.stall = '0') then -- stall bug
              src_out_int.cyc  <= '1';
              s_send_pck       <= S_DATA;
              pck_start_pgaddr <= mpm_pg_addr;
            end if;
            --===========================================================================================
          when S_WAIT_FREE_PCK =>
            --===========================================================================================        
            if(ppfm_free = '0') then
              free_sent_pck_req      <= '1';
              free_sent_pck_addr <= pck_start_pgaddr;

              if(s_prep_to_send = S_NEWPCK_PAGE_READY and src_i.err = '0' and src_i.stall = '0') then -- stall bug
                src_out_int.cyc  <= '1';
                s_send_pck       <= S_DATA;
                pck_start_pgaddr <= mpm_pg_addr;
              else
                s_send_pck <= S_IDLE;
              end if;
            end if;
            --===========================================================================================
          when others =>
            --=========================================================================================== 
            s_send_pck      <= S_IDLE;
            src_out_int.cyc <= '0';
            src_out_int.stb <= '0';
        end case;
      end if;
    end if;
  end process p_send_pck_fsm;
  
  p_count_ifg : process(clk_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
         cyc_d0     <= '0';
         ifg_count  <= (others =>'0');
      else
        cyc_d0 <= src_out_int.cyc;
        
        if(src_out_int.cyc = '1' and cyc_d0 = '0') then
          ifg_count  <= tx_interframe_gap;
        elsif(src_out_int.cyc = '1' and src_out_int.sel = "10") then
          ifg_count  <= tx_interframe_gap - x"1";
        elsif(s_send_pck = S_IDLE and ifg_count > x"0") then
          ifg_count <= ifg_count - x"1";
        end if;
      end if;
    end if;
  end process p_count_ifg;


  p_count_acks : process(clk_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0' or src_out_int.cyc = '0') then
        ack_count <= (others => '0');
      else
        if(src_out_int.stb = '1' and src_i.stall = '0' and src_i.ack = '0') then
          ack_count <= ack_count + 1;
        elsif(src_i.ack = '1' and not(src_out_int.stb = '1' and src_i.stall = '0')) then
          ack_count <= ack_count - 1;
        end if;
      end if;
    end if;
  end process p_count_acks;

  -- here we perform the "free pages of the pck" process, 
  -- we do it while reading already the next pck
  free : process(clk_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        ppfm_free            <= '0';
        ppfm_free_sent       <= '0';
        ppfm_free_dropped    <= '0';
        ppfm_free_pgaddr     <= (others => '0');
      else
        if(free_sent_pck_req = '1' and ppfm_free = '0') then
          ppfm_free          <= '1';
          ppfm_free_sent     <= '1';
          ppfm_free_pgaddr   <= free_sent_pck_addr;
         elsif(free_dped_pck_req = '1' and ppfm_free = '0') then
          ppfm_free          <= '1';
          ppfm_free_dropped  <= '1';
          ppfm_free_pgaddr   <= free_dped_pck_addr;
        elsif(ppfm_free_done_i = '1' and ppfm_free = '1') then
          ppfm_free          <= '0';
          ppfm_free_dropped  <= '0';
          ppfm_free_sent     <= '0';
          ppfm_free_pgaddr   <= (others => '0');
        end if;
      end if;
    end if;
  end process free;

  -------------- MPM ---------------------
  mpm_dreq       <= not src_i.stall when (s_send_pck = S_DATA or s_send_pck = S_FLUSH_STALL) else
--commented out caused it triggered recursive pre-fetching
--                     '1'             when ((s_send_pck = S_EOF or s_send_pck = S_IDLE) and 
--                                           page_set_in_advance = '1')                         else 
                    '0';
  mpm_dreq_o     <= mpm_dreq;
  mpm_abort_o    <= mpm_abort;
  mpm_pg_addr_o  <= mpm_pg_addr;
  mpm_pg_valid_o <= mpm_pg_valid;

  -------------- pWB ----------------------
  out_dat_err <= '1' when src_out_int.stb = '1' and  -- we have valid data           *and*
                 (src_out_int.adr = c_WRF_STATUS) and  -- the address indicates status *and*
                 (f_unmarshall_wrf_status(src_out_int.dat).error = '1') else  -- the status indicates error       
                 '0';
  drop_at_retry <= '1' when (c_always_drop_at_retry     = true  and 
                             src_i.rty                  = '1') else
                   '1' when (c_always_drop_at_retry     = false and 
                             src_i.rty                  = '1' and 
                              not_empty_and_shaped_array = zeros) else
                   '0' ;

--dsel--  mpm2wb_adr_int <= mpm_d_i(g_mpm_data_width -1 downto g_mpm_data_width - g_wb_addr_width);
--dsel--  mpm2wb_sel_int <= '1' & mpm_dsel_i;   -- TODO: something generic
--dsel--  mpm2wb_dat_int <= mpm_d_i(g_wb_data_width -1 downto 0);

  mpm2wb_adr_int_pre <= mpm_d_i(g_mpm_data_width -1 downto g_mpm_data_width - g_wb_addr_width);
  mpm2wb_dat_int_pre <= mpm_d_i(g_wb_data_width -1 downto 0);

  p_decode_sel : process(mpm2wb_dat_int_pre, mpm2wb_adr_int_pre)
  begin
    if(mpm2wb_adr_int_pre = c_WRF_USER) then
      mpm2wb_dat_int(15 downto 8) <= mpm2wb_dat_int_pre(15 downto 8);
      mpm2wb_dat_int(7 downto 0)  <= (others => 'X');
      mpm2wb_adr_int              <= mpm2wb_dat_int_pre(7 downto 6);
      mpm2wb_sel_int              <= mpm2wb_dat_int_pre(5 downto 4);
    else
      mpm2wb_dat_int <= mpm2wb_dat_int_pre;
      mpm2wb_adr_int <= mpm2wb_adr_int_pre;
      mpm2wb_sel_int <= (others => '1');
    end if;
  end process;

  -- source out
  src_o              <= src_out_int;
  -------------- PPFM ----------------------
  ppfm_free_o        <= ppfm_free;
  ppfm_free_pgaddr_o <= ppfm_free_pgaddr;

  send_FSM  <= x"0" when (s_send_pck = S_IDLE) else
               x"1" when (s_send_pck = S_DATA) else
               x"2" when (s_send_pck = S_FLUSH_STALL) else
               x"3" when (s_send_pck = S_FINISH_CYCLE) else
               x"4" when (s_send_pck = S_EOF) else
               x"5" when (s_send_pck = S_RETRY) else
               x"6" when (s_send_pck = S_WAIT_FREE_PCK) else
               x"7" ;

  prep_FSM  <= x"5" when (s_prep_to_send = S_IDLE) else
               x"1" when (s_prep_to_send = S_NEWPCK_PAGE_READY) else
               x"2" when (s_prep_to_send = S_NEWPCK_PAGE_SET_IN_ADVANCE) else
               x"3" when (s_prep_to_send = S_NEWPCK_PAGE_USED) else
               x"4" when (s_prep_to_send = S_RETRY_PREPARE) else
               x"0" when (s_prep_to_send = S_RETRY_READY) else
               x"6" ;
  dbg_hwdu_o(7 downto 0)<= send_FSM & prep_FSM;
end behavoural;
