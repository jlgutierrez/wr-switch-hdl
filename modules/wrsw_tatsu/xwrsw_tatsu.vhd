-------------------------------------------------------------------------------
-- Title      : (Extended) Time-Aware Traffic Shapper Unit
-- Project    : WhiteRabbit switch
-------------------------------------------------------------------------------
-- File       : xwrsw_tatsu.vhd
-- Author     : Maciej Lipinski
-- Company    : CERN BE-CO-HT
-- Created    : 2013-02-28
-- Last update: 2013-03-12
-- Platform   : FPGA-generic
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: The module implements simple Time-Aware Traffic Shaper. 
-- It can be configured to start at a given time (TAI+cycles) a time window
-- of time (quanta). In this window only defined output queues (prio_mask)
-- are allowed (the others are blocked). This traffic shaping concerns only 
-- defined ports (port_mask).
-- 
-- How it works:
-- 1) user writes configuration/settings through WB interface
-- 2) user validates the config/settings by writing proper bit in control reg
--    through WB I/F : (config: 
--    * start_tm_tai    - at which second (in TAI) the Shape shall start 
--    * start_tm_cycles - at which cycle (within second) the Shaper shall strt
--    * window_quanta   - how long shell bhe the window in which only indicated
--                        priorities are allowed
--    * repeat_cycles   - every how many cycles the window shall be repeated 
--    * prio_mask       - mask which indicates which priorities are allowed
--                        (at output queues of indicated ports, other priorities
--                         are blocked)
--    * ports_mask      - mask which indicates on which ports the shaper shall
--                        be applied to output queues
-- 3) if the parameters are incorrect, e.g. stat time in past, too long/short 
--    repeat time), the Shaper is not started but error occurs (type of error
--    written to status reg)
-- 4) if parameters are correct, the Shaper waits for preper time (TAI+CYCLE)
--    to arrive (compare seetings with: tm_tai_i, tm_cycle_i)
-- 5) if the input time (tm_tai_i,tm_cycles_i) is invalid (tm_time_valid LOW) at
--    the start time (start_tm_tai, start_tm_cycles), the shaper will start with 
--    the next repeat cycle: start_tm_cycles+repeat_cycles
-- 6) once the shaper is started, it uses it's internal counter (tm_cycles_int)
--    to trigger subsequent repeat_cycles. This counter is synched with tm_cycles_i
--    at Shaper's start
-- 7) the internal counter (tm_cycles_int) is synched with input time (tm_cycle_i)
--    periodically: ~ each 1s
-- 
--
-- 
-------------------------------------------------------------------------------
--
-- Copyright (c) 2013 CERN / BE-CO-HT
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
-- 2012-02-28  1.0      mlipinsk Created
-------------------------------------------------------------------------------
-- TODOs:
-- [1]: tm_time_valid only at the end of the second + huge time jump - do we
--      want to handle this?
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.CEIL;
use ieee.math_real.log2;

library work;
use work.wrsw_shared_types_pkg.all;
use work.gencores_pkg.all;
use work.wrsw_tatsu_pkg.all;
use work.tatsu_wbgen2_pkg.all;
use work.wishbone_pkg.all;         -- wishbone_{interface_mode,address_granularity}

entity xwrsw_tatsu is
  generic(     
     g_num_ports          : integer                        := 6;  
     g_interface_mode     : t_wishbone_interface_mode      := PIPELINED;
     g_simulation         : boolean                        := false;
     g_address_granularity: t_wishbone_address_granularity := BYTE
     );
  port (
    clk_sys_i                 : in std_logic;
    clk_ref_i                 : in std_logic;

    rst_n_i                   : in std_logic;

    -- pause request to SWcore's output queues in output_block of chosen ports
    -- (req, quanta, classes)
    shaper_request_o          : out t_global_pause_request ;
       
    -- configuration which causes the the SWcore to drop currently transmitted
    -- frame if a frame in high queue is waiting for transmission (affects all ports)
    shaper_drop_at_hp_ena_o   : out std_logic;    

    -- input WR time
    tm_utc_i                  : in  std_logic_vector(39 downto 0);
    tm_cycles_i               : in  std_logic_vector(27 downto 0);
    tm_time_valid_i           : in  std_logic;

    -- WB config I/F
    wb_i                      : in  t_wishbone_slave_in;
    wb_o                      : out t_wishbone_slave_out          
    );
end xwrsw_tatsu;

architecture rtl of xwrsw_tatsu is

  constant c_PERIOD           : integer := f_pick(g_simulation, 10000, 62500000);
  constant c_cycle_width      : integer := 28;
  constant c_cycle_ext_width  : integer := c_cycle_width + 2;
  constant c_min_repeat_cyc   : integer := 8;

  type t_tatsu_state is (S_IDLE,
                          S_WAIT_START,
                          S_WAIT_REPEAT,
                          S_PAUSE_REQ,
                          S_LOAD_NEW_CONFIG,
                          S_ERROR);

  type t_tatsu_status is record
    settings_err     : std_logic;
    settings_err_tai : std_logic;
    settings_err_cyc : std_logic;
    settings_err_rpt : std_logic;
    settings_ok      : std_logic;
    tatsu_started    : std_logic;
    tatsu_delayed    : std_logic;
    tm_sync_err      : std_logic;
  end record;
  
  constant c_stat_clear : t_tatsu_status := ('0','0','0','0','0','0','0','0');
  ------------------ sysclk domain  ---------------------------------------
  -- sygnals in sysclk domain  only
  signal wb_in                : t_wishbone_slave_in;
  signal wb_out               : t_wishbone_slave_out;
  signal regs_towb            : t_tatsu_in_registers;
  signal regs_fromwb          : t_tatsu_out_registers;  

  -- loaded in refclk, used in sysclk
  signal prio_mask            : std_logic_vector(7 downto 0);
  signal window_quanta        : std_logic_vector(15 downto 0);
  signal port_mask            : std_logic_vector(g_num_ports-1 downto 0);
  
  -- loaded in syslk, used in refclk
  signal config               : t_tatsu_config;
  
  -- signal in sysclk domain synched with refclk domain
  signal shaper_req_sysclk         : std_logic;
  
  ------------------ refclk domain -----------------------------------
  -- signals in refclk domained, synced with signals in sysclk
  signal rst_synced_refclk    : std_logic;
  signal valid_synced_refclk  : std_logic;
  signal disable_synced_refclk: std_logic;

  -- refclk domain only
  signal start_tm_tai         : std_logic_vector(39 downto 0);
  signal start_tm_cycles      : unsigned(c_cycle_ext_width-1 downto 0);
  signal repeat_cycles        : unsigned(c_cycle_ext_width-1 downto 0);
  signal next_start_tm_cycles : unsigned(c_cycle_ext_width-1 downto 0);
  signal tm_cycles_int        : unsigned(c_cycle_ext_width-1 downto 0);
  signal tatsu_state          : t_tatsu_state;

  -- signal exposed to sysclk domain
  signal shaper_req_refclk    : std_logic;
  signal status               :  t_tatsu_status;
  
begin --rtl

  next_start_tm_cycles       <= start_tm_cycles + repeat_cycles;
  
  shaper_p: process(clk_ref_i,rst_synced_refclk)
  begin 
    if rising_edge(clk_ref_i) then
      if (rst_synced_refclk = '0' or disable_synced_refclk ='1') then   

        status                <= c_stat_clear;

        start_tm_tai          <= (others => '0');
        start_tm_cycles       <= (others => '0');
        tm_cycles_int         <= (others => '0');
        repeat_cycles         <= (others => '0');
        
        shaper_req_refclk     <= '0';

        prio_mask             <= (others => '0');
        port_mask             <= (others => '0');
        window_quanta         <= (others => '0');

        tatsu_state           <= S_IDLE;

      else
      
        case tatsu_state is
          --==================================================================================
          when S_IDLE =>  -- only after disable or reset
          --==================================================================================
            
            if(valid_synced_refclk = '1') then
              tatsu_state           <= S_LOAD_NEW_CONFIG;
              status                <= c_stat_clear;
            end if;

          --==================================================================================
          when S_LOAD_NEW_CONFIG =>  -- validate and remember configuration
          --==================================================================================
            
            if(shaper_req_refclk = '1' and shaper_req_sysclk = '1') then 
              shaper_req_refclk <= '0';

            elsif(shaper_req_refclk = '0' and shaper_req_sysclk = '0') then -- make sure that there is no current requests to SWcore
              if (config.start_tm_tai      < tm_utc_i) then
                tatsu_state                    <= S_ERROR;
                status.settings_err_tai        <='1';
              elsif ((config.start_tm_tai  = tm_utc_i) and (config.start_tm_cycles < tm_cycles_i)) then
                tatsu_state                    <= S_ERROR;
                status.settings_err_cyc        <='1';
              elsif(config.start_tm_cycles > std_logic_vector(to_unsigned(c_PERIOD, c_cycle_width )) )  then
                tatsu_state                    <= S_ERROR;
                status.settings_err_cyc        <='1';
              elsif(config.repeat_cycles   = std_logic_vector(to_unsigned(0,c_cycle_width))) then 
                tatsu_state                    <= S_ERROR;
                status.settings_err_rpt        <='1';
              elsif(config.repeat_cycles   > std_logic_vector(to_unsigned(c_PERIOD, c_cycle_width )) ) then 
                tatsu_state                    <= S_ERROR;
                status.settings_err_rpt        <='1';                
              elsif(config.repeat_cycles   < std_logic_vector(to_unsigned(c_min_repeat_cyc, c_cycle_width )) ) then 
                tatsu_state                    <= S_ERROR;
                status.settings_err_rpt        <='1';                 
              else        
                start_tm_cycles(c_cycle_width    -1 downto 0) <= unsigned(config.start_tm_cycles);  
                repeat_cycles  (c_cycle_width    -1 downto 0) <= unsigned(config.repeat_cycles);
                start_tm_cycles(c_cycle_ext_width-1 downto c_cycle_width) <= (others =>'0');  
                repeat_cycles  (c_cycle_ext_width-1 downto c_cycle_width) <= (others =>'0');  
                
                tatsu_state                    <= S_WAIT_START;
                start_tm_tai                   <= config.start_tm_tai ;

                port_mask                      <= config.ports_mask(g_num_ports-1 downto 0); 
                prio_mask                      <= config.prio_mask;
                window_quanta                  <= config.window_quanta;
                
                status.settings_ok             <= '1';
                
              end if;              
            end if;
          --==================================================================================
          when S_WAIT_START =>  -- wait until the set time (TAI+CYCLE) arrives
          --==================================================================================
            
            if(valid_synced_refclk = '1') then
              tatsu_state        <= S_LOAD_NEW_CONFIG;
              status             <= c_stat_clear;
            elsif(tm_time_valid_i = '1') then

              -- this is standard case: we start when the time matches
              if((tm_utc_i    = start_tm_tai) and 
                 (tm_cycles_i = std_logic_vector(start_tm_cycles(c_cycle_width-1 downto 0)))) then 
                shaper_req_refclk    <= '1';    
                tatsu_state          <= S_PAUSE_REQ;   
                status.tatsu_started <= '1';  
                tm_cycles_int(c_cycle_width-1 downto 0)                 <= unsigned(tm_cycles_i) + 1;      
                tm_cycles_int(c_cycle_ext_width-1 downto c_cycle_width) <= (others =>'0');

              -- if the tm_time_valid_i was low when we should have started, we have probably 
              -- missed the right moment to start. In such case, we try to start with the next
              -- cycle and indicate in the status what happened (this is kind-of-recursive if the
              -- time adjustment was really huge step back, if it was step forward, it's OK)
              elsif((tm_utc_i    = start_tm_tai) and
                    (tm_cycles_i > std_logic_vector(start_tm_cycles(c_cycle_width-1 downto 0)))) then
            
                status.tatsu_delayed <= '1';
              
                if(next_start_tm_cycles >= to_unsigned(c_PERIOD,c_cycle_ext_width)) then
                  start_tm_tai     <= std_logic_vector(unsigned(start_tm_tai) + 1);
                  start_tm_cycles  <= next_start_tm_cycles - to_unsigned(c_PERIOD,c_cycle_ext_width);
                else
                  start_tm_cycles  <= next_start_tm_cycles;
                end if;          
              
              -- the time adjustment was substantial and we've missed the proper second
              elsif(tm_utc_i   > start_tm_tai) then
                tatsu_state                    <= S_ERROR;                
              end if;
            end if;

          --==================================================================================
          when S_PAUSE_REQ =>  -- send request to SWcore to activate pause
          --==================================================================================
            
            tm_cycles_int <= tm_cycles_int + 1;
            
            if(valid_synced_refclk = '1') then
              tatsu_state        <= S_LOAD_NEW_CONFIG;
              status             <= c_stat_clear;
            elsif(shaper_req_sysclk = '1') then -- request SWcore done
            
              shaper_req_refclk  <= '0';            
              tatsu_state        <= S_WAIT_REPEAT;
              --TODO [1]: if we have tm_time_valid high only at the end of 1sec and we have
              --          a huge time jump back... we are a bit fucked
              -- 
              if((tm_time_valid_i = '1') and (start_tm_cycles > to_unsigned(2*c_PERIOD,c_cycle_ext_width))) then
                tatsu_state        <= S_ERROR; 
                status.tm_sync_err <= '1';      
              elsif((tm_time_valid_i = '1') and (start_tm_cycles > to_unsigned(c_PERIOD,c_cycle_ext_width))) then
                start_tm_cycles  <= next_start_tm_cycles - to_unsigned(c_PERIOD,c_cycle_ext_width);
                if(tm_cycles_i = std_logic_vector(to_unsigned(c_PERIOD-1,tm_cycles_i'length))) then
                  tm_cycles_int  <= (others => '0');
                else
                  tm_cycles_int(c_cycle_width-1 downto 0)                 <= unsigned(tm_cycles_i) + 1;      
                  tm_cycles_int(c_cycle_ext_width-1 downto c_cycle_width) <= (others =>'0');
                end if;
              else
                start_tm_cycles  <= next_start_tm_cycles;
              end if;
            end if;

          --==================================================================================
          when S_WAIT_REPEAT =>  -- wait for window_repeat time (cycles)
          --==================================================================================
            
            tm_cycles_int <= tm_cycles_int + 1;
            
            if(valid_synced_refclk = '1') then
              tatsu_state        <= S_LOAD_NEW_CONFIG;
              status             <= c_stat_clear;
            elsif(tm_cycles_int = start_tm_cycles) then
                shaper_req_refclk <= '1';    
                tatsu_state      <= S_PAUSE_REQ;           
            end if;

          --==================================================================================
          when S_ERROR =>  -- something is wrong, the status bits should indicate what it is
          --==================================================================================

            if(valid_synced_refclk = '1') then
              tatsu_state         <= S_LOAD_NEW_CONFIG;
              status              <= c_stat_clear;
            else
              status.settings_err            <= '1';
              status.settings_ok             <= '0'; 
              start_tm_tai                   <= (others => '0');
              start_tm_cycles                <= (others => '0');
              shaper_req_refclk              <= '0';
            end if;

          --==================================================================================
          when others =>  --
          --==================================================================================
            tatsu_state       <= S_ERROR;
            
        end case;
      end if;
    end if;
  end process;

  shaper_request_o.req                              <= shaper_req_sysclk;
  shaper_request_o.quanta                           <= window_quanta;
  shaper_request_o.classes                          <= not prio_mask;
  shaper_request_o.ports(g_num_ports-1 downto 0)    <= port_mask;
  shaper_request_o.ports(shaper_request_o.ports'length-1 downto g_num_ports) <= (others=>'0');
  
  sync_req_refclk : gc_sync_ffs
    generic map (
      g_sync_edge => "positive")
    port map (
      clk_i    => clk_sys_i,
      rst_n_i  => '1',
      data_i   => shaper_req_refclk,
      synced_o => open,
      npulse_o => open,
      ppulse_o => shaper_req_sysclk);

  sync_valid_refclk : gc_sync_ffs
    generic map (
      g_sync_edge => "positive")
    port map (
      clk_i    => clk_ref_i,
      rst_n_i  => '1',
      data_i   => regs_fromwb.tcr_validate_o,
      synced_o => valid_synced_refclk,
      npulse_o => open,
      ppulse_o => open);

  sync_disable_refclk : gc_sync_ffs
    generic map (
      g_sync_edge => "positive")
    port map (
      clk_i    => clk_ref_i,
      rst_n_i  => '1',
      data_i   => regs_fromwb.tcr_disable_o,
      synced_o => disable_synced_refclk,
      npulse_o => open,
      ppulse_o => open);

  sync_reset_refclk : gc_sync_ffs
    generic map (
      g_sync_edge => "positive")
    port map (
      clk_i    => clk_ref_i,
      rst_n_i  => '1',
      data_i   => rst_n_i,
      synced_o => rst_synced_refclk,
      npulse_o => open,
      ppulse_o => open);

  U_WB_ADAPTER : wb_slave_adapter
    generic map (
      g_master_use_struct  => true,
      g_master_mode        => CLASSIC,
      g_master_granularity => WORD,
      g_slave_use_struct   => true,
      g_slave_mode         => g_interface_mode,
      g_slave_granularity  => g_address_granularity)
    port map (
      clk_sys_i => clk_sys_i,
      rst_n_i   => rst_n_i,
      slave_i   => wb_i,
      slave_o   => wb_o,
      master_i  => wb_out,
      master_o  => wb_in);

  U_WISHBONE_IF: tatsu_wishbone_controller
  port map(
    rst_n_i         => rst_n_i,              
    clk_sys_i       => clk_sys_i,            
    wb_adr_i        => wb_in.adr(2 downto 0),
    wb_dat_i        => wb_in.dat, 
    wb_dat_o        => wb_out.dat,
    wb_cyc_i        => wb_in.cyc, 
    wb_sel_i        => wb_in.sel, 
    wb_stb_i        => wb_in.stb, 
    wb_we_i         => wb_in.we,  
    wb_ack_o        => wb_out.ack,
    wb_stall_o      => open,      
    regs_i          => regs_towb, 
    regs_o          => regs_fromwb           
  );

  shaper_drop_at_hp_ena_o    <= regs_fromwb.tcr_drop_ena_o;

  config.start_tm_tai        <= regs_fromwb.tsr0_htai_o & regs_fromwb.tsr1_ltai_o ;  
  config.start_tm_cycles     <= regs_fromwb.tsr2_cyc_o;
  config.repeat_cycles       <= regs_fromwb.tsr3_cyc_o;
  config.window_quanta       <= regs_fromwb.tsr0_qnt_o;
  config.prio_mask           <= regs_fromwb.tsr0_prio_o;
  config.ports_mask          <= regs_fromwb.tsr4_ports_o;

  regs_towb.tcr_min_rpt_i    <= std_logic_vector(to_unsigned(c_min_repeat_cyc, regs_towb.tcr_min_rpt_i'length ));
  regs_towb.tcr_started_i    <= status.tatsu_started;
  regs_towb.tcr_delayed_i    <= status.tatsu_delayed;
  regs_towb.tcr_stg_ok_i     <= status.settings_ok;
  regs_towb.tcr_stg_err_i    <= status.settings_err;
  regs_towb.tcr_stg_err_tai_i<= status.settings_err_tai;
  regs_towb.tcr_stg_err_cyc_i<= status.settings_err_cyc;
  regs_towb.tcr_stg_err_rpt_i<= status.settings_err_rpt;
  regs_towb.tcr_stg_err_snc_i<= status.tm_sync_err;

end rtl;
