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



  -- multiplex mask from input to output
  multimux_out : process(sync_cntr,pto_output_mask,pto_pageaddr,pto_prio)
  begin 
  
     for i in 0 to c_swc_num_ports - 1 loop  
       pti_transfer_data_valid(i) <= pto_output_mask((sync_cntr + i) mod c_swc_num_ports)(i);
       pti_pageaddr           (i) <= pto_pageaddr   ((sync_cntr + i) mod c_swc_num_ports);
       pti_prio               (i) <= pto_prio       ((sync_cntr + i) mod c_swc_num_ports);
       pti_pck_size           (i) <= pto_pck_size   ((sync_cntr + i) mod c_swc_num_ports);
     end loop;
        
  end process;

      
  -- we get ack from output ports and translate it into masks' bits in input ports
  multidemux_in : process (clk_i, rst_n_i)
  begin
     if rising_edge(clk_i) then
       if(rst_n_i = '0') then
       
           for i in 0 to c_swc_num_ports -1 loop
               pto_read_mask(i) <= (others =>'0');  
           end loop;
       
       else


         for i in 0 to c_swc_num_ports-1 loop   
           
           if(i = 1) then
             pto_read_mask((sync_cntr_ack + i)  mod c_swc_num_ports)((i - 1))                            <= '0';  
           elsif(i > 1) then
             pto_read_mask((sync_cntr_ack + i)  mod c_swc_num_ports)((i - 1) downto 0)                   <= (others => '0');
           end if;
           
           pto_read_mask((sync_cntr_ack + i)  mod c_swc_num_ports)( i)                                   <= pti_transfer_data_ack(i);  
           
           if(i < c_swc_num_ports - 2) then
             pto_read_mask((sync_cntr_ack + i)  mod c_swc_num_ports)(c_swc_num_ports - 1 downto (i + 1)) <= (others => '0'); 
           elsif(i = c_swc_num_ports - 2) then
             pto_read_mask((sync_cntr_ack + i)  mod c_swc_num_ports)((i + 1))                            <=  '0';
           end if;
            
         end loop;
        
      end if;    
    end if;
         
   end process;  
   
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