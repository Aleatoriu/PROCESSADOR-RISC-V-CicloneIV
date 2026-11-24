library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity clk_divider is
    port(
        clk_50mhz : in  STD_LOGIC;
        reset     : in  STD_LOGIC;
        enable    : in  STD_LOGIC;
        speed_sel : in  STD_LOGIC_VECTOR(1 downto 0);
        step_btn  : in  STD_LOGIC;   -- KEY[1] active-low
        clk_out   : out STD_LOGIC
    );
end entity;

architecture behave of clk_divider is

    -- ── Contador de frequência automática ─────────────────────────────────────
    signal counter  : unsigned(24 downto 0) := (others => '0');
    signal clk_reg  : STD_LOGIC := '0';

    -- ── Debounce para o modo step ─────────────────────────────────────────────
    signal btn_prev  : STD_LOGIC := '1';
    signal deb_cnt   : unsigned(17 downto 0) := (others => '0');
    -- 250.000 ciclos de CLOCK_50 = 5ms de debounce (2^18 = 262.144 > 250.000) ✓

    type step_t is (IDLE, PULSING, DEBOUNCING);
    signal step_state : step_t := IDLE;

begin

    process(clk_50mhz, reset)
    begin
        if reset = '1' then
            counter    <= (others => '0');
            clk_reg    <= '0';
            btn_prev   <= '1';
            deb_cnt    <= (others => '0');
            step_state <= IDLE;

        elsif rising_edge(clk_50mhz) then

            btn_prev <= step_btn;   -- amostra o botão a cada ciclo

            -- ── Processador desabilitado (SW[2]=0) ───────────────────────────
            if enable = '0' then
                clk_reg    <= '0';
                counter    <= (others => '0');
                deb_cnt    <= (others => '0');
                step_state <= IDLE;

            -- ── Modo automático ───────────────────────────────────────────────
            -- Ao entrar no modo auto: resetar estado do step
            elsif speed_sel /= "11" then
                step_state <= IDLE;
                deb_cnt    <= (others => '0');

                if speed_sel = "00" then
                   
                    if counter >= 24999999 then
                        counter <= (others => '0');
                        clk_reg <= not clk_reg;
                    else
                        counter <= counter + 1;
                    end if;

                elsif speed_sel = "01" then
                    -- 2 Hz: toggle a cada 12.500.000 ciclos
                    if counter >= 12499999 then
                        counter <= (others => '0');
                        clk_reg <= not clk_reg;
                    else
                        counter <= counter + 1;
                    end if;

                else
                    -- 4 Hz (speed_sel = "10"): toggle a cada 6.250.000 ciclos
                    if counter >= 6249999 then
                        counter <= (others => '0');
                        clk_reg <= not clk_reg;
                    else
                        counter <= counter + 1;
                    end if;

                end if;

            -- ── Modo step com debounce ────────────────────────────────────────
            else
                counter <= (others => '0');   -- não usa contador de frequência

                case step_state is

                    when IDLE =>
                        -- Aguarda borda de descida em KEY[1] (active-low)
                        -- btn_prev='1' (solto) e step_btn='0' (pressionado)
                        clk_reg <= '0';
                        if btn_prev = '1' and step_btn = '0' then
                            clk_reg    <= '1';      -- gera pulso alto
                            step_state <= PULSING;
                        end if;

                    when PULSING =>
                        -- Encerra o pulso após 1 ciclo de CLOCK_50 (20ns)
                        -- Inicia o período de debounce para ignorar bounces
                        clk_reg    <= '0';
                        deb_cnt    <= to_unsigned(249999, 18);
                        step_state <= DEBOUNCING;

                    when DEBOUNCING =>
                        -- Ignora qualquer transição em KEY[1] durante 5ms
                        clk_reg <= '0';
                        if deb_cnt > 0 then
                            deb_cnt <= deb_cnt - 1;
                        else
                            step_state <= IDLE;   -- pronto para próxima pressão
                        end if;

                end case;

            end if;
        end if;
    end process;

    clk_out <= clk_reg;

end architecture;