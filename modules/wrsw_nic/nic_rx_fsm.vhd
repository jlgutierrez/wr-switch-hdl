-------------------------------------------------------------------------------
-- Title      : WRF Interface reception logic for WR NIC
-- Project    : WhiteRabbit Switch
-------------------------------------------------------------------------------
-- File       : nic_rx_fsm.vhd
-- Author     : Tomasz Wlostowski
-- Company    : CERN BE-Co-HT
-- Created    : 2010-11-24
-- Last update: 2012-01-19
-- Platform   : FPGA-generic
-- Standard   : VHDL
-------------------------------------------------------------------------------
-- Description: The NIC receive path state machine. Takes the packets coming to
-- the WRF sink, requests RX descriptors from RX descriptor manager and writes
-- the packet data and OOB into at specified addresses in the buffer.
-------------------------------------------------------------------------------
-- Copyright (c) 2010 Tomasz Wlostowski
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author          Description
-- 2010-11-24  1.0      twlostow        Created
-------------------------------------------------------------------------------

library IEEE;

use IEEE.std_logic_1164.all;
use IEEE.NUMERIC_STD.all;

use work.nic_constants_pkg.all;
use work.nic_descriptors_pkg.all;

use work.wr_fabric_pkg.all;
use work.nic_wbgen2_pkg.all;
use work.endpoint_private_pkg.all;


entity nic_rx_fsm is

  port (clk_sys_i : in std_logic;
        rst_n_i   : in std_logic;

-------------------------------------------------------------------------------
-- WRF sink
-------------------------------------------------------------------------------
        snk_i : in  t_wrf_sink_in;
        snk_o : out t_wrf_sink_out;

-------------------------------------------------------------------------------
-- Wishbone regs
-------------------------------------------------------------------------------           

        regs_i : in  t_nic_out_registers;
        regs_o : out t_nic_in_registers;

        irq_rcomp_o     : out std_logic;
        irq_rcomp_ack_i : in  std_logic;

-------------------------------------------------------------------------------
-- RX Descriptor Manager I/F
-------------------------------------------------------------------------------           

        -- 1 requests next available (empty) RX descriptor
        rxdesc_request_next_o : out std_logic;
        -- 1 indicates that an empty descriptor has been granted and it's available
        -- on rxdesc_current_i
        rxdesc_grant_i        : in  std_logic;
        -- currently granted RX descriptor
        rxdesc_current_i      : in  t_rx_descriptor;
        -- updated RX descriptor (with new length, error flags, timestamp, etc.)
        rxdesc_new_o          : out t_rx_descriptor;
        -- 1 requests an update of the current RX descriptor with the values
        -- given on rxdesc_new_o output
        rxdesc_write_o        : out std_logic;
        -- 1 indicates that the RX descriptor update is done
        rxdesc_write_done_i   : in  std_logic;

-------------------------------------------------------------------------------
-- Packet buffer RAM
-------------------------------------------------------------------------------

        -- 1 indicates that we'll have the memory access in the following clock
        -- cycle
        buf_grant_i : in  std_logic;
        -- buffer address, data and write enable lines.
        buf_addr_o  : out std_logic_vector(c_nic_buf_size_log2-3 downto 0);
        buf_wr_o    : out std_logic;
        buf_data_o  : out std_logic_vector(31 downto 0)
        );
end nic_rx_fsm;

architecture behavioral of NIC_RX_FSM is

  component nic_elastic_buffer
    generic (
      g_depth : integer);
    port (
      clk_sys_i : in  std_logic;
      rst_n_i   : in  std_logic;
      snk_i     : in  t_wrf_sink_in;
      snk_o     : out t_wrf_sink_out;
      fab_o     : out t_ep_internal_fabric;
      dreq_i    : in  std_logic);
  end component;


  type t_rx_fsm_state is (RX_DISABLED, RX_WAIT_SOF, RX_REQUEST_DESCRIPTOR, RX_DATA, RX_UPDATE_DESC, RX_MEM_RESYNC, RX_MEM_FLUSH);

  signal cur_rx_desc : t_rx_descriptor;

  signal state           : t_rx_fsm_state;
  signal rx_avail        : unsigned(c_nic_buf_size_log2-1 downto 0);
  signal rx_length       : unsigned(c_nic_buf_size_log2-1 downto 0);
  signal rx_dreq_mask    : std_logic;
  signal rx_rdreg_toggle : std_logic;

  signal rx_buf_addr     : unsigned(c_nic_buf_size_log2-3 downto 0);
  signal rx_buf_data     : std_logic_vector(31 downto 0);
  signal rx_is_payload   : std_logic;
  signal rx_newpacket    : std_logic;
  signal rx_newpacket_d0 : std_logic;

  signal wrf_is_payload : std_logic;
  signal wrf_terminate  : std_logic;
  signal wrf_is_oob     : std_logic;

  signal oob_sreg : std_logic_vector(2 downto 0);

  signal increase_addr : std_logic;

  signal fab_in   : t_ep_internal_fabric;
  signal fab_dreq : std_logic;
  
begin

  U_Buffer : nic_elastic_buffer
    generic map (
      g_depth => 64)
    port map (
      clk_sys_i => clk_sys_i,
      rst_n_i   => rst_n_i,
      snk_i     => snk_i,
      snk_o     => snk_o,
      fab_o     => fab_in,
      dreq_i    => fab_dreq);

  -- stupid VHDL type conversions
  buf_addr_o <= std_logic_vector(rx_buf_addr);

  buf_data_o   <= rx_buf_data;          -- so we can avoid "buffer" I/Os
  rxdesc_new_o <= cur_rx_desc;

  -- some combinatorial helpers to minimize conditions in IFs.
  wrf_is_payload <= '1' when (fab_in.addr = c_WRF_DATA)                else '0';
  wrf_is_oob     <= '1' when (fab_in.addr = c_WRF_OOB)                 else '0';
  wrf_terminate  <= '1' when (fab_in.eof = '1' or fab_in.error = '1') else '0';

-- process produces the RCOMP interrupt each time a packet has been received
  p_handle_rx_interrupt : process(clk_sys_i, rst_n_i)
  begin
    if rising_edge(clk_sys_i) then
      if rst_n_i = '0' then
        irq_rcomp_o     <= '0';
        rx_newpacket_d0 <= '0';
      else
        rx_newpacket_d0 <= rx_newpacket;
        -- we've got another packet? Trigger the IRQ
        if (rx_newpacket_d0 = '0' and rx_newpacket = '1') then
          irq_rcomp_o <= '1';
          -- host acked the interrupt?
        elsif (irq_rcomp_ack_i = '1') then
          irq_rcomp_o <= '0';
        end if;
      end if;
    end if;
  end process;


-- process produces the REC field in SR register
  p_handle_status_rec : process(clk_sys_i, rst_n_i)
  begin
    if rising_edge(clk_sys_i) then
      if rst_n_i = '0' then
        regs_o.sr_rec_i <= '0';
      else
        -- we've got a packet? Set REC to 1
        if (rx_newpacket_d0 = '0' and rx_newpacket = '1') then
          regs_o.sr_rec_i <= '1';
          -- host wrote 1 to REC bit? Clear!
        elsif (regs_i.sr_rec_o = '1' and regs_i.sr_rec_load_o = '1') then
          regs_o.sr_rec_i <= '0';
        end if;
      end if;
    end if;
  end process;

-- the big beast
  p_main_fsm : process(clk_sys_i, rst_n_i)
  begin

    if rising_edge(clk_sys_i) then
      if rst_n_i = '0' then
        state                 <= RX_DISABLED;
        rxdesc_request_next_o <= '0';
        rxdesc_write_o        <= '0';
        rx_newpacket          <= '0';
        rx_dreq_mask          <= '0';
        rx_buf_addr           <= (others => '0');
        rx_avail              <= (others => '0');
        buf_wr_o              <= '0';
        increase_addr         <= '0';
        
      else
        case state is
-------------------------------------------------------------------------------
-- State DISABLED: packet reception is OFF, all incoming traffic is dropped
-------------------------------------------------------------------------------
          when RX_DISABLED =>
            rxdesc_request_next_o <= '0';
            rx_rdreg_toggle       <= '0';

            if(regs_i.cr_rx_en_o = '1') then  -- check if the user has re-enabled
                                              -- the reception
              state        <= RX_REQUEST_DESCRIPTOR;
              rx_dreq_mask <= '0';
            else
              rx_dreq_mask <= '1';      -- enable RX, but everything goes to
                                        -- /dev/null
            end if;

-------------------------------------------------------------------------------
-- State REQUEST_DESCRIPTOR: take a next empty RX descriptor and have it ready
-- for the incoming packet
-------------------------------------------------------------------------------
          when RX_REQUEST_DESCRIPTOR =>
            rxdesc_request_next_o <= '1';  -- tell the RX desc manager that we
                                           -- need a descriptor


            if(rxdesc_grant_i = '1') then    -- RX manager assigned us a desc?
              cur_rx_desc           <= rxdesc_current_i;  -- save a local copy
              rxdesc_request_next_o <= '0';
              rx_dreq_mask          <= '1';  -- enable packet flow on WRF
              state                 <= RX_WAIT_SOF;  -- and start waiting for
                                                     -- incoming traffic
            else
              rx_dreq_mask <= '0';      -- disable RX (/dev/null)
            end if;

-------------------------------------------------------------------------------
-- State WAIT_SOF: Wait for incoming packets and initiate the reception
-------------------------------------------------------------------------------            
          when RX_WAIT_SOF =>

            -- this guy controls the memory write order. As the fabric is 16-bit and
            -- the memory is 32-bit wide, we have to write the data to the buffer
            -- with every two received words. The data is committed to the mem
            -- when rx_rdreg_toggle = 1, so if we initialize it to 1 before
            -- receiving the frame, we'll get a 2-byte gap at the beginning of
            -- the buffer (cheers, Alessandro :)
            rx_rdreg_toggle <= '1';

            -- rx_buf_addr is in 32-bit word, but the offsets and lengths in
            -- the descriptors are in bytes to make driver developer's life
            -- easier. 
            rx_buf_addr <= unsigned(cur_rx_desc.offset(c_nic_buf_size_log2-1 downto 2));

            rx_avail  <= unsigned(cur_rx_desc.len);
            rx_length <= (others => '0');

            oob_sreg     <= "001";
            rx_newpacket <= '0';

            if(fab_in.sof = '1') then   -- got a packet on WRF sink?
              state <= RX_DATA;         -- then start receiving it!
            end if;

-------------------------------------------------------------------------------
-- State RX_DATA: enormously big, messy and complicated data reception logic.
-- Does everything needed to put the received packet into the right place in
-- the buffer
-------------------------------------------------------------------------------             
            
          when RX_DATA =>

            -- increase the address 1 cycle after committing the data to the memory
            if(increase_addr = '1') then
              rx_buf_addr   <= rx_buf_addr + 1;
              increase_addr <= '0';
            end if;

            -- check if we still have enough space in the buffer
            if(fab_in.dvalid = '1' and rx_avail(rx_avail'length-1 downto 1) = to_unsigned(0, rx_avail'length-1)) then
              -- no space? drop an error
              cur_rx_desc.error <= '1';
              buf_wr_o          <= '0';
              state             <= RX_UPDATE_DESC;
            end if;

            -- got an abort/error/end-of-frame?
            if(wrf_terminate = '1') then

              -- check if the ends with an error and eventually indicate it.
              -- For the NIC, there's no difference between an abort and an RX
              -- error.
              cur_rx_desc.error <= fab_in.error;

              -- make sure the remaining packet data is written into the buffer
              state <= RX_MEM_FLUSH;

              -- disable the WRF sink data flow, so we won't get another
              -- packet before we are done with the memory flush and RX descriptor update
              rx_dreq_mask <= '0';
            end if;

            -- got a valid payload word?
            if(fab_in.dvalid = '1' and wrf_is_payload = '1') then
              -- check if it's a byte or a word transfer and update the length
              -- and buffer space counters accordingly
              if(fab_in.bytesel = '1') then
                rx_avail  <= rx_avail - 1;
                rx_length <= rx_length + 1;
              else
                rx_avail  <= rx_avail - 2;
                rx_length <= rx_length + 2;
              end if;

              -- pack two 16-bit words received from the fabric I/F into one
              -- 32-bit buffer word

              if(c_nic_buf_little_endian = false) then
                -- CPU is big-endian
                if(rx_rdreg_toggle = '0') then
                  -- 1st word
                  rx_buf_data(31 downto 16) <= fab_in.data;
                else
                  -- 2nd word
                  rx_buf_data(15 downto 0) <= fab_in.data;
                end if;
              else
                -- CPU is little endian
                
                if(rx_rdreg_toggle = '0') then
                  -- 1st word
                  rx_buf_data(15 downto 8) <= fab_in.data(7 downto 0);
                  rx_buf_data(7 downto 0)  <= fab_in.data(15 downto 8);
                else
                  -- 2nd word
                  rx_buf_data(31 downto 24) <= fab_in.data(7 downto 0);
                  rx_buf_data(23 downto 16) <= fab_in.data(15 downto 8);
                end if;
              end if;

              -- toggle the current word
              rx_rdreg_toggle <= not rx_rdreg_toggle;
            end if;


            -- got a valid OOB word?
            if(fab_in.dvalid = '1' and wrf_is_oob = '1') then

              -- oob_sreg is a shift register, where each bit represents one of
              -- 3 RX OOB words
              oob_sreg <= oob_sreg(oob_sreg'length-2 downto 0) & '0';


              -- check which word we've just received and put its contents into
              -- the descriptor

              if(oob_sreg (0) = '1') then  -- 1st OOB word
                cur_rx_desc.port_id <= '0' & fab_in.data(15 downto 11);
              end if;

              if(oob_sreg (1) = '1') then  -- 2nd OOB word
                cur_rx_desc.ts_f                <= fab_in.data(15 downto 12);
                cur_rx_desc.ts_r (27 downto 16) <= fab_in.data(11 downto 0);
              end if;

              if(oob_sreg (2) = '1') then  -- 3rd OOB word
                cur_rx_desc.ts_r(15 downto 0) <= fab_in.data;
                cur_rx_desc.got_ts            <= '1';
              end if;
            end if;


            -- we've got 2 valid word of the payload in rx_buf_data, write them to the
            -- memory
            if(rx_rdreg_toggle = '1' and fab_in.dvalid = '1' and ( wrf_is_oob = '1' or wrf_is_payload = '1') and wrf_terminate = '0') then
              increase_addr <= '1';
              buf_wr_o      <= '1';

              -- check if we are synchronized with the memory write arbiter,
              -- which grants us the memory acces every 2 clock cycles.
              -- If we're out of the "beat"  (for example when the RX traffic
              -- was throttled by the WRF source), we need to resynchronize ourselves.
              if(buf_grant_i = '1') then
                state <= RX_MEM_RESYNC;
              end if;
            else
              -- nothing to write
              buf_wr_o <= '0';
            end if;


-------------------------------------------------------------------------------
-- State "Memory resync": a "wait state" entered when the NIC tries to write the RX
-- payload, but the memory access is given for the TX path at the moment.
-------------------------------------------------------------------------------

          when RX_MEM_RESYNC =>

            -- check for error/abort conditions, they may appear even when
            -- the fabric is not accepting the data (tx_dreq_o = 0)
            if(fab_in.error = '1') then
              cur_rx_desc.error <= '1';
              state             <= RX_MEM_FLUSH;
              rx_dreq_mask      <= '0';
            else
              state <= RX_DATA;
            end if;

-------------------------------------------------------------------------------
-- State "Memory flush": flushes the remaining contents of RX data register
-- into the packet buffer after end-of-packet/error/abort
-------------------------------------------------------------------------------
          when RX_MEM_FLUSH =>
            buf_wr_o <= '1';

            -- make sure the data has been written
            if(buf_grant_i = '0') then
              state <= RX_UPDATE_DESC;
            end if;

-------------------------------------------------------------------------------
-- State "Update Descriptor": writes new length, timestamps, port ID, flags and
-- marks the descriptor as non-empty.
-------------------------------------------------------------------------------            
            
          when RX_UPDATE_DESC =>
            buf_wr_o          <= '0';
            cur_rx_desc.len   <= std_logic_vector(rx_length);
            cur_rx_desc.empty <= '0';
            rxdesc_write_o    <= '1';   -- request descriptor update

            -- update done?
            if(rxdesc_write_done_i = '1') then
              rxdesc_write_o <= '0';
              rx_newpacket   <= '1';

              -- check the RX_EN bit and eventually disable the reception.
              -- we can do that only here (disabling RX in the middle of
              -- received packet can corrupt the descriptor table).
              if(regs_i.cr_rx_en_o = '0') then
                state <= RX_DISABLED;
              else
                -- we're done - prepare another descriptor for the next
                -- incoming packet
                state <= RX_REQUEST_DESCRIPTOR;
              end if;
            end if;
          when others => null;
        end case;
      end if;
    end if;
  end process;


-------------------------------------------------------------------------------
-- helper process for producing the RX fabric data request signal (combinatorial)
-------------------------------------------------------------------------------  
  gen_rx_dreq : process(rx_dreq_mask, buf_grant_i, rx_rdreg_toggle, fab_in, regs_i)
  begin
-- make sure we don't have any incoming data when the reception is masked (e.g.
-- the NIC is updating the descriptors of finishing the memory write. 
    if(regs_i.cr_rx_en_o = '0' and state = RX_DISABLED) then
      fab_dreq <= '1';                  -- /dev/null
    elsif(fab_in.eof = '1' or fab_in.sof = '1' or rx_dreq_mask = '0') then
      fab_dreq <= '0';

-- the condition below forces the RX FSM to go into RX_MEM_RESYNC state. Don't
-- receive anything during the RESYNC cycle.
    elsif(rx_rdreg_toggle = '1' and buf_grant_i = '1' and state /= RX_WAIT_SOF) then
      fab_dreq <= '0';
    else
      fab_dreq <= '1';
    end if;
  end process;
end architecture;


