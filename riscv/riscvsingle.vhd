library IEEE;
use IEEE.STD_LOGIC_1164.all;

entity riscvsingle is
  generic(TEXT_BASE : natural := 0;      -- PC no reset (entrega 47: 0x3000)
          SP_INIT   : natural := 0);     -- sp (x2) no reset (entrega 47: 0x80)
  port(clk, reset:           in  STD_LOGIC;
       PC:                   out STD_LOGIC_VECTOR(31 downto 0);
       Instr:                in  STD_LOGIC_VECTOR(31 downto 0);
       MemWrite:             out STD_LOGIC;
       ALUResult, WriteData: out STD_LOGIC_VECTOR(31 downto 0);
       ReadData:             in  STD_LOGIC_VECTOR(31 downto 0);
       SysWE:                in  STD_LOGIC := '0';
       SysWD:                in  STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
       SysA0, SysA7:         out STD_LOGIC_VECTOR(31 downto 0));
end;

architecture struct of riscvsingle is
  component controller
    port(op:             in  STD_LOGIC_VECTOR(6 downto 0);
         funct3:         in  STD_LOGIC_VECTOR(2 downto 0);
         funct7b5:       in  STD_LOGIC;
         funct7b0:       in  STD_LOGIC;
         Zero, Lt, Ltu:  in  STD_LOGIC;
         ResultSrc:      out STD_LOGIC_VECTOR(2 downto 0);
         MemWrite:       out STD_LOGIC;
         PCSrc:          out STD_LOGIC_VECTOR(1 downto 0);
         ALUSrc:         out STD_LOGIC;
         RegWrite, Jump: out STD_LOGIC;
         ImmSrc:         out STD_LOGIC_VECTOR(2 downto 0);
         ALUControl:     out STD_LOGIC_VECTOR(3 downto 0));
  end component;
  component datapath
    generic(TEXT_BASE, SP_INIT : natural);
    port(clk, reset:           in  STD_LOGIC;
         ResultSrc:            in  STD_LOGIC_VECTOR(2  downto 0);
         PCSrc:                in  STD_LOGIC_VECTOR(1  downto 0);
         ALUSrc:               in  STD_LOGIC;
         RegWrite:             in  STD_LOGIC;
         ImmSrc:               in  STD_LOGIC_VECTOR(2  downto 0);
         ALUControl:           in  STD_LOGIC_VECTOR(3  downto 0);
         Zero, Lt, Ltu:        out STD_LOGIC;
         PC:                   out STD_LOGIC_VECTOR(31 downto 0);
         Instr:                in  STD_LOGIC_VECTOR(31 downto 0);
         ALUResult, WriteData: out STD_LOGIC_VECTOR(31 downto 0);
         ReadData:             in  STD_LOGIC_VECTOR(31 downto 0);
         SysWE:                in  STD_LOGIC;
         SysWD:                in  STD_LOGIC_VECTOR(31 downto 0);
         SysA0, SysA7:         out STD_LOGIC_VECTOR(31 downto 0));
  end component;
  signal ALUSrc, RegWrite, Jump, Zero, Lt, Ltu: STD_LOGIC;
  signal PCSrc: STD_LOGIC_VECTOR(1 downto 0);
  signal ResultSrc, ImmSrc: STD_LOGIC_VECTOR(2 downto 0);
  signal ALUControl: STD_LOGIC_VECTOR(3 downto 0);
begin
  c: controller port map(Instr(6 downto 0), Instr(14 downto 12),
                         Instr(30), Instr(25), Zero, Lt, Ltu, ResultSrc, MemWrite,
                         PCSrc, ALUSrc, RegWrite, Jump,
                         ImmSrc, ALUControl);
  dp: datapath generic map(TEXT_BASE => TEXT_BASE, SP_INIT => SP_INIT)
               port map(clk, reset, ResultSrc, PCSrc, ALUSrc,
                        RegWrite, ImmSrc, ALUControl, Zero, Lt, Ltu,
                        PC, Instr, ALUResult,  WriteData,
                        ReadData, SysWE, SysWD, SysA0, SysA7);
end;