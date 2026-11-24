-- =============================================================================
-- clk_divider.vhd
-- Divisor de clock: 50 MHz → clock lento configurável
--
-- A DE2-115 tem oscilador de 50 MHz (CLOCK_50).
-- Para visualizar cada instrução no LCD precisamos de ~1 Hz.
--
-- Fórmula: divisor = F_entrada / (2 * F_saida)
--   1 Hz  → divisor = 25_000_000
--   2 Hz  → divisor = 12_500_000
--   4 Hz  → divisor = 6_250_000
--
-- O SW(1 downto 0) da DE2-115 seleciona a velocidade em tempo real:
--   "00" → 1 Hz  (melhor para leitura no LCD)
--   "01" → 2 Hz
--   "10" → 4 Hz
--   "11" → clock livre via botão (KEY[1] da DE2-115)
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity clk_divider is
    port(
        clk_50mhz : in  STD_LOGIC;           -- clock de entrada 50 MHz
        reset     : in  STD_LOGIC;           -- reset assíncrono (ativo alto)
        speed_sel : in  STD_LOGIC_VECTOR(1 downto 0); -- seletor de velocidade (SW1,SW0)
        step_btn  : in  STD_LOGIC;           -- botão de step manual (KEY[1], active-low na DE2)
        clk_out   : out STD_LOGIC            -- clock lento para o processador
    );
end entity;

architecture behave of clk_divider is

    signal counter    : UNSIGNED(24 downto 0) := (others => '0');
    signal clk_reg    : STD_LOGIC := '0';
    signal divisor    : UNSIGNED(24 downto 0);
    signal step_prev  : STD_LOGIC := '1'; -- para detectar borda de descida do botão
    signal step_pulse : STD_LOGIC := '0';

begin

    -- Seleciona divisor conforme velocidade desejada
    process(speed_sel)
    begin
        case speed_sel is
            when "00"   => divisor <= to_unsigned(24_999_999, 25); -- 1 Hz
            when "01"   => divisor <= to_unsigned(12_499_999, 25); -- 2 Hz
            when "10"   => divisor <= to_unsigned(6_249_999,  25); -- 4 Hz
            when others => divisor <= to_unsigned(24_999_999, 25); -- 1 Hz (step mode usa botão)
        end case;
    end process;

    -- Gerador de clock por contagem
    process(clk_50mhz, reset)
    begin
        if reset = '1' then
            counter  <= (others => '0');
            clk_reg  <= '0';
            step_prev <= '1';
        elsif rising_edge(clk_50mhz) then

            if speed_sel = "11" then
                -- Modo step manual: detecta borda de descida do botão (active-low)
                step_prev <= step_btn;
                if step_prev = '1' and step_btn = '0' then
                    clk_reg <= '1';    -- sobe clock por 1 ciclo
                else
                    clk_reg <= '0';
                end if;
            else
                -- Modo automático: toggle baseado no divisor
                if counter >= divisor then
                    counter <= (others => '0');
                    clk_reg <= not clk_reg;
                else
                    counter <= counter + 1;
                end if;
            end if;

        end if;
    end process;

    clk_out <= clk_reg;

end architecture;