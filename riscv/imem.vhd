library IEEE;
use IEEE.STD_LOGIC_1164.all;
use STD.TEXTIO.all;
use IEEE.NUMERIC_STD.all; 
use ieee.std_logic_textio.all;

entity imem is -- instruction memory
  port(a:  in  STD_LOGIC_VECTOR(31 downto 0);
       rd: out STD_LOGIC_VECTOR(31 downto 0));
end;

architecture behave of imem is
  type ramtype is array(63 downto 0) of STD_LOGIC_VECTOR(31 downto 0);

  -- initialize memory from file
  impure function init_ram_hex return ramtype is
    file text_file : text open read_mode is "riscvtest.txt";
    variable text_line : line;
    variable ram_content : ramtype;
  begin
    -- Inicializa todo o array com zeros primeiro (limpo e seguro)
    for i in 0 to 63 loop 
      ram_content(i) := (others => '0');
    end loop;

    -- Usa um loop FOR fixo em vez de WHILE
    -- Isso garante ao Quartus que o loop não passará de 64 iterações
    for i in 0 to 63 loop
      if not endfile(text_file) then
        readline(text_file, text_line);
        if text_line'length > 0 then
          hread(text_line, ram_content(i));
        end if;
      else
        exit; -- Sai do loop se o arquivo acabar antes de chegar em 63
      end if;
    end loop;
      
    return ram_content;
  end function;
    
  signal mem : ramtype := init_ram_hex;
    
begin
  -- Leitura da memória (combinacional)
  -- Usamos unsigned para o cast (Opção 1)
  process(a, mem) begin
    -- Garante que o endereço não aponte para fora do array de 64 palavras
    -- a(7 downto 2) mapeia os bits de endereço para o range 0-63
    rd <= mem(to_integer(unsigned(a(7 downto 2))));
  end process;

end architecture;