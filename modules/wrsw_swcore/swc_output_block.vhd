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

-------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


library work;
use work.swc_swcore_pkg.all;
use work.genram_pkg.all;

entity swc_output_block is

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
-- Fabric I/F : output (goes to the Endpoint)
-------------------------------------------------------------------------------      

    rx_sof_p1_o         : out std_logic;
    rx_eof_p1_o         : out std_logic;
    rx_dreq_i           : in  std_logic;
    rx_ctrl_o           : out std_logic_vector(c_swc_ctrl_width - 1 downto 0);
    rx_data_o           : out std_logic_vector(c_swc_data_width - 1 downto 0);
    rx_valid_o          : out std_logic;
    rx_bytesel_o        : out std_logic;
    rx_idle_o           : out std_logic;
    rx_rerror_p1_o      : out std_logic;
    
    -- drop the pck in case of WRF error
    rx_terror_p1_i      : in  std_logic;
    
    -- retransmit the pck in case of  WRF abort
    rx_tabort_p1_i      : in  std_logic
    
    );
end swc_output_block;

architecture behavoural of swc_output_block is

   component generic_ssram_dualport_singleclock
     generic (
       g_width     : natural;
       g_addr_bits : natural;
       g_size      : natural);
     port (
       data_i    : in  std_logic_vector (g_width-1 downto 0);
       clk_i     : in  std_logic;
       rd_addr_i : in  std_logic_vector (g_addr_bits-1 downto 0);
       wr_addr_i : in  std_logic_vector (g_addr_bits-1 downto 0);
       wr_en_i   : in  std_logic := '1';
       q_o       : out std_logic_vector (g_width-1 downto 0));
   end component;
  
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
--  signal wr_en_array           : std_logic_vector(c_swc_output_prio_num - 1 downto 0);
  signal wr_en                 : std_logic;
  signal rd_data_valid         : std_logic;
  signal zeros                 : std_logic_vector(c_swc_output_prio_num - 1 downto 0);
  

  subtype t_head_and_head      is std_logic_vector(c_swc_output_fifo_addr_width - 1  downto 0);

  type t_addr_array      is array (c_swc_output_prio_num - 1 downto 0) of t_head_and_head;  

  signal wr_array    : t_addr_array;
  signal rd_array    : t_addr_array;
  
  type t_state is (IDLE, SET_PAGE, RE_SET_PAGE, READ_MPM, PAUSE_BY_SRC, PAUSE_BY_SINK, READ_LAST_WORD,WAIT_FREE_PCK, WAIT_DREQ, TABORT);
  signal state       : t_state;
  
  signal pgreq       : std_logic;  
  signal re_pgreq    : std_logic;  
  signal pgreq_d0    : std_logic;  
  signal re_pgreq_d0 : std_logic;
  signal pgreq_or    : std_logic;  

  
  signal wr_data            : std_logic_vector(c_swc_max_pck_size_width + c_swc_page_addr_width - 1 downto 0);
  signal rd_data            : std_logic_vector(c_swc_max_pck_size_width + c_swc_page_addr_width - 1 downto 0);
  signal rd_pck_size        : std_logic_vector(c_swc_max_pck_size_width - 1 downto 0);
  signal current_pck_size   : std_logic_vector(c_swc_max_pck_size_width - 1 downto 0);
  signal cnt_pck_size       : std_logic_vector(c_swc_max_pck_size_width - 1 downto 0);
  
  signal dreq              : std_logic;
  
  signal rx_sof_p1         : std_logic;
  signal rx_eof_p1         : std_logic;
  signal rx_valid          : std_logic;
  signal rx_rerror_p1      : std_logic;
  signal rx_ctrl           : std_logic_vector(c_swc_ctrl_width - 1 downto 0);
  signal rx_data           : std_logic_vector(c_swc_data_width - 1 downto 0);
  signal rx_bytesel        : std_logic;
  
  signal ppfm_free        : std_logic;
  signal ppfm_free_pgaddr       : std_logic_vector(c_swc_page_addr_width - 1 downto 0);
  
  signal pck_start_pgaddr       : std_logic_vector(c_swc_page_addr_width - 1 downto 0);
  
  signal cnt_last_word     : std_logic;
  signal cnt_one_but_last_word     : std_logic;
  
  signal start_free_pck          : std_logic;
  signal waiting_pck_start : std_logic;
  

  signal ram_zeros                 : std_logic_vector(c_swc_page_addr_width + c_swc_max_pck_size_width - 1 downto 0);
  signal ram_ones                  : std_logic_vector((c_swc_page_addr_width + c_swc_max_pck_size_width+7)/8 - 1 downto 0);


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
      generic map(
        g_per_prio_fifo_size_width => c_swc_output_fifo_addr_width
       )
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
  
--    PRIO_QUEUE : generic_ssram_dualport_singleclock
--      generic map (
--        g_width       => c_swc_page_addr_width + c_swc_max_pck_size_width,
--        g_addr_bits   => c_swc_output_prio_num_width + c_swc_output_fifo_addr_width,
--        g_size        => (c_swc_output_prio_num * c_swc_output_fifo_size) 
--                  )
--      port map (
--        clk_i         => clk_i,
--        rd_addr_i     => rd_addr,
--        wr_addr_i     => wr_addr,
--        data_i        => wr_data,
--        wr_en_i       => wr_en,
--        q_o           => rd_data
--        );
  
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
            
         
  --rd_data_valid <= '0' when (not_empty_array = zeros) else '1';

  pck_size_cnt : process(clk_i, rst_n_i)
  begin
     if rising_edge(clk_i) then
       if(rst_n_i = '0') then
       
         cnt_last_word         <= '0';
         cnt_pck_size          <= (others => '0');
         cnt_one_but_last_word <= '0';
         
       else

       
         
--         if(rx_eof_p1  = '1' or ) then
          if(state = SET_PAGE or state = RE_SET_PAGE) then
       
          cnt_pck_size           <= (others =>'0');
          cnt_one_but_last_word  <= '0';
          cnt_last_word          <= '0';

         elsif(rx_valid = '1' and rx_eof_p1 = '0') then
           
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




  
  fsm : process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
      
        pgreq             <= '0';
        current_pck_size  <= (others => '0');
        rx_sof_p1         <= '0';
        pck_start_pgaddr  <= (others => '0');
        ppfm_free_pgaddr  <= (others => '0');
        dreq              <= '0';
        start_free_pck    <= '0';
        rx_valid          <= '0';
        rx_ctrl           <= (others =>'0');
        rx_data           <= (others =>'0');
        rx_eof_p1         <= '0';
        rx_bytesel        <= '0';
        re_pgreq          <= '0';
        waiting_pck_start <= '0';
        pgreq_d0          <= '0';
        re_pgreq_d0       <= '0';
         
      else

        -- IMPORTANT : nasty trick here !!!
        --             basically, the 'read' is HIGH, to confirm reading from
        --             queue output, when state = SET_PAGE, but this is sync with
        --             the address in the queue, the data is available one cycle later !!
        --             basically, the data is available when 'pgreq' is HIGH (this is 
        --             how FSM works), so we capture the data when 'pgreq' is HIGH (to avoid
        --             extra states and waiting). to optimize the performance, during the
        --             'pgreq' strobe (HIGH), the data is outputed directly from queue to 
        --             mpm_pgaddr_o.
         
        if(pgreq = '1') then
          current_pck_size <= rd_pck_size;
          pck_start_pgaddr <= rd_data(c_swc_page_addr_width - 1 downto 0);
        end if;
        -- main finite state machine
        pgreq_d0    <= pgreq;
        re_pgreq_d0 <= re_pgreq;
        
        
        case state is


          when IDLE =>
            
            rx_eof_p1         <= '0';
            dreq              <= '0';
            start_free_pck    <= '0';
            rx_sof_p1         <= '0';

            -- 
            if(rd_data_valid = '1' and rx_dreq_i = '1' 
                 --and pta_transfer_data_valid_i = '0'
                 ) then    -- we can't start when transfering data, because the dataa is changing
            
              state             <= SET_PAGE;
              --rx_sof_p1         <= '1';
              rx_sof_p1         <= '0';
              
              rx_ctrl           <= (others =>'0');
              rx_data           <= (others =>'0');

              
            end if;
            
          when SET_PAGE =>
            
              rx_sof_p1        <= '0';
              pgreq            <= '1';
              --dreq             <= '1';
              dreq             <= '0';
              
              waiting_pck_start <='1';
              
              rx_valid          <= '0'; 
              state             <= PAUSE_BY_SRC;
              rx_ctrl           <= (others =>'0');
              rx_data           <= (others =>'0');

          when RE_SET_PAGE =>
            
              rx_sof_p1        <= '0';
              re_pgreq         <= '1';
              --dreq             <= '1';
              dreq             <= '0';--added
              
              waiting_pck_start<='1';

              rx_valid          <= '0'; 
              state             <= PAUSE_BY_SRC;
              rx_ctrl           <= (others =>'0');
              rx_data           <= (others =>'0');              
            
          when PAUSE_BY_SINK => 
            
            pgreq            <= '0';
            
            
--            if(rx_dreq_i = '1' and mpm_drdy_i = '1') then
            if(rx_tabort_p1_i = '1' and rx_dreq_i = '1') then
                            
               state             <= RE_SET_PAGE;
               dreq              <= '0';
               
               --rx_sof_p1         <= '1';
               rx_sof_p1          <= '0';
               
               rx_valid          <= '0';
              
               rx_ctrl           <= (others =>'0');
               rx_data           <= (others =>'0');  

             elsif(rx_tabort_p1_i = '1' and rx_dreq_i = '0') then
                 
               state             <= WAIT_DREQ;
               dreq              <= '0';
               rx_sof_p1         <= '0';
               rx_valid          <= '0';

               rx_ctrl           <= (others =>'0');
               rx_data           <= (others =>'0');
              
             elsif(rx_terror_p1_i = '1') then
           
               -- we release pages of this package for this port
               -- no "force free" here, since other ports
               -- may want to use the pck
               rx_valid          <= '0'; 
               rx_ctrl           <= (others =>'0');
               rx_data           <= (others =>'0');
             
              if(ppfm_free = '0') then
                
                 -- for WTF, refer 'nasty trick above'
                 -- improbable to be used
                 if(pgreq = '1') then
                   ppfm_free_pgaddr <= rd_data(c_swc_page_addr_width - 1 downto 0);
                 else
                   ppfm_free_pgaddr <= pck_start_pgaddr;  
                 end if;
                 
                 start_free_pck  <= '1';
                 state           <= IDLE;
               
              else 
              
                 state           <= WAIT_FREE_PCK;
              
              end if;

            elsif( rx_dreq_i = '1') then
            
              
              
              rx_valid            <= '1'; 
              rx_bytesel          <= '0';
              
              if(rx_ctrl = b"1111") then
                rx_ctrl           <= b"0111";
                rx_bytesel        <= '1';
              end if;
              
              if(cnt_one_but_last_word = '1') then   
                
                state             <= READ_MPM;
              elsif(cnt_last_word = '1') then

                rx_eof_p1         <= '1';
                state             <= READ_LAST_WORD;
                
              else
                
                state             <= READ_MPM; 
              end if;
              
            end if;
   
          when PAUSE_BY_SRC => 
            
            pgreq            <= '0';
            re_pgreq         <= '0';
            rx_sof_p1          <= '0';
            
--            if(rx_dreq_i = '1' and mpm_drdy_i = '1') then
            if(rx_tabort_p1_i = '1' and rx_dreq_i = '1') then
                            
               state             <= RE_SET_PAGE;
               dreq              <= '0';
               
               --rx_sof_p1         <= '1';
               rx_sof_p1          <= '0';
               
               rx_valid          <= '0';
              
               rx_ctrl           <= (others =>'0');
               rx_data           <= (others =>'0');  

             elsif(rx_tabort_p1_i = '1' and rx_dreq_i = '0') then
                 
               state             <= WAIT_DREQ;
               dreq              <= '0';
               rx_sof_p1         <= '0';
               rx_valid          <= '0';

               rx_ctrl           <= (others =>'0');
               rx_data           <= (others =>'0');
              
             elsif(rx_terror_p1_i = '1') then
           
               -- we release pages of this package for this port
               -- no "force free" here, since other ports
               -- may want to use the pck
               rx_valid          <= '0'; 
               rx_ctrl           <= (others =>'0');
               rx_data           <= (others =>'0');
             
              if(ppfm_free = '0') then
            
                 -- for WTF, refer 'nasty trick above'
                 -- improbable to be used
                 if(pgreq = '1') then
                   ppfm_free_pgaddr <= rd_data(c_swc_page_addr_width - 1 downto 0);
                 else
                   ppfm_free_pgaddr <= pck_start_pgaddr;  
                 end if;
                 start_free_pck  <= '1';
                 state           <= IDLE;
               
              else 
              
                 state           <= WAIT_FREE_PCK;
              
              end if;

            elsif( (mpm_drdy_i = '1' or rx_sof_p1 = '1') and waiting_pck_start = '0') then
            
            
              rx_valid            <= '1'; 
              rx_bytesel          <= '0';
              dreq                <= '1'; --added
              
              if(mpm_ctrl_i = b"1111") then
                rx_ctrl           <= b"0111";
                rx_bytesel        <= '1';
              else
                rx_ctrl           <= mpm_ctrl_i;
              end if;
              
              rx_data          <= mpm_data_i;
              
              
              if(cnt_last_word = '1') then   
                
                rx_eof_p1         <= '1';
                state             <= READ_LAST_WORD;
                
              else
                
                
                state             <= READ_MPM; 
              end if;
            else
              
              if(rx_dreq_i         = '1' and 
                 waiting_pck_start = '1' and    -- this is the start of pck, not a pause in the middle
                 mpm_sync_i        = '1' and    -- we've got sync, which means that data will be read
                 pgreq_or          = '0' ) then -- if page is request on the sync, it will be read in next sync
                 
                 dreq               <= '1'; -- added
                 rx_sof_p1          <= '1';
                 waiting_pck_start  <= '0';
                 
               else
                 
                 rx_sof_p1          <= '0';
                 
               end if;
              
              
              
            end if;   
             
          when READ_MPM =>
            
            pgreq                 <= '0';        
                    
              
            if(rx_tabort_p1_i = '1' and rx_dreq_i = '1') then
                            
              state             <= RE_SET_PAGE;
              dreq              <= '0';
              
              --rx_sof_p1         <= '1';
              rx_sof_p1          <= '0';
              
              rx_valid          <= '0';
             
              rx_ctrl           <= (others =>'0');
              rx_data           <= (others =>'0');  

            elsif(rx_tabort_p1_i = '1' and rx_dreq_i = '0') then
                 
              state             <= WAIT_DREQ;
              dreq              <= '0';
              rx_sof_p1         <= '0';
              rx_valid          <= '0';

              rx_ctrl           <= (others =>'0');
              rx_data           <= (others =>'0');
              
            elsif(rx_terror_p1_i = '1') then
           
              -- we release pages of this package for this port
              -- no "force free" here, since other ports
              -- may want to use the pck
              rx_valid          <= '0'; 
              rx_ctrl           <= (others =>'0');
              rx_data           <= (others =>'0');
             
              if(ppfm_free = '0') then
            
                -- for WTF, refer 'nasty trick above'
                -- improbable to be used
                if(pgreq = '1') then
                  ppfm_free_pgaddr <= rd_data(c_swc_page_addr_width - 1 downto 0);
                else
                  ppfm_free_pgaddr <= pck_start_pgaddr;  
                end if;
                start_free_pck  <= '1';
                state           <= IDLE;
               
              else 
              
                state           <= WAIT_FREE_PCK;
              
              end if;
              
            elsif(rx_dreq_i = '0' and mpm_drdy_i = '0') then              

              rx_valid          <= '0'; 
              state             <= PAUSE_BY_SRC;
              rx_ctrl           <= (others =>'0');
              rx_data           <= (others =>'0');
            
            elsif(rx_dreq_i = '0' and mpm_drdy_i = '1') then
            
              rx_valid          <= '0'; 
              state             <= PAUSE_BY_SINK;
              rx_ctrl           <= mpm_ctrl_i;
              rx_data           <= mpm_data_i;
            
            elsif(rx_dreq_i = '1' and mpm_drdy_i = '0') then
            
              rx_valid          <= '0'; 
              state             <= PAUSE_BY_SRC;
              rx_ctrl           <= (others =>'0');
              rx_data           <= (others =>'0');
            
            elsif(mpm_drdy_i = '1' and mpm_drdy_i = '1') then
            
              rx_valid            <= '1'; 
              rx_bytesel          <= '0';
              
              if(mpm_ctrl_i = b"1111") then
                rx_ctrl           <= b"0111";
                rx_bytesel        <= '1';
              else
                rx_ctrl           <= mpm_ctrl_i;
              end if;
              
              rx_data             <= mpm_data_i;
    
              -- we need to make sure that the last word has been read
              -- so we can only go to IDLE, if the last word was validated
              -- with rx_valid
              --if(cnt_pck_size = current_pck_size and rx_valid = '1') then
              if(cnt_one_but_last_word = '1') then
                
                -- writing request to freeing FIFO to free 
                -- the previous pck is finished
                -- so no problem to write new freeing request
                dreq               <= '0';
                rx_eof_p1          <= '1';
                rx_valid           <= '1'; 
                rx_bytesel         <= '0';
                if(mpm_ctrl_i = b"1111") then
                  rx_ctrl          <= b"0111";
                  rx_bytesel       <= '1';
                else
                  rx_ctrl          <= mpm_ctrl_i;
                end if;
                rx_data            <= mpm_data_i;
                state              <= READ_LAST_WORD;
                
             end if;
      
            else
    
              -- should not get here ?????????
              rx_valid         <= '0'; 
              state            <= PAUSE_BY_SRC;
              rx_ctrl           <= (others =>'0');
              rx_data           <= (others =>'0');

             end if;     
        
          when READ_LAST_WORD =>
        
            rx_eof_p1          <= '0';
            rx_valid           <= '0'; 
            rx_ctrl           <= (others =>'0');
            rx_data           <= (others =>'0');
            
                    
            if(ppfm_free = '0') then
        
              start_free_pck   <= '1';
           
              -- remember the starting page address
              -- for the free-ing process
              ppfm_free_pgaddr   <= pck_start_pgaddr;
          
              state              <= IDLE;
              
              -- very unlikely, but if writing request (to freeing FIFO)
              -- to free the   previous pck, has not finished yet,
              -- we just wait.
           else 
        
             state            <= WAIT_FREE_PCK;
        
           end if;-- if(ppfm_free = '0') then
               
         when WAIT_DREQ =>
         
         
           if(rx_dreq_i = '1') then
             
             state             <= RE_SET_PAGE;
             
             --rx_sof_p1         <= '1';
             rx_sof_p1          <= '0';

             rx_ctrl           <= (others =>'0');
             rx_data           <= (others =>'0');
             
           end if;
                       
           
         when WAIT_FREE_PCK => 
              
            rx_ctrl           <= (others =>'0');
            rx_data           <= (others =>'0');  
            rx_valid          <= '1';   
            rx_eof_p1         <= '0';
              
            if(ppfm_free = '0') then
              
              start_free_pck   <= '1';
              state            <= IDLE;

            end if;
              
          when others =>
          
            state              <= IDLE;
            
        end case;
        

      end if;
    end if;
    
  end process fsm;

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
  
  
  mpm_pgreq_o         <= pgreq or re_pgreq;
  
  pgreq_or            <= pgreq_d0 or pgreq or re_pgreq_d0 or re_pgreq; 
   
                      -- IMPORTANT : a trick needed here, to make things faster, we provide pgaddr straight 
                      --             from quque output, otherwise, in  the rare case when the queue is written
                      --             with new data (so the output can change accordingly) there was a problem
                      --             of acknowledging the wrong data (we ack'ed the address, but the data is one c
                      --             cycle later !!!),
  mpm_pgaddr_o        <= rd_data(c_swc_page_addr_width - 1 downto 0) when (pgreq = '1') else pck_start_pgaddr;
                        --rd_data(c_swc_page_addr_width - 1 downto 0); -- read_data;
                        
  mpm_dreq_o          <= (dreq and rx_dreq_i and (not rx_tabort_p1_i)) or pgreq;-- and (not waiting_pck_start);

--  rx_valid            <= mpm_drdy_i when (state = READ_MPM) else '0';
--  rx_eof_p1           <= cnt_last_word and rx_valid;
  rx_sof_p1_o         <= rx_sof_p1;
  rx_eof_p1_o         <= rx_eof_p1;
  rx_ctrl_o           <= rx_ctrl;
  rx_data_o           <= rx_data;
  rx_valid_o          <= rx_valid;
--  rx_bytesel_o        <= mpm_ctrl_i(3);
  rx_bytesel_o        <= rx_bytesel;
  rx_idle_o           <= '1' when (state = IDLE) else '0';
  rx_rerror_p1_o      <= '0'; --???
  
  ppfm_free_o         <= ppfm_free;
  ppfm_free_pgaddr_o  <= ppfm_free_pgaddr;

  
end behavoural;