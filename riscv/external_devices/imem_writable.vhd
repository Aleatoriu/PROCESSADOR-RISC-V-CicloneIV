library IEEE;
use IEEE.STD_LOGIC_1164.all;

package imem_pkg is
    type imem_t is array(natural range <>) of STD_LOGIC_VECTOR(31 downto 0);
end package;

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use work.imem_pkg.all;

entity imem_writable is
    generic(ABITS : positive := 7);
    port(
        clk   : in  STD_LOGIC;                            -- CLOCK_50
        we    : in  STD_LOGIC;
        waddr : in  STD_LOGIC_VECTOR(ABITS-1 downto 0);   -- linha
        wdata : in  STD_LOGIC_VECTOR(31 downto 0);
        raddr : in  STD_LOGIC_VECTOR(ABITS-1 downto 0);   -- CPU: PC[ABITS+1:2]
        rdata : out STD_LOGIC_VECTOR(31 downto 0);
        vaddr : in  STD_LOGIC_VECTOR(ABITS-1 downto 0);   -- painel do VGA
        vdata : out STD_LOGIC_VECTOR(31 downto 0)
    );
end entity;

architecture behave of imem_writable is
    signal mem : imem_t(0 to 2**ABITS - 1) := (others => x"00000013");   -- NOP
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if we = '1' then
                mem(to_integer(unsigned(waddr))) <= wdata;
            end if;
        end if;
    end process;

    rdata <= mem(to_integer(unsigned(raddr)));
    vdata <= mem(to_integer(unsigned(vaddr)));
end architecture;