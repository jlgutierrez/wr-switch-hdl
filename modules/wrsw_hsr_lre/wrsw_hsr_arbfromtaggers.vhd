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
  
  type	t_wr_state					is (IDLE, WRITING, FULL);
  signal	wr_state						:	t_wr_state;
  
  type	t_rd_state					is (IDLE, READING);
  signal rd_state						:	t_rd_state;
  
  type	t_mem_slot_status is record
		available						:	std_logic;
		writing							:	std_logic;
		written							:	std_logic;
		reading							:	std_logic;
		finished							:	std_logic;
	end record;
	
	signal slot0, slot1				: t_mem_slot_status :=('1','0','0','0','0');
  
	constant c_mem_width				: natural := 18;
	constant c_mem_size				: natural := 2*800;
	constant c_addr_size				: natural := f_log2_size(c_mem_size);
	constant c_frame0_base			: std_logic_vector := "00000000001";
	constant c_frame0_ctrl			: std_logic_vector := "00000000000";
	constant c_frame1_base			: std_logic_vector := "11001000001";
	constant c_frame1_ctrl			: std_logic_vector := "11001000000";

	signal	write_a, write_b		: std_logic := '0';
	signal	addr_a, addr_b			: std_logic_vector(c_addr_size-1 downto 0);
	signal	din_a, din_b				: std_logic_vector(c_mem_width-1 downto 0);
	signal	dout_a, dout_b			: std_logic_vector(c_mem_width-1 downto 0);

	signal   sof, eof					: std_logic_vector(1 downto 0) := (others => '0');
	signal   snk_cyc_d0				: std_logic_vector(1 downto 0) := (others => '0');
     
  begin 


--	Memory sized for 2 max-length frames (1520 bytes) at 16 bits/word
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
	
	p_wr_fsm : process(clk_i)
	begin
		if(rising_edge(clk_i)) then
			if(rst_n_i = '0') then
				write_a		<= '0';
				addr_a		<= (others => '0');
				wr_state		<= IDLE;
				
				slot0.writing <= '0';
				slot0.written <= '0';
				
				slot1.writing <= '0';
				slot1.written <= '0';
				
			else
			
				case wr_state is
					
					when IDLE =>
					
					when WRITING =>
					
					when FULL =>
					
					when others =>					
				
				end case;
			
			end if;
		end if;
	end process;
--	
	p_rd_fsm : process(clk_i)
	begin
		if(rising_edge(clk_i)) then
			if(rst_n_i = '0') then
				
				rd_state <= IDLE;
				
				slot0.available <= '1';
				slot0.reading   <= '0';
				slot0.finished  <= '0';
				
				slot1.available <= '1';
				slot1.reading	 <= '0';
				slot1.finished  <= '0';
				
			else
			
				case rd_state is
					
					when IDLE =>
					
					when READING =>
					
					when others =>
					
				end case;
			
			end if;
		end if;
	end process;	
	
	

end behavioral;