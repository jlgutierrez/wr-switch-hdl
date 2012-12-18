-------------------------------------------------------------------------------
-- Title      : Topology Resolution Unit: package
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : wrsw_tru_pkg.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-CO-HT
-- Created    : 2012-08-28
-- Last update: 2012-09-13
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: Package with records, function, constants and components
-- declarations for TRU module
--
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -
-- 
-- 
-- 
-- 
-------------------------------------------------------------------------------
--
-- Copyright (c) 2012 Maciej Lipinski / CERN
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
-- 2012-08-28  1.0      mlipinsk Created
-- 2012-09-03  1.0      mlipinsk changed pattern stuff
-------------------------------------------------------------------------------
library ieee;
use ieee.STD_LOGIC_1164.all;

library work;
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.CEIL;
use ieee.math_real.log2;
use work.wrsw_shared_types_pkg.all; -- need this for:
                                    -- * t_rtu_request
use work.rtu_private_pkg.all;       -- we need it for RTU's datatypes (records):
                                    -- * c_RTU_MAX_PORTS
                                    -- * c_wrsw_fid_width
use work.tru_wbgen2_pkg.all;       -- for wbgen-erated records
use work.wishbone_pkg.all;         -- wishbone_{interface_mode,address_granularity}
package wrsw_tru_pkg is

 -- constant c_RTU_MAX_PORTS           : integer                           := 24;
 -- constant c_wrsw_fid_width          : integer                           := 8;
 constant c_wrsw_pclass_number         : integer :=8;
 constant c_wrsw_pause_delay_width     : integer :=16;
 constant c_wrsw_max_queue_number      : integer :=8;
 constant c_tru_pattern_mode_width     : integer :=4;
  -------------------------- main input/output data ----------------------------------------

  type t_trans2ep is record
    pauseSend             : std_logic;
    pauseTime             : std_logic_vector(c_wrsw_pause_delay_width-1 downto 0);
    outQueueBlockMask     : std_logic_vector(c_wrsw_max_queue_number-1 downto 0);
  end record;
  
  type t_tru2ep is record
--     ctrlWr                : std_logic;
    --frmae generation
--     tx_pck                : std_logic;                    -- to be changed
--     tx_pck_class          : std_logic_vector(7 downto 0); -- to be changed
    -- pause generation
--     pauseSend             : std_logic;
--     pauseTime             : std_logic_vector(15 downto 0);
    outQueueBlockMask     : std_logic_vector(7 downto 0);
    -- new stuff
    link_kill             : std_logic;                      --ok
    fc_pause_req          : std_logic;                      --ok
    fc_pause_delay        : std_logic_vector(15 downto 0);  --ok
    inject_req            : std_logic;
    inject_packet_sel     : std_logic_vector(2 downto 0)  ;
    inject_user_value     : std_logic_vector(15 downto 0) ;
  end record;
  
  type t_ep2tru is record
    status           : std_logic;
--     ctrlRd           : std_logic;
    -- frame detectin
--     rx_pck           : std_logic;                    -- in Endpoint this is : pfilter_done_i
--     rx_pck_class     : std_logic_vector(7 downto 0); -- in Endpoint this is :pfilter_pclass_i    
    -- new stuff
    fc_pause_ready   : std_logic;
    inject_ready     : std_logic;
    pfilter_pclass   : std_logic_vector(7 downto 0);
    pfilter_drop     : std_logic;
    pfilter_done     : std_logic;    
  end record;

  type t_tru2ep_array       is array(integer range <>) of t_tru2ep;
  type t_ep2tru_array       is array(integer range <>) of t_ep2tru;

  type t_tru_tab_subentry is record
    valid          : std_logic;
    ports_ingress  : std_logic_vector(c_RTU_MAX_PORTS-1  downto 0); 
    ports_egress   : std_logic_vector(c_RTU_MAX_PORTS-1  downto 0); 
    ports_mask     : std_logic_vector(c_RTU_MAX_PORTS-1  downto 0); 
    pattern_match  : std_logic_vector(c_RTU_MAX_PORTS-1  downto 0); 
    pattern_mask   : std_logic_vector(c_RTU_MAX_PORTS-1  downto 0); 
    pattern_mode   : std_logic_vector(c_tru_pattern_mode_width-1  downto 0); 
  end record;
  

  type t_tru_endpoint is record
    status             : std_logic; -- port up/down
    rxFrameMask        : std_logic_vector(c_wrsw_pclass_number-1  downto 0); -- frame received (current)
    rxFrameMaskReg     : std_logic_vector(c_wrsw_pclass_number-1  downto 0); -- frame received (registered)
    stableUp           : std_logic;
  end record;

  type t_xFrameMask is array(c_wrsw_pclass_number-1  downto 0) of std_logic_vector(c_RTU_MAX_PORTS-1  downto 0); 
  type t_xFramePerPortMask is array(c_RTU_MAX_PORTS-1  downto 0) of std_logic_vector(c_RTU_MAX_PORTS-1  downto 0); 

  type t_tru_endpoints is record
    status             : std_logic_vector(c_RTU_MAX_PORTS-1  downto 0); -- port up/down
    rxFrameMask        : t_xFrameMask; -- frame received (current)
    rxFrameMaskReg     : t_xFrameMask; -- frame received (registered)
    rxFramePerPortMask : t_xFramePerPortMask; -- for LACP
    stableUp           : std_logic_vector(c_RTU_MAX_PORTS-1  downto 0);
  end record;

  type t_lagt_gr_id_mask_array is array(integer range <>) of std_logic_vector(3 downto 0);

  type t_tru_config is record
    --general config
    gcr_g_ena             : std_logic;
    gcr_rx_frame_reset    : std_logic_vector(23 downto 0);
    -- pattern match config
    mcr_pattern_mode_rep  : std_logic_vector(3 downto 0);
    mcr_pattern_mode_add  : std_logic_vector(3 downto 0);
    -- linc aggregation config
    lacr_agg_gr_num       : std_logic_vector(3 downto 0);
    lacr_agg_df_br_id     : std_logic_vector(3 downto 0);
    lacr_agg_df_un_id     : std_logic_vector(3 downto 0);
    lagt_gr_id_mask       : t_lagt_gr_id_mask_array(7 downto 0);
    -- transition config
    tcr_trans_ena         : std_logic;
    tcr_trans_clr         : std_logic;                     -- added
    tcr_trans_mode        : std_logic_vector(2 downto 0);
    tcr_trans_rx_id       : std_logic_vector(2 downto 0);
    tcr_trans_prio        : std_logic_vector(2 downto 0);  -- added
    tcr_trans_port_a_id   : std_logic_vector(5 downto 0);
    tcr_trans_port_a_pause: std_logic_vector(15 downto 0); -- added
    tcr_trans_port_a_valid: std_logic;
    tcr_trans_port_b_id   : std_logic_vector(5 downto 0);
    tcr_trans_port_b_pause: std_logic_vector(15 downto 0); -- added
    tcr_trans_port_b_valid: std_logic;
    -- real time reconfiguration config
    rtrcr_rtr_ena         : std_logic;
    rtrcr_rtr_reset       : std_logic;
    rtrcr_rtr_mode        : std_logic_vector(3 downto 0);
    rtrcr_rtr_rx          : std_logic_vector(3 downto 0);
    rtrcr_rtr_tx          : std_logic_vector(3 downto 0);
  end record;

  
  type t_resp_masks is record
    egress                : std_logic_vector(c_RTU_MAX_PORTS-1  downto 0); 
    ingress               : std_logic_vector(c_RTU_MAX_PORTS-1  downto 0); 
  end record;
 
  type t_tru_status is record
    transitionActive      : std_logic;
    transitionFinished    : std_logic;
    truTabBank            : std_logic;
  end record;
  --------------------------------- arrays ----------------------------------------------
--   type t_tru2ep_array       is array(integer range <>) of t_tru2ep;
--   type t_ep2tru_array       is array(integer range <>) of t_ep2tru;
  type t_trans2tru_array    is array(integer range <>) of t_trans2ep;
  
  type t_tru_tab_entry      is array(integer range <>) of t_tru_tab_subentry;
  type t_tru_tab_entries    is array(integer range <>,integer range <>) of t_tru_tab_subentry;
  type t_tru_endpoint_array is array(integer range<>) of t_tru_endpoint;
--   type t_tru_tab_subentry_array is array(integer range <>) of std_logic_vector(g_tru_subentry_width-1 downto 0); 
--   type t_ep_array is array(integer range <>) of std_logic_vector(g_ep2tru_record_width-1 downto 0); 

  
   


  function f_one_hot_to_binary   (One_Hot : std_logic_vector) 
           return integer;
  function f_unpack_tru_subentry (input_data: std_logic_vector;   port_number: integer) 
           return t_tru_tab_subentry;
  function f_pack_tru_subentry   (input_data: t_tru_tab_subentry; port_number: integer) 
           return std_logic_vector;
  function f_gen_mask_with_patterns(entry: t_tru_tab_entry; pattern_rep : std_logic_vector; 
           pattern_add  : std_logic_vector; subentry_num : integer) 
           return t_resp_masks;
--   function f_pack_tru_endpoint (input_data: t_tru_endpoint; port_number: integer ) 
--            return std_logic_vector;
  function f_unpack_tru_endpoint (input_data: std_logic_vector ) 
           return t_tru_endpoint;
  function f_pack_tru_request (input_data: t_tru_request;port_number: integer  ) 
           return std_logic_vector;
  function f_unpack_tru_request (input_data: std_logic_vector; port_number: integer ) 
           return t_tru_request;
  function f_pack_tru_response (input_data: t_tru_response; port_number: integer ) 
           return std_logic_vector;
  function f_unpack_tru_response (input_data: std_logic_vector; port_number: integer ) 
           return t_tru_response;
  function f_unpack_ep2tru (input_data: std_logic_vector ) 
           return t_ep2tru;
  function f_pack_tru2ep (input_data: t_tru2ep) 
           return std_logic_vector;
  function f_unpack_rtu (input_data: std_logic_vector;port_number: integer)
           return t_rtu2tru;

  function f_rxFrameMaskInv(input_data: t_tru_endpoint_array;rx_class_id: integer;port_number: integer)
           return std_logic_vector;
  function f_rxFrameMaskRegInv(input_data: t_tru_endpoint_array;rx_class_id: integer;port_number: integer)
           return std_logic_vector;
  function f_pattern_port_down (endpoints_i: t_tru_endpoints;config_i: t_tru_config; tru_req_i : t_tru_request;pattern_width_i : integer) 
           return std_logic_vector;
  function f_pattern_quick_fwd (endpoints_i: t_tru_endpoints; config_i : t_tru_config; tru_req_i : t_tru_request; pattern_width_i : integer) 
           return std_logic_vector;

  component tru_wishbone_slave
  port (
    rst_n_i            : in     std_logic;
    wb_clk_i           : in     std_logic;
    wb_addr_i          : in     std_logic_vector(3 downto 0);
    wb_data_i          : in     std_logic_vector(31 downto 0);
    wb_data_o          : out    std_logic_vector(31 downto 0);
    wb_cyc_i           : in     std_logic;
    wb_sel_i           : in     std_logic_vector(3 downto 0);
    wb_stb_i           : in     std_logic;
    wb_we_i            : in     std_logic;
    wb_ack_o           : out    std_logic;
    regs_i             : in     t_tru_in_registers;
    regs_o             : out    t_tru_out_registers
  );
  end component;

  component tru_sub_vlan_pattern
  generic(     
     g_num_ports        : integer;
     g_patternID_width  : integer;
     g_pattern_width    : integer
    );
  port (
    clk_i              : in std_logic;
    rst_n_i            : in std_logic;
    portID_i           : in std_logic_vector(integer(CEIL(LOG2(real(g_num_ports + 1))))-1 downto 0);
    patternID_i        : in std_logic_vector(g_patternID_width-1 downto 0);
    tru_req_i          : in  t_tru_request;
    endpoints_i        : in  t_tru_endpoints;
    config_i           : in  t_tru_config;
    pattern_o          : out std_logic_vector(g_pattern_width-1 downto 0)    
    );
  end component;
  
  component tru_reconfig_rt_port_handler
  generic(     
     g_num_ports        : integer; 
     g_tru_subentry_num : integer
    );
  port (
    clk_i              : in std_logic;
    rst_n_i            : in std_logic;
    read_valid_i       : in std_logic;
    read_data_i        : in t_tru_tab_entry(g_tru_subentry_num - 1 downto 0);
    resp_masks_i       : in  t_resp_masks;    
    config_i           : in  t_tru_config;
    tru_tab_bank_swap_i: in  std_logic;
    txFrameMask_o      : out std_logic_vector(g_num_ports-1 downto 0)
    );
  end component;  

  component tru_port
  generic(     
     g_num_ports        : integer; 
     g_tru_subentry_num : integer;
     g_patternID_width  : integer;
     g_pattern_width    : integer;
     g_tru_addr_width   : integer -- fid
    );
  port (
    clk_i              : in  std_logic;
    rst_n_i            : in  std_logic;
    tru_req_i          : in  t_tru_request;
    tru_resp_o         : out t_tru_response;   
    tru_tab_addr_o     : out std_logic_vector(g_tru_addr_width-1 downto 0);
    tru_tab_entry_i    : in  t_tru_tab_entry(g_tru_subentry_num - 1 downto 0);
    endpoints_i        : in  t_tru_endpoints;
    config_i           : in  t_tru_config;
    tru_tab_bank_swap_i: in  std_logic;
    txFrameMask_o      : out std_logic_vector(g_num_ports - 1 downto 0)
    );
  end component;

  component tru_endpoint is
  generic(     
     g_num_ports        : integer; 
     g_pclass_number    : integer;
     g_tru_subentry_num : integer;
     g_patternID_width  : integer;
     g_pattern_width    : integer;
     g_stableUP_treshold: integer
    );
  port (
    clk_i              : in  std_logic;
    rst_n_i            : in  std_logic;
    port_if_i          : in  t_ep2tru;
    port_if_ctrl_o     : out std_logic;
    rtu_pass_all_i     : in  std_logic;
    endpoint_o         : out  t_tru_endpoint;
    reset_rxFlag_i     : in  std_logic
    );
  end component;

  component xwrsw_tru is
  generic(     
     g_num_ports          : integer;
     g_tru_subentry_num   : integer;
     g_pattern_width      : integer;
     g_patternID_width    : integer;
     g_stableUP_treshold  : integer;
--      g_tru_addr_width     : integer;
     g_pclass_number      : integer;
     g_mt_trans_max_fr_cnt: integer;
     g_prio_width         : integer;
     g_pattern_mode_width : integer;
     g_tru_entry_num      : integer;
     g_interface_mode     : t_wishbone_interface_mode      := PIPELINED;
     g_address_granularity: t_wishbone_address_granularity := BYTE    
     );
  port (
    clk_i          : in std_logic;
    rst_n_i        : in std_logic;
    req_i              : in  t_tru_request;
    resp_o             : out t_tru_response;    
    rtu_i              : in  t_rtu2tru;
    ep_i               : in  t_ep2tru_array(g_num_ports-1 downto 0);
    ep_o               : out t_tru2ep_array(g_num_ports-1 downto 0);
    swc_o              : out std_logic_vector(g_num_ports-1 downto 0); -- for pausing
    enabled_o          : out std_logic;
    wb_i : in  t_wishbone_slave_in;
    wb_o : out t_wishbone_slave_out  
    );
  end component;

  component tru_transition 
  generic(     
     g_num_ports           : integer; 
     g_mt_trans_max_fr_cnt : integer;
     g_prio_width          : integer
    );
  port (
    clk_i              : in  std_logic;
    rst_n_i            : in  std_logic;
    endpoints_i        : in  t_tru_endpoints;
    config_i           : in  t_tru_config;
    tru_tab_bank_i     : in  std_logic;
    tru_tab_bank_o     : out std_logic;
    statTransActive_o  : out std_logic;
    statTransFinished_o: out std_logic;
    rxFrameMask_i      : in std_logic_vector(g_num_ports - 1 downto 0);
    rtu_i              : in  t_rtu2tru;
    ep_o               : out t_trans2tru_array(g_num_ports - 1 downto 0)
    );
  end component;

  component tru_trans_marker_trig 
  generic(     
     g_num_ports           : integer; 
     g_mt_trans_max_fr_cnt : integer;
     g_prio_width          : integer
    );
  port (
    clk_i              : in  std_logic;
    rst_n_i            : in  std_logic;
    endpoints_i        : in  t_tru_endpoints;
    config_i           : in  t_tru_config;
    tru_tab_bank_i     : in  std_logic;
    tru_tab_bank_o     : out std_logic;
    statTransActive_o  : out std_logic;
    statTransFinished_o: out std_logic;
    rxFrameMask_i      : in std_logic_vector(g_num_ports - 1 downto 0);
    rtu_i              : in  t_rtu2tru;
    ep_o               : out t_trans2tru_array(g_num_ports - 1 downto 0)
    );
  end component;

  component tru_trans_lacp_colect 
  generic(     
     g_num_ports        : integer; 
     g_mt_trans_max_fr_cnt : integer;
     g_prio_width       : integer
    );
  port (
    clk_i              : in  std_logic;
    rst_n_i            : in  std_logic;
    endpoints_i        : in  t_tru_endpoints;
    config_i           : in  t_tru_config;
    tru_tab_bank_i     : in  std_logic;
    tru_tab_bank_o     : out std_logic;
    statTransActive_o  : out std_logic;
    statTransFinished_o: out std_logic;
    rxFrameMask_i      : in std_logic_vector(g_num_ports - 1 downto 0);
    rtu_i              : in  t_rtu2tru;
    ep_o               : out t_trans2tru_array(g_num_ports - 1 downto 0)
    );
  end component;

  component tru_trans_lacp_dist 
  generic(     
     g_num_ports        : integer; 
     g_mt_trans_max_fr_cnt : integer;
     g_prio_width       : integer
    );
  port (
    clk_i              : in  std_logic;
    rst_n_i            : in  std_logic;
    endpoints_i        : in  t_tru_endpoints;
    config_i           : in  t_tru_config;
    tru_tab_bank_i     : in  std_logic;
    tru_tab_bank_o     : out std_logic;
    statTransActive_o  : out std_logic;
    statTransFinished_o: out std_logic;
    rxFrameMask_i      : in std_logic_vector(g_num_ports - 1 downto 0);
    rtu_i              : in  t_rtu2tru;
    ep_o               : out t_trans2tru_array(g_num_ports - 1 downto 0)
    );
  end component;


end wrsw_tru_pkg;

package body wrsw_tru_pkg is

  ----------------- translate one hot to binary --------------------------
  function f_one_hot_to_binary (
      One_Hot : std_logic_vector 
     ) return integer  is
  variable Bin_Vec_Var : integer range 0 to One_Hot'length -1;
  begin
    Bin_Vec_Var := 0;

     for I in 0 to (One_Hot'length - 1) loop
       if One_Hot(I) = '1' then
         Bin_Vec_Var := I;
       end if;
     end loop;
    return Bin_Vec_Var;
  end function;
  -----------------------------------------------------------------------
  function f_unpack_tru_subentry (
       input_data: std_logic_vector;
       port_number: integer 
    ) return t_tru_tab_subentry is
  variable entry: t_tru_tab_subentry;
  begin

    entry.valid                                 := input_data(0);
    entry.ports_ingress(port_number-1 downto 0) := input_data(1+1*port_number  -1 downto 1+0*port_number);
    entry.ports_egress (port_number-1 downto 0) := input_data(1+2*port_number  -1 downto 1+1*port_number);
    entry.ports_mask   (port_number-1 downto 0) := input_data(1+3*port_number  -1 downto 1+2*port_number);
    entry.pattern_match(port_number-1 downto 0) := input_data(1+4*port_number  -1 downto 1+3*port_number);
    entry.pattern_mask (port_number-1 downto 0) := input_data(1+5*port_number  -1 downto 1+4*port_number);
    entry.pattern_mode (c_tru_pattern_mode_width-1 downto 0) := input_data(1+5*port_number+c_tru_pattern_mode_width-1 downto 1+5*port_number);

    entry.ports_ingress(c_RTU_MAX_PORTS-1 downto port_number) := (others => '0');
    entry.ports_egress (c_RTU_MAX_PORTS-1 downto port_number) := (others => '0');
    entry.ports_mask   (c_RTU_MAX_PORTS-1 downto port_number) := (others => '0');
    entry.pattern_match(c_RTU_MAX_PORTS-1 downto port_number) := (others => '0');
    entry.pattern_mask (c_RTU_MAX_PORTS-1 downto port_number) := (others => '0');
    
    return(entry);

  end function;
  -----------------------------------------------------------------------
  function f_pack_tru_subentry (
       input_data: t_tru_tab_subentry ;
       port_number: integer 
    ) return std_logic_vector is
  variable entry: std_logic_vector((3*port_number)+(3*8)+1-1 downto 0);
  begin

    entry(0)                                          := input_data.valid;
    entry(1+1*port_number  -1 downto 1+0*port_number) := input_data.ports_ingress(port_number-1 downto 0);
    entry(1+2*port_number  -1 downto 1+1*port_number) := input_data.ports_egress (port_number-1 downto 0);
    entry(1+3*port_number  -1 downto 1+2*port_number) := input_data.ports_mask   (port_number-1 downto 0);
    entry(1+4*port_number  -1 downto 1+3*port_number) := input_data.pattern_match(port_number-1 downto 0);
    entry(1+5*port_number  -1 downto 1+4*port_number) := input_data.pattern_mask (port_number-1 downto 0);
    entry(1+6*port_number+c_tru_pattern_mode_width-1 downto 1+5*port_number) := input_data.pattern_mode(c_tru_pattern_mode_width-1 downto 0);
    return(entry);
  end function;

--   function f_pack_tru_endpoint (
--        input_data: t_tru_endpoint ;
--        port_number: integer 
--     ) return std_logic_vector is
--   variable entry: std_logic_vector(3*port_number-1 downto 0);
--   begin
-- 
--     entry(1*port_number -1 downto 0*port_number) := input_data.status  (port_number-1 downto 0);
--     entry(2*port_number -1 downto 1*port_number) := input_data.rxFrameMask    (port_number-1 downto 0);
--     entry(3*port_number -1 downto 2*port_number) := input_data.rxFrameMaskReg (port_number-1 downto 0);
--     return(entry);
--   end function;

  function f_unpack_tru_endpoint (
       input_data: std_logic_vector
    ) return t_tru_endpoint is
  variable entry: t_tru_endpoint;
  begin

    entry.status        := input_data(0);
    entry.rxFrameMask   := input_data(1+1*c_wrsw_pclass_number -1 downto 1+0*c_wrsw_pclass_number);
    entry.rxFrameMaskReg:= input_data(1+2*c_wrsw_pclass_number -1 downto 1+1*c_wrsw_pclass_number);

    return(entry);

  end function;
  
  function f_pack_tru_request (
       input_data: t_tru_request;
       port_number : integer 
    ) return std_logic_vector is
  variable entry: std_logic_vector(1+2*c_wrsw_mac_addr_width+c_wrsw_fid_width+1+1+c_RTU_MAX_PORTS-1 downto 0);
  begin
    entry(0)                                                                     := input_data.valid;
    entry(1+c_wrsw_mac_addr_width-1                                    downto 1) := input_data.smac;
    entry(1+2*c_wrsw_mac_addr_width-1                                  downto
          1+c_wrsw_mac_addr_width)                                               := input_data.dmac;
    entry(1+2*c_wrsw_mac_addr_width+c_wrsw_fid_width-1                 downto
          1+2*c_wrsw_mac_addr_width)                                             := input_data.fid;
    entry(1+2*c_wrsw_mac_addr_width+c_wrsw_fid_width)                            := input_data.isHP;
    entry(1+2*c_wrsw_mac_addr_width+c_wrsw_fid_width+1)                          := input_data.isBR;
    entry(1+2*c_wrsw_mac_addr_width+c_wrsw_fid_width+1+1+port_number-1 downto
          1+2*c_wrsw_mac_addr_width+c_wrsw_fid_width+1+1)                        := input_data.reqMask(port_number-1 downto 0);
    return(entry);
  end function;


  function f_unpack_tru_request (
       input_data  : std_logic_vector;
       port_number : integer 
    ) return t_tru_request is
  variable entry: t_tru_request;
  begin
    entry.valid  := input_data(0);
    entry.smac   := input_data(1+1*c_wrsw_mac_addr_width-1                  downto 1);
    entry.dmac   := input_data(1+2*c_wrsw_mac_addr_width-1                  downto 1+1*c_wrsw_mac_addr_width);
    entry.fid    := input_data(1+2*c_wrsw_mac_addr_width+c_wrsw_fid_width-1 downto 1+2*c_wrsw_mac_addr_width);
    entry.isHP   := input_data(1+2*c_wrsw_mac_addr_width+c_wrsw_fid_width);
    entry.isBR   := input_data(1+2*c_wrsw_mac_addr_width+c_wrsw_fid_width+1);
    entry.reqMask(port_number-1 downto 0) := input_data(1+2*c_wrsw_mac_addr_width+c_wrsw_fid_width+1+1+port_number-1 downto 1+2*c_wrsw_mac_addr_width+c_wrsw_fid_width+1+1) ;
    entry.reqMask(c_RTU_MAX_PORTS-1 downto port_number) := (others =>'0');
    return(entry);
  end function;

  function f_pack_tru_response (
       input_data: t_tru_response;
       port_number: integer 
    ) return std_logic_vector is
  variable entry: std_logic_vector(1+2*port_number+1-1 downto 0);
  begin
    entry(0)                                         := input_data.valid;
    entry(1+port_number-1    downto 1)               := input_data.port_mask(port_number-1 downto 0);
    entry(1+port_number)                             := input_data.drop;
    entry(1+2*port_number+1-1 downto 1+port_number+1)    := input_data.respMask(port_number-1 downto 0);
    return(entry);
  end function;


  function f_unpack_tru_response (
       input_data: std_logic_vector;
       port_number: integer 
    ) return t_tru_response is
  variable entry: t_tru_response;
  begin
    entry.valid                                           := input_data(0);
    entry.port_mask(port_number-1     downto 0)           := input_data(1+port_number-1   downto 1);
    entry.port_mask(c_RTU_MAX_PORTS-1 downto port_number) := (others => '0');
    entry.drop                                            := input_data(1+port_number);
    entry.respMask(port_number-1     downto 0)            := input_data(1+2*port_number-1 downto 1+port_number);
    entry.respMask(c_RTU_MAX_PORTS-1 downto port_number)  := (others => '0');
    return(entry);
  end function;


  function f_gen_mask_with_patterns(
        entry        : t_tru_tab_entry;
        pattern_rep  : std_logic_vector;
        pattern_add  : std_logic_vector;
        subentry_num : integer
  ) return t_resp_masks is
  variable resp_masks          : t_resp_masks;
  variable pattern_replacement : std_logic_vector(c_RTU_MAX_PORTS-1 downto 0);
  variable pattern_addition    : std_logic_vector(c_RTU_MAX_PORTS-1 downto 0);
  variable zeros               : std_logic_vector(c_RTU_MAX_PORTS-1 downto 0);
  begin  
    resp_masks.egress  := (others=>'0');
    resp_masks.ingress := (others=>'0');
    
    pattern_replacement(pattern_rep'length-1 downto 0)                := pattern_rep;
    pattern_addition   (pattern_add'length-1 downto 0)                := pattern_add;
    pattern_replacement(c_RTU_MAX_PORTS-1 downto pattern_rep'length)  := (others=>'0');
    pattern_addition   (c_RTU_MAX_PORTS-1 downto pattern_add'length)  := (others=>'0');
    
    for i in 0 to subentry_num-1 loop
      if(entry(i).valid = '1') then
        case entry(i).pattern_mode is
          when "0000" => --std_logic_vector(to_unsigned(0,entry(i).pattern_mode'length)) => 
            if((pattern_replacement and entry(i).pattern_mask) = entry(i).pattern_match) then
              resp_masks.egress  := (resp_masks.egress  and (not entry(i).ports_mask)) or (entry(i).ports_egress  and entry(i).ports_mask);
              resp_masks.ingress := (resp_masks.ingress and (not entry(i).ports_mask)) or (entry(i).ports_ingress and entry(i).ports_mask);
            end if;
          when "0001" => --std_logic_vector(to_unsigned(1,entry(i).pattern_mode'length)) =>
            if ((pattern_addition and entry(i).pattern_mask) = entry(i).pattern_match) then
              resp_masks.egress  := resp_masks.egress  or (entry(i).ports_egress  and entry(i).ports_mask);
              resp_masks.ingress := resp_masks.ingress or (entry(i).ports_ingress and entry(i).ports_mask);
            end if;
          when "0010" => --std_logic_vector(to_unsigned(2,entry(i).pattern_mode'length )) => 
            if ((pattern_addition and entry(i).pattern_mask and entry(i).pattern_match) /= zeros) then
              resp_masks.egress  := resp_masks.egress  or (entry(i).ports_egress  and entry(i).ports_mask and pattern_addition);
              resp_masks.ingress := resp_masks.ingress or (entry(i).ports_ingress and entry(i).ports_mask and pattern_addition);
            end if;
          when others =>
            resp_masks.egress  := resp_masks.egress; 
            resp_masks.ingress := resp_masks.ingress ;
          end case;
        else
          resp_masks.egress  := resp_masks.egress; 
          resp_masks.ingress := resp_masks.ingress ;
        end if;


--       if    (entry(i).pattern_mode = std_logic_vector(to_unsigned(0,entry(i).pattern_mode'length)) and  ((pattern_rep and entry(i).pattern_mask) = entry(i).pattern_match)) then
--         resp_masks.egress  := (resp_masks.egress  and not entry(i).ports_mask) or (entry(i).ports_egress  and entry(i).ports_mask);
--         resp_masks.ingress := (resp_masks.ingress and not entry(i).ports_mask) or (entry(i).ports_ingress and entry(i).ports_mask);
--       elsif((entry(i).pattern_mode = std_logic_vector(to_unsigned(1,entry(i).pattern_mode'length)) and (pattern_add and entry(i).pattern_mask) = entry(i).pattern_match)) then
--         resp_masks.egress  := resp_masks.egress  or (entry(i).ports_egress  and entry(i).ports_mask);
--         resp_masks.ingress := resp_masks.ingress or (entry(i).ports_ingress and entry(i).ports_mask);
--       elsif((entry(i).pattern_mode = std_logic_vector(to_unsigned(2,entry(i).pattern_mode'length ))) and (pattern_add and entry(i).pattern_mask and entry(i).pattern_match) /= zeros) then
--         resp_masks.egress  := resp_masks.egress  or (entry(i).ports_egress  and entry(i).ports_mask and pattern_add);
--         resp_masks.ingress := resp_masks.ingress or (entry(i).ports_ingress and entry(i).ports_mask and pattern_add);
--       end if;

--       if    ((pattern_rep and entry(i).pattern_mask) = entry(i).pattern_replace) then
--         resp_masks.egress  := (resp_masks.egress  and not entry(i).ports_mask) or (entry(i).ports_egress  and entry(i).ports_mask);
--         resp_masks.ingress := (resp_masks.ingress and not entry(i).ports_mask) or (entry(i).ports_ingress and entry(i).ports_mask);
--       elsif((pattern_add and entry(i).pattern_mask) = entry(i).pattern_add) then
--         resp_masks.egress  := resp_masks.egress  or (entry(i).ports_egress  and entry(i).ports_mask);
--         resp_masks.ingress := resp_masks.ingress or (entry(i).ports_ingress and entry(i).ports_mask);
--       end if;

    end loop;
    
    return(resp_masks);
  end function; 

  function f_rxFrameMaskInv(
       input_data: t_tru_endpoint_array;
       rx_class_id: integer ;
       port_number: integer
    ) return std_logic_vector is
  variable rxs_for_allPorts: std_logic_vector(c_RTU_MAX_PORTS-1 downto 0);
  begin
     for i in 0 to c_RTU_MAX_PORTS-1 loop
        if(i<port_number) then
           rxs_for_allPorts(i) := input_data(i).rxFrameMask(rx_class_id);
        else
           rxs_for_allPorts(i) := '0';
        end if;
     end loop;
     return(rxs_for_allPorts);
  end function;

  function f_rxFrameMaskRegInv(
       input_data: t_tru_endpoint_array;
       rx_class_id: integer ;
       port_number: integer
    ) return std_logic_vector is
  variable rxs_for_allPorts: std_logic_vector(c_RTU_MAX_PORTS-1 downto 0);
  begin
     for i in 0 to c_RTU_MAX_PORTS-1 loop
        if(i<port_number) then
           rxs_for_allPorts(i) := input_data(i).rxFrameMaskReg(rx_class_id);
        else
           rxs_for_allPorts(i) := '0';
        end if;
     end loop;
     return(rxs_for_allPorts);
  end function;


  function f_unpack_ep2tru (  -- this function needs to be changed for tru testbench to work
       input_data: std_logic_vector
    ) return t_ep2tru is
  variable entry: t_ep2tru;
  begin
    entry.status       := input_data(0);
--     entry.ctrlRd       := input_data(1);
--     entry.rx_pck       := input_data(2);
--     entry.rx_pck_class := input_data(3+c_wrsw_pclass_number-1 downto 3);
    return(entry);
  end function;

  function f_pack_tru2ep ( -- this function needs to be changed for tru testbench to work
       input_data: t_tru2ep
    ) return std_logic_vector is
  variable entry: std_logic_vector(3+c_wrsw_pclass_number+
                                     c_wrsw_pause_delay_width+
                                     c_wrsw_max_queue_number-1 downto 0);
  begin
--     entry(0)                                                        := input_data.ctrlWr;
--     entry(1)                                                        := input_data.tx_pck;
--     entry(2+ c_wrsw_pclass_number-1 downto 2)                       := input_data.tx_pck_class;
--     entry(2+ c_wrsw_pclass_number)                                  := input_data.pauseSend;
--     entry(2+ c_wrsw_pclass_number+1+c_wrsw_pause_delay_width-1 downto 
--           2+ c_wrsw_pclass_number+1)                                := input_data.pauseTime;
    entry(2+ c_wrsw_pclass_number+1+c_wrsw_pause_delay_width+
             c_wrsw_max_queue_number-1 downto 
          2+ c_wrsw_pclass_number+1+c_wrsw_pause_delay_width)     := input_data.outQueueBlockMask;
    return(entry);
  end function;

  function f_unpack_rtu (
       input_data: std_logic_vector;
       port_number: integer
    ) return t_rtu2tru is
  variable entry: t_rtu2tru;
  variable i    : integer;
  begin
    entry.pass_all(port_number-1 downto 0)           := input_data(1*port_number-1 downto 0*port_number);
    entry.forward_bpdu_only(port_number-1 downto 0)  := input_data(2*port_number-1 downto 1*port_number);
    entry.request_valid(port_number-1 downto 0)      := input_data(3*port_number-1 downto 2*port_number);
--     for i in 0 to port_number-1 loop
--       entry.priorities(i) := input_data(3*port_number+(i+1)*c_wrsw_prio_width-1 downto 3*port_number+i*c_wrsw_prio_width);
--     end loop;
    entry.pass_all(c_RTU_MAX_PORTS-1 downto port_number)           := (others =>'0');
    entry.forward_bpdu_only(c_RTU_MAX_PORTS-1 downto port_number)  := (others =>'0');
    entry.request_valid(c_RTU_MAX_PORTS-1 downto port_number)      := (others =>'0');

    return(entry);
  end function;

  --------------------------------------  pattern -------------------------------------------------
  function f_pattern_port_down (
       endpoints_i     : t_tru_endpoints;
       config_i        : t_tru_config;
       tru_req_i       : t_tru_request;       
       pattern_width_i : integer
    ) return std_logic_vector is
  variable pattern_o : std_logic_vector(pattern_width_i-1 downto 0);
  begin
    pattern_o := not (endpoints_i.status(pattern_width_i-1 downto 0));
    return(pattern_o);
  end function;

  function f_pattern_quick_fwd (
       endpoints_i     : t_tru_endpoints;
       config_i        : t_tru_config;
       tru_req_i       : t_tru_request;       
       pattern_width_i : integer
    ) return std_logic_vector is
  variable pattern_o     : std_logic_vector(pattern_width_i-1 downto 0);
  variable rxFrameNumber : integer range 0 to endpoints_i.rxFrameMaskReg'length-1;
  begin
    rxFrameNumber := to_integer(unsigned(config_i.rtrcr_rtr_rx));
    pattern_o     := endpoints_i.rxFrameMaskReg(rxFrameNumber)(pattern_width_i-1 downto 0);
    return(pattern_o);
  end function;

end wrsw_tru_pkg;

-- wbgen2 --lang=vhdl --hstyle=record --vo=tru_wishbone_slave.vhd --vpo=tru_wbgen2_pkg.vhd --doco=rtu_wishbone_slave.html tru_wishbone_slave.wb
