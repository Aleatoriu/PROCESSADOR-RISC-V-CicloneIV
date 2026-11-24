library IEEE;
use IEEE.STD_LOGIC_1164.all;
use STD.TEXTIO.all;
use IEEE.NUMERIC_STD.all; -- Opção 1

entity dmem is -- data memory
  port(clk, we: in  STD_LOGIC;
       a, wd:   in  STD_LOGIC_VECTOR(31 downto 0);
       rd:      out STD_LOGIC_VECTOR(31 downto 0));
end;

architecture behave of dmem is
  type ramtype is array (63 downto 0) of STD_LOGIC_VECTOR(31 downto 0);
  -- Inicializamos com zeros para evitar lixo de memória
  signal mem: ramtype := (others => (others => '0')); 
begin
  process(clk)
  begin
    if rising_edge(clk) then
      if we = '1' then
        mem(to_integer(unsigned(a(7 downto 2)))) <= wd;
      end if;
    end if;
  end process;

  -- Leitura assíncrona (comum em memórias de dados de ciclo único)
  -- Se o seu projeto exigir leitura síncrona, coloque esta linha dentro do process
  rd <= mem(to_integer(unsigned(a(7 downto 2))));
end architecture;
