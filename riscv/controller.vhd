library IEEE;
use IEEE.STD_LOGIC_1164.all;

entity controller is
  port(op:             in     STD_LOGIC_VECTOR(6 downto 0);
       funct3:         in     STD_LOGIC_VECTOR(2 downto 0);
       funct7b5:       in     STD_LOGIC;
       funct7b0:       in     STD_LOGIC;
       Zero, Lt, Ltu:  in     STD_LOGIC;
       ResultSrc:      out    STD_LOGIC_VECTOR(2 downto 0);
       MemWrite:       out    STD_LOGIC;
       PCSrc:          out    STD_LOGIC_VECTOR(1 downto 0);
       ALUSrc:         out    STD_LOGIC;
       RegWrite:       out    STD_LOGIC;
       Jump:           buffer STD_LOGIC;
       ImmSrc:         out    STD_LOGIC_VECTOR(2 downto 0);
       ALUControl:     out    STD_LOGIC_VECTOR(3 downto 0));
end;

architecture struct of controller is
  component maindec
    port(op:             in  STD_LOGIC_VECTOR(6 downto 0);
         ResultSrc:      out STD_LOGIC_VECTOR(2 downto 0);
         MemWrite:       out STD_LOGIC;
         Branch, ALUSrc: out STD_LOGIC;
         RegWrite, Jump: out STD_LOGIC;
         JumpReg:        out STD_LOGIC;
         ImmSrc:         out STD_LOGIC_VECTOR(2 downto 0);
         ALUOp:          out STD_LOGIC_VECTOR(1 downto 0));
  end component;
  component aludec
    port(opb5:       in  STD_LOGIC;
         funct3:     in  STD_LOGIC_VECTOR(2 downto 0);
         funct7b5:   in  STD_LOGIC;
         funct7b0:   in  STD_LOGIC;
         ALUOp:      in  STD_LOGIC_VECTOR(1 downto 0);
         ALUControl: out STD_LOGIC_VECTOR(3 downto 0));
  end component;
  signal ALUOp:   STD_LOGIC_VECTOR(1 downto 0);
  signal Branch, JumpReg, Taken: STD_LOGIC;
begin
  md: maindec port map(op, ResultSrc, MemWrite, Branch,
                       ALUSrc, RegWrite, Jump, JumpReg, ImmSrc, ALUOp);
  ad: aludec port map(op(5), funct3, funct7b5, funct7b0, ALUOp, ALUControl);

  -- condição do desvio conforme o funct3
  process(funct3, Zero, Lt, Ltu) begin
    case funct3 is
      when "000"  => Taken <= Zero;        -- beq
      when "001"  => Taken <= not Zero;    -- bne
      when "100"  => Taken <= Lt;          -- blt
      when "101"  => Taken <= not Lt;      -- bge
      when "110"  => Taken <= Ltu;         -- bltu
      when "111"  => Taken <= not Ltu;     -- bgeu
      when others => Taken <= '0';         -- 010, 011: não existem
    end case;
  end process;

  PCSrc <= "10" when JumpReg = '1' else
           "01" when (Branch = '1' and Taken = '1') or Jump = '1' else
           "00";
end;