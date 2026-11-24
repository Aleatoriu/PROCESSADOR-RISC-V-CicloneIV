library IEEE;
use IEEE.STD_LOGIC_1164.all;

entity maindec is
  port(op:             in  STD_LOGIC_VECTOR(6 downto 0);
       ResultSrc:      out STD_LOGIC_VECTOR(2 downto 0);
       MemWrite:       out STD_LOGIC;
       Branch, ALUSrc: out STD_LOGIC;
       RegWrite, Jump: out STD_LOGIC;
       JumpReg:        out STD_LOGIC;
       ImmSrc:         out STD_LOGIC_VECTOR(2 downto 0);
       ALUOp:          out STD_LOGIC_VECTOR(1 downto 0));
end;

architecture behave of maindec is
  signal controls: STD_LOGIC_VECTOR(13 downto 0);
begin
  process(op) begin
    --                  RegWrite ImmSrc ALUSrc MemWrite ResultSrc Branch ALUOp Jump JumpReg
    case op is
      when "0000011" => controls <= "1" & "000" & "1" & "0" & "001" & "0" & "00" & "0" & "0"; -- loads
      when "0100011" => controls <= "0" & "001" & "1" & "1" & "000" & "0" & "00" & "0" & "0"; -- stores
      when "0110011" => controls <= "1" & "000" & "0" & "0" & "000" & "0" & "10" & "0" & "0"; -- tipo R
      when "1100011" => controls <= "0" & "010" & "0" & "0" & "000" & "1" & "01" & "0" & "0"; -- desvios
      when "0010011" => controls <= "1" & "000" & "1" & "0" & "000" & "0" & "10" & "0" & "0"; -- tipo I
      when "1101111" => controls <= "1" & "011" & "0" & "0" & "010" & "0" & "00" & "1" & "0"; -- jal
      when "1100111" => controls <= "1" & "000" & "1" & "0" & "010" & "0" & "00" & "0" & "1"; -- jalr
      when "0110111" => controls <= "1" & "100" & "0" & "0" & "011" & "0" & "00" & "0" & "0"; -- lui
      when "0010111" => controls <= "1" & "100" & "0" & "0" & "100" & "0" & "00" & "0" & "0"; -- auipc
      when others    => controls <= (others => '0');                                         -- NOP
    end case;
  end process;

  RegWrite  <= controls(13);
  ImmSrc    <= controls(12 downto 10);
  ALUSrc    <= controls(9);
  MemWrite  <= controls(8);
  ResultSrc <= controls(7 downto 5);
  Branch    <= controls(4);
  ALUOp     <= controls(3 downto 2);
  Jump      <= controls(1);
  JumpReg   <= controls(0);
end;