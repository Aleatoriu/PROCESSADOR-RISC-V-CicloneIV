library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity vga_sync is
    port(
        clk_50    : in  STD_LOGIC;
        reset     : in  STD_LOGIC;
        pixel_clk : out STD_LOGIC;
        h_count   : out UNSIGNED(9 downto 0);   -- 0..799
        v_count   : out UNSIGNED(9 downto 0);   -- 0..524
        video_on  : out STD_LOGIC;
        h_sync    : out STD_LOGIC;
        v_sync    : out STD_LOGIC
    );
end entity;

architecture rtl of vga_sync is
    -- Parâmetros 640x480 @ 60Hz
    constant H_DISPLAY : integer := 640;
    constant H_FP      : integer := 16;
    constant H_PULSE   : integer := 96;
    constant H_BP      : integer := 48;
    constant H_TOTAL   : integer := 800;
    constant V_DISPLAY : integer := 480;
    constant V_FP      : integer := 10;
    constant V_PULSE   : integer := 2;
    constant V_BP      : integer := 33;
    constant V_TOTAL   : integer := 525;

    signal pclk : STD_LOGIC := '0';
    signal hc   : UNSIGNED(9 downto 0) := (others => '0');
    signal vc   : UNSIGNED(9 downto 0) := (others => '0');
begin
    -- Divide 50 MHz → 25 MHz
    process(clk_50)
    begin
        if rising_edge(clk_50) then
            pclk <= not pclk;
        end if;
    end process;

    -- Contadores horizontal e vertical
    process(pclk, reset)
    begin
        if reset = '1' then
            hc <= (others => '0');
            vc <= (others => '0');
        elsif rising_edge(pclk) then
            if hc = H_TOTAL - 1 then
                hc <= (others => '0');
                if vc = V_TOTAL - 1 then
                    vc <= (others => '0');
                else
                    vc <= vc + 1;
                end if;
            else
                hc <= hc + 1;
            end if;
        end if;
    end process;

    pixel_clk <= pclk;
    h_count   <= hc;
    v_count   <= vc;
    video_on  <= '1' when hc < H_DISPLAY and vc < V_DISPLAY else '0';
    h_sync    <= '0' when hc >= H_DISPLAY + H_FP and
                          hc <  H_DISPLAY + H_FP + H_PULSE else '1';
    v_sync    <= '0' when vc >= V_DISPLAY + V_FP and
                          vc <  V_DISPLAY + V_FP + V_PULSE else '1';
end architecture;
