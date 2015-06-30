-------------------------------------------------------------------------------
-- Title      : WR Switch - shared types package
-- Project    : White Rabbit Switch
-------------------------------------------------------------------------------
-- File       : wrsw_shared_types_pkg.vhd
-- Author     : Tomasz Wlostowski, Maciej Lipinski
-- Company    : CERN BE-CO-HT
-- Created    : 2012-01-22
-- Last update: 2013-11-14
-- Platform   : FPGA-generic
-- Standard   : VHDL
-------------------------------------------------------------------------------
--
-- Copyright (c) 2012 - 2013 CERN / BE-CO-HT
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
use ieee.STD_LOGIC_1164.all;

package wrsw_shared_types_pkg is

  constant c_RTU_MAX_PORTS : integer := 32;
  constant c_SWC_MAX_PORTS : integer := c_RTU_MAX_PORTS+1;

  type t_rtu_request is record
    valid    : std_logic;
    smac     : std_logic_vector(47 downto 0);
    dmac     : std_logic_vector(47 downto 0);
    vid      : std_logic_vector(11 downto 0);
    has_vid  : std_logic;
    prio     : std_logic_vector(2 downto 0);
    has_prio : std_logic;
  end record;

  type t_rtu_response is record
    valid     : std_logic;
    port_mask : std_logic_vector(c_RTU_MAX_PORTS-1 downto 0);
    prio      : std_logic_vector(2 downto 0);
    drop      : std_logic;
    hp        : std_logic;
  end record;

  type t_rtu_request_array is array(integer range <>) of t_rtu_request;
  type t_rtu_response_array is array(integer range <>) of t_rtu_response;

  type t_tru_request is record
    valid            : std_logic;
    smac             : std_logic_vector(47 downto 0);
    dmac             : std_logic_vector(47 downto 0);
    fid              : std_logic_vector(7  downto 0);
    isHP             : std_logic;                     -- high priority packet flag
    isBR             : std_logic;                     -- broadcast packet flag
    reqMask          : std_logic_vector(c_RTU_MAX_PORTS-1  downto 0); -- mask indicating requesting port
    prio             : std_logic_vector(2 downto 0); -- more for testing then to be used
  end record;
   
  type t_tru_response is record
    valid            : std_logic;
    port_mask        : std_logic_vector(c_RTU_MAX_PORTS-1 downto 0); -- mask with 1's at forward ports
    drop             : std_logic;
    respMask         : std_logic_vector(c_RTU_MAX_PORTS-1 downto 0); -- mask with 1 at requesting port
  end record;
  
  constant c_tru_response_zero : t_tru_response := (
                      valid            => '0',
                      port_mask        => (others => '0'),
                      drop             => '0',
                      respMask         => (others => '0'));
  
  type t_tru_request_array is array(integer range <>) of t_tru_request;
  type t_tru_response_array is array(integer range <>) of t_tru_response;

--   type t_tru2ep is record
-- --     ctrlWr                : std_logic;
--     --frmae generation
--     tx_pck                : std_logic;                    -- to be changed
--     tx_pck_class          : std_logic_vector(7 downto 0); -- to be changed
--     -- pause generation
-- --     pauseSend             : std_logic;
-- --     pauseTime             : std_logic_vector(15 downto 0);
--     outQueueBlockMask     : std_logic_vector(7 downto 0);
--     -- new stuff
--     link_kill             : std_logic;                      --ok
--     fc_pause_req          : std_logic;                      --ok
--     fc_pause_delay        : std_logic_vector(15 downto 0);  --ok
--     inject_req            : std_logic;
--     inject_packet_sel     : std_logic_vector(2 downto 0)  ;
--     inject_user_value     : std_logic_vector(15 downto 0) ;
--   end record;
--   
--   type t_ep2tru is record
--     status           : std_logic;
-- --     ctrlRd           : std_logic;
--     -- frame detectin
--     rx_pck           : std_logic;                    -- in Endpoint this is : pfilter_done_i
--     rx_pck_class     : std_logic_vector(7 downto 0); -- in Endpoint this is :pfilter_pclass_i    
--     -- new stuff
--     fc_pause_ready   : std_logic;
--     inject_ready     : std_logic;
--     pfilter_pclass_o : std_logic_vector(7 downto 0);
--     pfilter_drop_o   : std_logic;
--     pfilter_done_o   : std_logic;    
--   end record;
-- 
--   type t_tru2ep_array       is array(integer range <>) of t_tru2ep;
--   type t_ep2tru_array       is array(integer range <>) of t_ep2tru;

  type t_rtu_prio_array is array(integer range <>) of std_logic_vector(2 downto 0);  

  type t_rtu2tru is record -- single port
    pass_all         : std_logic_vector(c_RTU_MAX_PORTS-1  downto 0); 
    forward_bpdu_only: std_logic_vector(c_RTU_MAX_PORTS-1  downto 0); 
    request_valid    : std_logic_vector(c_RTU_MAX_PORTS-1  downto 0);
--     priorities       : std_logic_vector(c_RTU_MAX_PORTS-1  downto 0);
    priorities       : t_rtu_prio_array(c_RTU_MAX_PORTS-1  downto 0);
    has_prio         : std_logic_vector(c_RTU_MAX_PORTS-1  downto 0);
  end record;

  type t_pause_request is record
    req            : std_logic;
    quanta         : std_logic_vector(15 downto 0);
    classes        : std_logic_vector(7 downto 0); -- '1' for the classes which shall be PAUSED
  end record;

  type t_global_pause_request is record
    req            : std_logic;
    quanta         : std_logic_vector(15 downto 0);
    classes        : std_logic_vector(7 downto 0); -- '1' for the classes which shall be PAUSED
    ports          : std_logic_vector(c_SWC_MAX_PORTS-1 downto 0);
  end record;

  type t_pause_request_array        is array(integer range <>) of t_pause_request;  
  type t_global_pause_request_array is array(integer range <>) of t_global_pause_request;  

  type t_swc_fsms is array(integer range <>) of std_logic_vector(3 downto 0);
  type t_swc_fsms_array is array(integer range <>) of t_swc_fsms(6 downto 0);
  constant c_ALLOC_FSM_IDX : integer := 0;
  constant c_TRANS_FSM_IDX : integer := 1;
  constant c_RCV_FSM_IDX   : integer := 2;
  constant c_LL_FSM_IDX    : integer := 3;
  constant c_PREP_FSM_IDX  : integer := 4;
  constant c_SEND_FSM_IDX  : integer := 5;
  constant c_FREE_FSM_IDX  : integer := 6;

end wrsw_shared_types_pkg;
