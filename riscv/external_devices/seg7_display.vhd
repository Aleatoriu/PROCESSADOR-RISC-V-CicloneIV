-- =============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.all;

entity seg7_display is
    port(
        -- Valor a mostrar nos 8 displays (tipicamente PC ou ALUResult)
        value    : in  STD_LOGIC_VECTOR(31 downto 0);
        -- Saídas para os 8 displays HEX7..HEX0 (active-low, 7 bits cada)
        HEX0     : out STD_LOGIC_VECTOR(6 downto 0);
        HEX1     : out STD_LOGIC_VECTOR(6 downto 0);
        HEX2     : out STD_LOGIC_VECTOR(6 downto 0);
        HEX3     : out STD_LOGIC_VECTOR(6 downto 0);
        HEX4     : out STD_LOGIC_VECTOR(6 downto 0);
        HEX5     : out STD_LOGIC_VECTOR(6 downto 0);
        HEX6     : out STD_LOGIC_VECTOR(6 downto 0);
        HEX7     : out STD_LOGIC_VECTOR(6 downto 0)
    );
end entity;

architecture struct of seg7_display is

    component seg7_encoder
        port(
            nibble : in  STD_LOGIC_VECTOR(3 downto 0);
            seg    : out STD_LOGIC_VECTOR(6 downto 0)
        );
    end component;

begin
    -- HEX0 = bits 3..0   (nibble menos significativo)
    d0: seg7_encoder port map(nibble => value(3  downto 0),  seg => HEX0);
    d1: seg7_encoder port map(nibble => value(7  downto 4),  seg => HEX1);
    d2: seg7_encoder port map(nibble => value(11 downto 8),  seg => HEX2);
    d3: seg7_encoder port map(nibble => value(15 downto 12), seg => HEX3);
    d4: seg7_encoder port map(nibble => value(19 downto 16), seg => HEX4);
    d5: seg7_encoder port map(nibble => value(23 downto 20), seg => HEX5);
    d6: seg7_encoder port map(nibble => value(27 downto 24), seg => HEX6);
    -- HEX7 = bits 31..28 (nibble mais significativo)
    d7: seg7_encoder port map(nibble => value(31 downto 28), seg => HEX7);

end architecture;