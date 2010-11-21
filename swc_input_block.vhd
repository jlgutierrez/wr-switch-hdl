-------------------------------------------------------------------------------
-- Title      : Input block
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : swc_input_block.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-10-28
-- Last update: 2010-11-01
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
-- Copyright (c) 2010 Maciej Lipinski
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2010-11-01  2.0      mlipinsk added FSM

-------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.swc_swcore_pkg.all;


entity swc_input_block is

  port (
    clk_i   : in std_logic;
    rst_n_i : in std_logic;

-------------------------------------------------------------------------------
-- Fabric I/F  
-------------------------------------------------------------------------------

    tx_sof_p1_i    : in  std_logic;
    tx_eof_p1_i    : in  std_logic;
    tx_data_i      : in  std_logic_vector(c_swc_data_width - 1 downto 0);
    tx_ctrl_i      : in  std_logic_vector(c_swc_ctrl_width - 1 downto 0);
    tx_valid_i     : in  std_logic;
    tx_bytesel_i   : in  std_logic;
    tx_dreq_o      : out std_logic;
    tx_abort_p1_i  : in  std_logic;
    tx_rerror_p1_i : in  std_logic;
-------------------------------------------------------------------------------
-- I/F with Page allocator (MMU)
-------------------------------------------------------------------------------    

    -- indicates that a port X wants to write page address of the "write" access
    mmu_page_alloc_req_o  : out  std_logic;
    
    
    mmu_page_alloc_done_i : in std_logic;

    -- array of pages' addresses to which ports want to write
    mmu_pageaddr_i : in  std_logic_vector(c_swc_page_addr_width - 1 downto 0);
    
    mmu_pageaddr_o : out  std_logic_vector(c_swc_page_addr_width - 1 downto 0);
    
    -- force freeing package starting with page outputed on mmu_pageaddr_o
    mmu_force_free_o   : out std_logic;
    
    mmu_force_free_done_i : in std_logic;
    
    mmu_force_free_addr_o : out std_logic_vector(c_swc_page_addr_width - 1 downto 0);
    
    -- set user count to the already allocated page (on mmu_pageaddr_o)
    mmu_set_usecnt_o   : out std_logic;
    
    mmu_set_usecnt_done_i  : in  std_logic;
    
    -- user count to be set (associated with an allocated page) in two cases:
    -- * mmu_pagereq_o    is HIGH - normal allocation
    -- * mmu_set_usecnt_o is HIGH - force user count to existing page alloc
    mmu_usecnt_o       : out  std_logic_vector(c_swc_usecount_width - 1 downto 0);
    
    -- memory full
    mmu_nomem_i : in std_logic;     
-------------------------------------------------------------------------------
-- I/F with Routing Table Unit (RTU)
-------------------------------------------------------------------------------      
    
    rtu_rsp_valid_i     : in std_logic;
    rtu_rsp_ack_o       : out std_logic;
    rtu_dst_port_mask_i : in std_logic_vector(c_swc_num_ports  - 1 downto 0);
    rtu_drop_i          : in std_logic;
    rtu_prio_i          : in std_logic_vector(c_swc_prio_width - 1 downto 0);
  
    
-------------------------------------------------------------------------------
-- I/F with Multiport Memory (MPU)
-------------------------------------------------------------------------------    
    
    -- indicates the beginning of the package
    mpm_pckstart_o : out  std_logic;
       
    -- array of pages' addresses to which ports want to write
    mpm_pageaddr_o : out  std_logic_vector(c_swc_page_addr_width - 1 downto 0);
    
    
    mpm_pagereq_o : out std_logic;
    -- indicator that the current page is about to be full (the last FB SRAM word
    -- is being pumped in currently), after ~c_swc_packet_mem_multiply cycles 
    -- from the rising edge of this signal this page will finish
    mpm_pageend_i  : in std_logic;

    mpm_data_o  : out  std_logic_vector(c_swc_data_width - 1 downto 0);

    mpm_ctrl_o  : out  std_logic_vector(c_swc_ctrl_width - 1 downto 0);    
    
    -- data ready - request from each port to write data to port's pump
    mpm_drdy_o  : out  std_logic;
    
    -- the input register of a pump is full, this means that the pump cannot
    -- be written by the port. As soon as the data which is in the input registet
    -- is written to FB SRAM memory, the signal goes LOW and writing is possible
    mpm_full_i  : in std_logic;

    -- request to write the content of pump's input register to FB SRAM memory, 
    -- thus flash/clean input register of the pump
    mpm_flush_o : out  std_logic;    
    


-------------------------------------------------------------------------------
-- I/F with Page Transfer Arbiter (PTA)
-------------------------------------------------------------------------------     
    -- indicates the beginning of the package, strobe
    pta_transfer_pck_o : out  std_logic;
    
    pta_transfer_ack_i : in std_logic;
       
    -- array of pages' addresses to which ports want to write
    pta_pageaddr_o : out  std_logic_vector(c_swc_page_addr_width - 1 downto 0);
    
    -- destination mask - indicates to which ports the packet should be
    -- forwarded
    pta_mask_o     : out  std_logic_vector(c_swc_num_ports - 1 downto 0);
    
    pta_pck_size_o : out  std_logic_vector(c_swc_max_pck_size_width - 1 downto 0);

    pta_prio_o     : out  std_logic_vector(c_swc_prio_width - 1 downto 0)
    
    );
end swc_input_block;
    
architecture syn of swc_input_block is    


-------------------------------------------------------------------------------
-- Function which calculates number of 1's in a vector
------------------------------------------------------------------------------- 
  function cnt (a:std_logic_vector) return integer is
    variable nmb : integer range 0 to a'LENGTH;
    variable ai : std_logic_vector(a'LENGTH-1 downto 0);
    constant middle : integer := a'LENGTH/2;
  begin
    ai := a;
    if ai'length>=2 then
      nmb := cnt(ai(ai'length-1 downto middle)) + cnt(ai(middle-1 downto 0));
    else
      if ai(0)='1' then 
        nmb:=1; 
      else 
        nmb:=0; 
      end if;
    end if;
    return nmb;
  end cnt;

  
  -- this is a page which is used for pck start
  signal pckstart_page_in_advance  : std_logic;
  signal pckstart_pageaddr         : std_logic_vector(c_swc_page_addr_width - 1 downto 0);
  signal pckstart_page_alloc_req   : std_logic;
  
  signal current_pckstart_pageaddr : std_logic_vector(c_swc_page_addr_width - 1 downto 0);
    
  -- this is a page which used within the pck
  signal interpck_page_in_advance  : std_logic;  
  signal interpck_pageaddr         : std_logic_vector(c_swc_page_addr_width - 1 downto 0);
  signal interpck_page_alloc_req   : std_logic;  
    
  
  -- WHY two separate page's for inter and start pck allocated in advance:
  -- in the case in which one pck has just finished, we need new page addr for the new pck
  -- very soon after writing the last page of previous pck, 

  -- this one is written one of the above values    
  --signal mmu_pageaddr              : std_logic_vector(c_swc_page_addr_width - 1 downto 0);  
    

  signal tx_dreq                   : std_logic;
  signal set_usecnt                : std_logic;
  
  signal mpm_pckstart              : std_logic;
  signal mpm_pagereq               : std_logic;  

  signal transfering_pck           : std_logic;

  signal rtu_dst_port_mask         : std_logic_vector(c_swc_num_ports  - 1 downto 0);
  signal rtu_prio                  : std_logic_vector(c_swc_prio_width - 1 downto 0);
--  signal rtu_drop                  : std_logic;
  signal rtu_rsp_ack               : std_logic;
  signal usecnt                    : std_logic_vector(c_swc_usecount_width - 1 downto 0);

 -- signal mpm_flush                 : std_logic;

  signal mmu_force_free            : std_logic; 

 --signal mpm_pageend_d1            : std_logic;

  signal pck_error_occured         : std_logic;
  
  
  signal pta_pageaddr              : std_logic_vector(c_swc_page_addr_width - 1 downto 0);
  signal pta_mask                  : std_logic_vector(c_swc_num_ports  - 1 downto 0);
  signal pta_prio                  : std_logic_vector(c_swc_prio_width - 1 downto 0);
  signal pta_pck_size              : std_logic_vector(c_swc_max_pck_size_width - 1 downto 0);
  
  type t_pck_state is (S_IDLE, 
                      -- S_RTU_RSP_SERVE, 
                       S_WAIT_FOR_SOF,           -- we've got RTU response, but there is no SOF
                       S_WAIT_FOR_RTU_RSP,       -- we've got SOF (request from previous pck) but there is no RTU valid signal (quite improbable)
                       S_WAIT_TO_WRITE_PREV_PCK, -- waiting for the previous packet to be written, in FB SRAM by the pump, the next
                                                 -- packet in the endpoint is ready
                       S_WAIT_FOR_VALID_PAGE,    -- this is the case when the previous packet was written to a page allocated in advance 
                                                 -- and we need to wait for the page to be allocated
                       S_PCK_START_1,            -- first mode of PCK start: we have the page ready, so we can set the page
                       S_PCK_START_2,            -- second mode of PCK start: we do not have the page ready, so we start writing the packet but
                                                 -- need to set the page as soon as it's allocated
                       S_SET_USECNT,             -- setting user count to first page of the pck
                       S_SET_NEXT_PAGE,    
                       S_WAIT_FOR_PAGE_END,
                       S_WAIT_FOR_PAGE_END_TERMINATION  ,   -- we wait for the pageend signal (comint from MPM) to finish, otherwise, if we enter 
                                                          -- S_WAIT_FOR_PAGE_END state again, we will unnecesarily request new page
                       S_DROP_PCK,              -- droping pck
                       S_AWAIT_TRANSFER);              

  type t_page_state is (S_IDLE, 
                        S_PCKSTART_PAGE_REQ,    
                        S_INTERPCK_PAGE_REQ); -- droping pck

  type t_rerror_state is (S_IDLE, 
                          S_WAIT_TO_FREE_PCK,    
                          S_ONE_PERROR,
                          S_TWO_PERRORS); -- droping pck                   
                   
  signal pck_state       : t_pck_state;
  signal page_state      : t_page_state;  
  signal rerror_state    : t_rerror_state;  
  
  -- this goes HIGH for one cycle when all the
  -- initial staff related to starting new packet 
  -- transfer was finished, so when exiting S_SET_USECNT state
  signal pck_mpm_write_established : std_logic;
  
  signal mmu_force_free_addr : std_logic_vector(c_swc_page_addr_width - 1 downto 0);
  
  signal mpm_drdy          : std_logic;
  signal pck_size      : std_logic_vector(c_swc_max_pck_size_width - 1 downto 0);
  
begin --arch


 pck_size_cnt : process(clk_i, rst_n_i)
 begin
   if rising_edge(clk_i) then
     if(rst_n_i = '0') then
       
       pck_size <= (others =>'0');
       
     else
       
       if(tx_sof_p1_i = '1') then
       
         pck_size <= (others =>'0');
         
       elsif(tx_valid_i = '1' and tx_eof_p1_i = '0') then
       
         pck_size <= std_logic_vector(unsigned(pck_size) + 1);
         
       end if;
       
     end if;
   end if;
   
 end process;
     
 fsm_pck : process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        --================================================
        pck_state                <= S_IDLE;
        
        tx_dreq                  <= '0';
        
        mpm_pckstart             <= '0';
        mpm_pagereq              <= '0';
 --       mpm_flush                <= '0';
        
        set_usecnt               <= '0';
        
        rtu_rsp_ack              <= '0';
        rtu_dst_port_mask        <= (others => '0');
        rtu_prio                 <= (others => '0');
        --rtu_drop                 <= '0';
        
--        mpm_pageend_d1           <= '0';
        
        pck_mpm_write_established<= '0';
        current_pckstart_pageaddr<= (others => '0');
        usecnt                   <= (others => '0');
        
        --================================================
      else

        -- main finite state machine
        case pck_state is

          when S_IDLE =>
            
            --tx_dreq                  <= '1';
 --           mpm_flush                <= '0';
            
--            if(rtu_rsp_valid_i = '1') then
--            
--              tx_dreq                  <= '1';
--              pck_state                <= S_RTU_RSP_SERVE;
--              
--             end if;
--
--          when S_RTU_RSP_SERVE =>
            
            -- we need decision from RTU, but also we want the transfer
            -- of the fram eto be finished, the transfer in normal case should
            -- take 2 cycles
            
            if(rtu_rsp_valid_i = '1'  and rtu_drop_i = '1') then
            
               -- if we've got RTU decision to drop, we don't give a damn about 
               -- anything else, just pretend to be receiving the msg
               tx_dreq                  <= '1';
               rtu_rsp_ack              <= '1';
               pck_state                <= S_DROP_PCK;
            
            elsif(rtu_rsp_valid_i = '1' and tx_sof_p1_i = '1' and mpm_full_i = '0' and pckstart_page_in_advance = '1' ) then

               -- beutifull, everything that is needed, is there:
               --  * RTU decision
               --  * SOF
               --  * adress for the first page allocated
               --  * memory not full
               
               tx_dreq                  <= '1';
               mpm_pckstart             <= '1';
               mpm_pagereq              <= '1';
               set_usecnt               <= '1';
               
               rtu_dst_port_mask        <= rtu_dst_port_mask_i;
               rtu_prio                 <= rtu_prio_i;
--               rtu_drop                 <= rtu_drop_i;
               usecnt                   <= std_logic_vector(to_signed(cnt(rtu_dst_port_mask_i),usecnt'length));
               rtu_rsp_ack              <= '1';               
               -- next state
               pck_state                <= S_PCK_START_1;


             elsif(rtu_rsp_valid_i = '1' and tx_sof_p1_i = '1' and (mpm_full_i = '1' or pckstart_page_in_advance = '0') ) then 
             
               
               rtu_dst_port_mask      <= rtu_dst_port_mask_i;
               rtu_prio               <= rtu_prio_i;
 --              rtu_drop               <= rtu_drop_i;
               usecnt                 <= std_logic_vector(to_signed(cnt(rtu_dst_port_mask_i),usecnt'length));
               
               rtu_rsp_ack            <= '1';
               
               pck_state              <= S_WAIT_TO_WRITE_PREV_PCK;
 
             elsif(rtu_rsp_valid_i = '1' and tx_sof_p1_i = '0') then
             
               -- so we've got RTU decision, but no SOF, let's wait for SOF
               -- but remember RTU RSP and ack it, so RTU is free 
               rtu_rsp_ack              <= '1';
               pck_state                <= S_WAIT_FOR_SOF;
               
               tx_dreq                  <= '1';
               
               rtu_dst_port_mask        <= rtu_dst_port_mask_i;
               rtu_prio                 <= rtu_prio_i;
--               rtu_drop                 <= rtu_drop_i;
               usecnt                   <= std_logic_vector(to_signed(cnt(rtu_dst_port_mask_i),usecnt'length));
             
             elsif(rtu_rsp_valid_i = '0' and tx_sof_p1_i = '1') then
             
               -- we've got SOF because it was requested at the end of the last PCK
               -- but the RTU is still processing
               rtu_rsp_ack              <= '1';
               pck_state                <= S_WAIT_FOR_RTU_RSP;
               tx_dreq                  <= '0';

             else
               
               -- wait for sth to happpen
               tx_dreq                  <= '0';
               
             end if;
        
          when S_WAIT_TO_WRITE_PREV_PCK =>
            
            
              rtu_rsp_ack              <= '0';
              -- TODO !!!!!!!!!!!!!!
              -- needed some signal in advance to tell us that end of full is 
              -- approaching
              if(mpm_full_i = '0' and pckstart_page_in_advance = '1' ) then

                tx_dreq                  <= '1';              
                mpm_pckstart             <= '1';
                mpm_pagereq              <= '1';
                set_usecnt               <= '1';
                pck_state                <=  S_PCK_START_1;
              
              end if;                   
              
              
          when S_WAIT_FOR_SOF =>
              
              rtu_rsp_ack              <= '0';
              
              if(tx_sof_p1_i = '1' and mpm_full_i = '0' and pckstart_page_in_advance = '1' ) then
                tx_dreq                  <= '1';
                mpm_pckstart             <= '1';
                mpm_pagereq              <= '1';
                set_usecnt               <= '1';
                pck_state                <=  S_PCK_START_1;   
                
              elsif(tx_sof_p1_i = '1' and ( mpm_full_i = '1' or pckstart_page_in_advance = '0' )) then
               
               pck_state              <= S_WAIT_TO_WRITE_PREV_PCK;
               tx_dreq                <= '0'; 
                    
              end if;
              
          when S_WAIT_FOR_RTU_RSP => 
            
            
            if(tx_rerror_p1_i = '1' ) then
            
              pck_state                <= S_IDLE;
  --           mpm_flush                <= '1';
              tx_dreq                  <= '1';
              
            elsif(rtu_rsp_valid_i = '1' and mpm_full_i = '0' and pckstart_page_in_advance = '1') then

              tx_dreq                  <= '1';
              mpm_pckstart             <= '1';
              mpm_pagereq              <= '1';
              set_usecnt               <= '1';
            
              rtu_dst_port_mask        <= rtu_dst_port_mask_i;
              rtu_prio                 <= rtu_prio_i;
--              rtu_drop                 <= rtu_drop_i;
              usecnt                   <= std_logic_vector(to_signed(cnt(rtu_dst_port_mask_i),usecnt'length));
              rtu_rsp_ack              <= '1'; 
              pck_state                <=  S_PCK_START_1; 
              
            elsif(rtu_rsp_valid_i = '1' and ( mpm_full_i = '1' or pckstart_page_in_advance = '0' )) then
            
              tx_dreq                  <= '0';
              rtu_dst_port_mask        <= rtu_dst_port_mask_i;
              rtu_prio                 <= rtu_prio_i;
 --             rtu_drop                 <= rtu_drop_i;
              usecnt                   <= std_logic_vector(to_signed(cnt(rtu_dst_port_mask_i),usecnt'length));
              rtu_rsp_ack              <= '1'; 
              pck_state                <= S_WAIT_TO_WRITE_PREV_PCK;
              
            end if;
  
          when S_PCK_START_1 =>
              
               rtu_rsp_ack              <= '0';
               mpm_pckstart             <= '0';
               mpm_pagereq              <= '0';
               current_pckstart_pageaddr<=pckstart_pageaddr;
               -- next state
               pck_state                <= S_SET_USECNT;

          when S_SET_USECNT =>
              
           
              if(mmu_set_usecnt_done_i = '1') then
              
                set_usecnt               <= '0';   
                pck_state                <=  S_WAIT_FOR_PAGE_END;
                pck_mpm_write_established<= '1';                
              end if;          
               
          when S_WAIT_FOR_PAGE_END =>
            
            
           pck_mpm_write_established<= '0';  
           
--           if(mpm_pageend_i = '1' and mpm_pageend_d1 = '0'  and pckstart_page_alloc_req = '0' and tx_eof_p1_i = '0') then
--           if(mpm_pageend_i = '1' and mpm_pageend_d1 = '0'  and pckstart_page_alloc_req = '0' ) then
           if(tx_rerror_p1_i = '1')then
           
              pck_state               <= S_IDLE;
  --            mpm_flush               <= '1';
              tx_dreq                 <= '1';
           
--           elsif(mpm_pageend_i = '1'  and pckstart_page_alloc_req = '0' ) then
           elsif(mpm_pageend_i = '1' ) then
       
              pck_state                <=  S_SET_NEXT_PAGE;
              mpm_pagereq              <= '1';
              
           elsif(tx_eof_p1_i = '1' and transfering_pck = '1') then
              -- transfer arbiter busy, wait till it is free
              pck_state               <= S_AWAIT_TRANSFER;
 --             mpm_flush               <= '1';
              tx_dreq                 <= '0';
             
           elsif(tx_eof_p1_i = '1'  and transfering_pck = '0' ) then
 
              pck_state               <= S_IDLE;
 --             mpm_flush               <= '1';
              tx_dreq                 <= '1';
              
            end if;        

          when S_SET_NEXT_PAGE =>

            mpm_pagereq                <= '0';
              
            if(tx_eof_p1_i = '1' or tx_rerror_p1_i = '1' ) then

              pck_state                    <= S_IDLE;
 --             mpm_flush                <= '1';
              tx_dreq                  <= '1';
              
            elsif(mpm_pageend_i = '1') then
            
              pck_state                    <= S_WAIT_FOR_PAGE_END_TERMINATION;
            
            else

              pck_state                    <=  S_WAIT_FOR_PAGE_END;
                         
            end if;        

        
          when S_WAIT_FOR_PAGE_END_TERMINATION => 
            
            if(tx_eof_p1_i = '1' or tx_rerror_p1_i = '1' ) then

              pck_state                    <= S_IDLE;
 --             mpm_flush                    <= '1';
              tx_dreq                  <= '1';
              
            elsif(mpm_pageend_i = '0') then
            
              pck_state                    <= S_WAIT_FOR_PAGE_END;
            
            end if; 
            
            
          when S_DROP_PCK => 
             
            if(tx_eof_p1_i = '1' or tx_rerror_p1_i = '1' ) then 
              
              tx_dreq                 <= '1';    
              pck_state               <= S_IDLE;
              tx_dreq                  <= '1';
              
            end if;
          when S_AWAIT_TRANSFER =>
            
            tx_dreq                  <= '0';
 --           mpm_flush                <= '0';

            if(transfering_pck = '0') then
              pck_state               <= S_IDLE;
              tx_dreq                  <= '1';
            end if;

          when others =>
            
              pck_state                   <= S_IDLE;
              tx_dreq                  <= '1';
            
        end case;
        
 --       mpm_pageend_d1   <= mpm_pageend_i;

      end if;
    end if;
    
  end process;
  



fsm_page : process(clk_i, rst_n_i)
 begin
   if rising_edge(clk_i) then
     if(rst_n_i = '0') then
       --========================================
       page_state               <= S_IDLE;
       
       interpck_pageaddr        <= (others => '0');
       interpck_page_alloc_req  <= '0';
       
       
       
       pckstart_pageaddr        <= (others => '0');
       pckstart_page_alloc_req  <= '0';
       

       --========================================
     else

       -- main finite state machine
       case page_state is

        when S_IDLE =>
           
           interpck_page_alloc_req   <= '0';
           pckstart_page_alloc_req   <= '0';
           
           if(pckstart_page_in_advance = '0') then
           
             pckstart_page_alloc_req  <= '1';
             page_state               <= S_PCKSTART_PAGE_REQ;
             
           elsif(interpck_page_in_advance = '0') then 
             
             interpck_page_alloc_req  <= '1';
             page_state               <= S_INTERPCK_PAGE_REQ;
             
           end if;

        when S_PCKSTART_PAGE_REQ =>          
    
          if( mmu_page_alloc_done_i = '1') then

             pckstart_page_alloc_req  <= '0';
             -- remember the page start addr

             pckstart_pageaddr        <= mmu_pageaddr_i;

      
             if(interpck_page_in_advance = '0') then
             
               page_state               <= S_INTERPCK_PAGE_REQ;
               interpck_page_alloc_req  <= '1';
               
             else 
               
               page_state               <= S_IDLE;
              
             end if;
      
           end if;



        when S_INTERPCK_PAGE_REQ =>          
    
          if( mmu_page_alloc_done_i = '1') then
    
             interpck_page_alloc_req   <= '0';
             interpck_pageaddr         <= mmu_pageaddr_i;
             
             if(pckstart_page_in_advance = '0') then
               page_state                <= S_PCKSTART_PAGE_REQ;
               pckstart_page_alloc_req   <= '1';
             else 
               page_state                <= S_IDLE;
               interpck_page_alloc_req   <= '0';
             end if;             
      
           end if;

         when others =>
           
             page_state                   <= S_IDLE;
           
       end case;
       
       --

     end if;
   end if;
   
 end process;
  


fsm_perror : process(clk_i, rst_n_i)
 variable cnt : integer := 0;
 begin
   if rising_edge(clk_i) then
     if(rst_n_i = '0') then
       --========================================
       mmu_force_free_addr <= (others => '0');
       mmu_force_free      <= '0';
       cnt                 := 0;
       --========================================
     else

       -- main finite state machine
       case rerror_state is

        when S_IDLE =>
          
          mmu_force_free      <= '0';
          
          if(tx_rerror_p1_i = '1' and pck_state /=S_DROP_PCK) then 
          
            rerror_state                <= S_WAIT_TO_FREE_PCK;
            mmu_force_free_addr         <= current_pckstart_pageaddr;
            
          end if;

        -- wait till the next pck is started
        when S_WAIT_TO_FREE_PCK =>          
            
            
            if(pck_state =  S_WAIT_FOR_PAGE_END) then

              rerror_state              <= S_ONE_PERROR;--S_TWO_PERRORS;
              mmu_force_free            <= '1';
              
            elsif(cnt > 10 and pck_state = S_IDLE) then
            
              rerror_state              <= S_ONE_PERROR;
              mmu_force_free            <= '1';
              cnt                       :=  0;
            
            elsif(pck_state = S_IDLE) then
            
              cnt := cnt + 1;
            
            end if;
               

        when S_ONE_PERROR => 
          
          if(mmu_force_free_done_i = '1' ) then
            
            mmu_force_free            <= '0';
            rerror_state              <= S_IDLE;
            
          end if;
          
-- TODO: add two pck errors
--        when S_TWO_PERRORS =>          


         when others =>
           
             rerror_state        <= S_IDLE;
             mmu_force_free      <= '0';
       end case;
       
       --

     end if;
   end if;
   
 end process;

--===================================================================
  input: process(clk_i, rst_n_i)
  begin
    if rising_edge(clk_i) then
      
      
      if(rst_n_i = '0') then
      --===================================================
      pckstart_page_in_advance  <= '0';
      interpck_page_in_advance  <= '0';
      transfering_pck           <= '0';
      pck_error_occured         <= '0';
      pta_pageaddr              <=(others => '0');
      pta_mask                  <=(others => '0');
      pta_prio                  <=(others => '0');
      pta_pck_size              <=(others => '0');
      --===================================================
      else

        if(tx_eof_p1_i = '1' and pck_state /=S_DROP_PCK) then 
        
          transfering_pck <= '1';
          
          pta_pageaddr    <= current_pckstart_pageaddr;
          pta_mask        <= rtu_dst_port_mask;
          pta_prio        <= rtu_prio;
          pta_pck_size    <= pck_size;
          
        elsif(pta_transfer_ack_i = '1') then
          transfering_pck <= '0';
          
          pta_pageaddr    <= (others => '0');
          pta_mask        <= (others => '0');
          pta_prio        <= (others => '0');
          pta_pck_size    <= (others => '0');
--        elsif(tx_eof_p1_i = '1' or tx_rerror_p1_i = '1' ) then 
--          transfering_pck <= '0';
        end if;

--        if(tx_rerror_p1_i = '1' and pck_state /=S_DROP_PCK) then 
        if(tx_rerror_p1_i = '1' )then 
          pck_error_occured <= '1';
        elsif(mmu_force_free_done_i = '1') then 
          pck_error_occured <= '0';
        end if;
      
        if(pck_state = S_SET_NEXT_PAGE) then 
          interpck_page_in_advance <= '0';
        elsif(mmu_page_alloc_done_i = '1' and interpck_page_alloc_req = '1') then
          interpck_page_in_advance <= '1';
        end if;
          

        if(mmu_set_usecnt_done_i = '1') then 
          pckstart_page_in_advance <= '0';
        elsif(mmu_page_alloc_done_i = '1' and pckstart_page_alloc_req = '1') then
          pckstart_page_in_advance <= '1';
        end if;

     end if;
    end if;
  end process;


  mmu_set_usecnt_o       <= set_usecnt;
  mmu_usecnt_o           <= usecnt;

  mpm_pckstart_o         <= mpm_pckstart;

  mmu_page_alloc_req_o   <= interpck_page_alloc_req or pckstart_page_alloc_req;
--  tx_dreq_o              <= '1' when (state = S_WAIT_FOR_NEW_PAGE_REQ) else tx_dreq and not mpm_full_i;
  tx_dreq_o              <= tx_dreq                       when (pck_state = S_IDLE)                   else
                            not mpm_full_i                when (pck_state = S_WAIT_TO_WRITE_PREV_PCK) else 
                            tx_dreq and not mpm_full_i    ;
                            
                            
  mpm_drdy               <= '0' when (pck_state = S_DROP_PCK) else tx_valid_i ;
  mpm_drdy_o             <= mpm_drdy;
  mpm_flush_o            <= tx_eof_p1_i when (pck_state = S_WAIT_FOR_PAGE_END or 
                                              pck_state = S_SET_NEXT_PAGE     or 
                                              pck_state = S_WAIT_FOR_PAGE_END_TERMINATION) else '0'; --mpm_flush;
  mpm_pagereq_o          <= mpm_pagereq;
  
  mmu_force_free_o       <= mmu_force_free;
  
  mpm_data_o             <= tx_data_i;
  
  
  mpm_ctrl_o(3)          <= tx_bytesel_i;
  mpm_ctrl_o(2 downto 0) <= tx_ctrl_i(2 downto 0);
  
--  mmu_pageaddr_o         <= pckstart_pageaddr;
  mmu_pageaddr_o         <= interpck_pageaddr when (pck_state = S_SET_NEXT_PAGE         OR 
                                                    pck_state = S_WAIT_FOR_PAGE_END)   else pckstart_pageaddr;

  mpm_pageaddr_o         <= interpck_pageaddr when (pck_state = S_SET_NEXT_PAGE         OR 
                                                    pck_state = S_WAIT_FOR_PAGE_END)   else pckstart_pageaddr;
  
  rtu_rsp_ack_o          <= rtu_rsp_ack;
  
  
  mmu_force_free_addr_o  <= mmu_force_free_addr;
  
  pta_transfer_pck_o     <= transfering_pck;
  
--  pta_pageaddr_o         <= current_pckstart_pageaddr;
--  pta_mask_o             <= rtu_dst_port_mask;
--  pta_prio_o             <= rtu_prio;
--  pta_pck_size_o         <= pck_size;
  
  pta_pageaddr_o         <= pta_pageaddr;
  pta_mask_o             <= pta_mask;
  pta_prio_o             <= pta_prio;
  pta_pck_size_o         <= pta_pck_size;
  
end syn; -- arch