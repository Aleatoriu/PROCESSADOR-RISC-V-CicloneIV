library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity keyboard_buffer is
    port(
        clk        : in  STD_LOGIC;  -- 50 MHz
        reset      : in  STD_LOGIC;  -- reset ativo alto
        -- Entrada do teclado (do ps2_to_ascii)
        ascii_in   : in  STD_LOGIC_VECTOR(7 downto 0);
        ascii_valid: in  STD_LOGIC;  -- '1' por 1 ciclo quando ascii_in é válido
        -- Para o asm_parser (snapshot após ENTER)
        line_buf   : out STD_LOGIC_VECTOR(159 downto 0); -- 20 chars
        line_len   : out UNSIGNED(4 downto 0);           -- 0..20
        parse_en   : out STD_LOGIC;                       -- pulso de 1 ciclo
        -- Para o VGA (conteúdo atual sendo digitado, 20 chars, e quantos são)
        live_buf   : out STD_LOGIC_VECTOR(159 downto 0); -- char0 em 159:152
        live_len   : out UNSIGNED(4 downto 0)            -- 0..20 (posição do cursor)
    );
end entity;

architecture behave of keyboard_buffer is

    type buf_t is array(0 to 19) of STD_LOGIC_VECTOR(7 downto 0);

    -- Buffer de entrada atual (o que o usuário está digitando)
    signal buf      : buf_t := (others => x"20");
    signal len_reg  : UNSIGNED(4 downto 0) := (others => '0');

    -- Snapshot capturado no ENTER (entregue ao parser)
    signal latch_buf : buf_t := (others => x"20");
    signal latch_len : UNSIGNED(4 downto 0) := (others => '0');

    signal pen_reg   : STD_LOGIC := '0';

    -- Atraso ENTER -> parse_en
    constant PARSE_DLY_BITS : natural := 10;  -- 2**10 = 1024 ciclos = 20,48 us
    constant DLY_MAX : unsigned(PARSE_DLY_BITS-1 downto 0) := (others => '1');
    signal dly_cnt   : unsigned(PARSE_DLY_BITS-1 downto 0) := (others => '0');
    signal dly_run   : STD_LOGIC := '0';

begin

    process(clk, reset)
    begin
        if reset = '1' then
            buf       <= (others => x"20");
            latch_buf <= (others => x"20");
            len_reg   <= (others => '0');
            latch_len <= (others => '0');
            pen_reg   <= '0';
            dly_cnt   <= (others => '0');
            dly_run   <= '0';

        elsif rising_edge(clk) then
            pen_reg <= '0'; -- pulso de 1 ciclo

            -- ─────────────────────────────────────────────────────────────
            -- Contador de atraso: parse_en só sobe com line_buf estável
            -- ─────────────────────────────────────────────────────────────
            if dly_run = '1' then
                if dly_cnt = DLY_MAX then
                    dly_run <= '0';
                    pen_reg <= '1';
                else
                    dly_cnt <= dly_cnt + 1;
                end if;
            end if;

            if ascii_valid = '1' then

                case ascii_in is

                    -- ENTER (0x0D): congela snapshot, arma o atraso, limpa buf
                    when x"0D" =>
                        if dly_run = '0' then
                            latch_buf <= buf;
                            latch_len <= len_reg;
                            dly_cnt   <= (others => '0');
                            dly_run   <= '1';
                            buf       <= (others => x"20");
                            len_reg   <= (others => '0');
                        end if;

                    -- BACKSPACE (0x08): apaga último caractere
                    when x"08" =>
                        if len_reg > 0 then
                            buf(to_integer(len_reg) - 1) <= x"20";
                            len_reg <= len_reg - 1;
                        end if;

                    -- Qualquer outro char não-nulo: append se houver espaço
                    when others =>
                        if ascii_in /= x"00" and len_reg < 20 then
                            buf(to_integer(len_reg)) <= ascii_in;
                            len_reg                  <= len_reg + 1;
                        end if;

                end case;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- Saídas
    -- =========================================================================
    parse_en <= pen_reg;
    line_len <= latch_len;

    gen_line_buf: for i in 0 to 19 generate
        line_buf((19-i)*8+7 downto (19-i)*8) <= latch_buf(i);
    end generate;

    gen_live: for i in 0 to 19 generate
        live_buf((19-i)*8+7 downto (19-i)*8) <= buf(i);
    end generate;
    live_len <= len_reg;

end architecture;