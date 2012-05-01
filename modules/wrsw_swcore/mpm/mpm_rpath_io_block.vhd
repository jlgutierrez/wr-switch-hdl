library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.gencores_pkg.all;
use work.genram_pkg.all;

entity mpm_rpath_io_block is
  
  generic (
    g_num_pages            : integer;
    g_data_width           : integer;
    g_page_addr_width      : integer;
    g_page_size            : integer;
    g_partial_select_width : integer;
    g_ratio                : integer;
    g_ll_data_width        : integer;
    g_max_oob_size         : integer;
    g_min_packet_size      : integer := 32; -- words
    g_max_packet_size      : integer);

  port (
    clk_io_i   : in std_logic;
    rst_n_io_i : in std_logic;

-- Read Port Interface
    rport_d_o        : out std_logic_vector(g_data_width-1 downto 0);
    rport_dvalid_o   : out std_logic;
    rport_dlast_o    : out std_logic;
    rport_dsel_o     : out std_logic_vector(g_partial_select_width-1 downto 0);
    rport_dreq_i     : in  std_logic;
    rport_abort_i    : in  std_logic;
    rport_pg_req_o   : out std_logic;
    rport_pg_valid_i : in  std_logic;
    rport_pg_addr_i  : in  std_logic_vector(g_page_addr_width-1 downto 0);

-- Linked List Interface
    ll_req_o   : out std_logic;
    ll_grant_i : in  std_logic;
    ll_addr_o  : out std_logic_vector(g_page_addr_width-1 downto 0);
    ll_data_i  : in  std_logic_vector(g_ll_data_width  -1 downto 0);

-- Page FIFO interface
    pf_full_i     : in  std_logic;
    pf_we_o       : out std_logic;
    pf_fbm_addr_o : out std_logic_vector(f_log2_size(g_num_pages * g_page_size / g_ratio) - 1 downto 0);
    pf_pg_lines_o : out std_logic_vector(f_log2_size(g_page_size / g_ratio + 1)-1 downto 0);

-- Data FIFO interface
    df_empty_i : in  std_logic;
    df_flush_o : out std_logic;
    df_rd_o    : out std_logic;
    df_d_i     : in  std_logic_vector(g_data_width-1 downto 0)
    );

end mpm_rpath_io_block;

architecture behavioral of mpm_rpath_io_block is

  constant c_lines_per_page     : integer := g_page_size/g_ratio;
  constant c_page_lines_width   : integer := f_log2_size(c_lines_per_page + 1);
  constant c_page_size_width    : integer := f_log2_size(g_page_size + 1);
  constant c_word_count_width   : integer := f_log2_size(g_max_packet_size + 1);
  constant c_max_oob_size_width : integer := f_log2_size(g_max_oob_size + 1);
  
  function f_fast_div_pagesize
    (x : unsigned;
     y : integer) return unsigned is

    type t_div_factor is record
      adjust : integer range 0 to 15;
      mul    : integer range 0 to 4095;
      shift  : integer range 0 to 12;
    end record;

    type t_div_factor_array is array (1 to 16) of t_div_factor;

    constant c_div_factors : t_div_factor_array := (
      (0, 1, 0),                        -- ratio == 1
      (1, 1, 1),                        -- ratio == 2
      (3, 85, 8),                       -- ratio == 3
      (3, 1, 2),                        -- ratio == 4
      (5, 51, 8),                       -- ratio == 5
      (6, 341, 11),                     -- ratio == 6
      (7, 73, 9),                       -- ratio == 7
      (7, 1, 3),                        -- ratio == 8
      (9, 227, 11),                     -- ratio == 9
      (10, 409, 12),                    -- ratio == 10
      (11, 93, 10),                     -- ratio == 11
      (12, 341, 12),                    -- ratio == 12
      (13, 157, 11),                    -- ratio == 13
      (14, 73, 10),                     -- ratio == 14
      (15, 17, 8),                      -- ratio == 15
      (15, 1, 4));                      -- ratio == 16

    variable tmp    : unsigned(x'left + 12 downto 0);
    variable result : unsigned(c_page_lines_width-1 downto 0);

  begin

    tmp := (x+to_unsigned(c_div_factors(y).adjust, 4)) * to_unsigned(c_div_factors(y).mul, 12);

    return tmp(c_page_lines_width - 1 + c_div_factors(y).shift downto c_div_factors(y).shift);
  end f_fast_div_pagesize;


  type t_ll_entry is record
    valid     : std_logic;
    eof       : std_logic;
    next_page : std_logic_vector(g_page_addr_width-1 downto 0);
    dsel      : std_logic_vector(g_partial_select_width-1 downto 0);
    size      : std_logic_vector(f_log2_size(g_page_size + 1)-1 downto 0);
    oob_size  : std_logic_vector(c_max_oob_size_width   - 1 downto 0);
    oob_dsel  : std_logic_vector(g_partial_select_width - 1 downto 0);    
  end record;



  -- Page fetcher signals
  type   t_page_fetch_state is (FIRST_PAGE, NEXT_LINK, WAIT_LAST_ACK, WAIT_ACK, NASTY_WAIT);
  signal page_state : t_page_fetch_state;
  signal cur_page   : std_logic_vector(g_page_addr_width-1 downto 0);
  signal cur_ll     : t_ll_entry;
  signal fvalid_int : std_logic;

  -- Page fetch <> FIFO / output FSM signals

  -- Address of the current page
  signal fetch_pg_addr  : std_logic_vector(g_page_addr_width-1 downto 0);
  -- Number of words in the page (1 = 1 word...g_page_size-1 == full page)
  signal fetch_pg_words : unsigned(f_log2_size(g_page_size+1)-1 downto 0);
  -- Number of FBM lines used by this page (1 = 1 line, etc.)
  signal fetch_pg_lines : unsigned(c_page_lines_width-1 downto 0);
  -- Partial select bits for the last word of the packet
  signal fetch_dsel     : std_logic_vector(g_partial_select_width-1 downto 0);
  -- Is the page the last one in the current chain?
  signal fetch_last     : std_logic;
  -- Is the page the first one in the current chain?
  signal fetch_first    : std_logic;
  -- Acknowledge of the transfer on pg_addr/ast/valid/remaining/dsel lines. The
  -- fetcher will proceed with the next page/packet only after getting an ACK.
  signal fetch_ack      : std_logic;
  -- When HI, pg_addr/last/remaining/dsel contain a valid page entry.
  signal fetch_valid    : std_logic;
  -- When HI, fetcher aborts fetching the current page chain and proceeds to the
  -- next packet.
  signal fetch_abort    : std_logic;
  
  signal fetch_dsel_words  :  unsigned(f_log2_size(g_page_size+1)-1 downto 0);
  
  signal fetch_oob_dsel   : std_logic_vector(g_partial_select_width-1 downto 0);


  signal saved_dat_dsel : std_logic_vector(g_partial_select_width-1 downto 0);
  signal saved_oob_dsel : std_logic_vector(g_partial_select_width-1 downto 0);

-- Datapath signals
  signal df_we_d0      : std_logic;
  signal last_page     : std_logic;
  signal words_total   : unsigned(c_word_count_width-1 downto 0);
  signal dsel_words_total   : unsigned(c_word_count_width-1 downto 0);
  signal words_xmitted : unsigned(c_word_count_width-1 downto 0);

  signal last_int, d_valid_int, df_rd_int, d_endOfData_int : std_logic;
  signal pf_we_int                          : std_logic;

  signal ll_req_int, ll_grant_d0, ll_grant_d1 : std_logic;
  signal counters_equal : std_logic;
  signal data_dsel_valid  : std_logic;
  signal wait_first_fetched : std_logic;
  signal wait_next_valid_ll_read : std_logic;
  signal rport_pg_req  : std_logic;
  
  signal start_cnt: unsigned(f_log2_size(g_page_size+1)-1 downto 0);
  signal min_pck_size_reached : std_logic;
  
  signal d_counter_equal : std_logic;
  signal d_pre_fetch     : std_logic;
begin  -- behavioral



  
  fetch_abort <= '0';                   -- FIXME: add support for ABORT

  p_gen_page_ack : process(clk_io_i)
  begin
    if rising_edge(clk_io_i) then
      if rst_n_io_i = '0' then
        fetch_ack <= '0';
      else
        fetch_ack <= pf_we_int;
      end if;
    end if;
  end process;

  pf_we_int     <= fetch_valid and not pf_full_i;
  pf_we_o       <= pf_we_int;
  pf_fbm_addr_o <= std_logic_vector(resize(unsigned(fetch_pg_addr) * to_unsigned(c_lines_per_page, c_page_lines_width), pf_fbm_addr_o'length));
  pf_pg_lines_o <= std_logic_vector(fetch_pg_lines);

  -- ML (bugfix: dreq=LOW on one but last word caused readout problem and dlast to be HIGH
  --             when dvalid=LOW and not yet the last word)
  --counters_equal <= '1' when (words_total = words_xmitted) else '0';
  counters_equal <= '1' when (words_total = words_xmitted and rport_dreq_i = '1') else '0';
  -- ML
  data_dsel_valid  <= '1' when (dsel_words_total = words_xmitted and rport_dreq_i = '1') else '0';

  wait_next_valid_ll_read <= '1' when ((words_total <  words_xmitted+2) and 
                                       last_int   = '0'               and 
                                       page_state  /= FIRST_PAGE        and
                                       d_pre_fetch  = '0'               and
                                       fetch_first  = '0' )             else '0';
  min_pck_size_reached  <= '0' when (start_cnt < to_unsigned(g_min_packet_size, start_cnt'length ) ) else '1';
  
  
  p_count_words : process(clk_io_i)
  begin
    if rising_edge(clk_io_i) then
      if rst_n_io_i = '0' or (last_int = '1' and d_valid_int = '1') then
        -- ML : pre-fetching
        if(d_pre_fetch = '1') then
          words_total      <= resize(fetch_pg_words, words_total'length);
          dsel_words_total <= resize(fetch_dsel_words, dsel_words_total'length);          
        else
          words_total     <= (others => '0');
          dsel_words_total<= (others => '0');
        end if;
        -----
        words_xmitted   <= to_unsigned(1, words_xmitted'length);
        -- ML
        -- last_int      <= '0'; 
        d_counter_equal <= '0';
        d_endOfData_int <= '0';
      else

        if(data_dsel_valid = '1') then
          saved_dat_dsel <= fetch_dsel;
        elsif(fetch_last = '1' and fetch_ack = '1') then
          saved_oob_dsel <= fetch_oob_dsel;
        end if;

        if(df_rd_int = '1') then
          words_xmitted <= words_xmitted + 1;
        end if;

        if(fetch_ack = '1' and d_pre_fetch = '0') then
        --if(fetch_valid = '1') then
          --if(fetch_first = '1') then -- ML : prefetching
          if(fetch_first = '1' ) then
            words_total      <= resize(fetch_pg_words, words_total'length);
            dsel_words_total <= resize(fetch_dsel_words, dsel_words_total'length);
          else
            words_total      <= words_total      + fetch_pg_words;
            dsel_words_total <= dsel_words_total + fetch_dsel_words;
          end if;
        end if;

        -- ML:
        -- last_int      <= counters_equal;
        d_counter_equal    <= counters_equal;
        ---------
        
        d_endOfData_int <= data_dsel_valid;
      end if;
    end if;
  end process;
  
  -- ML: this is for the case when we got empty_i HIGH on the very last word
  last_int <= d_counter_equal and not counters_equal;
  ---------

  df_rd_int <= rport_dreq_i and not (df_empty_i or last_int or wait_first_fetched or wait_next_valid_ll_read);
  
  df_rd_o   <= df_rd_int;

  p_gen_d_valid : process(clk_io_i)
  begin
    if rising_edge(clk_io_i) then
      if rst_n_io_i = '0' then
        d_valid_int <= '0';
      else
        
        d_valid_int       <= df_rd_int;

      end if;
    end if;
  end process;

  p_gen_pre_fetch : process(clk_io_i)
  begin
    if rising_edge(clk_io_i) then
      if rst_n_io_i = '0' then
        d_pre_fetch <= '0';
      else
        
        if(fetch_last = '1' and rport_pg_valid_i = '1' and df_empty_i = '0') then
          d_pre_fetch <= '1';
        elsif(d_pre_fetch='1' and last_int = '1') then
          d_pre_fetch <= '0';
        end if;

      end if;
    end if;
  end process;



  df_flush_o <= last_int;-- counters_equal;
  
  rport_dvalid_o <= d_valid_int;

  rport_dlast_o  <= last_int;
  rport_d_o      <= df_d_i;
  rport_dsel_o   <= saved_dat_dsel when d_endOfData_int = '1' else                  -- order is important
                    saved_oob_dsel when last_int      = '1' else (others => '1'); -- first eod, then oob
  rport_pg_req_o <= rport_pg_req;
-------------------------------------------------------------------------------
-- Page fetcher logic
-------------------------------------------------------------------------------  

  -- pointer to the next page (shared with page size and partial select)
  cur_ll.next_page <= ll_data_i(g_page_addr_width-1 downto 0);
  -- 1: last page in the chain
  cur_ll.eof       <= ll_data_i(g_ll_data_width-2);
  -- 1: page is valid
  cur_ll.valid     <= ll_data_i(g_ll_data_width-1);
  -- 1: number of the words in page (1 = 1 word .. g_page_size-1 = full page)
  cur_ll.size      <= ll_data_i(c_page_size_width-1 downto 0);
  -- 1: partial select bits (number of bytes in the last word of the page. For
  -- 16-bit datapath: 0 = 1 byte, 1 = 2 bytes, etc.)
  cur_ll.dsel      <= ll_data_i(g_ll_data_width-3 downto g_ll_data_width-2-g_partial_select_width);
  
  cur_ll.oob_size  <= ll_data_i(g_ll_data_width-2-g_partial_select_width-1 downto 
                                g_ll_data_width-2-g_partial_select_width-c_max_oob_size_width);

  cur_ll.oob_dsel  <= ll_data_i(g_page_addr_width-1 downto g_page_addr_width-g_partial_select_width);

  fetch_valid <= fvalid_int and not fetch_ack;

  p_count_down_start : process(clk_io_i)
  begin
    if rising_edge(clk_io_i) then
      if rst_n_io_i = '0' or rport_pg_req = '1' then
        start_cnt <= to_unsigned(0, start_cnt'length);
      else
        if(fetch_first = '1' ) then
          start_cnt <= start_cnt + 1;
        end if;
      end if;
    end if;  
  end process;

  p_page_fsm : process(clk_io_i)
  begin
    if rising_edge(clk_io_i) then
      if rst_n_io_i = '0' then
        page_state <= FIRST_PAGE;

        fvalid_int     <= '0';
        rport_pg_req <= '0';
        ll_req_int       <= '0';
        ll_grant_d0 <= '0';
        ll_grant_d1 <= '0';
        fetch_dsel_words<= (others =>'0');
        fetch_oob_dsel  <=  (others =>'0');
        wait_first_fetched <='1';
        fetch_first     <= '0';
      else

        ll_grant_d0 <= ll_grant_i;
        ll_grant_d1 <= ll_grant_d0;

        if((cur_ll.valid = '1' or min_pck_size_reached = '1' or page_state = WAIT_ACK or page_state = WAIT_LAST_ACK) and fetch_first = '1') then
          wait_first_fetched <='0';
        elsif(fetch_first = '1' and (df_empty_i = '0' or min_pck_size_reached = '0') and  d_pre_fetch = '0') then
          wait_first_fetched <='1';
        end if;

        case page_state is
-- request the 1st page of the packet from the Read port interface. Once got
-- the 1st address, go to FIRST_LL state
          when FIRST_PAGE =>

            if(rport_pg_valid_i = '1') then
              rport_pg_req <= '0';
              cur_page       <= rport_pg_addr_i;
              ll_req_int       <= '1';
              ll_addr_o      <= rport_pg_addr_i;
              page_state     <= NEXT_LINK;
              fetch_first    <= '1';
            else
              rport_pg_req <= '1';
            end if;

-- fetch the length (or the link to the next packet) from the LL for the
-- current page
          when NEXT_LINK =>
            
            if(fetch_abort = '1') then
              page_state <= FIRST_PAGE;
              ll_req_int   <= '0';
            elsif(ll_grant_d1 = '1' and cur_ll.valid = '1') then
              cur_page  <= cur_ll.next_page;
              ll_addr_o <= cur_ll.next_page;

              if(cur_ll.eof = '1') then
                page_state     <= WAIT_LAST_ACK;
                fetch_pg_words <= unsigned(cur_ll.size);
                fetch_pg_lines <= f_fast_div_pagesize(unsigned(cur_ll.size), g_ratio);
                fetch_pg_addr  <= cur_page;
                fetch_oob_dsel <= cur_ll.oob_dsel;
                fvalid_int     <= '1';
                fetch_last     <= '1';
                fetch_dsel       <= cur_ll.dsel;
                fetch_dsel_words <= unsigned(cur_ll.size) - unsigned(cur_ll.oob_size);
              else
                page_state <= WAIT_ACK;
                
                if(unsigned(cur_ll.oob_size) /= to_unsigned(0, c_max_oob_size_width)) then
                  fetch_dsel       <= cur_ll.dsel;
                  fetch_dsel_words <= to_unsigned(g_page_size, fetch_dsel_words'length) - resize(unsigned(cur_ll.oob_size), fetch_dsel_words'length);
                else
                  fetch_dsel_words <= to_unsigned(g_page_size, fetch_pg_words'length);
                end if;

                fetch_pg_words <= to_unsigned(g_page_size, fetch_pg_words'length);
                fetch_pg_lines <= to_unsigned(c_lines_per_page, fetch_pg_lines'length);
                fetch_pg_addr  <= cur_page;
                fetch_pg_addr  <= cur_page;
                fvalid_int     <= '1';
                if(fetch_first = '1') then -- prefetching conditin
                  fetch_last     <= '1';
                else                       -- normal condition
                  fetch_last     <= '0';
                end if;
              end if;
              ll_req_int <= '0';
            else
              ll_req_int <= '1';
            end if;

          when WAIT_ACK =>
            if(fetch_abort = '1') then
              page_state <= FIRST_PAGE;
            elsif(fetch_ack = '1') then
              ll_req_int    <= '1';
              fetch_first <= '0';
              fvalid_int  <= '0';
              if(d_pre_fetch = '1' and last_int = '0') then
                page_state     <= NASTY_WAIT;
              else
                page_state <= NEXT_LINK;
              end if;
            end if;

          when WAIT_LAST_ACK =>
            if(fetch_ack = '1') then
              rport_pg_req <= '1';
              fetch_first    <= '0';
              fvalid_int     <= '0';
              page_state     <= FIRST_PAGE;
            end if;
          when NASTY_WAIT =>
            if(fetch_abort = '1') then
              page_state <= FIRST_PAGE;
              fetch_last     <= '0';
            elsif(last_int = '1') then
              page_state <= NEXT_LINK;
            end if;
        end case;
      end if;
    end if;
  end process;

  ll_req_o <= ll_req_int and not (ll_grant_i or ll_grant_d0 or ll_grant_d1);

  
end behavioral;
