library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity alu is
  port(a, b:       in     STD_LOGIC_VECTOR(31 downto 0);
       ALUControl: in     STD_LOGIC_VECTOR(3  downto 0);
       ALUResult:  buffer STD_LOGIC_VECTOR(31 downto 0);
       Zero:       out    STD_LOGIC;
       Lt, Ltu:    out    STD_LOGIC);
end;

architecture behave of alu is
  signal condinvb, sum     : STD_LOGIC_VECTOR(31 downto 0);
  signal sum33             : UNSIGNED(32 downto 0);
  signal v, lt_s, ltu_s    : STD_LOGIC;
  signal sa, sb            : STD_LOGIC;                  -- operando com sinal?
  signal ae, be            : STD_LOGIC_VECTOR(32 downto 0);
  signal a33, b33          : SIGNED(32 downto 0);
  signal prod              : SIGNED(65 downto 0);
  signal shamt             : NATURAL range 0 to 31;
begin
  -- somador / subtrator
  condinvb <= not b when ALUControl(0) = '1' else b;
  sum33    <= ('0' & unsigned(a)) + ('0' & unsigned(condinvb)) +
              unsigned(ALUControl(0 downto 0));
  sum      <= std_logic_vector(sum33(31 downto 0));
  v        <= (a(31) xor b(31)) and (a(31) xor sum(31));  -- overflow de a - b
  lt_s     <= sum(31) xor v;
  ltu_s    <= not sum33(32);

  -- multiplicador 33 x 33
  sa   <= '1' when ALUControl = "1100" or ALUControl = "1101" else '0';
  sb   <= '1' when ALUControl = "1100" else '0';
  ae   <= (a(31) and sa) & a;
  be   <= (b(31) and sb) & b;
  a33  <= signed(ae);
  b33  <= signed(be);
  prod <= a33 * b33;

  shamt <= to_integer(unsigned(b(4 downto 0)));

  process(ALUControl, a, b, sum, lt_s, ltu_s, prod, shamt) begin
    case ALUControl is
      when "0000" | "0001" => ALUResult <= sum;                     -- add, sub
      when "0010" => ALUResult <= a and b;
      when "0011" => ALUResult <= a or b;
      when "0100" => ALUResult <= a xor b;
      when "0101" => ALUResult <= (0 => lt_s,  others => '0');      -- slt
      when "0111" => ALUResult <= (0 => ltu_s, others => '0');      -- sltu
      when "0110" => ALUResult <= std_logic_vector(prod(31 downto 0));   -- mul
      when "1000" => ALUResult <= std_logic_vector(shift_left (unsigned(a), shamt));
      when "1001" => ALUResult <= std_logic_vector(shift_right(unsigned(a), shamt));
      when "1010" => ALUResult <= std_logic_vector(shift_right(signed(a),   shamt));
      when "1100" | "1101" | "1110" =>                               -- mulh*
                     ALUResult <= std_logic_vector(prod(63 downto 32));
      when others => ALUResult <= (others => '0');
    end case;
  end process;

  Zero <= '1' when ALUResult = X"00000000" else '0';
  Lt   <= lt_s;
  Ltu  <= ltu_s;
end;