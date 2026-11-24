library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
entity regfile is
  generic(SP_INIT : natural := 0);
  port(clk, reset : in  STD_LOGIC;
       we3        : in  STD_LOGIC;
       a1, a2, a3 : in  STD_LOGIC_VECTOR(4  downto 0);
       wd3        : in  STD_LOGIC_VECTOR(31 downto 0);
       rd1, rd2   : out STD_LOGIC_VECTOR(31 downto 0);
       sys_we     : in  STD_LOGIC := '0';
       sys_wd     : in  STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
       sys_a0     : out STD_LOGIC_VECTOR(31 downto 0);
       sys_a7     : out STD_LOGIC_VECTOR(31 downto 0));
end;
architecture behave of regfile is
    signal r00, r01, r02, r03 : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal r04, r05, r06, r07 : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal r08, r09, r10, r11 : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal r12, r13, r14, r15 : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal r16, r17, r18, r19 : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal r20, r21, r22, r23 : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal r24, r25, r26, r27 : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal r28, r29, r30, r31 : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
begin
    process(clk, reset)
    begin
        if reset = '1' then
            r00 <= (others => '0');
            r01 <= (others => '0');
            r02 <= STD_LOGIC_VECTOR(to_unsigned(SP_INIT, 32));   -- sp
            r03 <= (others => '0');
            r04 <= (others => '0');
            r05 <= (others => '0');
            r06 <= (others => '0');
            r07 <= (others => '0');
            r08 <= (others => '0');
            r09 <= (others => '0');
            r10 <= (others => '0');
            r11 <= (others => '0');
            r12 <= (others => '0');
            r13 <= (others => '0');
            r14 <= (others => '0');
            r15 <= (others => '0');
            r16 <= (others => '0');
            r17 <= (others => '0');
            r18 <= (others => '0');
            r19 <= (others => '0');
            r20 <= (others => '0');
            r21 <= (others => '0');
            r22 <= (others => '0');
            r23 <= (others => '0');
            r24 <= (others => '0');
            r25 <= (others => '0');
            r26 <= (others => '0');
            r27 <= (others => '0');
            r28 <= (others => '0');
            r29 <= (others => '0');
            r30 <= (others => '0');
            r31 <= (others => '0');
        elsif rising_edge(clk) then
            if we3 = '1' then
                case a3 is
                    when "00000" => r00 <= wd3;
                    when "00001" => r01 <= wd3;
                    when "00010" => r02 <= wd3;
                    when "00011" => r03 <= wd3;
                    when "00100" => r04 <= wd3;
                    when "00101" => r05 <= wd3;
                    when "00110" => r06 <= wd3;
                    when "00111" => r07 <= wd3;
                    when "01000" => r08 <= wd3;
                    when "01001" => r09 <= wd3;
                    when "01010" => r10 <= wd3;
                    when "01011" => r11 <= wd3;
                    when "01100" => r12 <= wd3;
                    when "01101" => r13 <= wd3;
                    when "01110" => r14 <= wd3;
                    when "01111" => r15 <= wd3;
                    when "10000" => r16 <= wd3;
                    when "10001" => r17 <= wd3;
                    when "10010" => r18 <= wd3;
                    when "10011" => r19 <= wd3;
                    when "10100" => r20 <= wd3;
                    when "10101" => r21 <= wd3;
                    when "10110" => r22 <= wd3;
                    when "10111" => r23 <= wd3;
                    when "11000" => r24 <= wd3;
                    when "11001" => r25 <= wd3;
                    when "11010" => r26 <= wd3;
                    when "11011" => r27 <= wd3;
                    when "11100" => r28 <= wd3;
                    when "11101" => r29 <= wd3;
                    when "11110" => r30 <= wd3;
                    when others => r31 <= wd3;
                end case;
            end if;
            if sys_we = '1' then
                r10 <= sys_wd;              -- a0 <- valor lido (ecall, a7 = 5)
            end if;
        end if;
    end process;
    sys_a0 <= r10;
    sys_a7 <= r17;
    process(a1, r00, r01, r02, r03, r04, r05, r06, r07, r08, r09, r10, r11, r12, r13, r14, r15, r16, r17, r18, r19, r20, r21, r22, r23, r24, r25, r26, r27, r28, r29, r30, r31)
    begin
        case a1 is
            when "00000" => rd1 <= (others => '0');
            when "00001" => rd1 <= r01;
            when "00010" => rd1 <= r02;
            when "00011" => rd1 <= r03;
            when "00100" => rd1 <= r04;
            when "00101" => rd1 <= r05;
            when "00110" => rd1 <= r06;
            when "00111" => rd1 <= r07;
            when "01000" => rd1 <= r08;
            when "01001" => rd1 <= r09;
            when "01010" => rd1 <= r10;
            when "01011" => rd1 <= r11;
            when "01100" => rd1 <= r12;
            when "01101" => rd1 <= r13;
            when "01110" => rd1 <= r14;
            when "01111" => rd1 <= r15;
            when "10000" => rd1 <= r16;
            when "10001" => rd1 <= r17;
            when "10010" => rd1 <= r18;
            when "10011" => rd1 <= r19;
            when "10100" => rd1 <= r20;
            when "10101" => rd1 <= r21;
            when "10110" => rd1 <= r22;
            when "10111" => rd1 <= r23;
            when "11000" => rd1 <= r24;
            when "11001" => rd1 <= r25;
            when "11010" => rd1 <= r26;
            when "11011" => rd1 <= r27;
            when "11100" => rd1 <= r28;
            when "11101" => rd1 <= r29;
            when "11110" => rd1 <= r30;
            when others => rd1 <= r31;
        end case;
    end process;
    process(a2, r00, r01, r02, r03, r04, r05, r06, r07, r08, r09, r10, r11, r12, r13, r14, r15, r16, r17, r18, r19, r20, r21, r22, r23, r24, r25, r26, r27, r28, r29, r30, r31)
    begin
        case a2 is
            when "00000" => rd2 <= (others => '0');
            when "00001" => rd2 <= r01;
            when "00010" => rd2 <= r02;
            when "00011" => rd2 <= r03;
            when "00100" => rd2 <= r04;
            when "00101" => rd2 <= r05;
            when "00110" => rd2 <= r06;
            when "00111" => rd2 <= r07;
            when "01000" => rd2 <= r08;
            when "01001" => rd2 <= r09;
            when "01010" => rd2 <= r10;
            when "01011" => rd2 <= r11;
            when "01100" => rd2 <= r12;
            when "01101" => rd2 <= r13;
            when "01110" => rd2 <= r14;
            when "01111" => rd2 <= r15;
            when "10000" => rd2 <= r16;
            when "10001" => rd2 <= r17;
            when "10010" => rd2 <= r18;
            when "10011" => rd2 <= r19;
            when "10100" => rd2 <= r20;
            when "10101" => rd2 <= r21;
            when "10110" => rd2 <= r22;
            when "10111" => rd2 <= r23;
            when "11000" => rd2 <= r24;
            when "11001" => rd2 <= r25;
            when "11010" => rd2 <= r26;
            when "11011" => rd2 <= r27;
            when "11100" => rd2 <= r28;
            when "11101" => rd2 <= r29;
            when "11110" => rd2 <= r30;
            when others => rd2 <= r31;
        end case;
    end process;
end;