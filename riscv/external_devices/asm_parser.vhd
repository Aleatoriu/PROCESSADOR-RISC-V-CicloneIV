library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity asm_parser is
    port(
        clk         : in  STD_LOGIC;
        reset       : in  STD_LOGIC;
        line_buf    : in  STD_LOGIC_VECTOR(159 downto 0);
        line_len    : in  UNSIGNED(4 downto 0);
        parse_en    : in  STD_LOGIC;
        instr_out   : out STD_LOGIC_VECTOR(31 downto 0);
        instr_valid : out STD_LOGIC;
        parse_err   : out STD_LOGIC
    );
end entity;

architecture behave of asm_parser is

    subtype byte_t is STD_LOGIC_VECTOR(7 downto 0);
    type buf_t is array(0 to 19) of byte_t;
    type mn_t  is array(0 to 5) of byte_t;

    type st_t  is (S_IDLE, S_LEAD, S_MNEM, S_DEC, S_SKIP, S_TOK, S_REGD, S_REGN,
                   S_NUMP, S_NUMD, S_FIN);
    -- formato dos operandos
    type fmt_t is (F_0, F_R, F_I, F_MEM, F_ST, F_B, F_RN, F_MV, F_JR, F_JN);
    -- item esperado
    type tok_t is (T_RD, T_RS1, T_RS2, T_COMMA, T_LPAR, T_RPAR, T_NUM, T_HEX, T_END);
    type pat_t is array(0 to 7) of tok_t;
    -- regra de faixa do imediato
    type ik_t  is (K_NONE, K_I12, K_SH, K_MEM, K_JALR, K_B, K_J, K_U);
    -- formato da codificação
    type ek_t  is (E_R, E_I, E_S, E_B, E_U, E_J, E_FIX);

    constant P_0   : pat_t := (T_END, others => T_END);
    constant P_R   : pat_t := (T_RD, T_COMMA, T_RS1, T_COMMA, T_RS2, others => T_END);
    constant P_I   : pat_t := (T_RD, T_COMMA, T_RS1, T_COMMA, T_NUM, others => T_END);
    constant P_MEM : pat_t := (T_RD, T_COMMA, T_HEX, T_LPAR, T_RS1, T_RPAR, others => T_END);
    constant P_ST  : pat_t := (T_RS2, T_COMMA, T_HEX, T_LPAR, T_RS1, T_RPAR, others => T_END);
    constant P_B   : pat_t := (T_RS1, T_COMMA, T_RS2, T_COMMA, T_NUM, others => T_END);
    constant P_RN  : pat_t := (T_RD, T_COMMA, T_NUM, others => T_END);
    constant P_MV  : pat_t := (T_RD, T_COMMA, T_RS1, others => T_END);
    constant P_JR  : pat_t := (T_RS1, others => T_END);              -- jr rs
    constant P_JN  : pat_t := (T_NUM, others => T_END);              -- j desl

    function pattern(f : fmt_t) return pat_t is
    begin
        case f is
            when F_R   => return P_R;
            when F_I   => return P_I;
            when F_MEM => return P_MEM;
            when F_ST  => return P_ST;
            when F_B   => return P_B;
            when F_RN  => return P_RN;
            when F_MV  => return P_MV;
            when F_JR  => return P_JR;
            when F_JN  => return P_JN;
            when others => return P_0;
        end case;
    end function;

    function to_upper(c : byte_t) return byte_t is
    begin
        if unsigned(c) >= 16#61# and unsigned(c) <= 16#7A# then
            return STD_LOGIC_VECTOR(unsigned(c) - 32);
        else
            return c;
        end if;
    end function;

    -- '0'..'9' -> 0..9, senão -1
    function dec_val(c : byte_t) return integer is
    begin
        if unsigned(c) >= 16#30# and unsigned(c) <= 16#39# then
            return to_integer(unsigned(c)) - 48;
        else
            return -1;
        end if;
    end function;

    -- '0'..'9', 'a'..'f', 'A'..'F' -> 0..15, senão -1
    function hex_val(c : byte_t) return integer is
        variable u : byte_t;
    begin
        u := to_upper(c);
        if unsigned(u) >= 16#30# and unsigned(u) <= 16#39# then
            return to_integer(unsigned(u)) - 48;
        elsif unsigned(u) >= 16#41# and unsigned(u) <= 16#46# then
            return to_integer(unsigned(u)) - 55;
        else
            return -1;
        end if;
    end function;

    -- 'A'..'Z' (já em maiúscula)?
    function is_letter(c : byte_t) return boolean is
    begin
        return unsigned(c) >= 16#41# and unsigned(c) <= 16#5A#;
    end function;

    -- nome da ABI -> número do registrador, ou -1 se não existir.
    --   l0..l3 = letras (maiúsculas), nl = quantas; v/nd = número depois
    --   das letras e quantos dígitos ele tem (0 = sem número)
    --   zero ra sp gp tp fp | t0-t2 = x5-x7, t3-t6 = x28-x31
    --   s0 = fp = x8, s1 = x9, s2-s11 = x18-x27 | a0-a7 = x10-x17
    function abi_num(l0, l1, l2, l3 : byte_t; nl : integer; v, nd : integer) return integer is
        variable two : STD_LOGIC_VECTOR(15 downto 0);
    begin
        two := l0 & l1;
        if nd = 0 then
            if nl = 4 and two = x"5A45" and l2 = x"52" and l3 = x"4F" then return 0;   -- ZERO
            elsif nl = 2 then
                case two is
                    when x"5241" => return 1;       -- RA
                    when x"5350" => return 2;       -- SP
                    when x"4750" => return 3;       -- GP
                    when x"5450" => return 4;       -- TP
                    when x"4650" => return 8;       -- FP
                    when others  => return -1;
                end case;
            end if;
        elsif nl = 1 and not (nd = 2 and v < 10) then  -- "t05" não vale
            case l0 is
                when x"54" =>                                       -- T
                    if v <= 2 then return 5 + v;
                    elsif v <= 6 then return 25 + v; end if;
                when x"53" =>                                       -- S
                    if v <= 1 then return 8 + v;
                    elsif v <= 11 then return 16 + v; end if;
                when x"41" =>                                       -- A
                    if v <= 7 then return 10 + v; end if;
                when others => null;
            end case;
        end if;
        return -1;
    end function;

    -- texto do mnemônico (até 6 letras) -> 48 bits, completado com espaços
    function m6(s : string) return STD_LOGIC_VECTOR is
        variable r : STD_LOGIC_VECTOR(47 downto 0);
        variable k : integer;
    begin
        for i in 0 to 5 loop
            if i < s'length then k := character'pos(s(s'low + i));
            else                 k := 32;
            end if;
            r(47 - 8*i downto 40 - 8*i) := STD_LOGIC_VECTOR(to_unsigned(k, 8));
        end loop;
        return r;
    end function;

    function enc_r(f7 : STD_LOGIC_VECTOR(6 downto 0); rs2, rs1 : integer;
                   f3 : STD_LOGIC_VECTOR(2 downto 0); rd : integer)
        return STD_LOGIC_VECTOR is
    begin
        return f7 & STD_LOGIC_VECTOR(to_unsigned(rs2, 5)) & STD_LOGIC_VECTOR(to_unsigned(rs1, 5)) &
               f3 & STD_LOGIC_VECTOR(to_unsigned(rd, 5)) & "0110011";
    end function;

    function enc_i(imm, rs1 : integer; f3 : STD_LOGIC_VECTOR(2 downto 0); rd : integer;
                   op : STD_LOGIC_VECTOR(6 downto 0)) return STD_LOGIC_VECTOR is
    begin
        return STD_LOGIC_VECTOR(to_signed(imm, 12)) & STD_LOGIC_VECTOR(to_unsigned(rs1, 5)) &
               f3 & STD_LOGIC_VECTOR(to_unsigned(rd, 5)) & op;
    end function;

    function enc_s(imm, rs2, rs1 : integer; f3 : STD_LOGIC_VECTOR(2 downto 0))
        return STD_LOGIC_VECTOR is
        variable i : STD_LOGIC_VECTOR(11 downto 0);
    begin
        i := STD_LOGIC_VECTOR(to_signed(imm, 12));
        return i(11 downto 5) & STD_LOGIC_VECTOR(to_unsigned(rs2, 5)) &
               STD_LOGIC_VECTOR(to_unsigned(rs1, 5)) & f3 & i(4 downto 0) & "0100011";
    end function;

    function enc_b(imm, rs1, rs2 : integer; f3 : STD_LOGIC_VECTOR(2 downto 0))
        return STD_LOGIC_VECTOR is
        variable i : STD_LOGIC_VECTOR(12 downto 0);
    begin
        i := STD_LOGIC_VECTOR(to_signed(imm, 13));
        return i(12) & i(10 downto 5) & STD_LOGIC_VECTOR(to_unsigned(rs2, 5)) &
               STD_LOGIC_VECTOR(to_unsigned(rs1, 5)) & f3 & i(4 downto 1) & i(11) & "1100011";
    end function;

    function enc_u(imm, rd : integer; op : STD_LOGIC_VECTOR(6 downto 0))
        return STD_LOGIC_VECTOR is
    begin
        return STD_LOGIC_VECTOR(to_unsigned(imm, 20)) & STD_LOGIC_VECTOR(to_unsigned(rd, 5)) & op;
    end function;

    function enc_j(imm, rd : integer) return STD_LOGIC_VECTOR is
        variable i : STD_LOGIC_VECTOR(20 downto 0);
    begin
        i := STD_LOGIC_VECTOR(to_signed(imm, 21));
        return i(20) & i(10 downto 1) & i(11) & i(19 downto 12) &
               STD_LOGIC_VECTOR(to_unsigned(rd, 5)) & "1101111";
    end function;

    -- ── estado ──────────────────────────────────────────────────────────────
    signal st    : st_t := S_IDLE;
    signal b     : buf_t := (others => x"20");     -- cópia da linha
    signal n     : integer range 0 to 20 := 0;     -- comprimento
    signal p     : integer range 0 to 21 := 0;     -- posição atual
    signal mn    : mn_t := (others => x"20");      -- mnemônico em maiúsculas
    signal mlen  : integer range 0 to 7 := 0;
    signal k     : integer range 0 to 7 := 0;      -- item atual do formato
    signal bad   : boolean := false;               -- erro de sintaxe
    -- tabela (resultado de S_DEC)
    signal fmt   : fmt_t := F_0;
    signal ik    : ik_t  := K_NONE;
    signal ek    : ek_t  := E_FIX;
    signal opc   : STD_LOGIC_VECTOR(6 downto 0) := (others => '0');
    signal f3    : STD_LOGIC_VECTOR(2 downto 0) := (others => '0');
    signal f7    : STD_LOGIC_VECTOR(6 downto 0) := (others => '0');
    signal size  : integer range 1 to 4 := 4;      -- bytes do acesso (memória)
    signal srai  : boolean := false;
    signal fixw  : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    -- operandos
    signal rd, rs1, rs2 : integer range 0 to 31 := 0;
    signal imm   : integer range -16777215 to 16777215 := 0;
    -- acumulador de número / registrador
    signal acc   : integer range 0 to 16777215 := 0;
    signal cnt   : integer range 0 to 8 := 0;
    signal neg   : boolean := false;
    signal hexm  : boolean := false;
    -- nome de registrador da ABI (a0, sp, zero, s11...): letras e quantas
    type rn_t is array(0 to 3) of byte_t;
    signal rl    : rn_t := (others => x"20");
    signal nl    : integer range 0 to 5 := 0;

begin

    process(clk, reset)
        variable c, c1  : byte_t;          -- caractere em p e em p+1 (00 = fim)
        variable eol    : boolean;
        variable tok    : tok_t;
        variable pt     : pat_t;
        variable d      : integer range -1 to 15;
        variable lim    : integer range 0 to 7;
        variable m      : STD_LOGIC_VECTOR(47 downto 0);
        variable ok     : boolean;
        variable iv     : integer range -16777215 to 16777215;
        variable w      : STD_LOGIC_VECTOR(31 downto 0);
        variable u      : byte_t;
        variable rnum   : integer range -1 to 31;
    begin
        if reset = '1' then
            st          <= S_IDLE;
            instr_out   <= (others => '0');
            instr_valid <= '0';
            parse_err   <= '0';

        elsif rising_edge(clk) then
            instr_valid <= '0';
            parse_err   <= '0';

            -- os dois únicos muxes de caractere do parser
            if p < n then c := b(p); else c := x"00"; end if;
            if p + 1 < n then c1 := b(p + 1); else c1 := x"00"; end if;
            eol := p >= n;
            pt  := pattern(fmt);
            tok := pt(k);

            case st is

                when S_IDLE =>
                    null;

                -- espaços antes do mnemônico
                when S_LEAD =>
                    if c = x"20" then
                        p <= p + 1;
                    else
                        st <= S_MNEM;
                    end if;

                -- mnemônico: tudo até o primeiro espaço (ou fim da linha)
                when S_MNEM =>
                    if c /= x"20" and c /= x"00" then
                        if mlen < 6 then mn(mlen) <= to_upper(c); end if;
                        if mlen < 7 then mlen <= mlen + 1; end if;
                        p <= p + 1;
                    else
                        st <= S_DEC;
                    end if;

                -- tabela de mnemônicos
                when S_DEC =>
                    m := mn(0) & mn(1) & mn(2) & mn(3) & mn(4) & mn(5);
                    k    <= 0;
                    st   <= S_SKIP;
                    fmt  <= F_0; ik <= K_NONE; ek <= E_FIX;
                    opc  <= "0110011"; f3 <= "000"; f7 <= "0000000";
                    size <= 4; srai <= false; fixw <= (others => '0');
                    if mlen > 6 then
                        bad <= true; st <= S_FIN;
                    -- tipo R
                    elsif m = m6("ADD")    then fmt <= F_R; ek <= E_R;
                    elsif m = m6("SUB")    then fmt <= F_R; ek <= E_R; f7 <= "0100000";
                    elsif m = m6("SLL")    then fmt <= F_R; ek <= E_R; f3 <= "001";
                    elsif m = m6("SLT")    then fmt <= F_R; ek <= E_R; f3 <= "010";
                    elsif m = m6("SLTU")   then fmt <= F_R; ek <= E_R; f3 <= "011";
                    elsif m = m6("XOR")    then fmt <= F_R; ek <= E_R; f3 <= "100";
                    elsif m = m6("SRL")    then fmt <= F_R; ek <= E_R; f3 <= "101";
                    elsif m = m6("SRA")    then fmt <= F_R; ek <= E_R; f3 <= "101"; f7 <= "0100000";
                    elsif m = m6("OR")     then fmt <= F_R; ek <= E_R; f3 <= "110";
                    elsif m = m6("AND")    then fmt <= F_R; ek <= E_R; f3 <= "111";
                    elsif m = m6("MUL")    then fmt <= F_R; ek <= E_R; f7 <= "0000001";
                    elsif m = m6("MULH")   then fmt <= F_R; ek <= E_R; f7 <= "0000001"; f3 <= "001";
                    elsif m = m6("MULHSU") then fmt <= F_R; ek <= E_R; f7 <= "0000001"; f3 <= "010";
                    elsif m = m6("MULHU")  then fmt <= F_R; ek <= E_R; f7 <= "0000001"; f3 <= "011";
                    -- tipo I (ULA)
                    elsif m = m6("ADDI")   then fmt <= F_I; ek <= E_I; ik <= K_I12; opc <= "0010011";
                    elsif m = m6("SLTI")   then fmt <= F_I; ek <= E_I; ik <= K_I12; opc <= "0010011"; f3 <= "010";
                    elsif m = m6("SLTIU")  then fmt <= F_I; ek <= E_I; ik <= K_I12; opc <= "0010011"; f3 <= "011";
                    elsif m = m6("XORI")   then fmt <= F_I; ek <= E_I; ik <= K_I12; opc <= "0010011"; f3 <= "100";
                    elsif m = m6("ORI")    then fmt <= F_I; ek <= E_I; ik <= K_I12; opc <= "0010011"; f3 <= "110";
                    elsif m = m6("ANDI")   then fmt <= F_I; ek <= E_I; ik <= K_I12; opc <= "0010011"; f3 <= "111";
                    elsif m = m6("SLLI")   then fmt <= F_I; ek <= E_I; ik <= K_SH;  opc <= "0010011"; f3 <= "001";
                    elsif m = m6("SRLI")   then fmt <= F_I; ek <= E_I; ik <= K_SH;  opc <= "0010011"; f3 <= "101";
                    elsif m = m6("SRAI")   then fmt <= F_I; ek <= E_I; ik <= K_SH;  opc <= "0010011"; f3 <= "101";
                                                srai <= true;
                    -- loads
                    elsif m = m6("LB")     then fmt <= F_MEM; ek <= E_I; ik <= K_MEM; opc <= "0000011"; size <= 1;
                    elsif m = m6("LH")     then fmt <= F_MEM; ek <= E_I; ik <= K_MEM; opc <= "0000011"; size <= 2; f3 <= "001";
                    elsif m = m6("LW")     then fmt <= F_MEM; ek <= E_I; ik <= K_MEM; opc <= "0000011"; f3 <= "010";
                    elsif m = m6("LBU")    then fmt <= F_MEM; ek <= E_I; ik <= K_MEM; opc <= "0000011"; size <= 1; f3 <= "100";
                    elsif m = m6("LHU")    then fmt <= F_MEM; ek <= E_I; ik <= K_MEM; opc <= "0000011"; size <= 2; f3 <= "101";
                    -- stores
                    elsif m = m6("SB")     then fmt <= F_ST; ek <= E_S; ik <= K_MEM; size <= 1;
                    elsif m = m6("SH")     then fmt <= F_ST; ek <= E_S; ik <= K_MEM; size <= 2; f3 <= "001";
                    elsif m = m6("SW")     then fmt <= F_ST; ek <= E_S; ik <= K_MEM; f3 <= "010";
                    -- desvios
                    elsif m = m6("BEQ")    then fmt <= F_B; ek <= E_B; ik <= K_B;
                    elsif m = m6("BNE")    then fmt <= F_B; ek <= E_B; ik <= K_B; f3 <= "001";
                    elsif m = m6("BLT")    then fmt <= F_B; ek <= E_B; ik <= K_B; f3 <= "100";
                    elsif m = m6("BGE")    then fmt <= F_B; ek <= E_B; ik <= K_B; f3 <= "101";
                    elsif m = m6("BLTU")   then fmt <= F_B; ek <= E_B; ik <= K_B; f3 <= "110";
                    elsif m = m6("BGEU")   then fmt <= F_B; ek <= E_B; ik <= K_B; f3 <= "111";
                    -- saltos e tipo U
                    elsif m = m6("JAL")    then fmt <= F_RN;  ek <= E_J; ik <= K_J;
                    elsif m = m6("JALR")   then fmt <= F_MEM; ek <= E_I; ik <= K_JALR; opc <= "1100111";
                    elsif m = m6("LUI")    then fmt <= F_RN;  ek <= E_U; ik <= K_U; opc <= "0110111";
                    elsif m = m6("AUIPC")  then fmt <= F_RN;  ek <= E_U; ik <= K_U; opc <= "0010111";
                    -- pseudoinstruções
                    elsif m = m6("LI")     then fmt <= F_RN;  ek <= E_I; ik <= K_I12; opc <= "0010011";
                    elsif m = m6("MV")     then fmt <= F_MV;  ek <= E_I; opc <= "0010011";
                    elsif m = m6("RET")    then fixw <= x"00008067";      -- jalr x0,0(x1)
                    elsif m = m6("NOP")    then fixw <= x"00000013";      -- addi x0,x0,0
                    elsif m = m6("JR")     then fmt <= F_JR; ek <= E_I; opc <= "1100111";  -- jalr x0,0(rs)
                    elsif m = m6("J")      then fmt <= F_JN; ek <= E_J; ik <= K_J;         -- jal x0,desl
                    -- sistema
                    elsif m = m6("FENCE")  then fixw <= x"0FF0000F";      -- fence iorw,iorw
                    elsif m = m6("ECALL")  then fixw <= x"00000073";
                    elsif m = m6("EBREAK") then fixw <= x"00100073";
                    else
                        bad <= true; st <= S_FIN;                       -- desconhecido
                    end if;

                -- espaços antes de cada item
                when S_SKIP =>
                    if c = x"20" then
                        p <= p + 1;
                    else
                        st <= S_TOK;
                    end if;

                -- início de cada item do formato
                when S_TOK =>
                    case tok is
                        when T_END =>
                            if not eol then bad <= true; end if;    -- sobrou texto
                            st <= S_FIN;
                        when T_COMMA | T_LPAR | T_RPAR =>
                            if (tok = T_COMMA and c = x"2C") or
                               (tok = T_LPAR  and c = x"28") or
                               (tok = T_RPAR  and c = x"29") then
                                p <= p + 1; k <= k + 1; st <= S_SKIP;
                            else
                                bad <= true; st <= S_FIN;
                            end if;
                        when T_RD | T_RS1 | T_RS2 =>
                            u := to_upper(c);
                            if u = x"58" then                       -- 'X': x0..x31
                                p <= p + 1; acc <= 0; cnt <= 0; st <= S_REGD;
                            elsif is_letter(u) then                 -- nome da ABI
                                rl <= (others => x"20"); nl <= 0;
                                acc <= 0; cnt <= 0; st <= S_REGN;
                            elsif tok = T_RD and ek = E_J and (dec_val(c) >= 0 or c = x"2D") then
                                -- "jal desl": só o deslocamento, rd = ra (x1)
                                rd <= 1; k <= k + 2;                -- pula rd e a vírgula
                                neg <= c = x"2D";
                                if c = x"2D" then p <= p + 1; end if;
                                st <= S_NUMP;
                            else
                                bad <= true; st <= S_FIN;
                            end if;
                        when others =>                              -- T_NUM, T_HEX
                            neg <= c = x"2D";                       -- '-'
                            if c = x"2D" then p <= p + 1; end if;
                            st <= S_NUMP;
                    end case;

                -- dígitos do registrador: 1 ou 2, valor 0..31
                when S_REGD =>
                    d := dec_val(c);
                    if d >= 0 then
                        if cnt < 2 then acc <= acc * 10 + d; end if;
                        if cnt < 3 then cnt <= cnt + 1; end if;
                        p <= p + 1;
                    elsif cnt = 0 or cnt > 2 or acc > 31 then
                        bad <= true; st <= S_FIN;
                    else
                        if    tok = T_RD  then rd  <= acc;
                        elsif tok = T_RS1 then rs1 <= acc;
                        else                   rs2 <= acc;
                        end if;
                        k <= k + 1; st <= S_SKIP;
                    end if;

                -- nome da ABI: letras e depois dígitos (a0, s11, zero, sp)
                when S_REGN =>
                    u := to_upper(c);
                    d := dec_val(c);
                    if is_letter(u) and cnt = 0 then
                        if nl < 4 then rl(nl) <= u; end if;
                        if nl < 5 then nl <= nl + 1; end if;
                        p <= p + 1;
                    elsif d >= 0 then
                        if cnt < 2 then acc <= acc * 10 + d; end if;
                        if cnt < 3 then cnt <= cnt + 1; end if;
                        p <= p + 1;
                    else
                        if nl > 4 or cnt > 2 then rnum := -1;
                        else rnum := abi_num(rl(0), rl(1), rl(2), rl(3), nl, acc, cnt);
                        end if;
                        if rnum < 0 then
                            bad <= true; st <= S_FIN;
                        else
                            if    tok = T_RD  then rd  <= rnum;
                            elsif tok = T_RS1 then rs1 <= rnum;
                            else                   rs2 <= rnum;
                            end if;
                            k <= k + 1; st <= S_SKIP;
                        end if;
                    end if;

                -- prefixo "0x" (opcional; nos números fora dos parênteses
                -- define a base, dentro dos parênteses a base já é 16)
                when S_NUMP =>
                    acc <= 0; cnt <= 0;
                    if c = x"30" and to_upper(c1) = x"58" then
                        hexm <= true; p <= p + 2;
                    else
                        hexm <= tok = T_HEX;
                    end if;
                    st <= S_NUMD;

                -- dígitos: decimal até 7, hex com 0x até 5, desl. de memória até 4
                when S_NUMD =>
                    if tok = T_HEX then lim := 4;
                    elsif hexm     then lim := 5;
                    else                lim := 7;
                    end if;
                    if hexm then d := hex_val(c); else d := dec_val(c); end if;
                    if d >= 0 then
                        if cnt < lim then
                            if hexm then acc <= acc * 16 + d;
                            else         acc <= acc * 10 + d;
                            end if;
                        end if;
                        if cnt <= lim then cnt <= cnt + 1; end if;
                        p <= p + 1;
                    elsif cnt = 0 or cnt > lim then
                        bad <= true; st <= S_FIN;
                    else
                        if neg then imm <= -acc; else imm <= acc; end if;
                        k <= k + 1; st <= S_SKIP;
                    end if;

                -- faixas, codificação e resultado
                when S_FIN =>
                    ok := not bad;
                    case ik is
                        when K_I12  => ok := ok and imm >= -2048 and imm <= 2047;
                        when K_SH   => ok := ok and imm >= 0 and imm <= 31;
                        when K_MEM  => ok := ok and imm >= -2048 and imm <= 2047 and
                                         not (size = 4 and (imm mod 4) /= 0) and
                                         not (size = 2 and (imm mod 2) /= 0) and
                                         not (rs1 = 0 and (imm < 0 or imm > 128 - size));
                        when K_JALR => ok := ok and imm >= -2048 and imm <= 2047 and (imm mod 4) = 0;
                        when K_B    => ok := ok and imm >= -4096 and imm <= 4092 and (imm mod 4) = 0;
                        when K_J    => ok := ok and imm >= -1048576 and imm <= 1048572 and (imm mod 4) = 0;
                        when K_U    => ok := ok and imm >= 0 and imm <= 1048575;
                        when others => null;
                    end case;
                    iv := 0;
                    if ok then
                        iv := imm;
                        if srai then iv := imm + 1024; end if;     -- funct7 0100000
                    end if;
                    case ek is
                        when E_R    => w := enc_r(f7, rs2, rs1, f3, rd);
                        when E_I    => w := enc_i(iv, rs1, f3, rd, opc);
                        when E_S    => w := enc_s(iv, rs2, rs1, f3);
                        when E_B    => w := enc_b(iv, rs1, rs2, f3);
                        when E_U    => w := enc_u(iv, rd, opc);
                        when E_J    => w := enc_j(iv, rd);
                        when others => w := fixw;
                    end case;
                    if ok then
                        instr_out   <= w;
                        instr_valid <= '1';
                    else
                        instr_out   <= (others => '0');
                        parse_err   <= '1';
                    end if;
                    st <= S_IDLE;
            end case;

            -- nova linha: copia e recomeça (tem prioridade sobre o resto)
            if parse_en = '1' then
                for i in 0 to 19 loop
                    b(i) <= line_buf(159 - 8*i downto 152 - 8*i);
                end loop;
                if line_len > 20 then n <= 20; else n <= to_integer(line_len); end if;
                p    <= 0;
                mn   <= (others => x"20");
                mlen <= 0;
                bad  <= false;
                rd   <= 0; rs1 <= 0; rs2 <= 0; imm <= 0;
                fmt  <= F_0;
                st   <= S_LEAD;
            end if;
        end if;
    end process;

end architecture;