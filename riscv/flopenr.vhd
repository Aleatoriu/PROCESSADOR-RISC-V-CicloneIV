library IEEE;
use IEEE.STD_LOGIC_1164.all;

entity flopenr is
  generic(width: integer);
  port(clk, reset, en: in  STD_LOGIC;
       d:              in  STD_LOGIC_VECTOR(width-1 downto 0);
       q:              out STD_LOGIC_VECTOR(width-1 downto 0));
end;
 
architecture asynchronous of flopenr is
begin
  process(clk, reset) begin
    if reset='1'    then                      q <= (others => '0');
    elsif rising_edge(clk) and en='1' then    q <= d;
    end if;
  end process;
end;

library IEEE;
use IEEE.STD_LOGIC_1164.all;

entity mux2 is -- two-input multiplexer
  generic(width: integer :=8);
  port(d0, d1: in  STD_LOGIC_VECTOR(width-1 downto 0);
       s:      in  STD_LOGIC;
       y:      out STD_LOGIC_VECTOR(width-1 downto 0));
end;

architecture behave of mux2 is
begin
  y <= d1 when s='1' else d0;
end;