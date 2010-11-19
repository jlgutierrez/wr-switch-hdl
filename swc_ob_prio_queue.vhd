-------------------------------------------------------------------------------
-- Title      : Priority Queue
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : swc_ob_prio_queue.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-11-03
-- Last update: 2010-11-03
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
-- Copyright (c) 2010 Maciej Lipinski
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2010-11-09  1.0      mlipinsk 

-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.swc_swcore_pkg.all;



entity swc_ob_prio_queue is

  port (
    clk_i   : in std_logic;
    rst_n_i : in std_logic;

-------------------------------------------------------------------------------
-- I/F 
-------------------------------------------------------------------------------

    write_i           : in   std_logic;
    read_i            : in   std_logic;
 
    not_full_o        : out   std_logic;
    not_empty_o       : out   std_logic;
    
-------------------------------------------------------------------------------
-- I/F with SRAM
-------------------------------------------------------------------------------
    
    wr_en_o           : out  std_logic;
    wr_addr_o         : out  std_logic_vector(c_swc_output_fifo_addr_width - 1 downto 0);
    rd_addr_o         : out  std_logic_vector(c_swc_output_fifo_addr_width - 1 downto 0)
    
    );
end swc_ob_prio_queue;


architecture behavoural of swc_ob_prio_queue is
  
  signal head          : std_logic_vector(c_swc_output_fifo_addr_width - 1  downto 0);
  signal tail          : std_logic_vector(c_swc_output_fifo_addr_width - 1  downto 0);
  signal not_full      : std_logic;  
  signal not_empty     : std_logic;
  signal read          : std_logic;
    
begin -- behavoural  
  
  
  sram_if : process (clk_i, rst_n_i)
  begin  -- process
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
      
        head          <= (others => '0');
        tail          <= (others => '0');
        read          <= '0';
        
      else
        
        if(write_i = '1' and not_full = '1') then 
          
          head <= std_logic_vector(unsigned(head) + 1);
          
        end if;
        
        if(read_i = '1' and not_empty = '1') then 
          
          tail <= std_logic_vector(unsigned(tail) + 1);
          
        end if;
        
      
      end if;
    end if;
  end process;  
  
  not_full  <= '0' when (head = std_logic_vector(unsigned(tail) - 1)) else '1';
  not_empty <= '0' when (tail = head ) else '1';
  
  
  wr_addr_o   <= head;
  rd_addr_o   <= tail;  
  wr_en_o     <= write_i and not_full;
  not_full_o  <= not_full;
  not_empty_o <= not_empty;
  
  
end behavoural;