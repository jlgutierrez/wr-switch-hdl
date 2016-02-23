-------------------------------------------------------------------------------
-- Title      : HSR Link Redundancy Entity - Manage from taggers
-- Project    : White Rabbit
-------------------------------------------------------------------------------
-- File       : wrsw_hsr_arbfromtaggers.vhd
-- Author     : 
-- Company    :  
-- Department : 
-- Created    : 2016-02-22
-- Last update: 2016-02-22
-- Platform   : FPGA-generic
-- Standard   : VHDL '93
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
--
-- Copyright (c) 2011 - 2012 CERN / BE-CO-HT
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

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.CEIL;
use ieee.math_real.log2;

library work;
use work.swc_swcore_pkg.all;
use work.wr_fabric_pkg.all;
use work.wrsw_shared_types_pkg.all;
use work.endpoint_private_pkg.all;
use work.mpm_pkg.all;
use work.wrsw_hsr_lre_pkg.all;
use work.genram_pkg.all;
use work.memory_loader_pkg.all;

entity wrsw_hsr_arbfromtaggers is

  generic(
    g_adr_width : integer := 2;
    g_dat_width : integer :=16
    );
  port(
  
	 	rst_n_i			: in	std_logic;
		clk_i				: in	std_logic;
		
		-- Towards endpoints Tx
		ep_src_o		: out	t_wrf_source_out_array(1 downto 0);
		ep_src_i		: in	t_wrf_source_in_array(1 downto 0);
		
		-- From hsr taggers
		tagger_snk_i	: in	t_wrf_sink_in_array(1 downto 0);
		tagger_snk_o	: out t_wrf_sink_out_array(1 downto 0)

    );
end wrsw_hsr_arbfromtaggers;

architecture behavioral of wrsw_hsr_arbfromtaggers is

  constant c_NUM_PORTS     : integer := 8;
  
  component ep_rx_wb_master
    generic (
      g_ignore_ack   : boolean;
      g_cyc_on_stall : boolean := false);
    port (
      clk_sys_i  : in  std_logic;
      rst_n_i    : in  std_logic;
      snk_fab_i  : in  t_ep_internal_fabric;
      snk_dreq_o : out std_logic;
      src_wb_i   : in  t_wrf_source_in;
      src_wb_o   : out t_wrf_source_out);
  end component;
  
  component chipscope_icon
    port (
      CONTROL0 : inout std_logic_vector(35 downto 0));
  end component;
  component chipscope_ila
    port (
      CONTROL : inout std_logic_vector(35 downto 0);
      CLK     : in    std_logic;
      TRIG0   : in    std_logic_vector(31 downto 0);
      TRIG1   : in    std_logic_vector(31 downto 0);
      TRIG2   : in    std_logic_vector(31 downto 0);
      TRIG3   : in    std_logic_vector(31 downto 0));
  end component;

  signal CONTROL0 : std_logic_vector(35 downto 0);
  signal TRIG0		: std_logic_vector(31 downto 0);
  signal TRIG1		: std_logic_vector(31 downto 0);
  signal TRIG2		: std_logic_vector(31 downto 0);
  signal TRIG3		: std_logic_vector(31 downto 0);
  
  signal tagger_snk_in		: t_wrf_source_out_array(1 downto 0);
  signal ep_src_in			: t_wrf_source_in_array(1 downto 0);
  
  type	t_wr_state					is (S_IDLE, S_WRITING, S_EOF, S_FULL);
  signal	wr_state						:	t_wr_state;
  
  type	t_rd_state					is (IDLE, READING);
  signal rd_state						:	t_rd_state;
  
  type	t_mem_slot_status is record
		available						:	std_logic;
		writing							:	std_logic;
		written							:	std_logic;
		reading							:	std_logic;
		finished							:	std_logic;
		source							:	std_logic;
	end record;
	
	signal slot0, slot1				: t_mem_slot_status :=('1','0','0','0','0','0');
  
	constant c_mem_width				: natural := 21;
	constant c_mem_size				: natural := 2*800;
	constant c_addr_size				: natural := f_log2_size(c_mem_size);
	constant c_slot0_base			: std_logic_vector(c_addr_size-1 downto 0) := "00000000000";
	constant c_slot1_base			: std_logic_vector(c_addr_size-1 downto 0) := "11001000000";
	
	constant c_sig_sof				: std_logic_vector(c_mem_width-1-1 downto 0) := "11000000000011111111";
	constant c_sig_eof				: std_logic_vector(c_mem_width-1-1 downto 0) := "11000000000010101010";

	signal	write_a, write_b		: std_logic := '0';
	signal	addr_a, addr_b			: std_logic_vector(c_addr_size-1 downto 0);
	signal	din_a, din_b				: std_logic_vector(c_mem_width-1 downto 0);
	signal	dout_a, dout_b			: std_logic_vector(c_mem_width-1 downto 0);
	signal	wr_offset				: unsigned(c_addr_size-1 downto 0);

	signal   sof, eof					: std_logic_vector(1 downto 0) := (others => '0');
	signal   snk_cyc_d0				: std_logic_vector(1 downto 0) := (others => '0');
	signal	snk_valid				: std_logic_vector(1 downto 0) := "00";
	signal	stall						: std_logic_vector(1 downto 0) := (others => '0');
	
	signal	snk_dreq					: std_logic_vector(1 downto 0) := "00";
	signal	snk_fab_0, snk_fab_1	: t_ep_internal_fabric;
   signal	ep_src_o_int			: t_wrf_source_out_array(1 downto 0);
	
	
     
  begin 


--	Memory sized for 2 max-length frames (1522 bytes) at 16 bits/word
-- plus 2 bits/word for wb adr field.
-- There is also some space reserved for future use.
	U_mem : generic_dpram
	generic map(
		g_data_width => c_mem_width,
		g_dual_clock => false,
		g_size		 => c_mem_size)
	port map(
		rst_n_i		=> rst_n_i,
		clka_i		=> clk_i,
		clkb_i		=> clk_i,
		
		wea_i			=> write_a,
		aa_i			=> addr_a,
		da_i			=> din_a,
		qa_o			=> dout_a,
		
		web_i			=> write_b,
		ab_i			=> addr_b,
		db_i			=> din_b,
		qb_o			=> dout_b	
	);
	
	p_detect_frame : process(clk_i)
	begin
		if(rising_edge(clk_i)) then
			if rst_n_i = '0' then
				snk_cyc_d0 <= (others => '0');
			else
				snk_cyc_d0 <= tagger_snk_i(0).cyc & tagger_snk_i(1).cyc;
			end if;		
		end if;
	end process;
	
	sof <= not snk_cyc_d0 and tagger_snk_i(0).cyc & tagger_snk_i(1).cyc;
	eof <= snk_cyc_d0 and tagger_snk_i(0).cyc & tagger_snk_i(1).cyc;
	
	snk_valid(0) <= tagger_snk_i(0).cyc and tagger_snk_i(0).stb and tagger_snk_i(0).we and not stall(0);
	snk_valid(1) <= tagger_snk_i(1).cyc and tagger_snk_i(1).stb and tagger_snk_i(1).we and not stall(1);
	
	p_wr_fsm : process(clk_i)
	begin
		if(rising_edge(clk_i)) then
			if(rst_n_i = '0') then
				write_a		<= '0';
				addr_a		<= (others => '0');
				wr_offset	<= (others => '0');
				wr_state		<= S_IDLE;
								
				slot0.writing <= '0';
				slot0.written <= '0';
				
				slot1.writing <= '0';
				slot1.written <= '0';
				
			else
			
				if(slot0.reading = '1' and slot0.written = '1') then
					slot0.written <= '0';
				end if;
				
				if(slot1.reading = '1' and slot1.written = '1') then
					slot1.written <= '0';
				end if;
			
				case wr_state is
					
					when S_IDLE =>
						
						if(sof(0) = '1') then -- IF LEV 1
						
							if(slot0.available = '1') then -- IF LEV 2
							
								addr_a 			<= c_slot0_base;
								din_a 			<= snk_valid(0) & c_sig_sof;
								write_a 			<= '1';
								slot0.available <= '0';
								slot0.writing	<= '1';
								slot0.source	<= '0';
								wr_state 		<= S_WRITING;
								stall(1)			<= '1';
								wr_offset		<= (others => '0');
								
							elsif(slot1.available = '1') then
							
								addr_a			<= c_slot1_base;
								din_a			<= snk_valid(0) & c_sig_sof;
								write_a			<= '1';
								slot1.writing 	<= '1';
								slot1.source 	<= '0';
								slot1.available <= '0';
								wr_state 		<= S_WRITING;
								stall(1)			<= '1';
								wr_offset		<= (others => '0');

								
							else
								
								wr_state 		<= S_FULL;
								stall 			<= (others => '1');
								
							end if; -- ENDIF LEV 1
						
						elsif(sof(1) = '1') then
						
							if(slot0.available = '1') then -- IF LEV 2
							
								addr_a			<= c_slot1_base;
								din_a			<= snk_valid(1) & c_sig_sof;
								write_a			<= '1';
								slot0.writing  <= '1';
								slot0.source	<= '1';
								slot0.available <= '0';
								wr_state			<= S_WRITING;
								wr_offset		<= (others => '0');

								
							elsif(slot1.available = '1') then
							
								addr_a			<= c_slot1_base;
								din_a			<= snk_valid(1) & c_sig_sof;
								write_a			<= '1';
								slot1.writing	<= '1';
								slot1.source	<= '1';
								slot1.available <= '0';
								wr_state			<= S_WRITING;
								wr_offset		<= (others => '0');
								
							else
								
								wr_state			<= S_FULL;
								stall				<= (others => '1');
								
							end if; -- ENDIF LEV 2
						
						end if; -- ENDIF LEV 1
					
					when S_WRITING => -- FIX ME! Memory needs to keep track of .sel!
					
						if(slot0.writing = '1') then -- IF LEV 1
						
							wr_offset	<= unsigned(wr_offset) + 1;
							addr_a 		<= std_logic_vector( unsigned(c_slot0_base) + unsigned(wr_offset) );
							write_a 		<= '1';
							
							if(slot0.source = '0') then -- IF LEV 2
								
								din_a <= snk_valid(0) & tagger_snk_i(0).adr & tagger_snk_i(0).sel & tagger_snk_i(0).dat;
								if(eof(0) = '1') then -- IF LEV 3
									
									din_a <= snk_valid(0) & c_sig_eof;
									wr_state <= S_EOF;
									slot0.writing <= '0';
									slot0.written <= '1';
									
								end if;  -- ENDIF LEV 3
								
							elsif(slot0.source = '1') then
							
								din_a <= snk_valid(1) & tagger_snk_i(1).adr & tagger_snk_i(0).sel & tagger_snk_i(1).dat;
								if(eof(1) = '1') then -- IF LEV 3
									
									din_a <= snk_valid(1) & c_sig_eof;
									wr_state <= S_EOF;
									slot0.writing <= '0';
									slot0.written <= '1';
									
								end if; -- ENDIF LEV 3
							
							end if; -- ENDIF LEV 2
							
						elsif(slot1.writing = '1') then
						
							wr_offset	<= unsigned(wr_offset) + 1;
							addr_a 		<= std_logic_vector( unsigned(c_slot1_base) + unsigned(wr_offset) );
							write_a		<= '1';
							
							if(slot1.source = '0') then -- IF LEV 2
								
								din_a <= snk_valid(0) & tagger_snk_i(0).adr & tagger_snk_i(0).sel & tagger_snk_i(0).dat;
								if(eof(0) = '1') then -- IF LEV 3
									
									din_a <= snk_valid(0) & c_sig_eof;
									wr_state <= S_EOF;
									slot1.writing <= '0';
									slot1.written <= '1';
									
								end if; -- ENDIF LEV 3
								
							elsif(slot1.source = '1') then 
							
								din_a <= snk_valid(1) & tagger_snk_i(1).adr & tagger_snk_i(0).sel & tagger_snk_i(1).dat;
								if(eof(1) = '1') then  -- IF LEV 3
									
									din_a <= snk_valid(1) & c_sig_eof;
									wr_state <= S_EOF;
									slot1.writing <= '0';
									slot1.written <= '1';
									
								end if;  -- ENDIF LEV 3
								
							end if; -- ENDIF LEV 2
							
						end if; -- ENDIF LEV 1
					
					when S_EOF =>
						
						write_a	<= '0';
						if(slot0.available = '0' and slot1.available = '0') then
							
							wr_state 	<= S_FULL;
							stall 		<= (others => '1');
							
						else
						
							wr_state 	<= S_IDLE;
							stall			<= (others => '0');
						
						end if;	
										
					when S_FULL =>
					
						stall	<= (others => '1');
						
						if(slot0.available = '1' or slot1.available = '1') then
							
							stall 		<= (others => '0');
							wr_state 	<= S_IDLE;
						
						end if;
						
						if(slot0.finished = '1') then
							slot0.available <= '1';
						end if;
						
						if(slot1.finished = '1') then
							slot1.available <= '1';
						end if;
					
					when others =>					
				
				end case;
			
			end if;
		end if;
	end process;




	p_rd_fsm : process(clk_i)
	begin
		if(rising_edge(clk_i)) then
			if(rst_n_i = '0') then
				
				rd_state <= IDLE;
				
				slot0.reading   <= '0';
				slot0.finished  <= '0';
				
				slot1.reading	 <= '0';
				slot1.finished  <= '0';
				
			else
			
				case rd_state is
					
					when IDLE =>
					
						if(slot0.available = '1' and slot0.finished = '1') then
							slot0.finished <= '0';
						end if;
						
						if(slot1.available = '1' and slot1.finished = '1') then
							slot1.finished <= '0';
						end if;
						
						if(slot0.written = '1' or slot1.written = '1') then
							rd_state <= READING;
						end if;
					
					when READING =>
					
					when others =>
					
				end case;
			
			end if;
		end if;
	end process;

  p_gen_ack : process(clk_i)
  begin
    if rising_edge(clk_i) then
      tagger_snk_o(0).ack <= snk_valid(0);
		tagger_snk_o(1).ack <= snk_valid(1);
    end if;
  end process;
  
  tagger_snk_o(0).stall	<= stall(0);
  tagger_snk_o(1).stall <= stall(1);
  
	U_master_ep0 : ep_rx_wb_master
		generic map(
			g_ignore_ack	=> true)
		port map(
			clk_sys_i 		=> clk_i,
			rst_n_i			=> rst_n_i,
			snk_fab_i		=> snk_fab_0,
			snk_dreq_o		=> snk_dreq(0),
			
			src_wb_o			=> ep_src_o_int(0),
			src_wb_i			=>	ep_src_i(0)
		);
	
	U_master_ep1 : ep_rx_wb_master
		generic map(
			g_ignore_ack	=> true)
		port map(
			clk_sys_i 		=> clk_i,
			rst_n_i			=> rst_n_i,
			snk_fab_i		=> snk_fab_1,
			snk_dreq_o		=> snk_dreq(1),
			
			src_wb_o			=> ep_src_o_int(1),
			src_wb_i			=> ep_src_i(1)
		);

	ep_src_o <= ep_src_o_int;
	
	

end behavioral;