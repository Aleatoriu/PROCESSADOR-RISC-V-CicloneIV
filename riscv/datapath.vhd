library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity datapath is
  generic(TEXT_BASE : natural := 0;
          SP_INIT   : natural := 0);
  port(clk, reset:           in     STD_LOGIC;
       ResultSrc:            in     STD_LOGIC_VECTOR(2  downto 0);
       PCSrc:                in     STD_LOGIC_VECTOR(1  downto 0);
       ALUSrc:               in     STD_LOGIC;
       RegWrite:             in     STD_LOGIC;
       ImmSrc:               in     STD_LOGIC_VECTOR(2  downto 0);
       ALUControl:           in     STD_LOGIC_VECTOR(3  downto 0);
       Zero, Lt, Ltu:        out    STD_LOGIC;
       PC:                   buffer STD_LOGIC_VECTOR(31 downto 0);
       Instr:                in     STD_LOGIC_VECTOR(31 downto 0);
       ALUResult, WriteData: buffer STD_LOGIC_VECTOR(31 downto 0);
       ReadData:             in     STD_LOGIC_VECTOR(31 downto 0);
       -- entrega 50: serviços do ecall (ver regfile)
       SysWE:                in     STD_LOGIC := '0';
       SysWD:                in     STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
       SysA0, SysA7:         out    STD_LOGIC_VECTOR(31 downto 0));
end;

architecture struct of datapath is
  component flopr generic(width: integer);
    port(clk, reset: in  STD_LOGIC;
         d:          in  STD_LOGIC_VECTOR(width-1 downto 0);
         q:          out STD_LOGIC_VECTOR(width-1 downto 0));
  end component;
  component adder
    port(a, b: in  STD_LOGIC_VECTOR(31 downto 0);
         y:    out STD_LOGIC_VECTOR(31 downto 0));
  end component;
  component mux2 generic(width: integer);
    port(d0, d1: in  STD_LOGIC_VECTOR(width-1 downto 0);
         s:      in  STD_LOGIC;
         y:      out STD_LOGIC_VECTOR(width-1 downto 0));
  end component;
  component mux3 generic(width: integer);
    port(d0, d1, d2: in  STD_LOGIC_VECTOR(width-1 downto 0);
         s:          in  STD_LOGIC_VECTOR(1 downto 0);
         y:          out STD_LOGIC_VECTOR(width-1 downto 0));
  end component;
  component regfile
    generic(SP_INIT : natural);
    port(clk, reset : in  STD_LOGIC;
         we3        : in  STD_LOGIC;
         a1, a2, a3 : in  STD_LOGIC_VECTOR(4  downto 0);
         wd3        : in  STD_LOGIC_VECTOR(31 downto 0);
         rd1, rd2   : out STD_LOGIC_VECTOR(31 downto 0);
         sys_we     : in  STD_LOGIC;
         sys_wd     : in  STD_LOGIC_VECTOR(31 downto 0);
         sys_a0     : out STD_LOGIC_VECTOR(31 downto 0);
         sys_a7     : out STD_LOGIC_VECTOR(31 downto 0));
  end component;
  component extend
    port(instr:  in  STD_LOGIC_VECTOR(31 downto 7);
         immsrc: in  STD_LOGIC_VECTOR(2  downto 0);
         immext: out STD_LOGIC_VECTOR(31 downto 0));
  end component;
  component alu
    port(a, b:       in     STD_LOGIC_VECTOR(31 downto 0);
         ALUControl: in     STD_LOGIC_VECTOR(3  downto 0);
         ALUResult:  buffer STD_LOGIC_VECTOR(31 downto 0);
         Zero:       out    STD_LOGIC;
         Lt, Ltu:    out    STD_LOGIC);
  end component;
  signal PCNext, PCPlus4, PCTarget : STD_LOGIC_VECTOR(31 downto 0);
  signal ImmExt                    : STD_LOGIC_VECTOR(31 downto 0);
  signal SrcA, SrcB                : STD_LOGIC_VECTOR(31 downto 0);
  signal Result                    : STD_LOGIC_VECTOR(31 downto 0);
  signal JumpRegTarget             : STD_LOGIC_VECTOR(31 downto 0);
begin
  -- registrador do PC: no reset vai para TEXT_BASE (1ª instrução)
  pcreg: process(clk, reset)
  begin
    if reset = '1' then
      PC <= STD_LOGIC_VECTOR(to_unsigned(TEXT_BASE, 32));
    elsif rising_edge(clk) then
      PC <= PCNext;
    end if;
  end process;
  pcadd4:      adder port map(PC, X"00000004", PCPlus4);
  pcaddbranch: adder port map(PC, ImmExt, PCTarget);
  JumpRegTarget <= ALUResult(31 downto 1) & '0';               -- jalr
  pcmux:       mux3 generic map(32) port map(PCPlus4, PCTarget, JumpRegTarget, PCSrc, PCNext);
  rf: regfile generic map(SP_INIT => SP_INIT) port map(
        clk   => clk,
        reset => reset,
        we3   => RegWrite,
        a1    => Instr(19 downto 15),
        a2    => Instr(24 downto 20),
        a3    => Instr(11 downto 7),
        wd3   => Result,
        rd1   => SrcA,
        rd2   => WriteData,
        sys_we => SysWE,
        sys_wd => SysWD,
        sys_a0 => SysA0,
        sys_a7 => SysA7);
  ext:       extend port map(Instr(31 downto 7), ImmSrc, ImmExt);
  srcbmux:   mux2 generic map(32) port map(WriteData, ImmExt, ALUSrc, SrcB);
  mainalu:   alu  port map(SrcA, SrcB, ALUControl, ALUResult, Zero, Lt, Ltu);
  -- resultado: 000 ULA, 001 memória, 010 PC+4 (jal/jalr), 011 imediato (lui),
  --            100 PC + imediato (auipc)
  with ResultSrc select
    Result <= ReadData  when "001",
              PCPlus4   when "010",
              ImmExt    when "011",
              PCTarget  when "100",
              ALUResult when others;
end;