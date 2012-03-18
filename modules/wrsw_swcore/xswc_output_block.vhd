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

entity xswc_output_block is
  generic (

    g_max_pck_size_width              : integer;  --:= c_swc_max_pck_size_width  
    g_output_block_per_prio_fifo_size : integer;  --:= c_swc_output_fifo_size
    g_prio_width                      : integer;  --:= c_swc_prio_width;, c_swc_output_prio_num_width
    g_prio_num                        : integer;  --:= c_swc_output_prio_num
    -- new stuff
    g_mpm_page_addr_width             : integer;  --:= c_swc_page_addr_width;
    g_mpm_data_width                  : integer;  --:= c_swc_page_addr_width;
    g_mpm_partial_select_width        : integer;
    g_mpm_fetch_next_pg_in_advance    : boolean := false;
    g_wb_data_width                   : integer;
    g_wb_addr_width                   : integer;
    g_wb_sel_width                    : integer;
    g_wb_ob_ignore_ack                : boolean := true
    );
  port (
    clk_i   : in std_logic;
    rst_n_i : in std_logic;

-------------------------------------------------------------------------------
-- I/F with Pck Transfer Arbiter
-------------------------------------------------------------------------------

    pta_transfer_data_valid_i : in  std_logic;
    pta_pageaddr_i            : in  std_logic_vector(g_mpm_page_addr_width - 1 downto 0);
    pta_prio_i                : in  std_logic_vector(g_prio_width - 1 downto 0);
--    pta_pck_size_i            : in   std_logic_vector(g_max_pck_size_width - 1 downto 0);
    pta_transfer_data_ack_o   : out std_logic;

-------------------------------------------------------------------------------
-- I/F with Multiport Memory's Read Pump (MMP)
-------------------------------------------------------------------------------

    mpm_d_i            : in  std_logic_vector (g_mpm_data_width -1 downto 0);
    mpm_dvalid_i       : in  std_logic;
    mpm_dlast_i        : in  std_logic;
    mpm_dsel_i         : in  std_logic_vector (g_mpm_partial_select_width -1 downto 0);
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
-- pWB : output (goes to the Endpoint)
-------------------------------------------------------------------------------  

    src_i : in  t_wrf_source_in;
    src_o : out t_wrf_source_out;

    tap_out_o : out std_logic_vector(15 downto 0)
    );
end xswc_output_block;

architecture behavoural of xswc_output_block is
  
  constant c_per_prio_fifo_size_width : integer := integer(CEIL(LOG2(real(g_output_block_per_prio_fifo_size-1))));  -- c_swc_output_fifo_addr_width

  signal pta_transfer_data_ack : std_logic;

  signal wr_addr : std_logic_vector(g_prio_width + c_per_prio_fifo_size_width -1 downto 0);
  signal rd_addr : std_logic_vector(g_prio_width + c_per_prio_fifo_size_width -1 downto 0);

-- drop_imp:  
--   signal drop_addr             : std_logic_vector(g_prio_width + c_per_prio_fifo_size_width -1 downto 0);
--   signal ram_rd_addr           : std_logic_vector(g_prio_width + c_per_prio_fifo_size_width -1 downto 0);
--   signal drop_index            : std_logic_vector(g_prio_width - 1 downto 0);
--   signal drop_array            : std_logic_vector(g_prio_num - 1 downto 0);

  signal wr_prio         : std_logic_vector(g_prio_width - 1 downto 0);
  signal rd_prio         : std_logic_vector(g_prio_width - 1 downto 0);
  signal not_full_array  : std_logic_vector(g_prio_num - 1 downto 0);
  signal full_array      : std_logic_vector(g_prio_num - 1 downto 0);
  signal not_empty_array : std_logic_vector(g_prio_num - 1 downto 0);
  signal read_array      : std_logic_vector(g_prio_num - 1 downto 0);
  signal read            : std_logic_vector(g_prio_num - 1 downto 0);
  signal write_array     : std_logic_vector(g_prio_num - 1 downto 0);
  signal write           : std_logic_vector(g_prio_num - 1 downto 0);
  signal wr_en           : std_logic;
  signal rd_data_valid   : std_logic;
  signal drop_data_valid : std_logic;
  signal zeros           : std_logic_vector(g_prio_num - 1 downto 0);

  subtype t_head_and_head is std_logic_vector(c_per_prio_fifo_size_width - 1 downto 0);

  type t_addr_array is array (g_prio_num - 1 downto 0) of t_head_and_head;

  signal wr_array : t_addr_array;
  signal rd_array : t_addr_array;

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

  function f_prepstate_2_slv (arg : t_prep_to_send) return std_logic_vector is
  begin
    case arg is
      when S_IDLE                       => return "000";
      when S_NEWPCK_PAGE_READY          => return "001";
      when S_NEWPCK_PAGE_SET_IN_ADVANCE => return "010";
      when S_NEWPCK_PAGE_USED           => return "011";
      when S_RETRY_PREPARE              => return "100";
      when S_RETRY_READY                => return "101";
      when others                       => return "111";
    end case;
    return "111";
  end f_prepstate_2_slv;

  function f_sendstate_2_slv (arg : t_send_pck) return std_logic_vector is
  begin
    case arg is
      when S_IDLE          => return "000";
      when S_DATA          => return "001";
      when S_FLUSH_STALL   => return "010";
      when S_FINISH_CYCLE  => return "011";
      when S_EOF           => return "100";
      when S_RETRY         => return "101";
      when S_WAIT_FREE_PCK => return "110";
    end case;
    return "111";
  end f_sendstate_2_slv;


  signal s_send_pck     : t_send_pck;
  signal s_prep_to_send : t_prep_to_send;

  signal wr_data : std_logic_vector(g_mpm_page_addr_width - 1 downto 0);
  signal rd_data : std_logic_vector(g_mpm_page_addr_width - 1 downto 0);


  signal ppfm_free        : std_logic;
  signal ppfm_free_pgaddr : std_logic_vector(g_mpm_page_addr_width - 1 downto 0);

  signal pck_start_pgaddr : std_logic_vector(g_mpm_page_addr_width - 1 downto 0);

  signal start_free_pck_addr : std_logic_vector(g_mpm_page_addr_width - 1 downto 0);
  signal start_free_pck      : std_logic;

  signal ram_zeros : std_logic_vector(g_mpm_page_addr_width- 1 downto 0);
  signal ram_ones  : std_logic_vector((g_mpm_page_addr_width+7)/8 - 1 downto 0);

  signal request_retry : std_logic;
  -- pipelined WB  
  -- source out
  signal src_adr_int   : std_logic_vector(1 downto 0);
  signal src_dat_int   : std_logic_vector(15 downto 0);
  signal src_dat_d     : std_logic_vector(15 downto 0);
  signal src_stb_d     : std_logic;
  signal src_cyc_int   : std_logic;
  signal src_stb_int   : std_logic;
  signal src_we_int    : std_logic;
  signal src_sel_int   : std_logic_vector(1 downto 0);
  signal out_dat_err   : std_logic;
  -- source in
  signal src_ack_int   : std_logic;
  signal src_stall_int : std_logic;
  signal src_err_int   : std_logic;
  signal src_rty_int   : std_logic;

  signal mpm_pg_addr_memorized       : std_logic_vector(g_mpm_page_addr_width -1 downto 0);
  signal mpm_pg_addr_memorized_valid : std_logic;

  signal mpm_dreq     : std_logic;
  signal mpm_abort    : std_logic;
  signal mpm_pg_addr  : std_logic_vector (g_mpm_page_addr_width -1 downto 0);
  signal mpm_pg_valid : std_logic;

  signal mpm2wb_dat_int : std_logic_vector (g_wb_data_width -1 downto 0);
  signal mpm2wb_sel_int : std_logic_vector (g_wb_sel_width -1 downto 0);
  signal mpm2wb_adr_int : std_logic_vector (g_wb_addr_width -1 downto 0);

  signal src_out_int : t_wrf_source_out;
  signal tmp_sel     : std_logic_vector(g_wb_sel_width - 1 downto 0);
  signal tmp_dat     : std_logic_vector(g_wb_data_width - 1 downto 0);
  signal tmp_adr     : std_logic_vector(g_wb_addr_width - 1 downto 0);

  signal ack_count : unsigned(3 downto 0);

  signal set_next_pg_addr     : std_logic;
  signal not_set_next_pg_addr : std_logic;

  signal wr_en_reg   : std_logic;
  signal wr_addr_reg : std_logic_vector(g_prio_width + c_per_prio_fifo_size_width -1 downto 0);
  signal wr_data_reg : std_logic_vector(g_mpm_page_addr_width - 1 downto 0);

  signal rd_addr_reg : std_logic_vector(g_prio_width + c_per_prio_fifo_size_width -1 downto 0);

  signal cycle_frozen     : std_logic;
  signal cycle_frozen_cnt : unsigned(5 downto 0);

  function f_slv_resize(x : std_logic_vector; len : natural) return std_logic_vector is
    variable tmp : std_logic_vector(len-1 downto 0);
  begin
    tmp                      := (others => '0');
    tmp(x'length-1 downto 0) := x;
    return tmp;
  end f_slv_resize;
  

  
begin  --  behavoural

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

  wr_prio <= not pta_prio_i;

  wr_data <= pta_pageaddr_i;

  wr_addr <= wr_prio & wr_array(0) when wr_prio = "000" else
             wr_prio & wr_array(1) when wr_prio = "001" else
             wr_prio & wr_array(2) when wr_prio = "010" else
             wr_prio & wr_array(3) when wr_prio = "011" else
             wr_prio & wr_array(4) when wr_prio = "100" else
             wr_prio & wr_array(5) when wr_prio = "101" else
             wr_prio & wr_array(6) when wr_prio = "110" else
             wr_prio & wr_array(7) when wr_prio = "111" else
             (others => 'X');
  
  rd_addr <= rd_prio & rd_array(0) when rd_prio = "000" else
             rd_prio & rd_array(1) when rd_prio = "001" else
             rd_prio & rd_array(2) when rd_prio = "010" else
             rd_prio & rd_array(3) when rd_prio = "011" else
             rd_prio & rd_array(4) when rd_prio = "100" else
             rd_prio & rd_array(5) when rd_prio = "101" else
             rd_prio & rd_array(6) when rd_prio = "110" else
             rd_prio & rd_array(7) when rd_prio = "111" else
             (others => 'X');

-- drop_imp:
--   drop_addr <= drop_index & rd_array(0) when drop_index = "000" else
--                drop_index & rd_array(1) when drop_index = "001" else
--                drop_index & rd_array(2) when drop_index = "010" else
--                drop_index & rd_array(3) when drop_index = "011" else
--                drop_index & rd_array(4) when drop_index = "100" else
--                drop_index & rd_array(5) when drop_index = "101" else
--                drop_index & rd_array(6) when drop_index = "110" else
--                drop_index & rd_array(7) when drop_index = "111" else
--                (others => 'X');   

--  ram_rd_addr <= rd_addr when (mpm_pg_valid = '1') else drop_addr;
  
  RD_ENCODE : swc_prio_encoder
    generic map (
      g_num_inputs  => g_prio_num,
      g_output_bits => g_prio_width)
    port map (
      in_i     => not_empty_array,
      onehot_o => read_array,
      out_o    => rd_prio);

  write_array <= "00000001" when wr_prio = "000" else
                 "00000010" when wr_prio = "001" else
                 "00000100" when wr_prio = "010" else
                 "00001000" when wr_prio = "011" else
                 "00010000" when wr_prio = "100" else
                 "00100000" when wr_prio = "101" else
                 "01000000" when wr_prio = "110" else
                 "10000000" when wr_prio = "111" else
                 "00000000";
  
  wr_en <= write(0) and not_full_array(0) when wr_prio = "000" else
           write(1) and not_full_array(1) when wr_prio = "001" else
           write(2) and not_full_array(2) when wr_prio = "010" else
           write(3) and not_full_array(3) when wr_prio = "011" else
           write(4) and not_full_array(4) when wr_prio = "100" else
           write(5) and not_full_array(5) when wr_prio = "101" else
           write(6) and not_full_array(6) when wr_prio = "110" else
           write(7) and not_full_array(7) when wr_prio = "111" else
           '0';
  -- I don't like this                 
  pta_transfer_data_ack_o <= not_full_array(0) when wr_prio = "000" else
                             not_full_array(1) when wr_prio = "001" else
                             not_full_array(2) when wr_prio = "010" else
                             not_full_array(3) when wr_prio = "011" else
                             not_full_array(4) when wr_prio = "100" else
                             not_full_array(5) when wr_prio = "101" else
                             not_full_array(6) when wr_prio = "110" else
                             not_full_array(7) when wr_prio = "111" else
                             '0';
  
  prio_ctrl : for i in 0 to g_prio_num - 1 generate
    
    write(i) <= write_array(i) and pta_transfer_data_valid_i;
    read(i)  <= read_array(i) and mpm_pg_valid;
-- drop_imp:
--     read(i)         <= (read_array(i)  and mpm_pg_valid) or (drop_array(i) and not mpm_pg_valid);    

    PRIO_QUEUE_CTRL : swc_ob_prio_queue
      generic map(
        g_per_prio_fifo_size_width => c_per_prio_fifo_size_width  -- c_swc_output_fifo_addr_width
        )
      port map (
        clk_i       => clk_i,
        rst_n_i     => rst_n_i,
        write_i     => write(i),
        read_i      => read(i),
        not_full_o  => not_full_array(i),
        not_empty_o => not_empty_array(i),
        wr_en_o     => open,            --wr_en_array(i),
        wr_addr_o   => wr_array(i),
        rd_addr_o   => rd_array(i)
        );
-- drop_imp:
--  full_array(i) <= not not_full_array(i);
  end generate prio_ctrl;

-- drop_imp:
--   DROP_ENCODE : swc_prio_encoder
--     generic map (
--       g_num_inputs  => g_prio_num,
--       g_output_bits => g_prio_width)
--     port map (
--       in_i     => full_array,
--       onehot_o => drop_array,
--       out_o    => drop_index);

  PRIO_QUEUE: swc_rd_wr_ram
    generic map (
      g_data_width => g_mpm_page_addr_width,  -- + g_max_pck_size_width,
      g_size       => (g_prio_num * g_output_block_per_prio_fifo_size))
    port map (
      clk_i => clk_i,
      we_i  => wr_en_reg,
      wa_i  => wr_addr_reg,
      wd_i  => wr_data_reg,
      ra_i  => rd_addr,
      rd_o  => rd_data);
  
  
  --PRIO_QUEUE : generic_dpram
  --  generic map (
  --    g_data_width => g_mpm_page_addr_width,  -- + g_max_pck_size_width,
  --    g_size       => (g_prio_num * g_output_block_per_prio_fifo_size)
  --    )
  --  port map (
  --    -- Port A -- writing
  --    clka_i => clk_i,
  --    bwea_i => (others => '1'),              --ram_ones,
  --    wea_i  => wr_en_reg,
  --    aa_i   => wr_addr_reg,
  --    da_i   => wr_data_reg,
  --    qa_o   => open,

  --    -- Port B  -- reading
  --    clkb_i => clk_i,
  --    bweb_i => (others => '1'),        --ram_ones, 
  --    web_i  => '0',
  --    ab_i   => rd_addr,                -- drop_imp : ram_rd_addr,
  --    db_i   => (others => '0'),        --ram_zeros,
  --    qb_o   => rd_data
  --    );


  wr_ram : process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        wr_en_reg   <= '0';
        wr_addr_reg <= (others => '0');
        wr_data_reg <= (others => '0');
        --rd_addr_reg <= (others => '0');
      else
        wr_en_reg   <= wr_en;
        wr_addr_reg <= wr_addr;
        wr_data_reg <= wr_data;
        --rd_addr_reg <= rd_addr;
      end if;
    end if;
  end process wr_ram;


  -- check if there is any valid frame in any output queue
  -- rd_data_valid=HIGH indicates that there is something to send out
  rd_valid : process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        rd_data_valid   <= '0';
        drop_data_valid <= '0';
      else
        
        if(not_empty_array = zeros) then
          rd_data_valid <= '0';
        else
          rd_data_valid <= '1';
        end if;
-- drop_imp :
--        if(full_array = zeros) then
--          drop_data_valid <= '0';
--        else
--          drop_data_valid <= '1';
--       end if;       
      end if;
    end if;
  end process;

  --==================================================================================================
  -- FSM to prepare next pck to be send
  --==================================================================================================
  -- This state machine takes data, if available) from the output queue. The data is only the 
  -- pckfirst_page address (this is all we need).
  -- It dane makes the page available for the MPM, once it's set to the MPM, the FSM waits until
  -- the MPM is ready to set pckstart_page for the next pck (in current implementation, this can
  -- happen when reading the last word). The pckstart_page is made available to the MPM, and 
  -- so again and again...
  -- The fun starts when the Endpoint requests retry of sending. we need to abort the current 
  -- MPM readout (currently not implemented in the MPM) and set again the same pckstart_page
  -- (this needs we need to put aside and remember the page which we've already read from the 
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
        mpm_pg_addr                 <= (others => '0');
        mpm_pg_valid                <= '0';
        mpm_abort                   <= '0';
        mpm_pg_addr_memorized_valid <= '0';
        mpm_pg_addr_memorized       <= (others => '0');
        --========================================
      else
        -- default values
        mpm_pg_valid <= '0';
        mpm_abort    <= '0';

        case s_prep_to_send is
          --===========================================================================================
          when S_IDLE =>
            --===========================================================================================   
            if(request_retry = '1') then
              mpm_abort      <= '1';
              s_prep_to_send <= S_RETRY_PREPARE;
            elsif(set_next_pg_addr = '1') then
              mpm_pg_addr  <= rd_data(g_mpm_page_addr_width - 1 downto 0);
              mpm_pg_valid <= '1';
              if(s_send_pck = S_DATA or s_send_pck = S_FINISH_CYCLE) then
                s_prep_to_send <= S_NEWPCK_PAGE_SET_IN_ADVANCE;
              else
                s_prep_to_send <= S_NEWPCK_PAGE_READY;
              end if;
            end if;
            --===========================================================================================
          when S_NEWPCK_PAGE_SET_IN_ADVANCE =>
            --===========================================================================================        
            if(request_retry = '1') then
              mpm_abort                   <= '1';
              s_prep_to_send              <= S_RETRY_PREPARE;
              mpm_pg_addr_memorized       <= mpm_pg_addr;
              mpm_pg_addr_memorized_valid <= '1';
            elsif(mpm_dlast_i = '1') then
              s_prep_to_send <= S_NEWPCK_PAGE_READY;
            end if;
            --===========================================================================================
          when S_NEWPCK_PAGE_READY =>
            --=========================================================================================== 
            
            if(request_retry = '1') then
              mpm_abort      <= '1';
              s_prep_to_send <= S_RETRY_PREPARE;
            elsif(s_send_pck = S_DATA) then
              s_prep_to_send <= S_NEWPCK_PAGE_USED;
            end if;


            --===========================================================================================
          when S_NEWPCK_PAGE_USED =>
            --=========================================================================================== 
            
            if(request_retry = '1') then
              mpm_abort      <= '1';
              s_prep_to_send <= S_RETRY_PREPARE;
            elsif(set_next_pg_addr = '1') then
              mpm_pg_addr  <= rd_data(g_mpm_page_addr_width - 1 downto 0);
              mpm_pg_valid <= '1';
              if(s_send_pck = S_DATA or s_send_pck = S_FINISH_CYCLE) then
                s_prep_to_send <= S_NEWPCK_PAGE_SET_IN_ADVANCE;
              else
                s_prep_to_send <= S_NEWPCK_PAGE_READY;
              end if;
            elsif(not_set_next_pg_addr = '1') then
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

            if(mpm_pg_addr_memorized_valid = '1' and set_next_pg_addr = '1') then
              mpm_pg_addr_memorized_valid <= '0';
              mpm_pg_addr                 <= mpm_pg_addr_memorized;
              mpm_pg_valid                <= '1';
              if(s_send_pck = S_DATA or s_send_pck = S_FINISH_CYCLE) then
                s_prep_to_send <= S_NEWPCK_PAGE_SET_IN_ADVANCE;
              else
                s_prep_to_send <= S_NEWPCK_PAGE_READY;
              end if;
              --elsif(rd_data_valid = '1' and mpm_pg_req_i = '1') then
            elsif(set_next_pg_addr = '1') then
              mpm_pg_addr  <= rd_data(g_mpm_page_addr_width - 1 downto 0);
              mpm_pg_valid <= '1';
              if(s_send_pck = S_DATA) then
                s_prep_to_send <= S_NEWPCK_PAGE_SET_IN_ADVANCE;
              else
                s_prep_to_send <= S_NEWPCK_PAGE_READY;
              end if;
            elsif(not_set_next_pg_addr = '1') then
              s_prep_to_send <= S_IDLE;
            end if;

            --===========================================================================================
          when others =>
            --=========================================================================================== 
            s_prep_to_send <= S_IDLE;
        end case;
      end if;
    end if;
  end process p_prep_to_send_fsm;

  next_page_set_in_advance : if (g_mpm_fetch_next_pg_in_advance = true) generate
    set_next_pg_addr     <= '1' when (rd_data_valid = '1' and mpm_pg_req_i = '1' and mpm_pg_valid = '0') else '0';
    not_set_next_pg_addr <= '1' when (rd_data_valid = '0' and mpm_pg_req_i = '1')                        else '0';
  end generate next_page_set_in_advance;

  next_page_set_after_pck_transmision : if (g_mpm_fetch_next_pg_in_advance = false) generate
    set_next_pg_addr     <= '1' when (rd_data_valid = '1' and mpm_pg_req_i = '1' and mpm_pg_valid = '0' and s_send_pck = S_IDLE) else '0';
    not_set_next_pg_addr <= '1' when (mpm_pg_req_i = '1' and mpm_pg_valid = '0')                                                 else '0';
  end generate next_page_set_after_pck_transmision;


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
        start_free_pck      <= '0';
        start_free_pck_addr <= (others => '0');
        tmp_adr             <= (others => '0');
        tmp_dat             <= (others => '0');
        tmp_sel             <= (others => '0');
        --========================================
      else
        -- default values
        start_free_pck <= '0';
        request_retry  <= '0';

        case s_send_pck is
          --===========================================================================================
          when S_IDLE =>
            --===========================================================================================   

            if(s_prep_to_send = S_NEWPCK_PAGE_READY and src_i.err = '0' and src_i.stall = '0') then
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

            if(src_i.err = '1') then
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

            if(((ack_count = 0) or g_wb_ob_ignore_ack) and src_out_int.stb = '0') then
              src_out_int.cyc <= '0';
              s_send_pck      <= S_EOF;  -- we free page in EOF
            end if;

            --===========================================================================================
          when S_EOF =>
            --===========================================================================================        
            if(ppfm_free = '0') then
              start_free_pck      <= '1';
              start_free_pck_addr <= pck_start_pgaddr;

              if(s_prep_to_send = S_NEWPCK_PAGE_READY and src_i.err = '0') then
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
            if(s_prep_to_send = S_RETRY_READY) then
              src_out_int.cyc  <= '1';
              s_send_pck       <= S_DATA;
              pck_start_pgaddr <= mpm_pg_addr;
            end if;
            --===========================================================================================
          when S_WAIT_FREE_PCK =>
            --===========================================================================================        
            if(ppfm_free = '0') then
              start_free_pck      <= '1';
              start_free_pck_addr <= pck_start_pgaddr;

              if(s_prep_to_send = S_NEWPCK_PAGE_READY and src_i.err = '0') then
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
            s_send_pck <= S_IDLE;
        end case;
      end if;
    end if;
  end process p_send_pck_fsm;

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
        ppfm_free        <= '0';
        ppfm_free_pgaddr <= (others => '0');
      else
        if(start_free_pck = '1') then
          ppfm_free        <= '1';
          ppfm_free_pgaddr <= start_free_pck_addr;
-- drop_imp:          
--         elsif(drop_data_valid = '1') then
--           ppfm_free         <= '1';
--           ppfm_free_pgaddr  <= rd_data(g_mpm_page_addr_width - 1 downto 0);
        elsif(ppfm_free_done_i = '1') then
          ppfm_free        <= '0';
          ppfm_free_pgaddr <= (others => '0');
        end if;
      end if;
    end if;
    
  end process free;

  -------------- MPM ---------------------
  mpm_dreq       <= not src_i.stall when (s_send_pck = S_DATA or s_send_pck = S_FLUSH_STALL) else '0';
  mpm_dreq_o     <= mpm_dreq;
  mpm_abort_o    <= mpm_abort;
  mpm_pg_addr_o  <= mpm_pg_addr;
  mpm_pg_valid_o <= mpm_pg_valid;

  -------------- pWB ----------------------
  out_dat_err <= '1' when src_out_int.stb = '1' and  -- we have valid data           *and*
                 (src_out_int.adr = c_WRF_STATUS) and  -- the address indicates status *and*
                 (f_unmarshall_wrf_status(src_out_int.dat).error = '1') else  -- the status indicates error       
                 '0';

  mpm2wb_adr_int <= mpm_d_i(g_mpm_data_width -1 downto g_mpm_data_width - g_wb_addr_width);
  mpm2wb_sel_int <= '1' & mpm_dsel_i;   -- TODO: something generic
  mpm2wb_dat_int <= mpm_d_i(g_wb_data_width -1 downto 0);

  -- source out
  src_o              <= src_out_int;
  -------------- PPFM ----------------------
  ppfm_free_o        <= ppfm_free;
  ppfm_free_pgaddr_o <= ppfm_free_pgaddr;
  


end behavoural;
