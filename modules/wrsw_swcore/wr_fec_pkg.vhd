-------------------------------------------------------------------------------
-- Title      : Forward Error Correction
-- Project    : WhiteRabbit Node
-------------------------------------------------------------------------------
-- File       : wr_fec_pkg.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-Co-HT
-- Created    : 2011-04-01
-- Last update: 2011-07-27
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
--
-- Copyright (c) 2011 Maciej Lipinski / CERN
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
-- 2011-04-01  1.0      mlipinsk Created
-- 2011-07-27  1.1      mlipinsk added staff for the wb->wrf converter
-------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.CEIL;
use ieee.math_real.log2;

package wr_fec_pkg is
 
 
  constant c_FEC_ETH_TYPE : std_logic_vector(15 downto 0) := x"DEED";
 
  ----------------------------------------------------------
  -- WISHBONE
  ---------------------------------------------------------

  -- wisbone Slave (from Etherbone)
  constant wishbone_address_width_in	: integer := 2; -- actually there is no address
  constant wishbone_data_width_in		  : integer := 16;
  
  -- wishbone Master (or WRF source) 
  constant wishbone_address_width_out	: integer := 2;
  constant wishbone_data_width_out		  : integer := 16;

  constant c_WBP_STATUS : std_logic_vector(1 downto 0) := "11";
  constant c_WBP_DATA   : std_logic_vector(1 downto 0) := "00";
  constant c_WBP_OOB    : std_logic_vector(1 downto 0) := "01";
  constant c_WBP_FEC    : std_logic_vector(1 downto 0) := "10";


  constant c_FECIN_NO_DATA : std_logic_vector(2 downto 0) := "000";
  constant c_FECIN_HEADER  : std_logic_vector(2 downto 0) := "001";
  constant c_FECIN_PAYLOAD : std_logic_vector(2 downto 0) := "010";
  constant c_FECIN_PAUSE   : std_logic_vector(2 downto 0) := "011";
  constant c_FECIN_MSG_END : std_logic_vector(2 downto 0) := "100";
  constant c_FECIN_ABANDON : std_logic_vector(2 downto 0) := "111";
  
  constant c_WBP_STATUS_ERR_MASK : std_logic_vector(15 downto 0) := "0000000000000001";
  
  constant c_WBP_OOB_EMPTY     : std_logic_vector(1 downto 0) := "00";
  constant c_WBP_OOB_RECEIVING : std_logic_vector(1 downto 0) := "01";
  constant c_WBP_OOB_AVAILABLE : std_logic_vector(1 downto 0) := "10";
  
  constant c_WBP_STATUS_EMPTY  : std_logic_vector(1 downto 0) := "00";
  constant c_WBP_STATUS_RX_INF : std_logic_vector(1 downto 0) := "01";
  constant c_WBP_STATUS_RX_ERR : std_logic_vector(1 downto 0) := "10";
  
  constant c_VLAN_ETHERTYPE        : std_logic_vector(15 downto 0):=  x"8100";
  constant c_ETHERTYPE_ADDR_noVLAN : std_logic_vector(4 downto 0) :=  "01100";
  constant c_ETHERTYPE_ADDR_VLAN   : std_logic_vector(4 downto 0) :=  "10000";
  
  constant c_eth_header_size_untagged     : std_logic_vector(4 downto 0) :=  "01110"; -- 14 bytes
  constant c_eth_header_size_tagged       : std_logic_vector(4 downto 0) :=  "10010"; -- 18 bytes


  ----------------------- for the dummy frame generator
  constant c_eth_header_src_addr          : std_logic_vector(47 downto 0) :=  x"da0203040506"; 
  constant c_eth_header_dst_addr          : std_logic_vector(47 downto 0) :=  x"fedcba987654" ;
  constant c_fec_header_etherType         : std_logic_vector(15 downto 0) :=  x"ABCD"; -- internet protocol, 
  constant c_vlan_priority                : std_logic_vector(2  downto 0) :=  "000"; 
  constant c_vlan_identifier              : std_logic_vector(11 downto 0) :=  x"000"; 
  -- could be bigger then ethernet max payload
  constant c_fec_input_payload_max_size   : std_logic_vector(15 downto 0) :=  x"05DC"; -- 1500 bytes, 
  constant c_zeros                        : std_logic_vector(15 downto 0) :=  x"0000"; 

  -----------------------------------------------------------

  -- M parameter in Wesley's implementation
  -- of R-S coding, the nubmer of bytes to decode/
  -- encode in parallel. M Bytes constitute one
  -- symbol
  constant c_fec_RS_parallel_Bytes       : integer := 8;

  -- K parameter in Wesley's implementation of R-S,
  -- it says how many lost symbols can be recovered.
  -- In this implementation it is translated to the 
  -- number of packets (Ethernet frames) which 
  -- can be lost out of all the frames sent with single
  -- Control Message
  constant c_fec_RS_parity_MSGs          : integer := 2;
  
  -- size of the word encoded with hamming at one go
  constant c_fec_Hamming_word_size       : integer := 64;--496;

  -- Maximum size (in bytes) of control messages - so the
  -- single chunk of data which is encoded into several
  -- FECed and encoded with Hamming messages
  constant c_fec_MSG_size_MAX_Bytes       : integer := 1500;
  
  -- Width of the input/output stream to/from the *FEC engine*
  -- this can be different from the input/output of the 
  -- FEC module, it makes engine independant from
  -- the interface, in bits
  -- DON'T TRY 32 BITS !!!!!!
  constant c_fec_engine_data_width       : integer := 16; --32;--8;


  -- Width of the input/output stream to/from the *FEC module*
  -- this can be different from the input/output of the 
  -- FEC engine, it makes engine independant from
  -- the interface (bits)
  constant c_fec_if_data_width           : integer := 16;
  
  -- MAX number of the Ethernet Frames into which input 
  -- Control Message can be FECed. 
  -- (for the current implementation it should be either
  -- 4 or 8)
  constant c_fec_out_MSG_num_MAX            : integer := 4; -- DON'T CHANGE
  
  -- ethernet payload size (in Bytes) - max size a FECed message 
  -- (in theory) could have
  constant c_fec_payload_size_MAX_Bytes     : integer := 1500;

  -- the number of parity bits added by Hamming SEC-DED
  constant c_fec_Hpb                        : integer := 9;  
  
  -- The size of Ethernet header (in Bytes) 
  -- (OK, I know it's 14 or 18 bytes, but if the input is 32bits,
  -- then we write 20 bytes = 5x32bits for simplisity of implementation)
  constant c_fec_Ethernet_header_size_MAX_Bytes  : integer := 20;  
  
  -- how much time we allow for the FEC settings to by made, starting
  -- with the beginning of input transfer. this is expressed in bytes 
  -- and is limited to the size of the header (16 bytes)
  constant c_fec_settings_input_threshold   : integer :=10; -- bytes
-------------------------------------------------------------------------------
--             fec header
-------------------------------------------------------------------------------
 
  constant c_fec_FEC_header_size_bits            : integer := 64;  
  constant c_fec_FEC_header_Scheme_bits          : integer := 4;  
  constant c_fec_FEC_header_FRAME_ID_bits        : integer := 4;
  constant c_fec_FEC_header_FEC_ID_bits          : integer := 16;  
  constant c_fec_FEC_header_etherType_bits       : integer := 16;  
  constant c_fec_FEC_original_len_bits           : integer := 13;
  constant c_fec_FEC_fragment_len_bits           : integer := 11;
  
  -- value to init auto-incrementing FEC_ID
  constant c_fec_FEC_ID_init : std_logic_vector(c_fec_FEC_header_FEC_ID_bits -1  downto 0) :=  x"AB00"; 
-------------------------------------------------------------------------------
--             PARAMETERS CALCULATED FROM THE ABOVE PARAMETERS
-------------------------------------------------------------------------------

  constant c_fec_Ethernet_header_ram_size  : integer :=
integer(real((c_fec_Ethernet_header_size_MAX_Bytes*8)/c_fec_engine_data_width));
  -- (20*8)/16 = 10
  
  constant c_fec_Ethernet_header_ram_addr_width  : integer :=
integer(CEIL(LOG2(real(c_fec_Ethernet_header_ram_size-1))));

  
  -- number of Bytes in the in/out data, 
  constant c_fec_engine_Byte_sel_num : integer := integer(real(c_fec_engine_data_width/8));

  constant c_fec_engine_data_width_Bytes : integer := c_fec_engine_data_width/8;--8;

  constant c_fec_Ethernet_header_size_MAX_bits:integer := (c_fec_Ethernet_header_size_MAX_Bytes*8); 
 
  constant c_fec_payload_size_MAX_bits   : integer := (c_fec_payload_size_MAX_Bytes * 8); 
  
  
  constant c_fec_MSG_size_MAX_bits       : integer := (c_fec_MSG_size_MAX_Bytes * 8); 

  -- width of the variable stating total size of message (Control Message)
  -- to be encoded
  constant c_fec_msg_size_MAX_bits_width : integer := integer(CEIL(LOG2(real(c_fec_MSG_size_MAX_bits-1))));

  -- basically, size of all the pointes to the msg_buffer
  constant c_fec_msg_size_MAX_Bytes_width : integer:=integer(CEIL(LOG2(real(c_fec_MSG_size_MAX_Bytes-1))));

  -- width of the max number of output Ethernet Frames input Param.
  constant c_fec_out_MSG_num_MAX_width : integer := integer(CEIL(LOG2(real(c_fec_out_MSG_num_MAX+1))));

  
  constant c_fec_Ethernet_header_size_MAX_Bytes_width :
                         integer:=integer(CEIL(LOG2(real(c_fec_Ethernet_header_size_MAX_Bytes+1))));

  constant c_fec_Ethernet_header_size_MAX_bits_width :integer:=16;
  -- integer:=integer(CEIL(LOG2(real(c_fec_Ethernet_header_size_MAX_bits+1))));

  
  -- width of the reg storing FECed message size
  constant c_fec_payload_size_MAX_bits_width : integer := integer(CEIL(LOG2(real(c_fec_payload_size_MAX_bits-1))));
  constant c_fec_payload_size_MAX_Bytes_width : integer := integer(CEIL(LOG2(real(c_fec_payload_size_MAX_Bytes-1))));
  
  -- width of the pointer to register storing Ethernet Header 
  constant c_fec_header_size_bits_width : integer := integer(CEIL(LOG2(real(c_fec_payload_size_MAX_bits-1))));
  
  -- the max size of the data feed into Hamming SEC-DED to get parity bits
  constant c_fec_Hamming_input_size     : integer := integer((2**c_fec_Hpb) - (c_fec_Hpb + 1));
  
  -- the siz of the message encoded with hamming (including parity bits)
  constant c_fec_Hamming_output_size     : integer := integer((2**c_fec_Hpb) - 1);

  constant c_fec_Hamming_wait_cycles     : integer := 1;


  constant c_min_fec_size                 : integer := 30; --bytes  ??
  
  constant c_oob_max_size                 : integer := 10;
  
  constant c_oob_max_size_width           : integer := integer((CEIL(LOG2(real(c_oob_max_size-1)))));
  
  ------------------------------------------------------------------------------
  --             types and other staff
  ------------------------------------------------------------------------------
  
  constant c_fec_ram_data_width   : integer := c_fec_Hamming_word_size; --64

  constant c_fec_ram_size   : integer :=
(c_fec_MSG_size_MAX_bits*c_fec_out_MSG_num_MAX) / c_fec_Hamming_word_size + 3;-- + 3000;--a bug here  
 -- ((1500 * 8) * 4) / 64 +3
  constant c_fec_ram_addr_width   : integer := 
                         integer(CEIL(LOG2(real(c_fec_ram_size-1))));

  
  -------------------------------------------------------------------------------
  --             types and other staff
  -------------------------------------------------------------------------------
  
  -- this is a pointer to the msg_buffer, 
  subtype t_buffer_pointer is std_logic_vector(c_fec_MSG_size_MAX_bits-1 downto 0);
  
  -- used for fec  
  
  type t_fec_parity_buffer_array is array (c_fec_RS_parity_MSGs        - 1 downto 0) of   
                          std_logic_vector(c_fec_payload_size_MAX_bits - 1 downto 0);

  -- array of above pointers
  type t_buffer_array is array (c_fec_out_MSG_num_MAX-1 downto 0) of t_buffer_pointer;
  
  component wr_fec_en_interface is
    port (
       clk_i   : in std_logic;
       rst_n_i : in std_logic;
      
      ---------------------------------------------------------------------------------------
      -- talk with outside word
      ---------------------------------------------------------------------------------------
      -- 32 bits wide wishbone slave RX input
       wbs_dat_i	  : in  std_logic_vector(wishbone_data_width_in-1 downto 0);
       wbs_adr_i	  : in  std_logic_vector(wishbone_address_width_in-1 downto 0);
       wbs_sel_i	  : in  std_logic_vector((wishbone_data_width_in/8)-1 downto 0);
       wbs_cyc_i	  : in  std_logic;
       wbs_stb_i	  : in  std_logic;
       wbs_we_i	   : in  std_logic;
       wbs_err_o	  : out std_logic;
       wbs_stall_o	: out std_logic;
       wbs_ack_o	  : out std_logic;
     
       -- 32 bits wide wishbone Master TX input
       
       wbm_dat_o 	: out std_logic_vector(wishbone_data_width_out-1 downto 0);
       wbm_adr_o	 : out std_logic_vector(wishbone_address_width_out-1 downto 0);
       wbm_sel_o	 : out std_logic_vector((wishbone_data_width_out/8)-1 downto 0);
       wbm_cyc_o	 : out std_logic;
       wbm_stb_o	 : out std_logic;
       wbm_we_o	  : out std_logic;
       wbm_err_i	 : in std_logic;
       wbm_stall_i: in  std_logic;
       wbm_ack_i	 : in  std_logic; 
 
       
       ---------------------------------------------------------------------------------------
       -- talk with FEC ENGINE
       ---------------------------------------------------------------------------------------
      
       -- input data to be encoded
       if_data_o         : out  std_logic_vector(c_fec_engine_data_width  - 1 downto 0);
       
       -- input data byte sel
       if_byte_sel_o     : out std_logic_vector(c_fec_engine_Byte_sel_num  - 1 downto 0);       
       
       -- encoded data
       if_data_i         : in std_logic_vector(c_fec_engine_data_width  - 1 downto 0);
       
       -- indicates which Bytes of the output data have valid data
       if_byte_sel_i     : in std_logic_vector(c_fec_engine_Byte_sel_num  - 1 downto 0);
       
       -- size of the incoming message to be encoded (entire Control Message)
       if_msg_size_o     : out  std_logic_vector(c_fec_msg_size_MAX_Bytes_width     - 1 downto 0);
       
       
       -- tells FEC whether use FEC_ID provided from outside word (HIGH)
       -- or generate it internally (LOW)
       if_FEC_ID_ena_o   : out std_logic;
       
       -- ID of the message to be FECed, used only if if_FEC_ID_ena_i=HIGH
       if_FEC_ID_o       : out  std_logic_vector(c_fec_FEC_header_FEC_ID_bits     - 1 downto 0);
       -- information what the engine is supposed to do:
       -- 0 = do nothing
       -- 1 = header is being transfered
       -- 2 = payload to be encoded is being transfered
       -- 3 = transfer pause
       -- 4 = message end
       -- 5 = abandond FECing
       if_in_ctrl_o         : out  std_logic_vector(2 downto 0);
  
       -- strobe when settings (msg size and output msg number) available
       if_in_settngs_ena_o  : out std_logic;
            
       -- it provides to the FEC engine original etherType, which should be 
       -- added to the FEC header, the interface remembers the original etherType 
       -- and sends to the FEC engine the frame header with already replaced 
       -- etherType (FEC etherType).
       -- this output is assumed to be valid on the finish of header trasmission
       -- so starting with the first word of the PAYLOAD
       if_in_etherType_o : out std_logic_vector(15 downto 0);            
            
       -- Input error indicator, :
       -- 0 = ready for data
       -- 1 = no frame size provided...
       if_in_ctrl_i         : in std_logic;
  
       -- indicates whether engine is ready to encode new Control Message
       -- 0 = idle
       -- 1 = busy
       if_busy_i         : in std_logic;
  
       -- info about output data
       -- 0 = no data ready
       -- 1 = outputing header 
       -- 2 = outputing payload
       -- 3 = output pause 
       --if_out_ctrl_o         : out  std_logic_vector(1 downto 0);
       
       -- 0 = data not available
       -- 1 data valid
       if_out_ctrl_i         : in  std_logic;
       
       -- is like cyc in WB, high thourhout single frame sending
       if_out_frame_cyc_i    : in std_logic;
       
       -- frame start (needs to be used with if_out_ctrl_o)
       if_out_start_frame_i  : in std_logic;        
       
       -- last (half)word of the frame
       if_out_end_of_frame_i : in std_logic;
       
       -- the end of the last frame
       if_out_end_of_fec_i   : in std_logic;
       
       -- indicates whether output interface is ready to take data
       -- 0 = ready
       -- 1 = busy     
       if_out_ctrl_o         : out  std_logic;
       
       -- '1' => VLAN-taged frame
       -- '0' => untagged frame
       -- vlan_taggged_frame_o  : out std_logic;       
       
       -- info on desired number of output messages, should be available 
       -- at the same time as
       if_out_MSG_num_o  : out  std_logic_vector(c_fec_out_MSG_num_MAX_width - 1 downto 0)      
  
    );
  end component;  

  component wr_fec_en_engine is
  port (
     clk_i   : in std_logic;
     rst_n_i : in std_logic;
    
     -- input data to be encoded
     if_data_in         : in  std_logic_vector(c_fec_engine_data_width  - 1 downto 0);
     
     -- input data byte sel
     if_byte_sel_i     : in std_logic_vector(c_fec_engine_Byte_sel_num  - 1 downto 0);     
     
     -- encoded data
     if_data_o         : out std_logic_vector(c_fec_engine_data_width  - 1 downto 0);
     
     -- indicates which Bytes of the output data have valid data
     if_byte_sel_o     : out std_logic_vector(c_fec_engine_Byte_sel_num  - 1 downto 0);
     
     -- size of the incoming message to be encoded (entire Control Message)
     if_msg_size_i     : in  std_logic_vector(c_fec_msg_size_MAX_Bytes_width     - 1 downto 0);
     
     
     -- tells FEC whether use FEC_ID provided from outside word (HIGH)
     -- or generate it internally (LOW)
     if_FEC_ID_ena_i   : in std_logic;
     
     -- ID of the message to be FECed, used only if if_FEC_ID_ena_i=HIGH
     if_FEC_ID_i       : in  std_logic_vector(c_fec_FEC_header_FEC_ID_bits     - 1 downto 0);
     -- information what the engine is supposed to do:
     -- 0 = do nothing
     -- 1 = header is being transfered
     -- 2 = payload to be encoded is being transfered
     -- 3 = transfer pause
     -- 4 = message end
     -- 5 = abandond FECing
     if_in_ctrl_i         : in  std_logic_vector(2 downto 0);

     -- strobe when settings (msg size and output msg number) available
     if_in_settngs_ena_i  : in std_logic;
          
     -- it provides to the FEC engine original etherType, which should be 
     -- added to the FEC header, the interface remembers the original etherType 
     -- and sends to the FEC engine the frame header with already replaced 
     -- etherType (FEC etherType).
     -- this output is assumed to be valid on the finish of header trasmission
     -- so starting with the first word of the PAYLOAD
     if_in_etherType_i : in std_logic_vector(15 downto 0);           
          
     -- Input error indicator, :
     -- 0 = ready for data
     -- 1 = no frame size provided...
     if_in_ctrl_o         : out std_logic;

     -- indicates whether engine is ready to encode new Control Message
     -- 0 = idle
     -- 1 = busy
     if_busy_o         : out std_logic;

     -- info about output data
     -- 0 = no data ready
     -- 1 = outputing header 
     -- 2 = outputing payload
     -- 3 = output pause 
     --if_out_ctrl_o         : out  std_logic_vector(1 downto 0);
     
     -- 0 = data not available
     -- 1 data valid
     if_out_ctrl_o         : out  std_logic;
     
     -- is like cyc in WB, high thourhout single frame sending
     if_out_frame_cyc_o    : out std_logic;
     
     -- frame start (needs to be used with if_out_ctrl_o)
     if_out_start_frame_o  : out std_logic;     
     
     -- last (half)word of the frame
     if_out_end_of_frame_o : out std_logic;
     
     -- the end of the last frame
     if_out_end_of_fec_o   : out std_logic;
     
     -- indicates whether output interface is ready to take data
     -- 0 = ready
     -- 1 = busy     
     if_out_ctrl_i         : in  std_logic;
     
     -- '1' => VLAN-taged frame
     -- '0' => untagged frame
     --vlan_taggged_frame_i  : in std_logic;
          
     -- info on desired number of output messages, should be available 
     -- at the same time as
     if_out_MSG_num_i  : in  std_logic_vector(c_fec_out_MSG_num_MAX_width - 1 downto 0)     

  );
end component;


component wr_fec_de_interface is
  port (
     clk_i   : in std_logic;
     rst_n_i : in std_logic;
    
    ---------------------------------------------------------------------------------------
    -- talk with outside word
    ---------------------------------------------------------------------------------------
    -- 32 bits wide wishbone slave RX input
     wbs_dat_i	  : in  std_logic_vector(wishbone_data_width_in-1 downto 0);
     wbs_adr_i	  : in  std_logic_vector(wishbone_address_width_in-1 downto 0);
     wbs_sel_i	  : in  std_logic_vector((wishbone_data_width_in/8)-1 downto 0);
     wbs_cyc_i	  : in  std_logic;
     wbs_stb_i	  : in  std_logic;
     wbs_we_i	   : in  std_logic;
     wbs_err_o	  : out std_logic;
     wbs_stall_o	: out std_logic;
     wbs_ack_o	  : out std_logic;
   
     -- 32 bits wide wishbone Master TX input
     
     wbm_dat_o 	: out std_logic_vector(wishbone_data_width_out-1 downto 0);
     wbm_adr_o	 : out std_logic_vector(wishbone_address_width_out-1 downto 0);
     wbm_sel_o	 : out std_logic_vector((wishbone_data_width_out/8)-1 downto 0);
     wbm_cyc_o	 : out std_logic;
     wbm_stb_o	 : out std_logic;
     wbm_we_o	  : out std_logic;
     wbm_err_i	 : in std_logic;
     wbm_stall_i: in  std_logic;
     wbm_ack_i	 : in  std_logic; 

     
     ---------------------------------------------------------------------------------------
     -- talk with FEC ENGINE
     ---------------------------------------------------------------------------------------
    
     -- input data to be encoded
     if_data_o         : out  std_logic_vector(c_fec_engine_data_width  - 1 downto 0);
     
     -- input data byte sel
     if_byte_sel_o     : out std_logic_vector(c_fec_engine_Byte_sel_num  - 1 downto 0);       
     
     -- encoded data
     if_data_i         : in std_logic_vector(c_fec_engine_data_width  - 1 downto 0);
     
     -- indicates which Bytes of the output data have valid data
     if_byte_sel_i     : in std_logic_vector(c_fec_engine_Byte_sel_num  - 1 downto 0);
     
     -- size of the incoming message to be encoded (entire Control Message)
     if_msg_size_o     : out  std_logic_vector(c_fec_msg_size_MAX_Bytes_width     - 1 downto 0);
     
     
     -- tells FEC whether use FEC_ID provided from outside word (HIGH)
     -- or generate it internally (LOW)
     if_FEC_ID_ena_o   : out std_logic;
     
     -- ID of the message to be FECed, used only if if_FEC_ID_ena_i=HIGH
     if_FEC_ID_o       : out  std_logic_vector(c_fec_FEC_header_FEC_ID_bits     - 1 downto 0);
     -- information what the engine is supposed to do:
     -- 0 = do nothing
     -- 1 = header is being transfered
     -- 2 = payload to be encoded is being transfered
     -- 3 = transfer pause
     -- 4 = message end
     -- 5 = abandond FECing
     if_in_ctrl_o         : out  std_logic_vector(2 downto 0);

     -- strobe when settings (msg size and output msg number) available
     if_in_settngs_ena_o  : out std_logic;
          
     -- it provides to the FEC engine original etherType, which should be 
     -- added to the FEC header, the interface remembers the original etherType 
     -- and sends to the FEC engine the frame header with already replaced 
     -- etherType (FEC etherType).
     -- this output is assumed to be valid on the finish of header trasmission
     -- so starting with the first word of the PAYLOAD
     if_in_etherType_o : out std_logic_vector(15 downto 0);            
          
     -- Input error indicator, :
     -- 0 = ready for data
     -- 1 = no frame size provided...
     if_in_ctrl_i         : in std_logic;

     -- indicates whether engine is ready to encode new Control Message
     -- 0 = idle
     -- 1 = busy
     if_busy_i         : in std_logic;

     -- info about output data
     -- 0 = no data ready
     -- 1 = outputing header 
     -- 2 = outputing payload
     -- 3 = output pause 
     --if_out_ctrl_o         : out  std_logic_vector(1 downto 0);
     
     -- 0 = data not available
     -- 1 data valid
     if_out_ctrl_i         : in  std_logic;
     
     -- is like cyc in WB, high thourhout single frame sending
     if_out_frame_cyc_i    : in std_logic;
     
     -- frame start (needs to be used with if_out_ctrl_o)
     if_out_start_frame_i  : in std_logic;        
     
     -- last (half)word of the frame
     if_out_end_of_frame_i : in std_logic;
     
     -- the end of the last frame
     if_out_end_of_fec_i   : in std_logic;
     
     -- indicates whether output interface is ready to take data
     -- 0 = ready
     -- 1 = busy     
     if_out_ctrl_o         : out  std_logic;
     
     -- '1' => VLAN-taged frame
     -- '0' => untagged frame
     -- vlan_taggged_frame_o  : out std_logic;       
     
     -- info on desired number of output messages, should be available 
     -- at the same time as
     if_out_MSG_num_o  : out  std_logic_vector(c_fec_out_MSG_num_MAX_width - 1 downto 0)      

  );
end component;  

component wr_fec_de_engine is
port (
   clk_i   : in std_logic;
   rst_n_i : in std_logic;
  
   -- input data to be encoded
   if_data_in         : in  std_logic_vector(c_fec_engine_data_width  - 1 downto 0);
   
   -- input data byte sel
   if_byte_sel_i     : in std_logic_vector(c_fec_engine_Byte_sel_num  - 1 downto 0);     
   
   -- encoded data
   if_data_o         : out std_logic_vector(c_fec_engine_data_width  - 1 downto 0);
   
   -- indicates which Bytes of the output data have valid data
   if_byte_sel_o     : out std_logic_vector(c_fec_engine_Byte_sel_num  - 1 downto 0);
   
   -- size of the incoming message to be encoded (entire Control Message)
   if_msg_size_i     : in  std_logic_vector(c_fec_msg_size_MAX_Bytes_width     - 1 downto 0);
   
   
   -- tells FEC whether use FEC_ID provided from outside word (HIGH)
   -- or generate it internally (LOW)
   if_FEC_ID_ena_i   : in std_logic;
   
   -- ID of the message to be FECed, used only if if_FEC_ID_ena_i=HIGH
   if_FEC_ID_i       : in  std_logic_vector(c_fec_FEC_header_FEC_ID_bits     - 1 downto 0);
   -- information what the engine is supposed to do:
   -- 0 = do nothing
   -- 1 = header is being transfered
   -- 2 = payload to be encoded is being transfered
   -- 3 = transfer pause
   -- 4 = message end
   -- 5 = abandond FECing
   if_in_ctrl_i         : in  std_logic_vector(2 downto 0);

   -- strobe when settings (msg size and output msg number) available
   if_in_settngs_ena_i  : in std_logic;
        
   -- it provides to the FEC engine original etherType, which should be 
   -- added to the FEC header, the interface remembers the original etherType 
   -- and sends to the FEC engine the frame header with already replaced 
   -- etherType (FEC etherType).
   -- this output is assumed to be valid on the finish of header trasmission
   -- so starting with the first word of the PAYLOAD
   if_in_etherType_i : in std_logic_vector(15 downto 0);           
        
   -- Input error indicator, :
   -- 0 = ready for data
   -- 1 = no frame size provided...
   if_in_ctrl_o         : out std_logic;

   -- indicates whether engine is ready to encode new Control Message
   -- 0 = idle
   -- 1 = busy
   if_busy_o         : out std_logic;

   -- info about output data
   -- 0 = no data ready
   -- 1 = outputing header 
   -- 2 = outputing payload
   -- 3 = output pause 
   --if_out_ctrl_o         : out  std_logic_vector(1 downto 0);
   
   -- 0 = data not available
   -- 1 data valid
   if_out_ctrl_o         : out  std_logic;
   
   -- is like cyc in WB, high thourhout single frame sending
   if_out_frame_cyc_o    : out std_logic;
   
   -- frame start (needs to be used with if_out_ctrl_o)
   if_out_start_frame_o  : out std_logic;     
   
   -- last (half)word of the frame
   if_out_end_of_frame_o : out std_logic;
   
   -- the end of the last frame
   if_out_end_of_fec_o   : out std_logic;
   
   -- indicates whether output interface is ready to take data
   -- 0 = ready
   -- 1 = busy     
   if_out_ctrl_i         : in  std_logic;
   
   -- '1' => VLAN-taged frame
   -- '0' => untagged frame
   --vlan_taggged_frame_i  : in std_logic;
        
   -- info on desired number of output messages, should be available 
   -- at the same time as
   if_out_MSG_num_i  : in  std_logic_vector(c_fec_out_MSG_num_MAX_width - 1 downto 0)     

);
end component;

component wr_fec_dummy_pck_gen_if is
  port (
    rst_n_i                                  : in     std_logic;
    wb_clk_i                                 : in     std_logic;
    wb_addr_i                                : in     std_logic_vector(2 downto 0);
    wb_data_i                                : in     std_logic_vector(31 downto 0);
    wb_data_o                                : out    std_logic_vector(31 downto 0);
    wb_cyc_i                                 : in     std_logic;
    wb_sel_i                                 : in     std_logic_vector(3 downto 0);
    wb_stb_i                                 : in     std_logic;
    wb_we_i                                  : in     std_logic;
    wb_ack_o                                 : out    std_logic;
    clk_i                                    : in     std_logic;
-- Port for std_logic_vector field: 'Payload Value' in reg: 'Dummy paylaod size (bytes)'
    wr_fec_dummy_pck_gen_payload_size_o      : out    std_logic_vector(15 downto 0);
-- Port for std_logic_vector field: 'Increment Value' in reg: 'Paylaod increment step size (bytes)'
    wr_fec_dummy_pck_gen_increment_size_o    : out    std_logic_vector(7 downto 0);
-- Port for std_logic_vector field: 'Generate Number Value' in reg: 'Number of frames to be generated'
    wr_fec_dummy_pck_gen_gen_frame_number_o  : out    std_logic_vector(15 downto 0);
-- Port for BIT field: 'Start generation' in reg: 'Control register'
    wr_fec_dummy_pck_gen_ctrl_start_o        : out    std_logic;
-- Port for BIT field: 'Stop generation' in reg: 'Control register'
    wr_fec_dummy_pck_gen_ctrl_stop_o         : out    std_logic;
-- Port for BIT field: 'Enable FEC' in reg: 'Control register'
    wr_fec_dummy_pck_gen_ctrl_fec_o          : out    std_logic;
-- Port for BIT field: 'Continuous mode' in reg: 'Control register'
    wr_fec_dummy_pck_gen_ctrl_continuous_o   : out    std_logic;
-- Port for BIT field: 'VLAN-tagging enable' in reg: 'Control register'
    wr_fec_dummy_pck_gen_ctrl_vlan_o         : out    std_logic;
-- Port for std_logic_vector field: 'Status Register Value' in reg: 'Status register'
    wr_fec_dummy_pck_gen_status_i            : in     std_logic_vector(15 downto 0)
  );
end component;

component wr_fec_en is
  port (
     clk_i   : in std_logic;
     rst_n_i : in std_logic;
    
     ---------------------------------------------------------------------------------------
     -- talk with outside word
     ---------------------------------------------------------------------------------------
     -- 32 bits wide wishbone slave RX input
     wbs_dat_i	 : in  std_logic_vector(wishbone_data_width_in-1 downto 0);
     wbs_adr_i	 : in  std_logic_vector(wishbone_address_width_in-1 downto 0);
     wbs_sel_i	 : in  std_logic_vector((wishbone_data_width_in/8)-1 downto 0);
     wbs_cyc_i	 : in  std_logic;
     wbs_stb_i	 : in  std_logic;
     wbs_we_i	  : in  std_logic;
     wbs_err_o	 : out std_logic;
     wbs_stall_o: out std_logic;
     wbs_ack_o	 : out std_logic;
    
     -- 32 bits wide wishbone Master TX input
      
     wbm_dat_o 	: out std_logic_vector(wishbone_data_width_out-1 downto 0);
     wbm_adr_o	 : out std_logic_vector(wishbone_address_width_out-1 downto 0);
     wbm_sel_o	 : out std_logic_vector((wishbone_data_width_out/8)-1 downto 0);
     wbm_cyc_o	 : out std_logic;
     wbm_stb_o	 : out std_logic;
     wbm_we_o	  : out std_logic;
     wbm_err_i	 : in std_logic;
     wbm_stall_i: in  std_logic;
     wbm_ack_i	 : in  std_logic
  );
end component;


component wr_fec_dummy_pck_gen is
  port (
     clk_i   : in std_logic;
     rst_n_i : in std_logic;
    
     ---------------------------------------------------------------------------------------
     -- talk with outside word
     ---------------------------------------------------------------------------------------

    
     -- 32 bits wide wishbone Master TX input
      
     wbm_dat_o 	: out std_logic_vector(wishbone_data_width_out-1 downto 0);
     wbm_adr_o	 : out std_logic_vector(wishbone_address_width_out-1 downto 0);
     wbm_sel_o	 : out std_logic_vector((wishbone_data_width_in/8)-1 downto 0);
     wbm_cyc_o	 : out std_logic;
     wbm_stb_o	 : out std_logic;
     wbm_we_o	  : out std_logic;
     wbm_err_i	 : in std_logic;
     wbm_stall_i: in  std_logic;
     wbm_ack_i	 : in  std_logic; 
     
     ---------------------------------------------------------------------------------------
     -- ctrl_regs -> to be controlled by WB
     ---------------------------------------------------------------------------------------
     
       wb_clk_i                                 : in     std_logic;
       wb_addr_i                                : in     std_logic_vector(2 downto 0);
       wb_data_i                                : in     std_logic_vector(31 downto 0);
       wb_data_o                                : out    std_logic_vector(31 downto 0);
       wb_cyc_i                                 : in     std_logic;
       wb_sel_i                                 : in     std_logic_vector(3 downto 0);
       wb_stb_i                                 : in     std_logic;
       wb_we_i                                  : in     std_logic;
       wb_ack_o                                 : out    std_logic
       );
end component; 

component wr_fec_and_gen is
  port (
     clk_i   : in std_logic;
     rst_n_i : in std_logic;
    
     ---------------------------------------------------------------------------------------
     -- talk with outside word
     ---------------------------------------------------------------------------------------
     -- 32 bits wide wishbone Master TX input
      
     wbm_dat_o 	: out std_logic_vector(wishbone_data_width_out-1 downto 0);
     wbm_adr_o	 : out std_logic_vector(wishbone_address_width_out-1 downto 0);
     wbm_sel_o	 : out std_logic_vector((wishbone_data_width_out/8)-1 downto 0);
     wbm_cyc_o	 : out std_logic;
     wbm_stb_o	 : out std_logic;
     wbm_we_o	  : out std_logic;
     wbm_err_i	 : in std_logic;
     wbm_stall_i: in  std_logic;
     wbm_ack_i	 : in  std_logic;
     
     -- control generator
     wb_clk_i   : in     std_logic;
     wb_addr_i  : in     std_logic_vector(2 downto 0);
     wb_data_i  : in     std_logic_vector(31 downto 0);
     wb_data_o  : out    std_logic_vector(31 downto 0);
     wb_cyc_i   : in     std_logic;
     wb_sel_i   : in     std_logic_vector(3 downto 0);
     wb_stb_i   : in     std_logic;
     wb_we_i    : in     std_logic;
     wb_ack_o   : out    std_logic     
  );
end component;

component wr_fec_and_gen_with_wrf is
  port (
     clk_i   : in std_logic;
     rst_n_i : in std_logic;
    
     ---------------------------------------------------------------------------------------
     -- talk with outside word
     ---------------------------------------------------------------------------------------
     -- 32 bits wide WRF sink TX input
      
     -- WRF sink
     src_data_o     : out std_logic_vector(15 downto 0);
     src_ctrl_o     : out std_logic_vector(3 downto 0);
     src_bytesel_o  : out std_logic;
     src_dreq_i     : in  std_logic;
     src_valid_o    : out std_logic;
     src_sof_p1_o   : out std_logic;
     src_eof_p1_o   : out std_logic;
     src_error_p1_i : in  std_logic;
     src_abort_p1_o : out std_logic;      
      
           -- control generator
     wb_clk_i   : in     std_logic;
     wb_addr_i  : in     std_logic_vector(2 downto 0);
     wb_data_i  : in     std_logic_vector(31 downto 0);
     wb_data_o  : out    std_logic_vector(31 downto 0);
     wb_cyc_i   : in     std_logic;
     wb_sel_i   : in     std_logic_vector(3 downto 0);
     wb_stb_i   : in     std_logic;
     wb_we_i    : in     std_logic;
     wb_ack_o   : out    std_logic     
  );
end component;

constant c_WRF_STATUS : std_logic_vector(1 downto 0) := "11";
constant c_WRF_DATA   : std_logic_vector(1 downto 0) := "00";
constant c_WRF_OOB    : std_logic_vector(1 downto 0) := "01";

-- Size of fabric control bus
  constant c_wrsw_ctrl_size : integer := 4;
  
-- empty control field (such as empty source MAC address) left by the sender to
-- be filled by the endpoint.
constant c_wrsw_ctrl_none : std_logic_vector(c_wrsw_ctrl_size - 1 downto 0) := x"0";
  
constant c_wrsw_ctrl_dst_mac   : std_logic_vector(c_wrsw_ctrl_size - 1 downto 0) := x"1";
constant c_wrsw_ctrl_src_mac   : std_logic_vector(c_wrsw_ctrl_size - 1 downto 0) := x"2";
constant c_wrsw_ctrl_ethertype : std_logic_vector(c_wrsw_ctrl_size - 1 downto 0) := x"3";
constant c_wrsw_ctrl_vid_prio  : std_logic_vector(c_wrsw_ctrl_size - 1 downto 0) := x"4";
constant c_wrsw_ctrl_tx_oob    : std_logic_vector(c_wrsw_ctrl_size - 1 downto 0) := x"5";
constant c_wrsw_ctrl_rx_oob    : std_logic_vector(c_wrsw_ctrl_size - 1 downto 0) := x"6";
constant c_wrsw_ctrl_payload   : std_logic_vector(c_wrsw_ctrl_size - 1 downto 0) := x"7";
constant c_wrsw_ctrl_fcs       : std_logic_vector(c_wrsw_ctrl_size - 1 downto 0) := x"8";
  
  type t_wrf_status_reg is record
    is_hp       : std_logic;
    has_smac    : std_logic;
    has_crc     : std_logic;
    rx_error    : std_logic;
    match_class : std_logic_vector(7 downto 0);
  end record;    
  function f_unmarshall_wrf_status(stat : std_logic_vector) return t_wrf_status_reg;   
    
component wr_fec_wb_to_wrf is
port(
  clk_sys_i : in std_logic;
  rst_n_i   : in std_logic;

-- WRF sink
  src_data_o     : out std_logic_vector(15 downto 0);
  src_ctrl_o     : out std_logic_vector(3 downto 0);
  src_bytesel_o  : out std_logic;
  src_dreq_i     : in  std_logic;
  src_valid_o    : out std_logic;
  src_sof_p1_o   : out std_logic;
  src_eof_p1_o   : out std_logic;
  src_error_p1_i : in  std_logic;
  src_abort_p1_o : out std_logic;

-- Pipelined Wishbone slave
  wb_dat_i   : in  std_logic_vector(15 downto 0);
  wb_adr_i   : in  std_logic_vector(1 downto 0);
  wb_sel_i   : in  std_logic_vector(1 downto 0);
  wb_cyc_i   : in  std_logic;
  wb_stb_i   : in  std_logic;
  wb_we_i    : in  std_logic;
  wb_stall_o : out std_logic;
  wb_ack_o   : out std_logic;
  wb_err_o   : out std_logic;
  wb_rty_o   : out std_logic

  );

end component;



end wr_fec_pkg;  
-------------------------------------------------------------------------------

package body wr_fec_pkg is

  function f_marshall_wrf_status(stat : t_wrf_status_reg)
    return std_logic_vector is
    variable tmp : std_logic_vector(15 downto 0);
  begin
    tmp(0)           := stat.is_hp;
    tmp(1)           := stat.rx_error;
    tmp(2)           := stat.has_smac;
    tmp(15 downto 8) := stat.match_class;
    return tmp;
  end function;

  function f_unmarshall_wrf_status(stat : std_logic_vector) return t_wrf_status_reg is
    variable tmp : t_wrf_status_reg;
  begin
    tmp.is_hp       := stat(0);
    tmp.rx_error    := stat(1);
    tmp.has_smac    := stat(2);
    tmp.match_class := stat(15 downto 8);
    return tmp;
    
  end function;
    
end wr_fec_pkg;

-------------------------------------------------------------------------------