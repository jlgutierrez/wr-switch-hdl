library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.gencores_pkg.all;
use work.genram_pkg.all;

entity mpm_rpath_io_block is
  
  generic (
    g_data_width           : integer;
    g_page_addr_width      : integer;
    g_page_size            : integer;
    g_partial_select_width : integer;
    g_ratio                : integer;
    g_max_packet_size      : integer);

  port (
    clk_io_i : in std_logic;
    rst_n_io_i  : in std_logic;

-- Read Port Interface
    rport_d_o        : out std_logic_vector(g_page_addr_width-1 downto 0);
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
    ll_data_i  : in  std_logic_vector(g_page_addr_width + 1 downto 0);

-- Page FIFO interface
    pf_full_i     : in  std_logic;
    pf_we_o       : out std_logic;
    pf_pg_addr_o  : out std_logic_vector(g_page_addr_width-1 downto 0);
    pf_pg_lines_o : out std_logic_vector(f_log2_size(g_page_size / g_ratio)-1 downto 0);

-- Data FIFO interface
    df_empty_i : in  std_logic;
    df_flush_o : out std_logic;
    df_rd_o    : out std_logic;
    df_d_i     : in  std_logic_vector(g_data_width-1 downto 0)
    );

end mpm_rpath_io_block;

architecture behavioral of mpm_rpath_io_block is

  constant c_lines_per_page   : integer := g_page_size/g_ratio;
  constant c_page_lines_width : integer := f_log2_size(c_lines_per_page + 1);
  constant c_page_size_width  : integer := f_log2_size(g_page_size + 1);
  constant c_word_count_width : integer := f_log2_size(g_max_packet_size + 1);

  function f_fast_div_pagesize
    (x : unsigned;
     y : integer) return unsigned is

    type t_div_factor is record
      inc   : boolean;
      mul   : integer;
      shift : integer;
    end record;

    type t_div_factor_array is array (1 to 10) of t_div_factor;

    constant c_div_factors : t_div_factor_array :=
      ((false, 1, 0),
       (false, 1, 1),
       (true, 85, 8),
       (false, 1, 2),
       (true, 51, 8),
       (true, 85, 9),
       (true, 73, 9),
       (false, 1, 3),
       (true, 227, 11),
       (true, 51, 9));

    variable tmp    : unsigned(x'left + 11 downto 0);
    variable result : unsigned(c_page_lines_width-1 downto 0);

  begin

    if(c_div_factors(y).inc) then
      tmp := (x+1) * to_unsigned(c_div_factors(y).mul, 11);
    else
      tmp := x * to_unsigned(c_div_factors(y).mul, 11);
    end if;

    return tmp(c_page_lines_width - 1 + c_div_factors(y).shift downto c_div_factors(y).shift);
  end f_fast_div_pagesize;


  type t_ll_entry is record
    valid     : std_logic;
    eof       : std_logic;
    next_page : std_logic_vector(g_page_addr_width-1 downto 0);
    dsel      : std_logic_vector(g_partial_select_width-1 downto 0);
    size      : std_logic_vector(f_log2_size(g_page_size)-1 downto 0);
  end record;



  -- Page fetcher signals
  type   t_page_fetch_state is (FIRST_PAGE, NEXT_LINK, WAIT_LAST_ACK, WAIT_ACK);
  signal page_state : t_page_fetch_state;
  signal cur_page   : std_logic_vector(g_page_addr_width-1 downto 0);
  signal cur_ll     : t_ll_entry;

  -- Page fetch <> FIFO / output FSM signals

  -- Address of the current page
  signal fetch_pg_addr  : std_logic_vector(g_page_addr_width-1 downto 0);
  -- Number of words in the page (1 = 1 word...g_page_size-1 == full page)
  signal fetch_pg_words : unsigned(c_page_lines_width-1 downto 0);
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

  signal saved_dsel : std_logic_vector(g_partial_select_width-1 downto 0);

-- Datapath signals
  signal df_we_d0      : std_logic;
  signal last_page     : std_logic;
  signal words_total   : unsigned(c_word_count_width-1 downto 0);
  signal words_xmitted : unsigned(c_word_count_width-1 downto 0);

  signal d_last_int, d_valid_int, df_rd_int : std_logic;
  signal pf_we_int : std_logic;
  
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
  pf_we_o <= pf_we_int;
  pf_pg_addr_o  <= fetch_pg_addr;
  pf_pg_lines_o <= std_logic_vector(fetch_pg_lines);

  p_count_words : process(clk_io_i)
  begin
    if rising_edge(clk_io_i) then
      if rst_n_io_i = '0' or (d_last_int = '1' and d_valid_int = '1') then
        words_total   <= (others => '0');
        words_xmitted <= to_unsigned(1, words_xmitted'length);
      else

        if(fetch_last = '1' and fetch_ack = '1') then
          saved_dsel <= fetch_dsel;
        end if;

        if(df_rd_int = '1') then
          words_xmitted <= words_xmitted + 1;
        end if;

        if(fetch_ack = '1') then
          if(fetch_first = '1') then
            words_total <= fetch_pg_words;
          else
            words_total <= words_total + fetch_pg_words;
          end if;
        end if;
      end if;
    end if;
  end process;

  d_last_int <= '1' when (words_total = words_xmitted) else '0';


  df_rd_int <= rport_dreq_i and not df_empty_i;
  df_rd_o   <= df_rd_int;

  p_gen_d_valid : process(clk_io_i)
  begin
    if rising_edge(clk_io_i) then
      if rst_n_io_i = '0' then
        d_valid_int <= '0';
      else
        d_valid_int <= df_rd_int;
      end if;
    end if;
  end process;

  df_flush_o <= df_rd_int and d_last_int;

  rport_dvalid_o <= d_valid_int;
  rport_dlast_o  <= d_last_int;
  rport_d_o      <= df_d_i;
  rport_dsel_o <= saved_dsel when (words_total = words_xmitted) else (others => '1');
  

-------------------------------------------------------------------------------
-- Page fetcher logic
-------------------------------------------------------------------------------  

  -- pointer to the next page (shared with page size and partial select)
  cur_ll.next_page <= ll_data_i(g_page_addr_width-1 downto 0);
  -- 1: last page in the chain
  cur_ll.eof       <= ll_data_i(g_page_addr_width);
  -- 1: page is valid
  cur_ll.valid     <= ll_data_i(g_page_addr_width+1);
  -- 1: number of the words in page (1 = 1 word .. g_page_size-1 = full page)
  cur_ll.size      <= ll_data_i(c_page_size_width-1 downto 0);
  -- 1: partial select bits (number of bytes in the last word of the page. For
  -- 16-bit datapath: 0 = 1 byte, 1 = 2 bytes, etc.)
  cur_ll.dsel      <= ll_data_i(g_page_addr_width-1 downto g_page_addr_width-g_partial_select_width);

  p_page_fsm : process(clk_io_i)
  begin
    if rising_edge(clk_io_i) then
      if rst_n_io_i = '0' then
        page_state <= FIRST_PAGE;

        fetch_valid    <= '0';
        rport_pg_req_o <= '0';
        ll_req_o       <= '0';

      else
        case page_state is
-- request the 1st page of the packet from the Read port interface. Once got
-- the 1st address, go to FIRST_LL state
          when FIRST_PAGE =>

            if(rport_pg_valid_i = '1') then
              rport_pg_req_o <= '0';
              cur_page       <= rport_pg_addr_i;
              ll_req_o       <= '1';
              ll_addr_o      <= rport_pg_addr_i;
              page_state     <= NEXT_LINK;
              fetch_first    <= '1';
            else
              rport_pg_req_o <= '1';
            end if;

-- fetch the length (or the link to the next packet) from the LL for the
-- current page
          when NEXT_LINK =>
            if(fetch_abort = '1') then
              page_state <= FIRST_PAGE;
              ll_req_o   <= '0';
            elsif(ll_grant_i = '1' and cur_ll.valid = '1') then
              cur_page <= cur_ll.next_page;

              if(cur_ll.eof = '1') then
                page_state     <= WAIT_LAST_ACK;
                fetch_pg_words <= unsigned(cur_ll.size);
                fetch_pg_lines <= f_fast_div_pagesize(unsigned(cur_ll.size), g_ratio);
                fetch_dsel     <= cur_ll.dsel;
                fetch_valid    <= '1';
                fetch_last     <= '1';
              else
                page_state    <= WAIT_ACK;
                fetch_pg_addr <= cur_page;
                fetch_valid   <= '1';
                fetch_last    <= '0';
              end if;
              ll_req_o <= '0';
            else
              ll_req_o <= '1';
            end if;

          when WAIT_ACK =>
            if(fetch_abort = '1') then
              page_state <= FIRST_PAGE;
            elsif(fetch_ack = '1') then
              ll_req_o    <= '1';
              fetch_first <= '0';
              page_state  <= NEXT_LINK;
            end if;

          when WAIT_LAST_ACK =>
            if(fetch_ack = '1') then
              rport_pg_req_o <= '1';
              fetch_first    <= '0';
              page_state     <= FIRST_PAGE;
            end if;
            
        end case;
      end if;
    end if;
  end process;


end behavioral;
