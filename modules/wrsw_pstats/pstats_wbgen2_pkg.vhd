---------------------------------------------------------------------------------------
-- Title          : Wishbone slave core for WR Switch Per-Port Statistic Counters
---------------------------------------------------------------------------------------
-- File           : pstats_wbgen2_pkg.vhd
-- Author         : auto-generated by wbgen2 from wrsw_pstats.wb
-- Created        : Tue Jun 24 15:56:25 2014
-- Standard       : VHDL'87
---------------------------------------------------------------------------------------
-- THIS FILE WAS GENERATED BY wbgen2 FROM SOURCE FILE wrsw_pstats.wb
-- DO NOT HAND-EDIT UNLESS IT'S ABSOLUTELY NECESSARY!
---------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.wbgen2_pkg.all;

package pstats_wbgen2_pkg is
  
  
  -- Input registers (user design -> WB slave)
  
  type t_pstats_in_registers is record
    cr_rd_en_i                               : std_logic;
    cr_rd_irq_i                              : std_logic;
    l1_cnt_val_i                             : std_logic_vector(31 downto 0);
    l2_cnt_val_i                             : std_logic_vector(31 downto 0);
    info_ver_i                               : std_logic_vector(7 downto 0);
    info_cpw_i                               : std_logic_vector(7 downto 0);
    info_cpp_i                               : std_logic_vector(15 downto 0);
    end record;
  
  constant c_pstats_in_registers_init_value: t_pstats_in_registers := (
    cr_rd_en_i => '0',
    cr_rd_irq_i => '0',
    l1_cnt_val_i => (others => '0'),
    l2_cnt_val_i => (others => '0'),
    info_ver_i => (others => '0'),
    info_cpw_i => (others => '0'),
    info_cpp_i => (others => '0')
    );
    
    -- Output registers (WB slave -> user design)
    
    type t_pstats_out_registers is record
      cr_rd_en_o                               : std_logic;
      cr_rd_en_load_o                          : std_logic;
      cr_rd_irq_o                              : std_logic;
      cr_rd_irq_load_o                         : std_logic;
      cr_port_o                                : std_logic_vector(4 downto 0);
      cr_addr_o                                : std_logic_vector(4 downto 0);
      end record;
    
    constant c_pstats_out_registers_init_value: t_pstats_out_registers := (
      cr_rd_en_o => '0',
      cr_rd_en_load_o => '0',
      cr_rd_irq_o => '0',
      cr_rd_irq_load_o => '0',
      cr_port_o => (others => '0'),
      cr_addr_o => (others => '0')
      );
    function "or" (left, right: t_pstats_in_registers) return t_pstats_in_registers;
    function f_x_to_zero (x:std_logic) return std_logic;
    function f_x_to_zero (x:std_logic_vector) return std_logic_vector;
end package;

package body pstats_wbgen2_pkg is
function f_x_to_zero (x:std_logic) return std_logic is
begin
if(x = 'X' or x = 'U') then
return '0';
else
return x;
end if; 
end function;
function f_x_to_zero (x:std_logic_vector) return std_logic_vector is
variable tmp: std_logic_vector(x'length-1 downto 0);
begin
for i in 0 to x'length-1 loop
if(x(i) = 'X' or x(i) = 'U') then
tmp(i):= '0';
else
tmp(i):=x(i);
end if; 
end loop; 
return tmp;
end function;
function "or" (left, right: t_pstats_in_registers) return t_pstats_in_registers is
variable tmp: t_pstats_in_registers;
begin
tmp.cr_rd_en_i := f_x_to_zero(left.cr_rd_en_i) or f_x_to_zero(right.cr_rd_en_i);
tmp.cr_rd_irq_i := f_x_to_zero(left.cr_rd_irq_i) or f_x_to_zero(right.cr_rd_irq_i);
tmp.l1_cnt_val_i := f_x_to_zero(left.l1_cnt_val_i) or f_x_to_zero(right.l1_cnt_val_i);
tmp.l2_cnt_val_i := f_x_to_zero(left.l2_cnt_val_i) or f_x_to_zero(right.l2_cnt_val_i);
tmp.info_ver_i := f_x_to_zero(left.info_ver_i) or f_x_to_zero(right.info_ver_i);
tmp.info_cpw_i := f_x_to_zero(left.info_cpw_i) or f_x_to_zero(right.info_cpw_i);
tmp.info_cpp_i := f_x_to_zero(left.info_cpp_i) or f_x_to_zero(right.info_cpp_i);
return tmp;
end function;
end package body;
