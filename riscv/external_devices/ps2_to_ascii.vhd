library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity ps2_to_ascii is
    port(
        clk        : in  STD_LOGIC;
        reset      : in  STD_LOGIC;
        scan_code  : in  STD_LOGIC_VECTOR(7 downto 0);
        data_valid : in  STD_LOGIC;
        ascii_out  : out STD_LOGIC_VECTOR(7 downto 0);
        ascii_valid: out STD_LOGIC;
        nav_up     : out STD_LOGIC;   -- pulsos de 1 ciclo (teclas de navegação)
        nav_down   : out STD_LOGIC;
        nav_home   : out STD_LOGIC;
        nav_end    : out STD_LOGIC;
        nav_pgup   : out STD_LOGIC;
        nav_pgdn   : out STD_LOGIC
    );
end entity;

architecture behave of ps2_to_ascii is

    type state_t is (IDLE, GOT_F0, GOT_E0, GOT_E0_F0);
    signal state      : state_t := IDLE;
    signal shift_held : STD_LOGIC := '0';
    signal ascii_reg  : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
    signal valid_reg  : STD_LOGIC := '0';
    signal nav_reg    : STD_LOGIC_VECTOR(5 downto 0) := "000000";  -- up,down,home,end,pgup,pgdn

    -- Scan Code Set 2 → ASCII minúsculo
    function sc_to_ascii_lower(sc : STD_LOGIC_VECTOR(7 downto 0))
        return STD_LOGIC_VECTOR is
    begin
        case sc is
            when x"1C" => return x"61"; -- a
            when x"32" => return x"62"; -- b
            when x"21" => return x"63"; -- c
            when x"23" => return x"64"; -- d
            when x"24" => return x"65"; -- e
            when x"2B" => return x"66"; -- f
            when x"34" => return x"67"; -- g
            when x"33" => return x"68"; -- h
            when x"43" => return x"69"; -- i
            when x"3B" => return x"6A"; -- j
            when x"42" => return x"6B"; -- k
            when x"4B" => return x"6C"; -- l
            when x"3A" => return x"6D"; -- m
            when x"31" => return x"6E"; -- n
            when x"44" => return x"6F"; -- o
            when x"4D" => return x"70"; -- p
            when x"15" => return x"71"; -- q
            when x"2D" => return x"72"; -- r
            when x"1B" => return x"73"; -- s
            when x"2C" => return x"74"; -- t
            when x"3C" => return x"75"; -- u
            when x"2A" => return x"76"; -- v
            when x"1D" => return x"77"; -- w
            when x"22" => return x"78"; -- x
            when x"35" => return x"79"; -- y
            when x"1A" => return x"7A"; -- z
            -- Números
            when x"45" => return x"30"; -- 0
            when x"16" => return x"31"; -- 1
            when x"1E" => return x"32"; -- 2
            when x"26" => return x"33"; -- 3
            when x"25" => return x"34"; -- 4
            when x"2E" => return x"35"; -- 5
            when x"36" => return x"36"; -- 6
            when x"3D" => return x"37"; -- 7
            when x"3E" => return x"38"; -- 8
            when x"46" => return x"39"; -- 9
            -- Símbolos úteis para assembly RISC-V
            when x"41" => return x"2C"; -- , vírgula
            when x"4E" => return x"2D"; -- - hífen/menos
            when x"55" => return x"3D"; -- = igual
            when x"29" => return x"20"; -- espaço
            when x"54" => return x"28"; -- ( parêntese esquerdo
            when x"5B" => return x"29"; -- ) parêntese direito
            -- Controle
            when x"5A" => return x"0D"; -- ENTER
            when x"66" => return x"08"; -- BACKSPACE
            when others => return x"00";
        end case;
    end function;

    -- Scan Code Set 2 → ASCII maiúsculo (com SHIFT)
    function sc_to_ascii_upper(sc : STD_LOGIC_VECTOR(7 downto 0))
        return STD_LOGIC_VECTOR is
    begin
        case sc is
            when x"1C" => return x"41"; -- A
            when x"32" => return x"42"; -- B
            when x"21" => return x"43"; -- C
            when x"23" => return x"44"; -- D
            when x"24" => return x"45"; -- E
            when x"2B" => return x"46"; -- F
            when x"34" => return x"47"; -- G
            when x"33" => return x"48"; -- H
            when x"43" => return x"49"; -- I
            when x"3B" => return x"4A"; -- J
            when x"42" => return x"4B"; -- K
            when x"4B" => return x"4C"; -- L
            when x"3A" => return x"4D"; -- M
            when x"31" => return x"4E"; -- N
            when x"44" => return x"4F"; -- O
            when x"4D" => return x"50"; -- P
            when x"15" => return x"51"; -- Q
            when x"2D" => return x"52"; -- R
            when x"1B" => return x"53"; -- S
            when x"2C" => return x"54"; -- T
            when x"3C" => return x"55"; -- U
            when x"2A" => return x"56"; -- V
            when x"1D" => return x"57"; -- W
            when x"22" => return x"58"; -- X
            when x"35" => return x"59"; -- Y
            when x"1A" => return x"5A"; -- Z
            -- Números com SHIFT
            when x"45" => return x"29"; -- )
            when x"16" => return x"21"; -- !
            when x"1E" => return x"40"; -- @
            when x"26" => return x"23"; -- #
            when x"25" => return x"24"; -- $
            when x"2E" => return x"25"; -- %
            when x"3D" => return x"26"; -- &
            when x"3E" => return x"2A"; -- *
            when x"46" => return x"28"; -- (
            -- Controle (SHIFT não muda)
            when x"5A" => return x"0D"; -- ENTER
            when x"66" => return x"08"; -- BACKSPACE
            when x"29" => return x"20"; -- espaço
            when x"41" => return x"3B"; -- ; (shift+vírgula ABNT2)
            when others => return x"00";
        end case;
    end function;

begin

    -- =========================================================================
    -- Processo único de decodificação
    -- (CORREÇÃO: segundo processo removido — causava multiple-driver em ascii_reg)
    -- =========================================================================
    process(clk, reset)
        variable ascii_new : STD_LOGIC_VECTOR(7 downto 0);
    begin
        if reset = '1' then
            state      <= IDLE;
            shift_held <= '0';
            ascii_reg  <= (others => '0');
            valid_reg  <= '0';
            nav_reg    <= "000000";

        elsif rising_edge(clk) then
            valid_reg <= '0'; -- pulso de 1 ciclo
            nav_reg   <= "000000";

            if data_valid = '1' then
                case state is

                    when IDLE =>
                        if scan_code = x"F0" then
                            state <= GOT_F0;

                        elsif scan_code = x"E0" then
                            state <= GOT_E0;

                        elsif scan_code = x"12" or scan_code = x"59" then
                            -- SHIFT esquerdo ou direito pressionado
                            shift_held <= '1';

                        else
                            -- Tecla comum: calcula o ASCII novo numa variável
                            -- ── CORREÇÃO: usa variável local para checar o valor
                            --    antes de atribuir ao sinal (evita ler valor antigo)
                            if shift_held = '1' then
                                ascii_new := sc_to_ascii_upper(scan_code);
                            else
                                ascii_new := sc_to_ascii_lower(scan_code);
                            end if;

                            if ascii_new /= x"00" then
                                ascii_reg <= ascii_new;
                                valid_reg <= '1';
                            end if;
                        end if;

                    when GOT_F0 =>
                        -- Byte após F0: tecla sendo solta → não gera ASCII
                        state <= IDLE;
                        if scan_code = x"12" or scan_code = x"59" then
                            shift_held <= '0'; -- SHIFT solto
                        end if;

                    when GOT_E0 =>
                        -- Tecla estendida (setas, etc.)
                        if scan_code = x"F0" then
                            state <= GOT_E0_F0;
                        else
                            state <= IDLE;
                            case scan_code is
                                when x"75"  => nav_reg <= "100000";  -- seta cima
                                when x"72"  => nav_reg <= "010000";  -- seta baixo
                                when x"6C"  => nav_reg <= "001000";  -- Home
                                when x"69"  => nav_reg <= "000100";  -- End
                                when x"7D"  => nav_reg <= "000010";  -- Page Up
                                when x"7A"  => nav_reg <= "000001";  -- Page Down
                                when others => null;               -- demais: ignora
                            end case;
                        end if;

                    when GOT_E0_F0 =>
                        state <= IDLE; -- ignora tecla estendida solta

                end case;
            end if;
        end if;
    end process;

    ascii_out   <= ascii_reg;
    ascii_valid <= valid_reg;
    nav_up      <= nav_reg(5);
    nav_down    <= nav_reg(4);
    nav_home    <= nav_reg(3);
    nav_end     <= nav_reg(2);
    nav_pgup    <= nav_reg(1);
    nav_pgdn    <= nav_reg(0);

end architecture;