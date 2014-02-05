-------------------------------------------------------------------------------
-- Title      : WR NIC - descriptors package
-- Project    : WhiteRabbit Switch
-------------------------------------------------------------------------------
-- File       : nic_descriptors_pkg.vhd
-- Author     : Tomasz Wlostowski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-11-24
-- Last update: 2012-03-16
-- Platform   : FPGA-generic
-- Standard   : VHDL
-------------------------------------------------------------------------------
-- Description: Package declares RX/TX descriptor data types and functions for
-- marshalling/unmarshalling the descriptors to/from SLVs
-------------------------------------------------------------------------------
-- Copyright (c) 2010 Tomasz Wlostowski
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author          Description
-- 2010-11-24  1.0      twlostow        Created
-------------------------------------------------------------------------------

library IEEE;

use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library work;
use work.nic_constants_pkg.all;


package nic_descriptors_pkg is

  type t_tx_descriptor is record
    ts_id  : std_logic_vector(15 downto 0);  --  OOB frame id (for TX timestamping)
    pad_e  : std_logic;                 -- padding enable
    ts_e   : std_logic;                 -- timestamp enable
    error  : std_logic;                 -- TX error indication
    ready  : std_logic;  -- Descriptor ready for transmission flag
    len    : std_logic_vector(c_nic_buf_size_log2-1 downto 0);  -- Length of the packet
    offset : std_logic_vector(c_nic_buf_size_log2-1 downto 0);  -- Offset of the packet in the buffer
    dpm    : std_logic_vector(31 downto 0);  -- Destination port mask
  end record;


  type t_rx_descriptor is record
    empty   : std_logic;                -- Descriptor empty (ready for
                                        -- reception) flag
    error   : std_logic;                -- RX error indication
    port_id : std_logic_vector(5 downto 0);   -- Packet source port ID
    got_ts  : std_logic;                -- Got a timestamp?
    ts_incorrect: std_logic;            -- 1: Timestamp may be incorrect (generated
                                        -- during time base adjustment)
    
    ts_r    : std_logic_vector(27 downto 0);  -- Rising edge timestamp
    ts_f    : std_logic_vector(3 downto 0);   -- Falling edge timestamp
    len     : std_logic_vector(c_nic_buf_size_log2-1 downto 0);  -- Length of the allocated buffer
                                        -- (or length of the received
                                        -- packet when the desc is not empty)
    offset  : std_logic_vector(c_nic_buf_size_log2-1 downto 0);  -- Address of the buffer;
  end record;

  function f_marshall_tx_descriptor(desc   : t_tx_descriptor;
                                    regnum : integer) return std_logic_vector;
  function f_marshall_rx_descriptor(desc   : t_rx_descriptor;
                                    regnum : integer) return std_logic_vector;

  function f_unmarshall_tx_descriptor(mem_input : std_logic_vector(31 downto 0);
                                      regnum : integer) return t_tx_descriptor;

  function f_unmarshall_rx_descriptor(mem_input : std_logic_vector(31 downto 0);
                                       regnum   : integer) return t_rx_descriptor;

  function f_resize_slv(x : std_logic_vector;
                      newsize : integer) return std_logic_vector;

  
end NIC_descriptors_pkg;

package body NIC_descriptors_pkg is

  function f_resize_slv(x : std_logic_vector; newsize : integer) return std_logic_vector is
    variable tmp:std_logic_vector(newsize-1 downto 0);
  begin
      tmp(x'length-1 downto 0) := x;
      tmp(newsize-1 downto x'length) := (others => '0');
      return tmp;
  end f_resize_slv;


  function f_marshall_tx_descriptor(desc : t_tx_descriptor; regnum : integer) return std_logic_vector is
    variable tmp : std_logic_vector(31 downto 0);
  begin

    case regnum is
      when 3      => tmp := desc.ts_id & x"000" & desc.pad_e & desc.ts_e & desc.error & desc.ready;
      when 0      => tmp := f_resize_slv(desc.len, 16) & f_resize_slv(desc.offset, 16);
      when 1      => tmp := desc.dpm;
      when others => null;
    end case;

    return tmp;
  end f_marshall_tx_descriptor;

  function f_marshall_rx_descriptor(desc : t_rx_descriptor; regnum : integer) return std_logic_vector is
    variable tmp : std_logic_vector(31 downto 0);
  begin
    case regnum is
      when 3      => tmp := "0000000000000000" & desc.ts_incorrect & desc.got_ts & desc.port_id & "000000" & desc.error & desc.empty;
      when 0      => tmp := desc.ts_f & desc.ts_r;
      when 1      => tmp := f_resize_slv(desc.len, 16) & f_resize_slv(desc.offset, 16);
      when others => null;
    end case;

    return tmp;
    
  end f_marshall_rx_descriptor;

  
  function f_unmarshall_tx_descriptor(mem_input : std_logic_vector(31 downto 0); regnum : integer)
    return t_tx_descriptor is
      variable desc : t_tx_descriptor;
  begin
    case regnum is
      when 1 =>
        desc.ts_id := mem_input(31 downto 16);
        desc.pad_e := mem_input(3);
        desc.ts_e  := mem_input(2);
        desc.error := mem_input(1);
        desc.ready := mem_input(0);
      when 2 =>
        desc.len    := mem_input(16+c_nic_buf_size_log2-1 downto 16);
        desc.offset := mem_input(c_nic_buf_size_log2-1 downto 0);
      when 3 =>
        desc.dpm := mem_input;
      when others => null;
    end case;
    return desc;
  end f_unmarshall_tx_descriptor;

  function f_unmarshall_rx_descriptor(mem_input : std_logic_vector(31 downto 0); regnum : integer)
    return t_rx_descriptor is
      variable desc : t_rx_descriptor;
  begin
    case regnum is
      when 1 =>
        desc.empty   := mem_input(0);
        desc.error   := mem_input(1);
        desc.port_id := mem_input(13 downto 8);
        desc.got_ts  := mem_input(14);
        desc.ts_incorrect := mem_input(15);

      when 2 =>
        desc.ts_f := mem_input(31 downto 28);
        desc.ts_r := mem_input(27 downto 0);

      when 3 =>
        desc.len    := mem_input(16+c_nic_buf_size_log2-1 downto 16);
        desc.offset := mem_input(c_nic_buf_size_log2-1 downto 0);
      when others => null;
    end case;
    return desc;
  end f_unmarshall_rx_descriptor;


end package body;
