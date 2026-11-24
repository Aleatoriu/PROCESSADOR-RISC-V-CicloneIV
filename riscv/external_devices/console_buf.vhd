library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity console_buf is
    generic(ROWS : positive := 6;
            COLS : positive := 48);
    port(clk  : in  STD_LOGIC;
         rst  : in  STD_LOGIC;
         put  : in  STD_LOGIC;
         ch   : in  STD_LOGIC_VECTOR(7 downto 0);
         flat : out STD_LOGIC_VECTOR(ROWS*COLS*8-1 downto 0));
end;

architecture behave of console_buf is
    type line_t is array(0 to COLS-1) of STD_LOGIC_VECTOR(7 downto 0);
    type scr_t  is array(0 to ROWS-1) of line_t;
    constant BLANK : line_t := (others => x"20");
    signal scr : scr_t := (others => BLANK);
    signal row : integer range 0 to ROWS-1 := 0;
    signal col : integer range 0 to COLS   := 0;    -- COLS = linha cheia
begin
    process(clk, rst)
        variable c8 : STD_LOGIC_VECTOR(7 downto 0);
    begin
        if rst = '1' then
            scr <= (others => BLANK);
            row <= 0;
            col <= 0;
        elsif rising_edge(clk) then
            if put = '1' then
                if ch = x"0A" then                              -- nova linha
                    if row < ROWS - 1 then
                        row <= row + 1;
                    else
                        for i in 0 to ROWS - 2 loop scr(i) <= scr(i + 1); end loop;
                        scr(ROWS - 1) <= BLANK;
                    end if;
                    col <= 0;
                else
                    if unsigned(ch) < 32 or unsigned(ch) > 126 then
                        c8 := x"3F";                            -- '?'
                    else
                        c8 := ch;
                    end if;
                    if col = COLS then                          -- quebra a linha
                        if row < ROWS - 1 then
                            scr(row + 1)(0) <= c8;
                            row <= row + 1;
                        else
                            for i in 0 to ROWS - 2 loop scr(i) <= scr(i + 1); end loop;
                            scr(ROWS - 1)    <= BLANK;
                            scr(ROWS - 1)(0) <= c8;
                        end if;
                        col <= 1;
                    else
                        scr(row)(col) <= c8;
                        col <= col + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    gen_r: for r in 0 to ROWS - 1 generate
        gen_c: for c in 0 to COLS - 1 generate
            flat((r*COLS + c)*8 + 7 downto (r*COLS + c)*8) <= scr(r)(c);
        end generate;
    end generate;
end;