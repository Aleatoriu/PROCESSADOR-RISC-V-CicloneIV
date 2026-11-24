library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity ps2_receiver is
    port(
        clk        : in  STD_LOGIC;
        reset      : in  STD_LOGIC;
        ps2_clk    : in  STD_LOGIC;
        ps2_dat    : in  STD_LOGIC;
        scan_code  : out STD_LOGIC_VECTOR(7 downto 0);
        data_valid : out STD_LOGIC
    );
end entity;

architecture behave of ps2_receiver is

    -- Sincronizadores de 2 estágios (evita metaestabilidade)
    signal ps2_clk_sync : STD_LOGIC_VECTOR(1 downto 0) := "11";
    signal ps2_dat_sync : STD_LOGIC_VECTOR(1 downto 0) := "11";
    signal ps2_clk_s    : STD_LOGIC;
    signal ps2_dat_s    : STD_LOGIC;

    signal ps2_clk_prev     : STD_LOGIC := '1';
    signal falling_edge_det : STD_LOGIC;

    signal shift_reg  : STD_LOGIC_VECTOR(10 downto 0) := (others => '1');
    signal bit_count  : UNSIGNED(3 downto 0) := (others => '0');

    signal valid_reg  : STD_LOGIC := '0';
    signal scan_reg   : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');

begin

    -- Sincronizadores
    process(clk, reset)
    begin
        if reset = '1' then
            ps2_clk_sync <= "11";
            ps2_dat_sync <= "11";
        elsif rising_edge(clk) then
            ps2_clk_sync <= ps2_clk_sync(0) & ps2_clk;
            ps2_dat_sync <= ps2_dat_sync(0) & ps2_dat;
        end if;
    end process;

    ps2_clk_s <= ps2_clk_sync(1);
    ps2_dat_s <= ps2_dat_sync(1);

    falling_edge_det <= ps2_clk_prev and (not ps2_clk_s);

    -- =========================================================================
    -- Receptor principal
    -- =========================================================================
    process(clk, reset)
        -- CORREÇÃO: variável captura o novo valor do shift na mesma borda
        -- (signals só atualizam na próxima borda — tarde demais para a checagem)
        variable new_shift : STD_LOGIC_VECTOR(10 downto 0);
    begin
        if reset = '1' then
            ps2_clk_prev <= '1';
            bit_count    <= (others => '0');
            shift_reg    <= (others => '1');
            scan_reg     <= (others => '0');
            valid_reg    <= '0';

        elsif rising_edge(clk) then
            ps2_clk_prev <= ps2_clk_s;
            valid_reg    <= '0';

            if falling_edge_det = '1' then

                -- Calcula o novo estado do shift register IMEDIATAMENTE via variável
                -- Novo bit vai para o topo (bit 10); os demais descem um
                new_shift := ps2_dat_s & shift_reg(10 downto 1);

                -- Salva no signal (vai atualizar na próxima borda — não importa,
                -- pois next_shift já tem o valor correto para checar agora)
                shift_reg <= new_shift;
                bit_count <= bit_count + 1;

                if bit_count = 10 then
                    -- 11ª borda: frame completo com new_shift
                    -- Layout de new_shift após 11 shifts:
                    --   [10]   = stop bit    (deve ser '1')
                    --   [9]    = paridade
                    --   [8..1] = dados d7..d0
                    --   [0]    = start bit   (deve ser '0')
                    bit_count <= (others => '0');

                    if new_shift(0) = '0' and new_shift(10) = '1' then
                        scan_reg  <= new_shift(8 downto 1);
                        valid_reg <= '1';
                    end if;
                    -- Se start/stop inválidos: frame corrompido, descarta silenciosamente
                end if;
            end if;
        end if;
    end process;

    scan_code  <= scan_reg;
    data_valid <= valid_reg;

end architecture;