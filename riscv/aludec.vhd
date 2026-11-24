library IEEE;
use IEEE.STD_LOGIC_1164.all;

entity aludec is
  port(opb5:       in  STD_LOGIC;
       funct3:     in  STD_LOGIC_VECTOR(2 downto 0);
       funct7b5:   in  STD_LOGIC;
       funct7b0:   in  STD_LOGIC;
       ALUOp:      in  STD_LOGIC_VECTOR(1 downto 0);
       ALUControl: out STD_LOGIC_VECTOR(3 downto 0));
end;

architecture behave of aludec is
  signal RtypeSub, RtypeMul: STD_LOGIC;
begin
  RtypeSub <= funct7b5 and opb5;
  RtypeMul <= funct7b0 and opb5;
  process(funct3, funct7b5, ALUOp, RtypeSub, RtypeMul) begin
    case ALUOp is
      when "00" =>                     ALUControl <= "0000";   -- add
      when "01" =>                     ALUControl <= "0001";   -- sub
      when others =>
        if RtypeMul = '1' then                                 -- RV32M
          case funct3 is
            when "000"  => ALUControl <= "0110";               -- mul
            when "001"  => ALUControl <= "1100";               -- mulh
            when "010"  => ALUControl <= "1101";               -- mulhsu
            when "011"  => ALUControl <= "1110";               -- mulhu
            when others => ALUControl <= "1111";               -- div/rem: 0
          end case;
        else
          case funct3 is
            when "000"  => if RtypeSub = '1' then
                             ALUControl <= "0001";             -- sub
                           else
                             ALUControl <= "0000";             -- add, addi
                           end if;
            when "001"  => ALUControl <= "1000";               -- sll, slli
            when "010"  => ALUControl <= "0101";               -- slt, slti
            when "011"  => ALUControl <= "0111";               -- sltu, sltiu
            when "100"  => ALUControl <= "0100";               -- xor, xori
            when "101"  => if funct7b5 = '1' then
                             ALUControl <= "1010";             -- sra, srai
                           else
                             ALUControl <= "1001";             -- srl, srli
                           end if;
            when "110"  => ALUControl <= "0011";               -- or, ori
            when others => ALUControl <= "0010";               -- and, andi
          end case;
        end if;
    end case;
  end process;
end;