-------------------------------------------------------------------------------
-- Title      : Output Block
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : swc_output_block.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-11-03
-- Last update: 2010-11-03
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

-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


library work;
use work.swc_swcore_pkg.all;
use work.genram_pkg.all;
use work.wr_fabric_pkg.all;

entity xswc_output_block is

  port (
    clk_i   : in std_logic;
    rst_n_i : in std_logic;

-------------------------------------------------------------------------------
-- I/F with Pck Transfer Arbiter
-------------------------------------------------------------------------------

    pta_transfer_data_valid_i : in   std_logic;
    pta_pageaddr_i            : in   std_logic_vector(c_swc_page_addr_width - 1 downto 0);
    pta_prio_i                : in   std_logic_vector(c_swc_prio_width - 1 downto 0);
    pta_pck_size_i            : in   std_logic_vector(c_swc_max_pck_size_width - 1 downto 0);
    pta_transfer_data_ack_o   : out  std_logic;

-------------------------------------------------------------------------------
-- I/F with Multiport Memory's Read Pump (MMP)
-------------------------------------------------------------------------------

    mpm_pgreq_o  : out std_logic;
    mpm_pgaddr_o : out std_logic_vector(c_swc_page_addr_width - 1 downto 0);
    mpm_pckend_i : in  std_logic;
    mpm_pgend_i  : in  std_logic;
    mpm_drdy_i   : in  std_logic;
    mpm_dreq_o   : out std_logic;
    mpm_data_i   : in  std_logic_vector(c_swc_data_width - 1 downto 0);
    mpm_ctrl_i   : in  std_logic_vector(c_swc_ctrl_width - 1 downto 0);
    mpm_sync_i   : in  std_logic; 
   
-------------------------------------------------------------------------------
-- I/F with Pck's Pages Free Module(PPFM)
-------------------------------------------------------------------------------      
    -- correctly read pck
    ppfm_free_o            : out  std_logic;
    ppfm_free_done_i       : in   std_logic;
    ppfm_free_pgaddr_o     : out  std_logic_vector(c_swc_page_addr_width - 1 downto 0);

-------------------------------------------------------------------------------
-- pWB : output (goes to the Endpoint)
-------------------------------------------------------------------------------  

    src_i : in  t_wrf_source_in;
    src_o : out t_wrf_source_out
    
    );
end xswc_output_block;

architecture behavoural of xswc_output_block is
  
  signal pta_transfer_data_ack : std_logic;

  signal wr_addr               : std_logic_vector(c_swc_output_prio_num_width + c_swc_output_fifo_addr_width -1 downto 0);
  signal rd_addr               : std_logic_vector(c_swc_output_prio_num_width + c_swc_output_fifo_addr_width -1 downto 0);
  signal wr_prio               : std_logic_vector(c_swc_output_prio_num_width - 1 downto 0);
  signal rd_prio               : std_logic_vector(c_swc_output_prio_num_width - 1 downto 0);
  signal not_full_array        : std_logic_vector(c_swc_output_prio_num - 1 downto 0);
  signal not_empty_array       : std_logic_vector(c_swc_output_prio_num - 1 downto 0);
  signal read_array            : std_logic_vector(c_swc_output_prio_num - 1 downto 0);
  signal read                  : std_logic_vector(c_swc_output_prio_num - 1 downto 0);
  signal write_array           : std_logic_vector(c_swc_output_prio_num - 1 downto 0);
  signal write                 : std_logic_vector(c_swc_output_prio_num - 1 downto 0);
  signal wr_en                 : std_logic;
  signal rd_data_valid         : std_logic;
  signal zeros                 : std_logic_vector(c_swc_output_prio_num - 1 downto 0);

  subtype t_head_and_head      is std_logic_vector(c_swc_output_fifo_addr_width - 1  downto 0);

  type t_addr_array      is array (c_swc_output_prio_num - 1 downto 0) of t_head_and_head;  

  signal wr_array    : t_addr_array;
  signal rd_array    : t_addr_array;
  
  type t_state is (IDLE, SET_PAGE, WAIT_READ, READ_MPM, READ_LAST_WORD, WAIT_FREE_PCK);
  signal state       : t_state;
  
  signal wr_data            : std_logic_vector(c_swc_max_pck_size_width + c_swc_page_addr_width - 1 downto 0);
  signal rd_data            : std_logic_vector(c_swc_max_pck_size_width + c_swc_page_addr_width - 1 downto 0);
  signal rd_pck_size        : std_logic_vector(c_swc_max_pck_size_width - 1 downto 0);
  signal current_pck_size   : std_logic_vector(c_swc_max_pck_size_width - 1 downto 0);
  signal cnt_pck_size       : std_logic_vector(c_swc_max_pck_size_width - 1 downto 0);
  
  signal dreq              : std_logic;
  signal pgreq             : std_logic;
    
  signal ppfm_free        : std_logic;
  signal ppfm_free_pgaddr       : std_logic_vector(c_swc_page_addr_width - 1 downto 0);
  
  signal pck_start_pgaddr       : std_logic_vector(c_swc_page_addr_width - 1 downto 0);
  
  signal cnt_last_word     : std_logic;
  signal cnt_one_but_last_word     : std_logic;
  
  signal start_free_pck          : std_logic;
  signal waiting_pck_start : std_logic;
  

  signal ram_zeros                 : std_logic_vector(c_swc_page_addr_width + c_swc_max_pck_size_width - 1 downto 0);
  signal ram_ones                  : std_logic_vector((c_swc_page_addr_width + c_swc_max_pck_size_width+7)/8 - 1 downto 0);


  -- pipelined WB
  
  -- source out
  signal src_adr_int : std_logic_vector(1 downto 0);
  signal src_dat_int : std_logic_vector(15 downto 0);
  signal src_cyc_int : std_logic;
  signal src_stb_int : std_logic;
  signal src_we_int  : std_logic;
  signal src_sel_int : std_logic_vector(1 downto 0);

  signal src_stb_d0  : std_logic;

  signal src_adr_tmp : std_logic_vector(1 downto 0);
  signal src_dat_tmp : std_logic_vector(15 downto 0);
  signal src_cyc_tmp : std_logic;
  signal src_stb_tmp : std_logic;
  signal src_sel_tmp : std_logic_vector(1 downto 0);

  -- source in
  signal src_ack_int   : std_logic;
  signal src_stall_int : std_logic;
  signal src_err_int   : std_logic;
  signal src_rty_int   : std_logic;

  signal snk_ack_count : unsigned(2 downto 0); -- size?

  signal src_stall_d0  : std_logic;

  signal mpm_drdy_d0   : std_logic;

  signal special_dreq  : std_logic;

  signal special_dreq_d0 : std_logic;

begin  --  behavoural
  
  zeros     <=(others => '0');
  ram_zeros <=(others => '0');
  ram_ones  <=(others => '1');
    
  wr_prio <= not pta_prio_i;
    
  wr_data <= pta_pck_size_i & pta_pageaddr_i;
    
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
  
  RD_ENCODE : swc_prio_encoder
    generic map (
      g_num_inputs  => 8,
      g_output_bits => 3)
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
                 "00000000" ;
  
  wr_en       <= write(0) and not_full_array(0) when wr_prio = "000" else
                 write(1) and not_full_array(1) when wr_prio = "001" else
                 write(2) and not_full_array(2) when wr_prio = "010" else
                 write(3) and not_full_array(3) when wr_prio = "011" else
                 write(4) and not_full_array(4) when wr_prio = "100" else
                 write(5) and not_full_array(5) when wr_prio = "101" else
                 write(6) and not_full_array(6) when wr_prio = "110" else
                 write(7) and not_full_array(7) when wr_prio = "111" else
                 '0';
                 
  pta_transfer_data_ack_o <= not_full_array(0)  when wr_prio = "000" else
                             not_full_array(1)  when wr_prio = "001" else
                             not_full_array(2)  when wr_prio = "010" else
                             not_full_array(3)  when wr_prio = "011" else
                             not_full_array(4)  when wr_prio = "100" else
                             not_full_array(5)  when wr_prio = "101" else
                             not_full_array(6)  when wr_prio = "110" else
                             not_full_array(7)  when wr_prio = "111" else                 
                            '0';
  
   prio_ctrl : for i in 0 to c_swc_output_prio_num - 1 generate 
    
    write(i)        <= write_array(i) and pta_transfer_data_valid_i ;
    read(i)         <= read_array(i)  when (state = SET_PAGE) else '0';--rx_dreq_i;
      
    PRIO_QUEUE_CTRL : swc_ob_prio_queue
      port map (
        clk_i       => clk_i,
        rst_n_i     => rst_n_i,
        write_i     => write(i),
        read_i      => read(i),
        not_full_o  => not_full_array(i),
        not_empty_o => not_empty_array(i),
        wr_en_o     => open, --wr_en_array(i),
        wr_addr_o   => wr_array(i),
        rd_addr_o   => rd_array(i) 
        );
  end generate prio_ctrl;
  
   PRIO_QUEUE : generic_dpram
     generic map (
       g_data_width       => c_swc_page_addr_width + c_swc_max_pck_size_width,
       g_size        => (c_swc_output_prio_num * c_swc_output_fifo_size) 
                 )
     port map (
     -- Port A -- writing
       clka_i => clk_i,
       bwea_i => ram_ones,
       wea_i  => wr_en,
       aa_i   => wr_addr,
       da_i   => wr_data,
       qa_o   => open,   
 
      -- Port B  -- reading
       clkb_i => clk_i,
       bweb_i => ram_ones, 
       web_i  => '0',
       ab_i   => rd_addr,
       db_i   => ram_zeros,
       qb_o   => rd_data
      );
  
  -- check if there is any valid frame in any output queue
  -- rd_data_valid=HIGH indicates that there is something to send out
  rd_valid : process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        rd_data_valid <= '0';
      else
         
       if(not_empty_array = zeros) then
         rd_data_valid <= '0';
       else
         rd_data_valid <= '1';
       end if;
       
     end if;
   end if;
 end process;
            
  -- tracks the number of bytes already sent in order to indicate
  -- when the sending is about to finish and the finish
  pck_size_cnt : process(clk_i, rst_n_i)
  begin
     if rising_edge(clk_i) then
       if(rst_n_i = '0') then
       
         cnt_last_word         <= '0';
         cnt_pck_size          <= (others => '0');
	-- cnt_pck_size(0)        <= '1';
         cnt_one_but_last_word <= '0';
         
       else
 
          src_stb_d0 <= src_stb_int;
  
          if(state = SET_PAGE) then
       
            cnt_pck_size           <= (others =>'0');
	   -- cnt_pck_size(0)        <= '1';
            cnt_one_but_last_word  <= '0';
            cnt_last_word          <= '0';

          elsif(src_stb_int = '1' and src_stall_int = '0') then

            cnt_last_word         <= '0';
            cnt_one_but_last_word <= '0';
          
            if(current_pck_size = std_logic_vector(unsigned(cnt_pck_size) + 1)) then
               cnt_last_word             <= '1';   
            elsif(current_pck_size = std_logic_vector(unsigned(cnt_pck_size) + 2)) then
               cnt_one_but_last_word     <= '1';
            end if;
           
            cnt_pck_size <= std_logic_vector(unsigned(cnt_pck_size) + 1);
         
          end if;
      end if;
    end if;
  end process;

  -- sending frame (pipelined WB)
  -- it reads the data from MultiPortMemory (which has an interface more-or-less like a FIFO) 
  -- and sends it out with pipelined WB interface
  src_fsm: process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then

	  -- source out
	  src_adr_int       <= (others => '0'); 
	  src_dat_int       <= (others => '0'); 
	  src_cyc_int       <= '0';
	  src_stb_int       <= '0';
	  src_sel_int       <= (others => '0'); 

	  src_adr_tmp       <= (others => '0');
	  src_dat_tmp       <= (others => '0');
	  src_sel_tmp       <= (others => '0');

	  src_stall_d0      <= '0'; -- delayed stall-> needed to know whether to read data from tmp 
	                            -- or from MPM
	  start_free_pck    <= '0';
	  ppfm_free_pgaddr  <= (others => '0');

	  pgreq             <= '0';
          current_pck_size  <= (others => '0');
	  pck_start_pgaddr  <= (others => '0');
	  dreq              <= '0';
	  special_dreq      <= '0';
	  special_dreq_d0   <= '0';
	  waiting_pck_start <= '0';

	  mpm_drdy_d0       <= '0';

      else

	--------------------------------------------------------------------------------------------
	-- some helpers to the state machines
        --------------------------------------------------------------------------------------------
	src_stall_d0      <= src_stall_int;
	special_dreq_d0   <= special_dreq;
	mpm_drdy_d0       <= mpm_drdy_i;

	-- traccking ACKs from the sink
	if (src_cyc_int = '0' or src_err_int = '1') then
	  snk_ack_count <= (others => '0');
	else
	  if(src_ack_int = '0' and src_stb_int = '1' and src_stall_int = '0') then
	      snk_ack_count <= snk_ack_count + 1;
	  elsif(src_ack_int = '1' and not(src_stb_int = '1' and src_stall_int = '0')) then
	      snk_ack_count <= snk_ack_count - 1;
	  end if;
	end if;

	-- registering parameters of the currently read frame
        if(pgreq = '1') then
          current_pck_size <= rd_pck_size;
          pck_start_pgaddr <= rd_data(c_swc_page_addr_width - 1 downto 0);
        end if;

	--------------------------------------------------------------------------------------------
	-- main finite state machine
        --------------------------------------------------------------------------------------------
        case state is

          when IDLE =>
	    
	    src_adr_int       <= (others => '0'); 
	    src_dat_int       <= (others => '0'); 
	    src_cyc_int       <= '0';
	    src_stb_int       <= '0';
	    src_sel_int       <= (others => '0'); 

	    src_adr_tmp       <= (others => '0');
	    src_dat_tmp       <= (others => '0');
	    src_sel_tmp       <= (others => '0');

	    start_free_pck    <= '0';
	    pgreq             <= '0';
	    dreq              <= '0';
	    special_dreq      <= '0';
	    waiting_pck_start <= '0';

            if(rd_data_valid = '1' and src_stall_int = '0' and src_err_int ='0') then
	      state             <= SET_PAGE;
	    end if;
            
	  -- requesting to MPM the next frame (inputting the starting page address)
          when SET_PAGE =>
	    
	    pgreq                <= '1';
	    waiting_pck_start    <= '1';
	    state                <= WAIT_READ;
   
	  -- waiting for the indication that the data is ready (the first page has been retrieved
	  -- from the MPM
          when WAIT_READ => 
	    
	    pgreq                 <= '0';
	    
	    if(mpm_sync_i = '1' and waiting_pck_start = '1') then -- start reading new frame

	      state               <= READ_MPM;
	      waiting_pck_start   <= '0';
	      dreq                <= '1';                          -- we enable stall-to-dreq 
	                                                           -- conversion here
	    end if;

	  -- reading process (FIFO-to-pWB)
          when READ_MPM =>
	    
	    src_cyc_int         <= '1';
	    src_stb_int         <= '1';

	    if(src_err_int = '1') then                             -- error: free pages allocated to 
	                                                           -- the packet(frame) and finish
	      src_cyc_int         <= '0';
	      src_stb_int         <= '0';
	      src_adr_int         <= (others => '0');
	      src_dat_int         <= (others => '0');
	      src_sel_int         <= (others => '0');
	      dreq                <= '0';
	      state               <= WAIT_FREE_PCK;

	    else                                                    -- everything works

	      dreq                <= '1';                           -- enable stall-to-dreq translation
	      special_dreq        <= '0';

	      if(mpm_drdy_i = '0' ) then     -- paused by source

		  src_cyc_int         <= '1';
		  src_stb_int         <= '0';

	      elsif(mpm_drdy_i = '1' and src_stall_int = '1') then  -- paused by sink

		  src_cyc_tmp         <= '1';
		  src_stb_tmp         <= '1';

		  if(src_stb_int = '1') then                        -- when stall is after drdy_i LOW
		    src_adr_tmp         <= mpm_ctrl_i(1 downto 0);
		    src_sel_tmp         <= mpm_ctrl_i(3 downto 2);
		    src_dat_tmp         <= mpm_data_i;
		  else
		    src_adr_int         <= mpm_ctrl_i(1 downto 0);
		    src_sel_int         <= mpm_ctrl_i(3 downto 2);
		    src_dat_int         <= mpm_data_i;	

		  end if;

		
	      elsif(mpm_drdy_i = '1' and src_stall_int = '0') then  -- read data
		
		if(src_stall_d0 = '1') then  -- read stored data in tmp reg 
		                                                    -- (stopped by source before)
		    src_adr_int         <= src_adr_tmp;
		    src_dat_int         <= src_dat_tmp;
		    src_sel_int         <= src_sel_tmp;

		else                                                -- normal read

		    src_adr_int         <= mpm_ctrl_i(1 downto 0);
		    src_sel_int         <= mpm_ctrl_i(3 downto 2);
		    src_dat_int         <= mpm_data_i;

		
		end if;

--		if(cnt_one_but_last_word = '1') then                        -- this was the last word of the 
		if(cnt_last_word = '1') then                        -- this was the last word of the 

		  state              <= READ_LAST_WORD;             -- frame (package)

-- 		  if(src_stall_int = '0') then
-- 		    src_stb_int        <= '0';
-- 		  end if;

		end if;
	      
	      end if; --if(mpm_drdy_i = '0') then   
	    end if; --if(src_err_int = '1') then        

          when READ_LAST_WORD =>
        
	    if(src_stall_int = '0') then
	      src_stb_int        <= '0';
	      dreq               <= '0';
	    end if;
	    
	    if(snk_ack_count = 0 and src_stb_int = '0') then
	      src_cyc_int <= '0';
	      dreq        <= '0';
	      state       <= WAIT_FREE_PCK;
	    end if;
               
          when WAIT_FREE_PCK => 

              if(ppfm_free = '0') then
                
                 ppfm_free_pgaddr <= pck_start_pgaddr;  
                 start_free_pck   <= '1';
                 state            <= IDLE;
               
              end if;
              
          when others =>
	    state       <= IDLE;
        end case; -- src_fsm
      end if; -- (rst_n_i = '0') 
    end if; -- rising_edge(clk_i)
  end process src_fsm;

  -- here we perform the "free pages of the pck" process, 
  -- we do it while reading already the next pck
  free : process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        ppfm_free                <= '0';
      else
        if(start_free_pck = '1') then
          ppfm_free <= '1';
        elsif(ppfm_free_done_i = '1') then
          ppfm_free  <='0';
        end if;
      end if;
    end if;
    
  end process free;
  rd_pck_size         <= rd_data(c_swc_max_pck_size_width + c_swc_page_addr_width - 1 downto c_swc_page_addr_width);  

  -------------- MPM ---------------------
  mpm_dreq_o    <= ((not src_stall_int) and dreq);
  mpm_pgreq_o         <= pgreq;
  mpm_pgaddr_o        <= rd_data(c_swc_page_addr_width - 1 downto 0) when (pgreq = '1') else pck_start_pgaddr;  
  -------------- pWB ----------------------
  -- source out
  src_o.adr     <= src_adr_int; 
  src_o.dat     <= src_dat_int;
  src_o.cyc     <= src_cyc_int;
  src_o.stb     <= src_stb_int;
  src_o.we      <= '1'; 
  src_o.sel     <= src_sel_int; 
  -- source in
  src_ack_int   <= src_i.ack; 
  src_stall_int <= src_i.stall; 
  src_err_int   <= src_i.err;
  src_rty_int   <= src_i.rty;
  -------------- PPFM ----------------------
  ppfm_free_o         <= ppfm_free;
  ppfm_free_pgaddr_o  <= ppfm_free_pgaddr;
  
end behavoural;