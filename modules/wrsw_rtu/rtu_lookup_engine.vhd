-------------------------------------------------------------------------------
-- Title      : Routing Table Unit - CAM (BRAM) lookup 
-- Project    : White Rabbit Switch
-------------------------------------------------------------------------------
-- File       : wrsw_rtu_cam_lookup.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-05-22
-- Last update: 2013-03-24
-- Platform   : FPGA-generic
-- Standard   : VHDL
-------------------------------------------------------------------------------
-- Looks for MAC entry in CAM (BRAM)
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
-- 2010-05-22  1.0      lipinskimm          Created
-- 2013-03-24  1.1      lipinskimm          aging-related bugfix
-------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


use work.rtu_private_pkg.all;
use work.genram_pkg.all;


entity rtu_lookup_engine is
  generic(
    g_num_ports : integer;
    g_hash_size : integer := 11);
  port(

    -----------------------------------------------------------------
    --| General IOs
    -----------------------------------------------------------------
    clk_match_i : in std_logic;
    clk_sys_i   : in std_logic;

    -- reset (synchronous, active low)
    rst_n_i : in std_logic;

    -------------------------------------------------------------------------
    -- MFIFO I/F
    -------------------------------------------------------------------------

    mfifo_rd_req_o   : out std_logic;
    mfifo_rd_empty_i : in  std_logic;
    mfifo_ad_sel_i   : in  std_logic;
    mfifo_ad_val_i   : in  std_logic_vector(31 downto 0);
    mfifo_trigger_i  : in  std_logic;
    mfifo_busy_o     : out std_logic;

    -------------------------------------------------------------------------------
    -- read ctrl/search
    -------------------------------------------------------------------------------
    -- high pulse - start searching
    start_i : in  std_logic;
    -- high pulse acknowledges that the response data was read
    ack_i   : in  std_logic;
    -- '1' - entry foud, '0'- not found
    found_o : out std_logic;
    -- indicates the address of entry (address read from hash table)
    hash_i  : in  std_logic_vector(c_wrsw_hash_width-1 downto 0);
    -- mac to be found
    mac_i   : in  std_logic_vector(c_wrsw_mac_addr_width -1 downto 0);
    -- fid to be found
    fid_i   : in  std_logic_vector(c_wrsw_fid_width - 1 downto 0);
    -- indicates that the search has been finished (whether the entry was found or not)
    drdy_o  : out std_logic;

    -- mask indicating the source of request (on which port the frame was received)
    port_i : in std_logic_vector(g_num_ports -1 downto 0); -- ML (24/03/2013): aging bugfix
    
    -- indicates whetehr the sarch concenrs
    -- 0: source MAC
    -- 1: destination MAC
    src_dst_i : in std_logic; -- ML (24/03/2013): aging bugfix

    -------------------------------------------------------------------------------
    -- read data
    -------------------------------------------------------------------------------  

    entry_o : out t_rtu_htab_entry

    );

end rtu_lookup_engine;

architecture behavioral of rtu_lookup_engine is

  type t_slv32_array is array(integer range<>) of std_logic_vector(31 downto 0);
  type t_lookup_state is (IDLE, NEXT_BUCKET, OUTPUT_RESULT);
  type t_mfifo_state is (EMPTY, READ_1ST_WORD, WAIT_LOOKUP_IDLE, UPDATE_MEM);

  signal cur_entry   : t_rtu_htab_entry;
  signal mem_out     : t_slv32_array(4 downto 0);
  signal mem_host_we : std_logic_vector(4 downto 0);
  signal mem_addr    : std_logic_vector(c_wrsw_hash_width-1 + 2 downto 0);

  signal bucket_entry    : unsigned(1 downto 0);
  signal bucket_entry_d0 : unsigned(1 downto 0);
  signal lookup_state    : t_lookup_state;
  signal hash_reg        : std_logic_vector(c_wrsw_hash_width-1 downto 0);


  signal host_waddr : std_logic_vector(c_wrsw_hash_width+4 downto 0);
  signal host_wdata : std_logic_vector(31 downto 0);
  signal host_we    : std_logic;

  signal mfifo_state       : t_mfifo_state;
  signal mfifo_update_busy : std_logic;


begin

  process(host_we, host_waddr)
  begin
    if(host_we = '1') then
      case host_waddr(2 downto 0) is
        when "000"  => mem_host_we <= "00001";
        when "001"  => mem_host_we <= "00010";
        when "010"  => mem_host_we <= "00100";
        when "011"  => mem_host_we <= "01000";
        when "100"  => mem_host_we <= "10000";
        when others => mem_host_we <= "00000";
      end case;
    else
      mem_host_we <= (others => '0');
    end if;
  end process;

  gen_ram_blocks : for i in 0 to 4 generate

    U_dpram : generic_dpram
      generic map (
        g_data_width       => 32,
        g_size             => 2**(c_wrsw_hash_width+2),
        g_with_byte_enable => false,
        g_dual_clock       => true)
      port map (
        rst_n_i => rst_n_i,
        clka_i  => clk_sys_i,
        bwea_i  => "1111",
        wea_i   => mem_host_we(i),
        aa_i    => host_waddr(host_waddr'left downto 3),
        da_i    => host_wdata,
        qa_o    => open,

        clkb_i => clk_match_i,
        bweb_i => "1111",
        web_i  => '0',
        ab_i   => mem_addr,
        db_i   => x"00000000",
        qb_o   => mem_out(i));

  end generate gen_ram_blocks;


  p_register_hash : process(clk_match_i)
  begin
    if rising_edge(clk_match_i) then
      if(start_i = '1' and lookup_state = IDLE) then
        hash_reg <= hash_i;
      end if;
    end if;
  end process;


  p_gen_mem_addr : process(bucket_entry, hash_i, lookup_state, start_i, hash_reg)
  begin
    if(start_i = '1' and lookup_state = IDLE) then
      mem_addr <= hash_i & "00";
    else
      mem_addr <= hash_reg &std_logic_vector(bucket_entry);
    end if;
  end process;

  cur_entry              <= f_unmarshall_htab_entry(mem_out(0), mem_out(1), mem_out(2), mem_out(3), mem_out(4));
  cur_entry.bucket_entry <= std_logic_vector(bucket_entry_d0);

  p_match : process(clk_match_i)
  begin
    if rising_edge(clk_match_i) then
      if(rst_n_i = '0') then
        lookup_state    <= IDLE;
        bucket_entry    <= (others => '0');
        bucket_entry_d0 <= (others => '0');
        drdy_o          <= '0';
        found_o         <= '0';
      else

        bucket_entry_d0 <= bucket_entry;

        case lookup_state is
          when IDLE =>

            
            if(start_i = '1' and mfifo_update_busy = '0') then
              lookup_state <= NEXT_BUCKET;
              bucket_entry <= bucket_entry +1;
            else
              bucket_entry <= (others => '0');
            end if;

            
          when NEXT_BUCKET =>

            -- got a match?
            -- ML (24/03/2013): aging bugfix --------------------------------------------------
            if(cur_entry.valid = '1' and cur_entry.fid = fid_i and cur_entry.mac = mac_i and 
               src_dst_i = '0' and -- this is source MAC => need to check that it's been received
                                   -- on the correct port:
               (cur_entry.port_mask_dst(g_num_ports-1 downto 0) and port_i) = port_i)  then
              drdy_o       <= '1';
              found_o      <= '1';
              entry_o      <= cur_entry;
              lookup_state <= OUTPUT_RESULT;
            elsif(cur_entry.valid = '1' and cur_entry.fid = fid_i and cur_entry.mac = mac_i and 
                  src_dst_i = '1')  then  -- this is destination MAC search, 
              drdy_o       <= '1';
              found_o      <= '1';
              entry_o      <= cur_entry;
              lookup_state <= OUTPUT_RESULT;
            ------------------------------------------------------------------------------------
            elsif(bucket_entry = "00" or cur_entry.valid = '0') then
              drdy_o       <= '1';
              found_o      <= '0';
              lookup_state <= OUTPUT_RESULT;
            end if;

            bucket_entry <= bucket_entry + 1;
            
          when OUTPUT_RESULT =>
            bucket_entry <= (others => '0');
            if(ack_i = '1') then
              lookup_state <= IDLE;
              found_o      <= '0';
              drdy_o       <= '0';
            end if;
        end case;
      end if;
    end if;
  end process;

  p_mfifo_update : process(clk_sys_i)
  begin
    if rising_edge(clk_sys_i) then
      if rst_n_i = '0' then
        host_wdata        <= (others => '0');
        host_waddr        <= (others => '0');
        host_we           <= '0';
        mfifo_state       <= EMPTY;
        mfifo_update_busy <= '0';
        mfifo_rd_req_o    <= '0';
      else
        case mfifo_state is
          when EMPTY =>
            host_we <= '0';

            if(mfifo_rd_empty_i = '0' and mfifo_trigger_i = '1') then
              if(lookup_state /= IDLE) then
                mfifo_state <= WAIT_LOOKUP_IDLE;
              else
                mfifo_rd_req_o    <= '1';
                mfifo_state       <= READ_1ST_WORD;
                mfifo_update_busy <= '1';
              end if;
            end if;

          when WAIT_LOOKUP_IDLE =>
            if(lookup_state = IDLE) then
              mfifo_rd_req_o    <= '1';
              mfifo_state       <= READ_1ST_WORD;
              mfifo_update_busy <= '1';
            end if;

          when READ_1ST_WORD =>
            mfifo_state <= UPDATE_MEM;
            
          when UPDATE_MEM =>
            if(mfifo_rd_empty_i = '1') then
              mfifo_state       <= EMPTY;
              mfifo_rd_req_o    <= '0';
              mfifo_update_busy <= '0';
            end if;

            if(mfifo_ad_sel_i = '1') then
              host_waddr <= mfifo_ad_val_i (host_waddr'left downto 0);
              host_we    <= '0';
            else
              if(host_we = '1') then
                host_waddr <= std_logic_vector(unsigned(host_waddr) + 1);
              end if;

              host_wdata <= mfifo_ad_val_i;
              host_we    <= '1';
            end if;
            
        end case;
        
      end if;
    end if;
  end process;


  mfifo_busy_o <= mfifo_update_busy;
  
end architecture;
