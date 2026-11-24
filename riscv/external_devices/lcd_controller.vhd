library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity lcd_controller is
    port(
        clk      : in  STD_LOGIC;                      -- 50 MHz
        reset    : in  STD_LOGIC;
        line1    : in  STD_LOGIC_VECTOR(127 downto 0); -- 16 chars, MSB=char0
        line2    : in  STD_LOGIC_VECTOR(127 downto 0);
        LCD_DATA : out STD_LOGIC_VECTOR(7 downto 0);
        LCD_EN   : out STD_LOGIC;
        LCD_RS   : out STD_LOGIC;
        LCD_RW   : out STD_LOGIC;
        LCD_ON   : out STD_LOGIC;
        LCD_BLON : out STD_LOGIC
    );
end entity;

architecture behave of lcd_controller is

    constant C_PW_ON   : natural := 2_500_000;
    constant C_F1      : natural :=   250_000;
    constant C_F2      : natural :=    10_000;
    constant C_CMD     : natural :=     5_000;
    constant C_CLEAR   : natural :=   150_000;
    constant C_SETUP   : natural :=        25;
    constant C_EN_HI   : natural :=        50;
    constant C_RST_MIN : natural :=         8;

    type state_t is (
        PW_WAIT,
        TX_SETUP, TX_EN_HI, TX_EN_LO,
        I_F1, I_F2, I_F3, I_F4, I_DOFF, I_CLR, I_ENT, I_DON,
        IDLE, WR_L1H, WR_L1D, WR_L2H, WR_L2D
    );

    signal state   : state_t := PW_WAIT;
    signal next_st : state_t := I_F1;
    signal counter : unsigned(21 downto 0) := (others => '0');
    signal col     : unsigned(3 downto 0)  := (others => '0');

    signal tx_rs    : STD_LOGIC := '0';
    signal tx_data  : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
    signal tx_delay : unsigned(21 downto 0) := (others => '0');

    signal r_data : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
    signal r_en   : STD_LOGIC := '0';
    signal r_rs   : STD_LOGIC := '0';

    -- cópia do texto que está sendo (ou foi) escrito no LCD
    signal snap1 : STD_LOGIC_VECTOR(127 downto 0) := (others => '0');
    signal snap2 : STD_LOGIC_VECTOR(127 downto 0) := (others => '0');
    signal dirty : STD_LOGIC := '1';   -- força a primeira escrita

    signal cur_l1_s : STD_LOGIC_VECTOR(7 downto 0);
    signal cur_l2_s : STD_LOGIC_VECTOR(7 downto 0);

    -- reset sincronizado e filtrado
    signal rst_s1, rst_s2 : STD_LOGIC := '0';
    signal rst_cnt        : unsigned(3 downto 0) := (others => '0');
    signal rst_i          : STD_LOGIC;

begin

    -- =========================================================================
    -- Saídas fixas
    -- =========================================================================
    LCD_RW   <= '0';
    LCD_ON   <= '1';
    LCD_BLON <= '1';
    LCD_DATA <= r_data;
    LCD_EN   <= r_en;
    LCD_RS   <= r_rs;

    -- =========================================================================
    -- Reset: 2 flip-flops de sincronização + exige 8 ciclos seguidos em '1'
    -- =========================================================================
    process(clk)
    begin
        if rising_edge(clk) then
            rst_s1 <= reset;
            rst_s2 <= rst_s1;
            if rst_s2 = '1' then
                if rst_cnt /= C_RST_MIN then
                    rst_cnt <= rst_cnt + 1;
                end if;
            else
                rst_cnt <= (others => '0');
            end if;
        end if;
    end process;
    rst_i <= '1' when rst_cnt = C_RST_MIN else '0';

    process(col, snap1)
        variable raw : STD_LOGIC_VECTOR(7 downto 0);
    begin
        case col is
            when "0000" => raw := snap1(127 downto 120);
            when "0001" => raw := snap1(119 downto 112);
            when "0010" => raw := snap1(111 downto 104);
            when "0011" => raw := snap1(103 downto  96);
            when "0100" => raw := snap1( 95 downto  88);
            when "0101" => raw := snap1( 87 downto  80);
            when "0110" => raw := snap1( 79 downto  72);
            when "0111" => raw := snap1( 71 downto  64);
            when "1000" => raw := snap1( 63 downto  56);
            when "1001" => raw := snap1( 55 downto  48);
            when "1010" => raw := snap1( 47 downto  40);
            when "1011" => raw := snap1( 39 downto  32);
            when "1100" => raw := snap1( 31 downto  24);
            when "1101" => raw := snap1( 23 downto  16);
            when "1110" => raw := snap1( 15 downto   8);
            when others => raw := snap1(  7 downto   0);
        end case;
        if raw = x"00" then cur_l1_s <= x"20"; else cur_l1_s <= raw; end if;
    end process;

    process(col, snap2)
        variable raw : STD_LOGIC_VECTOR(7 downto 0);
    begin
        case col is
            when "0000" => raw := snap2(127 downto 120);
            when "0001" => raw := snap2(119 downto 112);
            when "0010" => raw := snap2(111 downto 104);
            when "0011" => raw := snap2(103 downto  96);
            when "0100" => raw := snap2( 95 downto  88);
            when "0101" => raw := snap2( 87 downto  80);
            when "0110" => raw := snap2( 79 downto  72);
            when "0111" => raw := snap2( 71 downto  64);
            when "1000" => raw := snap2( 63 downto  56);
            when "1001" => raw := snap2( 55 downto  48);
            when "1010" => raw := snap2( 47 downto  40);
            when "1011" => raw := snap2( 39 downto  32);
            when "1100" => raw := snap2( 31 downto  24);
            when "1101" => raw := snap2( 23 downto  16);
            when "1110" => raw := snap2( 15 downto   8);
            when others => raw := snap2(  7 downto   0);
        end case;
        if raw = x"00" then cur_l2_s <= x"20"; else cur_l2_s <= raw; end if;
    end process;


    process(clk)
    begin
        if rising_edge(clk) then
            if rst_i = '1' then
                state   <= PW_WAIT;
                counter <= (others => '0');
                col     <= (others => '0');
                r_data  <= (others => '0');
                r_en    <= '0';
                r_rs    <= '0';
                dirty   <= '1';
            else
                case state is

                    -- espera o LCD estabilizar após ligar
                    when PW_WAIT =>
                        r_en <= '0';
                        if counter >= C_PW_ON - 1 then
                            counter <= (others => '0');
                            state   <= I_F1;
                        else
                            counter <= counter + 1;
                        end if;

                    -- envio de um byte: RS/dados -> EN alto -> EN baixo + espera
                    when TX_SETUP =>
                        r_rs   <= tx_rs;
                        r_data <= tx_data;
                        r_en   <= '0';
                        if counter >= C_SETUP - 1 then
                            counter <= (others => '0');
                            state   <= TX_EN_HI;
                        else
                            counter <= counter + 1;
                        end if;

                    when TX_EN_HI =>
                        r_en <= '1';
                        if counter >= C_EN_HI - 1 then
                            counter <= (others => '0');
                            r_en    <= '0';
                            state   <= TX_EN_LO;
                        else
                            counter <= counter + 1;
                        end if;

                    when TX_EN_LO =>
                        r_en <= '0';
                        if counter >= tx_delay - 1 then
                            counter <= (others => '0');
                            state   <= next_st;
                        else
                            counter <= counter + 1;
                        end if;

                    -- inicialização (sequência do datasheet do HD44780)
                    when I_F1 =>
                        tx_rs <= '0'; tx_data <= x"38";
                        tx_delay <= to_unsigned(C_F1, 22);  next_st <= I_F2;
                        counter <= (others => '0'); state <= TX_SETUP;

                    when I_F2 =>
                        tx_rs <= '0'; tx_data <= x"38";
                        tx_delay <= to_unsigned(C_F2, 22);  next_st <= I_F3;
                        counter <= (others => '0'); state <= TX_SETUP;

                    when I_F3 =>
                        tx_rs <= '0'; tx_data <= x"38";
                        tx_delay <= to_unsigned(C_CMD, 22); next_st <= I_F4;
                        counter <= (others => '0'); state <= TX_SETUP;

                    when I_F4 =>                                -- 8 bits, 2 linhas, 5x8
                        tx_rs <= '0'; tx_data <= x"38";
                        tx_delay <= to_unsigned(C_CMD, 22); next_st <= I_DOFF;
                        counter <= (others => '0'); state <= TX_SETUP;

                    when I_DOFF =>                              -- display desligado
                        tx_rs <= '0'; tx_data <= x"08";
                        tx_delay <= to_unsigned(C_CMD, 22); next_st <= I_CLR;
                        counter <= (others => '0'); state <= TX_SETUP;

                    when I_CLR =>                               -- limpa
                        tx_rs <= '0'; tx_data <= x"01";
                        tx_delay <= to_unsigned(C_CLEAR, 22); next_st <= I_ENT;
                        counter <= (others => '0'); state <= TX_SETUP;

                    when I_ENT =>                               -- endereço incrementa
                        tx_rs <= '0'; tx_data <= x"06";
                        tx_delay <= to_unsigned(C_CMD, 22); next_st <= I_DON;
                        counter <= (others => '0'); state <= TX_SETUP;

                    when I_DON =>                               -- display ligado, sem cursor
                        tx_rs <= '0'; tx_data <= x"0C";
                        tx_delay <= to_unsigned(C_CMD, 22); next_st <= IDLE;
                        counter <= (others => '0'); state <= TX_SETUP;

                    -- parado: só escreve se o texto mudou (ou na primeira vez)
                    when IDLE =>
                        r_en <= '0';
                        if dirty = '1' or line1 /= snap1 or line2 /= snap2 then
                            snap1 <= line1;
                            snap2 <= line2;
                            dirty <= '0';
                            state <= WR_L1H;
                        end if;

                    when WR_L1H =>
                        tx_rs <= '0'; tx_data <= x"80";
                        tx_delay <= to_unsigned(C_CMD, 22); next_st <= WR_L1D;
                        col <= (others => '0');
                        counter <= (others => '0'); state <= TX_SETUP;

                    when WR_L1D =>
                        tx_rs    <= '1';
                        tx_data  <= cur_l1_s;
                        tx_delay <= to_unsigned(C_CMD, 22);
                        counter  <= (others => '0');
                        if col = 15 then
                            col     <= (others => '0');
                            next_st <= WR_L2H;
                        else
                            col     <= col + 1;
                            next_st <= WR_L1D;
                        end if;
                        state <= TX_SETUP;

                    when WR_L2H =>
                        tx_rs <= '0'; tx_data <= x"C0";
                        tx_delay <= to_unsigned(C_CMD, 22); next_st <= WR_L2D;
                        col <= (others => '0');
                        counter <= (others => '0'); state <= TX_SETUP;

                    when WR_L2D =>
                        tx_rs    <= '1';
                        tx_data  <= cur_l2_s;
                        tx_delay <= to_unsigned(C_CMD, 22);
                        counter  <= (others => '0');
                        if col = 15 then
                            col     <= (others => '0');
                            next_st <= IDLE;
                        else
                            col     <= col + 1;
                            next_st <= WR_L2D;
                        end if;
                        state <= TX_SETUP;

                end case;
            end if;
        end if;
    end process;

end architecture;