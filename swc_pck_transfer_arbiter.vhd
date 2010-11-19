-------------------------------------------------------------------------------
-- Title      : Packet Transfer Arbiter
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : swc_pck_transfer_arbiter.vhd
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
-- 2010-11-03  1.0      mlipinsk added FSM

-------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.swc_swcore_pkg.all;


entity swc_pck_transfer_arbiter is

  port (
    clk_i   : in std_logic;
    rst_n_i : in std_logic;

-------------------------------------------------------------------------------
-- I/F with output block
-------------------------------------------------------------------------------

    ob_data_valid_o : out  std_logic_vector(c_swc_num_ports -1 downto 0);
    
    ob_ack_i : in  std_logic_vector(c_swc_num_ports -1 downto 0);

    ob_pageaddr_o : out  std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
    
    ob_prio_o     : out  std_logic_vector(c_swc_num_ports * c_swc_prio_width - 1 downto 0);

    ob_pck_size_o : out  std_logic_vector(c_swc_num_ports * c_swc_max_pck_size_width - 1 downto 0);
-------------------------------------------------------------------------------
-- I/F with Input Block
-------------------------------------------------------------------------------     
    ib_transfer_pck_i : in  std_logic_vector(c_swc_num_ports -1 downto 0);
    
    ib_transfer_ack_o : out  std_logic_vector(c_swc_num_ports -1 downto 0);
    
    ib_busy_o     : out  std_logic_vector(c_swc_num_ports  - 1 downto 0);  
    
    ib_pck_size_i : in  std_logic_vector(c_swc_num_ports * c_swc_max_pck_size_width - 1 downto 0);
    
    ib_pageaddr_i : in  std_logic_vector(c_swc_num_ports * c_swc_page_addr_width - 1 downto 0);
    
    ib_mask_i     : in  std_logic_vector(c_swc_num_ports * c_swc_num_ports - 1 downto 0);

    ib_prio_i     : in  std_logic_vector(c_swc_num_ports * c_swc_prio_width - 1 downto 0)
    
    );
end swc_pck_transfer_arbiter;
    
architecture syn of swc_pck_transfer_arbiter is    


     subtype t_pageaddr     is std_logic_vector(c_swc_page_addr_width    - 1 downto 0);
     subtype t_prio         is std_logic_vector(c_swc_prio_width         - 1 downto 0);
     subtype t_mask         is std_logic_vector(c_swc_num_ports          - 1 downto 0);
     subtype t_pck_size     is std_logic_vector(c_swc_max_pck_size_width - 1 downto 0);
     
     type t_pageaddr_array  is array (c_swc_num_ports - 1 downto 0) of t_pageaddr;
     type t_prio_array      is array (c_swc_num_ports - 1 downto 0) of t_prio;
     type t_mask_array      is array (c_swc_num_ports - 1 downto 0) of t_mask;
     type t_pck_size_array  is array (c_swc_num_ports - 1 downto 0) of t_pck_size;
     
     ---------------------------------------------------------------------------
     -- signals outputed from Pck Transfer Input (PTI)
     -- before MUX !!!!
     ---------------------------------------------------------------------------
--     signal pto_transfer_pck  : std_logic_vector(c_swc_num_ports - 1 downto 0);
     signal pto_pageaddr      : t_pageaddr_array;
     signal pto_output_mask   : t_mask_array;
     signal pto_read_mask     : t_mask_array;
     signal pto_prio          : t_prio_array;
     signal pto_pck_size      : t_pck_size_array;
     
     ---------------------------------------------------------------------------
     -- signals inputed to Pck Transfer Output (PTO) from Pck Transfer Input (TPI)
     -- MUXED !!!!!!!!!!
     ---------------------------------------------------------------------------     
     signal pti_transfer_data_valid : std_logic_vector(c_swc_num_ports  - 1 downto 0);
     signal pti_transfer_data_ack   : std_logic_vector(c_swc_num_ports  - 1 downto 0);
     signal pti_pageaddr            : t_pageaddr_array;
     signal pti_prio                : t_prio_array;
     signal pti_pck_size      : t_pck_size_array;     
     
     
     
--     signal rd_pageaddr  : t_pageaddr;
---     signal rd_prio      : t_prio;
--     signal rd_mask      : t_mask;

     
     
--     signal transfer_pck : std_logic;
--     signal transfer_ack : std_logic;
--     signal pageaddr     : std_logic_vector(c_swc_page_addr_width - 1 downto 0);
--     signal prio         : std_logic_vector(c_swc_prio_width - 1 downto 0);
--     signal read_mask    : std_logic_vector(c_swc_num_ports - 1 downto 0); 
--     signal output_mask  : std_logic_vector(c_swc_num_ports - 1 downto 0); 
--     signal transfer_data_valid : std_logic;
     
     
     signal sync_sreg    : std_logic_vector(c_swc_num_ports - 1 downto 0);
     signal sync_cntr    : integer range 0 to c_swc_num_ports - 1;
     signal sync_cntr_ack : integer range 0 to c_swc_num_ports-1;
     
begin --arch


  
  
  sync_gen : process (clk_i, rst_n_i)
  begin  -- process
    if rising_edge(clk_i) then
      if(rst_n_i = '0') then
        sync_sreg (0)                             <= '1';
        sync_sreg (sync_sreg'length - 1 downto 1) <= (others => '0');
        sync_cntr                                 <= 0; --c_swc_num_ports - 1;
        sync_cntr_ack                             <= c_swc_num_ports - 1; --c_swc_num_ports - 2; -- c_swc_packet_mem_multiply-1;

      else
        sync_sreg <= sync_sreg(sync_sreg'length-2 downto 0) & sync_sreg(sync_sreg'length-1);

        if(sync_cntr = c_swc_num_ports-1) then
          sync_cntr <= 0;
        else
          sync_cntr <= sync_cntr + 1;
        end if;

        if(sync_cntr_ack = c_swc_num_ports-1) then
          sync_cntr_ack <= 0;
        else
          sync_cntr_ack <= sync_cntr_ack + 1;
        end if;

        
      end if;
    end if;
  end process;




  multimux_out : process(sync_cntr,pto_output_mask,pto_pageaddr,pto_prio)
  begin 
  
        
           pti_transfer_data_valid(0) <= pto_output_mask((sync_cntr + 0) mod c_swc_num_ports)(0);
           pti_pageaddr           (0) <= pto_pageaddr   ((sync_cntr + 0) mod c_swc_num_ports);
           pti_prio               (0) <= pto_prio       ((sync_cntr + 0) mod c_swc_num_ports);
           pti_pck_size           (0) <= pto_pck_size   ((sync_cntr + 0) mod c_swc_num_ports);

           pti_transfer_data_valid(1) <= pto_output_mask((sync_cntr + 1) mod c_swc_num_ports)(1);
           pti_pageaddr           (1) <= pto_pageaddr   ((sync_cntr + 1) mod c_swc_num_ports);
           pti_prio               (1) <= pto_prio       ((sync_cntr + 1) mod c_swc_num_ports);
           pti_pck_size           (1) <= pto_pck_size   ((sync_cntr + 1) mod c_swc_num_ports);

           pti_transfer_data_valid(2) <= pto_output_mask((sync_cntr + 2) mod c_swc_num_ports)(2);
           pti_pageaddr           (2) <= pto_pageaddr   ((sync_cntr + 2) mod c_swc_num_ports);
           pti_prio               (2) <= pto_prio       ((sync_cntr + 2) mod c_swc_num_ports);
           pti_pck_size           (2) <= pto_pck_size   ((sync_cntr + 2) mod c_swc_num_ports);
           
           pti_transfer_data_valid(3) <= pto_output_mask((sync_cntr + 3) mod c_swc_num_ports)(3);
           pti_pageaddr           (3) <= pto_pageaddr   ((sync_cntr + 3) mod c_swc_num_ports);
           pti_prio               (3) <= pto_prio       ((sync_cntr + 3) mod c_swc_num_ports);
           pti_pck_size           (3) <= pto_pck_size   ((sync_cntr + 3) mod c_swc_num_ports);

           pti_transfer_data_valid(4) <= pto_output_mask((sync_cntr + 4) mod c_swc_num_ports)(4);
           pti_pageaddr           (4) <= pto_pageaddr   ((sync_cntr + 4) mod c_swc_num_ports);
           pti_prio               (4) <= pto_prio       ((sync_cntr + 4) mod c_swc_num_ports);
           pti_pck_size           (4) <= pto_pck_size   ((sync_cntr + 4) mod c_swc_num_ports);

           pti_transfer_data_valid(5) <= pto_output_mask((sync_cntr + 5) mod c_swc_num_ports)(5);
           pti_pageaddr           (5) <= pto_pageaddr   ((sync_cntr + 5) mod c_swc_num_ports);
           pti_prio               (5) <= pto_prio       ((sync_cntr + 5) mod c_swc_num_ports);
           pti_pck_size           (5) <= pto_pck_size   ((sync_cntr + 5) mod c_swc_num_ports);

           pti_transfer_data_valid(6) <= pto_output_mask((sync_cntr + 6) mod c_swc_num_ports)(6);
           pti_pageaddr           (6) <= pto_pageaddr   ((sync_cntr + 6) mod c_swc_num_ports);
           pti_prio               (6) <= pto_prio       ((sync_cntr + 6) mod c_swc_num_ports);
           pti_pck_size           (6) <= pto_pck_size   ((sync_cntr + 6) mod c_swc_num_ports);          
          
           pti_transfer_data_valid(7) <= pto_output_mask((sync_cntr + 7) mod c_swc_num_ports)(7);
           pti_pageaddr           (7) <= pto_pageaddr   ((sync_cntr + 7) mod c_swc_num_ports);
           pti_prio               (7) <= pto_prio       ((sync_cntr + 7) mod c_swc_num_ports);
           pti_pck_size           (7) <= pto_pck_size   ((sync_cntr + 7) mod c_swc_num_ports);

           pti_transfer_data_valid(8) <= pto_output_mask((sync_cntr + 8) mod c_swc_num_ports)(8);
           pti_pageaddr           (8) <= pto_pageaddr   ((sync_cntr + 8) mod c_swc_num_ports);
           pti_prio               (8) <= pto_prio       ((sync_cntr + 8) mod c_swc_num_ports);
           pti_pck_size           (8) <= pto_pck_size   ((sync_cntr + 8) mod c_swc_num_ports);

           pti_transfer_data_valid(9) <= pto_output_mask((sync_cntr + 9) mod c_swc_num_ports)(9);
           pti_pageaddr           (9) <= pto_pageaddr   ((sync_cntr + 9) mod c_swc_num_ports);
           pti_prio               (9) <= pto_prio       ((sync_cntr + 9) mod c_swc_num_ports);
           pti_pck_size           (9) <= pto_pck_size   ((sync_cntr + 9) mod c_swc_num_ports);


           pti_transfer_data_valid(10) <= pto_output_mask((sync_cntr + 10) mod c_swc_num_ports)(10);
           pti_pageaddr           (10) <= pto_pageaddr   ((sync_cntr + 10) mod c_swc_num_ports);
           pti_prio               (10) <= pto_prio       ((sync_cntr + 10) mod c_swc_num_ports);
           pti_pck_size           (10) <= pto_pck_size   ((sync_cntr + 10) mod c_swc_num_ports);

  end process;
     
     
--    multimux_in : process(sync_cntr_ack,pti_transfer_data_ack,pto_read_mask)
--    begin
      
   test : process (clk_i, rst_n_i)
   begin
     if rising_edge(clk_i) then
       if(rst_n_i = '0') then
       
           for i in 0 to c_swc_num_ports -1 loop
               pto_read_mask(i) <= (others =>'0');  
           end loop;
       
       else


         pto_read_mask((sync_cntr_ack + 0)  mod c_swc_num_ports)(0)                                  <= pti_transfer_data_ack(0);  
         pto_read_mask((sync_cntr_ack + 0)  mod c_swc_num_ports)(c_swc_num_ports - 1 downto (0 + 1)) <= (others => '0');  
         
         pto_read_mask((sync_cntr_ack + 1)  mod c_swc_num_ports)((1 - 1))                            <=  '0';  
         pto_read_mask((sync_cntr_ack + 1)  mod c_swc_num_ports)( 1)                                 <= pti_transfer_data_ack(1);  
         pto_read_mask((sync_cntr_ack + 1)  mod c_swc_num_ports)(c_swc_num_ports - 1 downto (1 + 1)) <= (others => '0');  

         pto_read_mask((sync_cntr_ack + 2)  mod c_swc_num_ports)((2 - 1) downto 0)                   <=  (others => '0'); 
         pto_read_mask((sync_cntr_ack + 2)  mod c_swc_num_ports)( 2)                                 <=  pti_transfer_data_ack(2);  
         pto_read_mask((sync_cntr_ack + 2)  mod c_swc_num_ports)(c_swc_num_ports - 1 downto (2 + 1)) <=  (others => '0');


         pto_read_mask((sync_cntr_ack + 3)  mod c_swc_num_ports)((3 - 1) downto 0)                   <=  (others => '0');
         pto_read_mask((sync_cntr_ack + 3)  mod c_swc_num_ports)( 3)                                 <=  pti_transfer_data_ack(3);  
         pto_read_mask((sync_cntr_ack + 3)  mod c_swc_num_ports)(c_swc_num_ports - 1 downto (3 + 1)) <=  (others => '0');

         pto_read_mask((sync_cntr_ack + 4)  mod c_swc_num_ports)((4 - 1) downto 0)                   <=  (others => '0');
         pto_read_mask((sync_cntr_ack + 4)  mod c_swc_num_ports)(4)                                  <=  pti_transfer_data_ack(4);  
         pto_read_mask((sync_cntr_ack + 4)  mod c_swc_num_ports)(c_swc_num_ports - 1 downto (4 + 1)) <=  (others => '0');

         pto_read_mask((sync_cntr_ack + 5)  mod c_swc_num_ports)((5 - 1) downto 0)                   <=  (others => '0');
         pto_read_mask((sync_cntr_ack + 5)  mod c_swc_num_ports)(5)                                  <=  pti_transfer_data_ack(5);  
         pto_read_mask((sync_cntr_ack + 5)  mod c_swc_num_ports)(c_swc_num_ports - 1 downto (5 + 1)) <=  (others => '0');
         
         
         pto_read_mask((sync_cntr_ack + 6)  mod c_swc_num_ports)((6 - 1) downto 0)                   <=  (others => '0');
         pto_read_mask((sync_cntr_ack + 6)  mod c_swc_num_ports)(6)                                  <=  pti_transfer_data_ack(6); 
         pto_read_mask((sync_cntr_ack + 6)  mod c_swc_num_ports)(c_swc_num_ports - 1 downto (6 + 1)) <=  (others => '0');
         
          
         pto_read_mask((sync_cntr_ack + 7)  mod c_swc_num_ports)((7 - 1) downto 0)                   <=  (others => '0'); 
         pto_read_mask((sync_cntr_ack + 7)  mod c_swc_num_ports)(7)                                  <=  pti_transfer_data_ack(7); 
         pto_read_mask((sync_cntr_ack + 7)  mod c_swc_num_ports)(c_swc_num_ports - 1 downto (7 + 1)) <=  (others => '0');
          
         pto_read_mask((sync_cntr_ack + 8)  mod c_swc_num_ports)((8 - 1) downto 0)                   <=  (others => '0'); 
         pto_read_mask((sync_cntr_ack + 8)  mod c_swc_num_ports)(8)                                  <=  pti_transfer_data_ack(8); 
         pto_read_mask((sync_cntr_ack + 8)  mod c_swc_num_ports)(c_swc_num_ports - 1 downto (8 + 1)) <= (others => '0');         
         
         pto_read_mask((sync_cntr_ack + 9)  mod c_swc_num_ports)((9 - 1) downto 0)                   <=  (others => '0'); 
         pto_read_mask((sync_cntr_ack + 9)  mod c_swc_num_ports)(9)                                  <=  pti_transfer_data_ack(9); 
         pto_read_mask((sync_cntr_ack + 9)  mod c_swc_num_ports)((9 + 1))                            <=  '0';
                  
         pto_read_mask((sync_cntr_ack +10)  mod c_swc_num_ports)((10 - 1) downto 0)                  <=  (others => '0');
         pto_read_mask((sync_cntr_ack +10)  mod c_swc_num_ports)(10)                                 <=  pti_transfer_data_ack(10);
         
      end if;    
    end if;
         
--         pto_read_mask(sync_cntr_ack + 0)(c_swc_num_ports-1  downto 1)  <= (others =>'0');
   end process;  
   
      
     
--  gen_mux : for i in 0 to c_swc_num_ports-1 generate
--    multimux_out : process(sync_cntr,pto_output_mask,pto_pageaddr,pto_prio)
--    begin
--
--      for i in 0 to c_swc_num_ports-1 loop    
--
--       if(((sync_cntr + i) mod c_swc_num_ports) < c_swc_num_ports) then
--  
--           pti_transfer_data_valid(i) <= pto_output_mask((sync_cntr + i) mod c_swc_num_ports)(i);
--           pti_pageaddr           (i) <= pto_pageaddr   ((sync_cntr + i) mod c_swc_num_ports);
--           pti_prio               (i) <= pto_prio       ((sync_cntr + i) mod c_swc_num_ports);
--           
--        else
--          
--           pti_transfer_data_valid(i)       <= '0';
--           pti_pageaddr           (i)       <= (others =>'0'); 
----           pti_prio               (i)       <= (others =>'0');
--
--        end if;
--      end loop;
--    end process;
--  end generate gen_mux;

--gen_mux : for i in 0 to c_swc_num_ports-1 generate
--  
--           pti_transfer_data_valid(i) <= pto_output_mask((sync_cntr + i) mod c_swc_num_ports)(i);
--           pti_pageaddr           (i) <= pto_pageaddr   ((sync_cntr + i) mod c_swc_num_ports);
--           pti_prio               (i) <= pto_prio       ((sync_cntr + i) mod c_swc_num_ports);
--           
--end generate gen_mux;
--
--gen_mux_1: for i in 0 to c_swc_num_ports-1 generate    
--
--        pto_read_mask((sync_cntr_ack + i) mod c_swc_num_ports)(i)  <=  pti_transfer_data_ack(i);  
--           
--end generate gen_mux_1;

  
--  gen_mux_1: for i in 0 to c_swc_num_ports-1 generate    
--    multimux_in : process(sync_cntr_ack,pti_transfer_data_ack)
--    begin
--  
--    for i in 0 to c_swc_num_ports-1 loop    
--
--         if(((sync_cntr_ack + i) mod c_swc_num_ports ) < c_swc_num_ports ) then
--
--           pto_read_mask((sync_cntr_ack + i) mod c_swc_num_ports)(i)  <=  pti_transfer_data_ack(i);  
--           
--        else
--          
--           pto_read_mask((sync_cntr_ack + i) mod c_swc_num_ports)(i)  <=  '0';  
--
--        end if;
--      end loop;
--   end process;
--end generate gen_mux_1;
      
  gen_input : for i in 0 to c_swc_num_ports-1 generate
    TRANSFER_INPUT : swc_pck_transfer_input 
    port map (
      clk_i               => clk_i,
      rst_n_i             => rst_n_i,
      pto_transfer_pck_o  => open,
      pto_pageaddr_o      => pto_pageaddr      (i),
      pto_output_mask_o   => pto_output_mask   (i),
      pto_read_mask_i     => pto_read_mask     (i),
      pto_prio_o          => pto_prio          (i),
      pto_pck_size_o      => pto_pck_size      (i),
      ib_transfer_pck_i   => ib_transfer_pck_i (i),
      ib_pageaddr_i       => ib_pageaddr_i    ((i + 1)*c_swc_page_addr_width    - 1 downto i*c_swc_page_addr_width),
      ib_mask_i           => ib_mask_i        ((i + 1)*c_swc_num_ports          - 1 downto i*c_swc_num_ports),
      ib_prio_i           => ib_prio_i        ((i + 1)*c_swc_prio_width         - 1 downto i*c_swc_prio_width),
      ib_pck_size_i       => ib_pck_size_i    ((i + 1)*c_swc_max_pck_size_width - 1 downto i*c_swc_max_pck_size_width),
      ib_transfer_ack_o   => ib_transfer_ack_o (i),
      ib_busy_o           => ib_busy_o         (i)
      
      );
  end generate gen_input;
  
  gen_output : for i in 0 to c_swc_num_ports-1 generate
    TRANSFER_OUTPUT : swc_pck_transfer_output
    port map(
      clk_i                    => clk_i,
      rst_n_i                  => rst_n_i,
      ob_transfer_data_valid_o => ob_data_valid_o        (i),
      ob_pageaddr_o            => ob_pageaddr_o         ((i + 1)*c_swc_page_addr_width    - 1 downto i*c_swc_page_addr_width),
      ob_prio_o                => ob_prio_o             ((i + 1)*c_swc_prio_width         - 1 downto i*c_swc_prio_width),
      ob_pck_size_o            => ob_pck_size_o         ((i + 1)*c_swc_max_pck_size_width - 1 downto i*c_swc_max_pck_size_width),
      ob_transfer_data_ack_i   => ob_ack_i               (i),
      pti_transfer_data_valid_i=> pti_transfer_data_valid(i),
      pti_transfer_data_ack_o  => pti_transfer_data_ack  (i),
      pti_pageaddr_i           => pti_pageaddr           (i),
      pti_prio_i               => pti_prio               (i),
      pti_pck_size_i           => pti_pck_size           (i)
      
      );
  end generate gen_output;
  
end syn; -- arch