library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity top_de2115 is
    generic(
        DEB_CYCLES : natural := 249999;    -- 5 ms a 50 MHz
        RUN_HALF   : natural := 2499999;   -- 10 Hz
        TURBO_HALF : positive := 1;        -- 25 MHz (CLOCK_50 / 2)
        IMEM_BITS  : positive := 7;        -- 128 instruções
        TEXT_BASE  : natural  := 16#3000#; -- endereço da 1ª instrução (PC no reset)
        STACK_TOP  : natural  := 16#80#;   -- topo da área da pilha (40-7F) no VGA
        SP_INIT    : natural  := 16#80#    -- x2 (sp) no reset: o topo da pilha,
                                           -- como o RARS faz. 0 = como os outros
                                           -- registradores; aí o programa precisa
                                           -- iniciar o sp (li sp,0x80)
    );
    port(
        CLOCK_50 : in    STD_LOGIC;
        KEY      : in    STD_LOGIC_VECTOR(3 downto 0);
        SW       : in    STD_LOGIC_VECTOR(17 downto 0);
        PS2_CLK  : in    STD_LOGIC;
        PS2_DAT  : in    STD_LOGIC;
        HEX0     : out   STD_LOGIC_VECTOR(6 downto 0);
        HEX1     : out   STD_LOGIC_VECTOR(6 downto 0);
        HEX2     : out   STD_LOGIC_VECTOR(6 downto 0);
        HEX3     : out   STD_LOGIC_VECTOR(6 downto 0);
        HEX4     : out   STD_LOGIC_VECTOR(6 downto 0);
        HEX5     : out   STD_LOGIC_VECTOR(6 downto 0);
        HEX6     : out   STD_LOGIC_VECTOR(6 downto 0);
        HEX7     : out   STD_LOGIC_VECTOR(6 downto 0);
        LEDR     : out   STD_LOGIC_VECTOR(17 downto 0);
        LEDG     : out   STD_LOGIC_VECTOR(7 downto 0);
        LCD_DATA : out   STD_LOGIC_VECTOR(7 downto 0);
        LCD_EN   : out   STD_LOGIC;
        LCD_RS   : out   STD_LOGIC;
        LCD_RW   : out   STD_LOGIC;
        LCD_ON   : out   STD_LOGIC;
        LCD_BLON : out   STD_LOGIC;
        VGA_CLK     : out   STD_LOGIC;
        VGA_HS      : out   STD_LOGIC;
        VGA_VS      : out   STD_LOGIC;
        VGA_BLANK_N : out   STD_LOGIC;
        VGA_SYNC_N  : out   STD_LOGIC;
        VGA_R       : out   STD_LOGIC_VECTOR(7 downto 0);
        VGA_G       : out   STD_LOGIC_VECTOR(7 downto 0);
        VGA_B       : out   STD_LOGIC_VECTOR(7 downto 0)
    );
end entity;

architecture struct of top_de2115 is

    -- ══════════════════════════════════════════════════════════════════════════
    -- Componentes
    -- ══════════════════════════════════════════════════════════════════════════

    component ps2_receiver
        port(clk : in STD_LOGIC; reset : in STD_LOGIC;
             ps2_clk : in STD_LOGIC; ps2_dat : in STD_LOGIC;
             scan_code : out STD_LOGIC_VECTOR(7 downto 0); data_valid : out STD_LOGIC);
    end component;

    component ps2_to_ascii
        port(clk : in STD_LOGIC; reset : in STD_LOGIC;
             scan_code : in STD_LOGIC_VECTOR(7 downto 0); data_valid : in STD_LOGIC;
             ascii_out : out STD_LOGIC_VECTOR(7 downto 0); ascii_valid : out STD_LOGIC;
             nav_up : out STD_LOGIC; nav_down : out STD_LOGIC;
             nav_home : out STD_LOGIC; nav_end : out STD_LOGIC;
             nav_pgup : out STD_LOGIC; nav_pgdn : out STD_LOGIC);
    end component;

    component keyboard_buffer
        port(clk : in STD_LOGIC; reset : in STD_LOGIC;
             ascii_in : in STD_LOGIC_VECTOR(7 downto 0); ascii_valid : in STD_LOGIC;
             line_buf : out STD_LOGIC_VECTOR(159 downto 0);
             line_len : out UNSIGNED(4 downto 0); parse_en : out STD_LOGIC;
             live_buf : out STD_LOGIC_VECTOR(159 downto 0);
             live_len : out UNSIGNED(4 downto 0));
    end component;

    component asm_parser
        port(clk : in STD_LOGIC; reset : in STD_LOGIC;
             line_buf : in STD_LOGIC_VECTOR(159 downto 0);
             line_len : in UNSIGNED(4 downto 0); parse_en : in STD_LOGIC;
             instr_out : out STD_LOGIC_VECTOR(31 downto 0);
             instr_valid : out STD_LOGIC; parse_err : out STD_LOGIC);
    end component;

    component imem_writable
        generic(ABITS : positive);
        port(clk   : in STD_LOGIC;
             we    : in STD_LOGIC;
             waddr : in STD_LOGIC_VECTOR(ABITS-1 downto 0);
             wdata : in STD_LOGIC_VECTOR(31 downto 0);
             raddr : in STD_LOGIC_VECTOR(ABITS-1 downto 0);
             rdata : out STD_LOGIC_VECTOR(31 downto 0);
             vaddr : in STD_LOGIC_VECTOR(ABITS-1 downto 0);
             vdata : out STD_LOGIC_VECTOR(31 downto 0));
    end component;

    component riscvsingle
        generic(TEXT_BASE, SP_INIT : natural);
        port(clk, reset : in STD_LOGIC;
             PC         : out STD_LOGIC_VECTOR(31 downto 0);
             Instr      : in  STD_LOGIC_VECTOR(31 downto 0);
             MemWrite   : out STD_LOGIC;
             ALUResult  : out STD_LOGIC_VECTOR(31 downto 0);
             WriteData  : out STD_LOGIC_VECTOR(31 downto 0);
             ReadData   : in  STD_LOGIC_VECTOR(31 downto 0);
             SysWE      : in  STD_LOGIC;
             SysWD      : in  STD_LOGIC_VECTOR(31 downto 0);
             SysA0      : out STD_LOGIC_VECTOR(31 downto 0);
             SysA7      : out STD_LOGIC_VECTOR(31 downto 0));
    end component;

    component console_buf
        generic(ROWS, COLS : positive);
        port(clk, rst : in  STD_LOGIC;
             put      : in  STD_LOGIC;
             ch       : in  STD_LOGIC_VECTOR(7 downto 0);
             flat     : out STD_LOGIC_VECTOR(ROWS*COLS*8-1 downto 0));
    end component;

    component lcd_controller
        port(clk      : in  STD_LOGIC;
             reset    : in  STD_LOGIC;
             line1    : in  STD_LOGIC_VECTOR(127 downto 0);
             line2    : in  STD_LOGIC_VECTOR(127 downto 0);
             LCD_DATA : out STD_LOGIC_VECTOR(7 downto 0);
             LCD_EN   : out STD_LOGIC;
             LCD_RS   : out STD_LOGIC;
             LCD_RW   : out STD_LOGIC;
             LCD_ON   : out STD_LOGIC;
             LCD_BLON : out STD_LOGIC);
    end component;

    component vga_display
        generic(IMEM_BITS : positive; TEXT_BASE : natural; STACK_TOP : natural);
        port(
            clk_50      : in  STD_LOGIC;
            reset       : in  STD_LOGIC;
            proc_pc     : in  STD_LOGIC_VECTOR(31 downto 0);
            proc_instr  : in  STD_LOGIC_VECTOR(31 downto 0);
            proc_halt   : in  STD_LOGIC;
            write_addr  : in  UNSIGNED(IMEM_BITS downto 0);
            steps_bcd   : in  STD_LOGIC_VECTOR(31 downto 0);
            turbo       : in  STD_LOGIC;
            view_idx    : out UNSIGNED(IMEM_BITS-1 downto 0);
            view_word   : in  STD_LOGIC_VECTOR(31 downto 0);
            view_count  : in  UNSIGNED(IMEM_BITS downto 0);
            edit_on     : in  STD_LOGIC;
            edit_ptr    : in  UNSIGNED(IMEM_BITS downto 0);
            parse_err   : in  STD_LOGIC;
            diag_mode   : in  STD_LOGIC;
            demo_sel    : in  STD_LOGIC_VECTOR(4 downto 0);
            speed_sel   : in  STD_LOGIC_VECTOR(1 downto 0);
            regs        : in  STD_LOGIC_VECTOR(1023 downto 0);
            dmem        : in  STD_LOGIC_VECTOR(1023 downto 0);
            reg_hex     : in  STD_LOGIC;
            abi_names   : in  STD_LOGIC;
            hl_reg      : in  STD_LOGIC_VECTOR(5 downto 0);
            hl_mem      : in  STD_LOGIC_VECTOR(5 downto 0);
            kbd_line    : in  STD_LOGIC_VECTOR(159 downto 0);
            kbd_len     : in  UNSIGNED(4 downto 0);
            con_flat    : in  STD_LOGIC_VECTOR(6*48*8-1 downto 0);
            in_wait     : in  STD_LOGIC;
            VGA_CLK     : out STD_LOGIC;
            VGA_HS      : out STD_LOGIC;
            VGA_VS      : out STD_LOGIC;
            VGA_BLANK_N : out STD_LOGIC;
            VGA_SYNC_N  : out STD_LOGIC;
            VGA_R       : out STD_LOGIC_VECTOR(7 downto 0);
            VGA_G       : out STD_LOGIC_VECTOR(7 downto 0);
            VGA_B       : out STD_LOGIC_VECTOR(7 downto 0)
        );
    end component;

    -- ══════════════════════════════════════════════════════════════════════════
    -- Sinais
    -- ══════════════════════════════════════════════════════════════════════════

    -- ── Sincronização das entradas mecânicas (2 FFs, evita metaestabilidade) ─
    signal key_s0, key_s  : STD_LOGIC_VECTOR(3 downto 0) := "1111";
    -- SW[10:6] & SW[2]: número da demo e modo demo (sincronizados)
    signal mode_s0, mode_s1, mode_prev : STD_LOGIC_VECTOR(5 downto 0) := "000000";

    -- ── Domínios de reset ───────────────────────────────────────────────────
    --   prog_rst : KEY[0]            → apaga programa + teclado + CPU
    --   key1_rst : KEY[1]            → só CPU (programa preservado)
    --   mode_rst : troca de SW[2] (ou de SW[10:6] no modo demo) → só CPU (pulso de 1 ciclo)
    --   ld_busy  : carregando demo   → só CPU (enquanto copia)
    --   edit_rst : linha sobrescrita → só CPU (pulso de 1 ciclo)
    --   cpu_rst  = prog_rst or key1_rst or mode_rst or edit_rst or ld_busy
    signal prog_rst       : STD_LOGIC := '1';
    signal key1_rst       : STD_LOGIC := '1';
    signal mode_rst       : STD_LOGIC := '0';
    signal edit_rst       : STD_LOGIC := '0';
    signal cpu_rst        : STD_LOGIC;
    signal kbd_reset      : STD_LOGIC;
    signal proc_reset     : STD_LOGIC;

    signal proc_clk       : STD_LOGIC;
    signal proc_halt      : STD_LOGIC := '1';

    signal scan_code_s    : STD_LOGIC_VECTOR(7 downto 0);
    signal ps2_dvalid     : STD_LOGIC;
    signal ascii_char_s   : STD_LOGIC_VECTOR(7 downto 0);
    signal ascii_val_s    : STD_LOGIC;

    signal line_buf_s     : STD_LOGIC_VECTOR(159 downto 0);
    signal line_len_s     : UNSIGNED(4 downto 0);
    signal parse_en_s     : STD_LOGIC;
    signal kbd_buf_s      : STD_LOGIC_VECTOR(159 downto 0);  -- linha sendo digitada → VGA
    signal kbd_len_s      : UNSIGNED(4 downto 0);            -- posição do cursor
    signal instr_out_s    : STD_LOGIC_VECTOR(31 downto 0);
    signal instr_valid_s  : STD_LOGIC;
    signal parse_err_s    : STD_LOGIC;

    -- ── Ponteiro de escrita: 0..2**IMEM_BITS ────────────────────────────────
    -- write_addr_s = quantidade de instruções gravadas = próximo slot livre
    signal write_addr_s   : UNSIGNED(IMEM_BITS downto 0) := (others => '0');
    signal imem_full      : STD_LOGIC;
    signal imem_we        : STD_LOGIC;                        -- linha do teclado
    signal ram_we         : STD_LOGIC;                        -- teclado ou demo
    signal ram_waddr      : STD_LOGIC_VECTOR(IMEM_BITS-1 downto 0);
    signal ram_wdata      : STD_LOGIC_VECTOR(31 downto 0);

    -- ── Carregador de demo (copia a ROM para a memória de instruções) ──────
    signal demo_on        : STD_LOGIC;                        -- SW[2] sincronizado
    signal prog_rst_prev  : STD_LOGIC := '1';
    signal ld_busy        : STD_LOGIC := '0';
    signal ld_fin         : STD_LOGIC := '0';                 -- pulso: terminou
    signal ld_we          : STD_LOGIC := '0';
    signal ld_sel         : integer range 0 to 31 := 0;
    signal ld_idx         : integer range 0 to 511 := 0;
    signal ld_addr        : STD_LOGIC_VECTOR(IMEM_BITS-1 downto 0) := (others => '0');
    signal ld_data        : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');

    -- ── Edição (CPU desligada + modo teclado) ──────────────────────────────
    signal nav_up, nav_down, nav_home, nav_end : STD_LOGIC;
    signal nav_pgup, nav_pgdn : STD_LOGIC;
    signal edit_on        : STD_LOGIC;                        -- modo edição
    signal edit_ptr       : UNSIGNED(IMEM_BITS downto 0) := (others => '0'); -- slot do próximo ENTER
    signal edit_ovr       : STD_LOGIC;                        -- ENTER sobrescreve

    -- ── Indicadores persistentes da última linha digitada ──────────────────
    signal ok_hold        : STD_LOGIC := '0';
    signal err_hold       : STD_LOGIC := '0';

    signal proc_pc        : STD_LOGIC_VECTOR(31 downto 0);
    signal proc_instr     : STD_LOGIC_VECTOR(31 downto 0);
    signal proc_instr_mux : STD_LOGIC_VECTOR(31 downto 0);
    signal proc_memwrite  : STD_LOGIC;
    signal proc_alu       : STD_LOGIC_VECTOR(31 downto 0);
    signal proc_wdata     : STD_LOGIC_VECTOR(31 downto 0);
    signal proc_rdata     : STD_LOGIC_VECTOR(31 downto 0);   -- dado para a CPU (já com lb/lh)
    signal proc_rword     : STD_LOGIC_VECTOR(31 downto 0);   -- palavra lida da memória

    -- Memória de dados: 32 palavras com nomes próprios (o Quartus não infere
    -- RAM em bloco a partir delas); 00-3F = dados, 40-7F = pilha
    signal dmem_00, dmem_01, dmem_02, dmem_03 : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal dmem_04, dmem_05, dmem_06, dmem_07 : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal dmem_08, dmem_09, dmem_10, dmem_11 : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal dmem_12, dmem_13, dmem_14, dmem_15 : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal dmem_16, dmem_17, dmem_18, dmem_19 : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal dmem_20, dmem_21, dmem_22, dmem_23 : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal dmem_24, dmem_25, dmem_26, dmem_27 : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal dmem_28, dmem_29, dmem_30, dmem_31 : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');

    -- LCD 16x2: título fixo (ASCII, char 0 nos bits 127:120)
    --   "  PROCESSADOR   "
    --   "RISC-V MONOCICLO"
    constant LCD_L1 : STD_LOGIC_VECTOR(127 downto 0) := x"202050524F4345535341444F52202020";
    constant LCD_L2 : STD_LOGIC_VECTOR(127 downto 0) := x"524953432D56204D4F4E4F4349434C4F";

    -- ── Shadow register file (x0..x31) para o VGA ──────────────────────────
    type reg_arr_t is array(0 to 31) of STD_LOGIC_VECTOR(31 downto 0);
    signal shadow_regs : reg_arr_t := (others => (others => '0'));

    signal regs_flat : STD_LOGIC_VECTOR(1023 downto 0) := (others => '0');
    signal dmem_flat : STD_LOGIC_VECTOR(1023 downto 0) := (others => '0');

    signal proc_clk_r   : STD_LOGIC := '0';
    signal run_cnt      : natural range 0 to RUN_HALF := 0;
    signal key3_prev    : STD_LOGIC := '1';
    signal key3_deb     : STD_LOGIC := '1';

    -- ── Latch pipeline para o shadow (domínio CLOCK_50) ────────────────────
    signal instr_latch     : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal alu_latch       : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal pc_latch        : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal rdata_latch     : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal memw_latch      : STD_LOGIC := '0';
    -- Destaque no VGA: último registrador e última palavra de memória
    -- escritos (bit mais alto = válido). Zerados junto com a CPU.
    signal hl_reg          : STD_LOGIC_VECTOR(5 downto 0) := (others => '0');
    signal hl_mem          : STD_LOGIC_VECTOR(5 downto 0) := (others => '0');
    signal shadow_clk_prev : STD_LOGIC := '0';

    -- ── Painel "Programa" do VGA: pede um slot, recebe a palavra ──────────
    signal view_idx        : UNSIGNED(IMEM_BITS-1 downto 0);
    signal view_word       : STD_LOGIC_VECTOR(31 downto 0);

    -- ── Serviços do ecall (entrega 50) ────────────────────────────────────
    signal sys_a0, sys_a7  : STD_LOGIC_VECTOR(31 downto 0);   -- a0 e a7 do banco
    signal sys_we          : STD_LOGIC := '0';                -- escreve a0 (a7 = 5)
    signal sys_wd          : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal is_ecall        : STD_LOGIC;                       -- PC num ecall
    signal svc_ok          : STD_LOGIC;                       -- a7 é 1, 4, 5 ou 11
    signal sys_done        : STD_LOGIC := '0';                -- serviço deste ecall feito
    signal sys_hold        : STD_LOGIC;                       -- segura a borda da CPU
    signal sys_go          : STD_LOGIC := '0';                -- pedido do gerador de clock
    signal step_pend       : STD_LOGIC := '0';                -- STEP esperando o serviço
    type sys_st_t is (SY_IDLE, SY_INT, SY_NL, SY_STR, SY_WAIT, SY_PARSE, SY_FIN);
    signal sys_st          : sys_st_t := SY_IDLE;
    signal sys_wait        : STD_LOGIC;                       -- esperando o número (a7 = 5)
    signal input_mode      : STD_LOGIC;                       -- ENTER vai para o número
    signal parse_en_asm    : STD_LOGIC;                       -- ENTER vai para o montador
    signal sys_err, sys_okin : STD_LOGIC := '0';              -- número inválido / aceito
    signal num_mag         : UNSIGNED(31 downto 0) := (others => '0');
    signal num_k           : integer range 0 to 9 := 9;
    signal num_dig         : UNSIGNED(3 downto 0) := (others => '0');
    signal num_started     : STD_LOGIC := '0';
    signal num_echo        : STD_LOGIC := '0';
    signal str_addr        : UNSIGNED(6 downto 0) := (others => '0');
    signal str_cnt         : integer range 0 to 128 := 0;
    signal str_word        : STD_LOGIC_VECTOR(31 downto 0);
    signal str_byte        : STD_LOGIC_VECTOR(7 downto 0);
    signal in_i            : integer range 0 to 20 := 0;
    signal in_acc          : UNSIGNED(31 downto 0) := (others => '0');
    signal in_neg          : STD_LOGIC := '0';
    signal in_ph           : integer range 0 to 3 := 0;  -- 0 espaços, 1 sinal, 2 dígitos, 3 espaços
    signal in_bad          : STD_LOGIC := '0';
    signal con_put         : STD_LOGIC := '0';
    signal con_ch          : STD_LOGIC_VECTOR(7 downto 0) := x"20";
    signal con_flat        : STD_LOGIC_VECTOR(6*48*8-1 downto 0);

    -- ── Contador de passos: 8 dígitos BCD (31:28 .. 3:0 unidade) ──────────
    signal steps_bcd       : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal turbo_on        : STD_LOGIC;

    -- ── ROM das demos (gerada por demos10.py a partir das palavras do montador
    --    GNU, as mesmas conferidas na simulação). A demo n (SW[10:6]) ocupa
    --    DEMO_LEN(n) palavras a partir de DEMO_BASE(n). Os rótulos dos
    --    comentários são só documentação: a palavra já tem o deslocamento.
    type demo_rom_t is array(0 to 1023) of STD_LOGIC_VECTOR(31 downto 0);
    constant DEMO_ROM : demo_rom_t := (
           0 => x"00C00293",   -- D1 3000: li t0,12
           1 => x"00500313",   -- D1 3004: li t1,5
           2 => x"006283B3",   -- D1 3008: add t2,t0,t1
           3 => x"40628E33",   -- D1 300C: sub t3,t0,t1
           4 => x"40530EB3",   -- D1 3010: sub t4,t1,t0
           5 => x"FEC38F13",   -- D1 3014: addi t5,t2,-20
           6 => x"00900013",   -- D1 3018: addi zero,zero,9
           7 => x"05A00293",   -- D2 3000: li t0,0x5a
           8 => x"00F00313",   -- D2 3004: li t1,0x0f
           9 => x"0062F3B3",   -- D2 3008: and t2,t0,t1
          10 => x"0062EE33",   -- D2 300C: or t3,t0,t1
          11 => x"0062CEB3",   -- D2 3010: xor t4,t0,t1
          12 => x"FFF2CF13",   -- D2 3014: xori t5,t0,-1
          13 => x"0F02FF93",   -- D2 3018: andi t6,t0,0xf0
          14 => x"00300293",   -- D3 3000: li t0,3
          15 => x"00429313",   -- D3 3004: slli t1,t0,4
          16 => x"FC000393",   -- D3 3008: li t2,-64
          17 => x"4023DE13",   -- D3 300C: srai t3,t2,2
          18 => x"0023DE93",   -- D3 3010: srli t4,t2,2
          19 => x"00A00F13",   -- D3 3014: li t5,10
          20 => x"01E29FB3",   -- D3 3018: sll t6,t0,t5
          21 => x"FFF00293",   -- D4 3000: li t0,-1
          22 => x"00100313",   -- D4 3004: li t1,1
          23 => x"0062A3B3",   -- D4 3008: slt t2,t0,t1
          24 => x"0062BE33",   -- D4 300C: sltu t3,t0,t1
          25 => x"00532E93",   -- D4 3010: slti t4,t1,5
          26 => x"00133F13",   -- D4 3014: sltiu t5,t1,1
          27 => x"00603FB3",   -- D4 3018: sltu t6,zero,t1
          28 => x"123452B7",   -- D5 3000: lui t0,0x12345
          29 => x"67828293",   -- D5 3004: addi t0,t0,0x678
          30 => x"DEADC337",   -- D5 3008: lui t1,0xdeadc
          31 => x"EEF30313",   -- D5 300C: addi t1,t1,-0x111
          32 => x"800003B7",   -- D5 3010: lui t2,0x80000
          33 => x"FFF38E13",   -- D5 3014: addi t3,t2,-1
          34 => x"00000E97",   -- D5 3018: auipc t4,0
          35 => x"00700293",   -- D6 3000: li t0,7
          36 => x"FFA00313",   -- D6 3004: li t1,-6
          37 => x"026283B3",   -- D6 3008: mul t2,t0,t1
          38 => x"00018E37",   -- D6 300C: lui t3,0x18
          39 => x"6A0E0E13",   -- D6 3010: addi t3,t3,0x6a0
          40 => x"03CE0EB3",   -- D6 3014: mul t4,t3,t3
          41 => x"03CE3F33",   -- D6 3018: mulhu t5,t3,t3
          42 => x"03C31FB3",   -- D6 301C: mulh t6,t1,t3
          43 => x"01900293",   -- D7 3000: li t0,25
          44 => x"00502023",   -- D7 3004: sw t0,0(zero)
          45 => x"01100293",   -- D7 3008: li t0,17
          46 => x"00502223",   -- D7 300C: sw t0,4(zero)
          47 => x"00002303",   -- D7 3010: lw t1,0(zero)
          48 => x"00402383",   -- D7 3014: lw t2,4(zero)
          49 => x"00730E33",   -- D7 3018: add t3,t1,t2
          50 => x"01C02423",   -- D7 301C: sw t3,8(zero)
          51 => x"001E1E93",   -- D7 3020: slli t4,t3,1
          52 => x"01D02623",   -- D7 3024: sw t4,c(zero)
          53 => x"01000413",   -- D8 3000: li s0,0x10
          54 => x"00A00293",   -- D8 3004: li t0,10
          55 => x"00542023",   -- D8 3008: sw t0,0(s0)
          56 => x"01400293",   -- D8 300C: li t0,20
          57 => x"00542223",   -- D8 3010: sw t0,4(s0)
          58 => x"01E00293",   -- D8 3014: li t0,30
          59 => x"00542423",   -- D8 3018: sw t0,8(s0)
          60 => x"00442303",   -- D8 301C: lw t1,4(s0)
          61 => x"00200393",   -- D8 3020: li t2,2
          62 => x"00239E13",   -- D8 3024: slli t3,t2,2
          63 => x"01C40E33",   -- D8 3028: add t3,s0,t3
          64 => x"000E2E83",   -- D8 302C: lw t4,0(t3)
          65 => x"05200293",   -- D9 3000: li t0,0x52
          66 => x"00500023",   -- D9 3004: sb t0,0(zero)
          67 => x"04900293",   -- D9 3008: li t0,0x49
          68 => x"005000A3",   -- D9 300C: sb t0,1(zero)
          69 => x"05300293",   -- D9 3010: li t0,0x53
          70 => x"00500123",   -- D9 3014: sb t0,2(zero)
          71 => x"04300293",   -- D9 3018: li t0,0x43
          72 => x"005001A3",   -- D9 301C: sb t0,3(zero)
          73 => x"FFE00313",   -- D9 3020: li t1,-2
          74 => x"00601223",   -- D9 3024: sh t1,4(zero)
          75 => x"00000383",   -- D9 3028: lb t2,0(zero)
          76 => x"00401E03",   -- D9 302C: lh t3,4(zero)
          77 => x"00405E83",   -- D9 3030: lhu t4,4(zero)
          78 => x"00500F03",   -- D9 3034: lb t5,5(zero)
          79 => x"00504F83",   -- D9 3038: lbu t6,5(zero)
          80 => x"FF900413",   -- D10 3000: li s0,-7
          81 => x"00400493",   -- D10 3004: li s1,4
          82 => x"00045463",   -- D10 3008: bge s0,zero,8
          83 => x"40800433",   -- D10 300C: sub s0,zero,s0
          84 => x"0084C663",   -- D10 3010: pos: blt s1,s0,12
          85 => x"00048913",   -- D10 3014: mv s2,s1
          86 => x"0080006F",   -- D10 3018: j 8
          87 => x"00040913",   -- D10 301C: xmaior: mv s2,s0
          88 => x"00A00413",   -- D11 3000: li s0,10
          89 => x"00000493",   -- D11 3004: li s1,0
          90 => x"00100293",   -- D11 3008: li t0,1
          91 => x"00544863",   -- D11 300C: laco: blt s0,t0,16
          92 => x"005484B3",   -- D11 3010: add s1,s1,t0
          93 => x"00128293",   -- D11 3014: addi t0,t0,1
          94 => x"FF5FF06F",   -- D11 3018: j -12
          95 => x"00000413",   -- D12 3000: li s0,0
          96 => x"00100493",   -- D12 3004: li s1,1
          97 => x"00000293",   -- D12 3008: li t0,0
          98 => x"04000313",   -- D12 300C: li t1,0x40
          99 => x"0082A023",   -- D12 3010: laco: sw s0,0(t0)
         100 => x"009403B3",   -- D12 3014: add t2,s0,s1
         101 => x"00048413",   -- D12 3018: mv s0,s1
         102 => x"00038493",   -- D12 301C: mv s1,t2
         103 => x"00428293",   -- D12 3020: addi t0,t0,4
         104 => x"FE6296E3",   -- D12 3024: bne t0,t1,-20
         105 => x"00700293",   -- D13 3000: li t0,7
         106 => x"00502023",   -- D13 3004: sw t0,0(zero)
         107 => x"FFD00293",   -- D13 3008: li t0,-3
         108 => x"00502223",   -- D13 300C: sw t0,4(zero)
         109 => x"00C00293",   -- D13 3010: li t0,12
         110 => x"00502423",   -- D13 3014: sw t0,8(zero)
         111 => x"00500293",   -- D13 3018: li t0,5
         112 => x"00502623",   -- D13 301C: sw t0,c(zero)
         113 => x"00000413",   -- D13 3020: li s0,0
         114 => x"01000493",   -- D13 3024: li s1,0x10
         115 => x"00000913",   -- D13 3028: li s2,0
         116 => x"00002983",   -- D13 302C: lw s3,0(zero)
         117 => x"00002A03",   -- D13 3030: lw s4,0(zero)
         118 => x"00042303",   -- D13 3034: laco: lw t1,0(s0)
         119 => x"00690933",   -- D13 3038: add s2,s2,t1
         120 => x"0069D463",   -- D13 303C: bge s3,t1,8
         121 => x"00030993",   -- D13 3040: mv s3,t1
         122 => x"01435463",   -- D13 3044: nmaior: bge t1,s4,8
         123 => x"00030A13",   -- D13 3048: mv s4,t1
         124 => x"00440413",   -- D13 304C: nmenor: addi s0,s0,4
         125 => x"FE9442E3",   -- D13 3050: blt s0,s1,-28
         126 => x"03202023",   -- D13 3054: sw s2,20(zero)
         127 => x"03302223",   -- D13 3058: sw s3,24(zero)
         128 => x"03402423",   -- D13 305C: sw s4,28(zero)
         129 => x"00700293",   -- D14 3000: li t0,7
         130 => x"00502023",   -- D14 3004: sw t0,0(zero)
         131 => x"FFD00293",   -- D14 3008: li t0,-3
         132 => x"00502223",   -- D14 300C: sw t0,4(zero)
         133 => x"00C00293",   -- D14 3010: li t0,12
         134 => x"00502423",   -- D14 3014: sw t0,8(zero)
         135 => x"00000293",   -- D14 3018: li t0,0
         136 => x"00502623",   -- D14 301C: sw t0,c(zero)
         137 => x"00500293",   -- D14 3020: li t0,5
         138 => x"00502823",   -- D14 3024: sw t0,10(zero)
         139 => x"FF800293",   -- D14 3028: li t0,-8
         140 => x"00502A23",   -- D14 302C: sw t0,14(zero)
         141 => x"01400493",   -- D14 3030: li s1,0x14
         142 => x"00000413",   -- D14 3034: fora: li s0,0
         143 => x"00000913",   -- D14 3038: li s2,0
         144 => x"00042283",   -- D14 303C: dentro: lw t0,0(s0)
         145 => x"00442303",   -- D14 3040: lw t1,4(s0)
         146 => x"00535863",   -- D14 3044: bge t1,t0,16
         147 => x"00642023",   -- D14 3048: sw t1,0(s0)
         148 => x"00542223",   -- D14 304C: sw t0,4(s0)
         149 => x"00100913",   -- D14 3050: li s2,1
         150 => x"00440413",   -- D14 3054: ok: addi s0,s0,4
         151 => x"FE9442E3",   -- D14 3058: blt s0,s1,-28
         152 => x"FFC48493",   -- D14 305C: addi s1,s1,-4
         153 => x"FC091AE3",   -- D14 3060: bne s2,zero,-44
         154 => x"00000413",   -- D15 3000: li s0,0
         155 => x"7D000493",   -- D15 3004: li s1,2000
         156 => x"7D000913",   -- D15 3008: fora: li s2,2000
         157 => x"00140413",   -- D15 300C: dentro: addi s0,s0,1
         158 => x"FFF90913",   -- D15 3010: addi s2,s2,-1
         159 => x"FE091CE3",   -- D15 3014: bne s2,zero,-8
         160 => x"FFF48493",   -- D15 3018: addi s1,s1,-1
         161 => x"FE0496E3",   -- D15 301C: bne s1,zero,-20
         162 => x"00802023",   -- D15 3020: sw s0,0(zero)
         163 => x"00500513",   -- D16 3000: main: li a0,5
         164 => x"01C000EF",   -- D16 3004: jal 28
         165 => x"00050413",   -- D16 3008: mv s0,a0
         166 => x"01500513",   -- D16 300C: li a0,21
         167 => x"010000EF",   -- D16 3010: jal 16
         168 => x"00050493",   -- D16 3014: mv s1,a0
         169 => x"00A00893",   -- D16 3018: li a7,10
         170 => x"00000073",   -- D16 301C: ecall
         171 => x"00A50533",   -- D16 3020: dobro: add a0,a0,a0
         172 => x"00008067",   -- D16 3024: jr ra
         173 => x"33300993",   -- D17 3000: main: li s3,0x333
         174 => x"11100293",   -- D17 3004: li t0,0x111
         175 => x"22200313",   -- D17 3008: li t1,0x222
         176 => x"00200513",   -- D17 300C: li a0,2
         177 => x"00300593",   -- D17 3010: li a1,3
         178 => x"00400613",   -- D17 3014: li a2,4
         179 => x"00500693",   -- D17 3018: li a3,5
         180 => x"010000EF",   -- D17 301C: jal 16
         181 => x"00050B93",   -- D17 3020: mv s7,a0
         182 => x"00A00893",   -- D17 3024: li a7,10
         183 => x"00000073",   -- D17 3028: ecall
         184 => x"00B502B3",   -- D17 302C: diffofsums: add t0,a0,a1
         185 => x"00D60333",   -- D17 3030: add t1,a2,a3
         186 => x"406289B3",   -- D17 3034: sub s3,t0,t1
         187 => x"00098513",   -- D17 3038: mv a0,s3
         188 => x"00008067",   -- D17 303C: jr ra
         189 => x"33300993",   -- D18 3000: main: li s3,0x333
         190 => x"11100293",   -- D18 3004: li t0,0x111
         191 => x"22200313",   -- D18 3008: li t1,0x222
         192 => x"00200513",   -- D18 300C: li a0,2
         193 => x"00300593",   -- D18 3010: li a1,3
         194 => x"00400613",   -- D18 3014: li a2,4
         195 => x"00500693",   -- D18 3018: li a3,5
         196 => x"010000EF",   -- D18 301C: jal 16
         197 => x"00050B93",   -- D18 3020: mv s7,a0
         198 => x"00A00893",   -- D18 3024: li a7,10
         199 => x"00000073",   -- D18 3028: ecall
         200 => x"FF410113",   -- D18 302C: diffofsums: addi sp,sp,-12
         201 => x"01312423",   -- D18 3030: sw s3,8(sp)
         202 => x"00512223",   -- D18 3034: sw t0,4(sp)
         203 => x"00612023",   -- D18 3038: sw t1,0(sp)
         204 => x"00B502B3",   -- D18 303C: add t0,a0,a1
         205 => x"00D60333",   -- D18 3040: add t1,a2,a3
         206 => x"406289B3",   -- D18 3044: sub s3,t0,t1
         207 => x"00098513",   -- D18 3048: mv a0,s3
         208 => x"00812983",   -- D18 304C: lw s3,8(sp)
         209 => x"00412283",   -- D18 3050: lw t0,4(sp)
         210 => x"00012303",   -- D18 3054: lw t1,0(sp)
         211 => x"00C10113",   -- D18 3058: addi sp,sp,12
         212 => x"00008067",   -- D18 305C: jr ra
         213 => x"33300993",   -- D19 3000: main: li s3,0x333
         214 => x"11100293",   -- D19 3004: li t0,0x111
         215 => x"00200513",   -- D19 3008: li a0,2
         216 => x"00300593",   -- D19 300C: li a1,3
         217 => x"00400613",   -- D19 3010: li a2,4
         218 => x"00500693",   -- D19 3014: li a3,5
         219 => x"00C000EF",   -- D19 3018: jal 12
         220 => x"00A00893",   -- D19 301C: li a7,10
         221 => x"00000073",   -- D19 3020: ecall
         222 => x"00B502B3",   -- D19 3024: diffofsums: add t0,a0,a1
         223 => x"00D60333",   -- D19 3028: add t1,a2,a3
         224 => x"40628533",   -- D19 302C: sub a0,t0,t1
         225 => x"00008067",   -- D19 3030: jr ra
         226 => x"00600513",   -- D20 3000: main: li a0,6
         227 => x"00500593",   -- D20 3004: li a1,5
         228 => x"010000EF",   -- D20 3008: jal 16
         229 => x"00050413",   -- D20 300C: mv s0,a0
         230 => x"00A00893",   -- D20 3010: li a7,10
         231 => x"00000073",   -- D20 3014: ecall
         232 => x"FFC10113",   -- D20 3018: area: addi sp,sp,-4
         233 => x"00112023",   -- D20 301C: sw ra,0(sp)
         234 => x"02B50533",   -- D20 3020: mul a0,a0,a1
         235 => x"010000EF",   -- D20 3024: jal 16
         236 => x"00012083",   -- D20 3028: lw ra,0(sp)
         237 => x"00410113",   -- D20 302C: addi sp,sp,4
         238 => x"00008067",   -- D20 3030: jr ra
         239 => x"40155513",   -- D20 3034: divdois: srai a0,a0,1
         240 => x"00008067",   -- D20 3038: jr ra
         241 => x"00300513",   -- D21 3000: main: li a0,3
         242 => x"00200593",   -- D21 3004: li a1,2
         243 => x"44400A13",   -- D21 3008: li s4,0x444
         244 => x"55500A93",   -- D21 300C: li s5,0x555
         245 => x"010000EF",   -- D21 3010: jal 16
         246 => x"00050B93",   -- D21 3014: mv s7,a0
         247 => x"00A00893",   -- D21 3018: li a7,10
         248 => x"00000073",   -- D21 301C: ecall
         249 => x"FF410113",   -- D21 3020: f1: addi sp,sp,-12
         250 => x"00112423",   -- D21 3024: sw ra,8(sp)
         251 => x"01412223",   -- D21 3028: sw s4,4(sp)
         252 => x"01512023",   -- D21 302C: sw s5,0(sp)
         253 => x"00B50AB3",   -- D21 3030: add s5,a0,a1
         254 => x"40B50E33",   -- D21 3034: sub t3,a0,a1
         255 => x"03CA8AB3",   -- D21 3038: mul s5,s5,t3
         256 => x"00000A13",   -- D21 303C: addi s4,zero,0
         257 => x"02AA5863",   -- D21 3040: for: bge s4,a0,48
         258 => x"FF810113",   -- D21 3044: addi sp,sp,-8
         259 => x"00A12223",   -- D21 3048: sw a0,4(sp)
         260 => x"00B12023",   -- D21 304C: sw a1,0(sp)
         261 => x"01458533",   -- D21 3050: add a0,a1,s4
         262 => x"034000EF",   -- D21 3054: jal 52
         263 => x"00AA8AB3",   -- D21 3058: add s5,s5,a0
         264 => x"00412503",   -- D21 305C: lw a0,4(sp)
         265 => x"00012583",   -- D21 3060: lw a1,0(sp)
         266 => x"00810113",   -- D21 3064: addi sp,sp,8
         267 => x"001A0A13",   -- D21 3068: addi s4,s4,1
         268 => x"FD5FF06F",   -- D21 306C: j -44
         269 => x"01500533",   -- D21 3070: return: add a0,zero,s5
         270 => x"00812083",   -- D21 3074: lw ra,8(sp)
         271 => x"00412A03",   -- D21 3078: lw s4,4(sp)
         272 => x"00012A83",   -- D21 307C: lw s5,0(sp)
         273 => x"00C10113",   -- D21 3080: addi sp,sp,12
         274 => x"00008067",   -- D21 3084: jr ra
         275 => x"FFC10113",   -- D21 3088: f2: addi sp,sp,-4
         276 => x"01412023",   -- D21 308C: sw s4,0(sp)
         277 => x"00550A13",   -- D21 3090: addi s4,a0,5
         278 => x"00AA0533",   -- D21 3094: add a0,s4,a0
         279 => x"00012A03",   -- D21 3098: lw s4,0(sp)
         280 => x"00410113",   -- D21 309C: addi sp,sp,4
         281 => x"00008067",   -- D21 30A0: jr ra
         282 => x"00600513",   -- D22 3000: main: li a0,6
         283 => x"010000EF",   -- D22 3004: jal 16
         284 => x"00050413",   -- D22 3008: mv s0,a0
         285 => x"00A00893",   -- D22 300C: li a7,10
         286 => x"00000073",   -- D22 3010: ecall
         287 => x"FF810113",   -- D22 3014: fatorial: addi sp,sp,-8
         288 => x"00A12223",   -- D22 3018: sw a0,4(sp)
         289 => x"00112023",   -- D22 301C: sw ra,0(sp)
         290 => x"00100293",   -- D22 3020: li t0,1
         291 => x"00A2C863",   -- D22 3024: blt t0,a0,16
         292 => x"00100513",   -- D22 3028: li a0,1
         293 => x"00810113",   -- D22 302C: addi sp,sp,8
         294 => x"00008067",   -- D22 3030: jr ra
         295 => x"FFF50513",   -- D22 3034: senao: addi a0,a0,-1
         296 => x"FDDFF0EF",   -- D22 3038: jal -36
         297 => x"00412303",   -- D22 303C: lw t1,4(sp)
         298 => x"00012083",   -- D22 3040: lw ra,0(sp)
         299 => x"00810113",   -- D22 3044: addi sp,sp,8
         300 => x"02A30533",   -- D22 3048: mul a0,t1,a0
         301 => x"00008067",   -- D22 304C: jr ra
         302 => x"00300293",   -- D23 3000: main: li t0,3
         303 => x"00502823",   -- D23 3004: sw t0,10(zero)
         304 => x"00100293",   -- D23 3008: li t0,1
         305 => x"00502A23",   -- D23 300C: sw t0,14(zero)
         306 => x"00400293",   -- D23 3010: li t0,4
         307 => x"00502C23",   -- D23 3014: sw t0,18(zero)
         308 => x"00100293",   -- D23 3018: li t0,1
         309 => x"00502E23",   -- D23 301C: sw t0,1c(zero)
         310 => x"00500293",   -- D23 3020: li t0,5
         311 => x"02502023",   -- D23 3024: sw t0,20(zero)
         312 => x"01000513",   -- D23 3028: li a0,0x10
         313 => x"00500593",   -- D23 302C: li a1,5
         314 => x"020000EF",   -- D23 3030: jal 32
         315 => x"00A02023",   -- D23 3034: sw a0,0(zero)
         316 => x"01800513",   -- D23 3038: li a0,0x18
         317 => x"00300593",   -- D23 303C: li a1,3
         318 => x"010000EF",   -- D23 3040: jal 16
         319 => x"00A02223",   -- D23 3044: sw a0,4(zero)
         320 => x"00A00893",   -- D23 3048: li a7,10
         321 => x"00000073",   -- D23 304C: ecall
         322 => x"00000293",   -- D23 3050: soma: li t0,0
         323 => x"00052303",   -- D23 3054: laco: lw t1,0(a0)
         324 => x"006282B3",   -- D23 3058: add t0,t0,t1
         325 => x"00450513",   -- D23 305C: addi a0,a0,4
         326 => x"FFF58593",   -- D23 3060: addi a1,a1,-1
         327 => x"FE0598E3",   -- D23 3064: bne a1,zero,-16
         328 => x"00028513",   -- D23 3068: mv a0,t0
         329 => x"00008067",   -- D23 306C: jr ra
         330 => x"00400513",   -- D24 3000: main: li a0,4
         331 => x"010000EF",   -- D24 3004: jal 16
         332 => x"00050413",   -- D24 3008: mv s0,a0
         333 => x"00A00893",   -- D24 300C: li a7,10
         334 => x"00000073",   -- D24 3010: ecall
         335 => x"FF010113",   -- D24 3014: somaquad: addi sp,sp,-16
         336 => x"00000293",   -- D24 3018: li t0,0
         337 => x"00010E13",   -- D24 301C: mv t3,sp
         338 => x"00128293",   -- D24 3020: enche: addi t0,t0,1
         339 => x"02528333",   -- D24 3024: mul t1,t0,t0
         340 => x"006E2023",   -- D24 3028: sw t1,0(t3)
         341 => x"004E0E13",   -- D24 302C: addi t3,t3,4
         342 => x"FEA2C8E3",   -- D24 3030: blt t0,a0,-16
         343 => x"00000393",   -- D24 3034: li t2,0
         344 => x"00010E13",   -- D24 3038: mv t3,sp
         345 => x"000E2303",   -- D24 303C: soma: lw t1,0(t3)
         346 => x"006383B3",   -- D24 3040: add t2,t2,t1
         347 => x"004E0E13",   -- D24 3044: addi t3,t3,4
         348 => x"FFF28293",   -- D24 3048: addi t0,t0,-1
         349 => x"FE0298E3",   -- D24 304C: bne t0,zero,-16
         350 => x"00038513",   -- D24 3050: mv a0,t2
         351 => x"01010113",   -- D24 3054: addi sp,sp,16
         352 => x"00008067",   -- D24 3058: jr ra
         353 => x"00600513",   -- D25 3000: main: li a0,6
         354 => x"010000EF",   -- D25 3004: jal 16
         355 => x"00050493",   -- D25 3008: mv s1,a0
         356 => x"00A00893",   -- D25 300C: li a7,10
         357 => x"00000073",   -- D25 3010: ecall
         358 => x"00200293",   -- D25 3014: fib: li t0,2
         359 => x"02554E63",   -- D25 3018: blt a0,t0,60
         360 => x"FF410113",   -- D25 301C: addi sp,sp,-12
         361 => x"00112423",   -- D25 3020: sw ra,8(sp)
         362 => x"00812223",   -- D25 3024: sw s0,4(sp)
         363 => x"00A12023",   -- D25 3028: sw a0,0(sp)
         364 => x"FFF50513",   -- D25 302C: addi a0,a0,-1
         365 => x"FE5FF0EF",   -- D25 3030: jal -28
         366 => x"00050413",   -- D25 3034: mv s0,a0
         367 => x"00012503",   -- D25 3038: lw a0,0(sp)
         368 => x"FFE50513",   -- D25 303C: addi a0,a0,-2
         369 => x"FD5FF0EF",   -- D25 3040: jal -44
         370 => x"00A40533",   -- D25 3044: add a0,s0,a0
         371 => x"00812083",   -- D25 3048: lw ra,8(sp)
         372 => x"00412403",   -- D25 304C: lw s0,4(sp)
         373 => x"00C10113",   -- D25 3050: addi sp,sp,12
         374 => x"00008067",   -- D25 3054: base: jr ra
         375 => x"FFF00293",   -- D26 3000: main: li t0,-1
         376 => x"02502823",   -- D26 3004: sw t0,30(zero)
         377 => x"02502A23",   -- D26 3008: sw t0,34(zero)
         378 => x"02502C23",   -- D26 300C: sw t0,38(zero)
         379 => x"02502E23",   -- D26 3010: sw t0,3c(zero)
         380 => x"00A00513",   -- D26 3014: li a0,10
         381 => x"014000EF",   -- D26 3018: jal 20
         382 => x"00050413",   -- D26 301C: mv s0,a0
         383 => x"03C02483",   -- D26 3020: lw s1,3c(zero)
         384 => x"00A00893",   -- D26 3024: li a7,10
         385 => x"00000073",   -- D26 3028: ecall
         386 => x"FF810113",   -- D26 302C: fatorial: addi sp,sp,-8
         387 => x"00A12223",   -- D26 3030: sw a0,4(sp)
         388 => x"00112023",   -- D26 3034: sw ra,0(sp)
         389 => x"00100293",   -- D26 3038: li t0,1
         390 => x"00A2C863",   -- D26 303C: blt t0,a0,16
         391 => x"00100513",   -- D26 3040: li a0,1
         392 => x"00810113",   -- D26 3044: addi sp,sp,8
         393 => x"00008067",   -- D26 3048: jr ra
         394 => x"FFF50513",   -- D26 304C: senao: addi a0,a0,-1
         395 => x"FDDFF0EF",   -- D26 3050: jal -36
         396 => x"00412303",   -- D26 3054: lw t1,4(sp)
         397 => x"00012083",   -- D26 3058: lw ra,0(sp)
         398 => x"00810113",   -- D26 305C: addi sp,sp,8
         399 => x"02A30533",   -- D26 3060: mul a0,t1,a0
         400 => x"00008067",   -- D26 3064: jr ra
         401 => x"00700293",   -- D27 3000: main: li t0,7
         402 => x"00502023",   -- D27 3004: sw t0,0(zero)
         403 => x"FFD00293",   -- D27 3008: li t0,-3
         404 => x"00502223",   -- D27 300C: sw t0,4(zero)
         405 => x"00C00293",   -- D27 3010: li t0,12
         406 => x"00502423",   -- D27 3014: sw t0,8(zero)
         407 => x"00000293",   -- D27 3018: li t0,0
         408 => x"00502623",   -- D27 301C: sw t0,c(zero)
         409 => x"00500293",   -- D27 3020: li t0,5
         410 => x"00502823",   -- D27 3024: sw t0,10(zero)
         411 => x"FF800293",   -- D27 3028: li t0,-8
         412 => x"00502A23",   -- D27 302C: sw t0,14(zero)
         413 => x"06300293",   -- D27 3030: li t0,99
         414 => x"00502C23",   -- D27 3034: sw t0,18(zero)
         415 => x"00100293",   -- D27 3038: li t0,1
         416 => x"00502E23",   -- D27 303C: sw t0,1c(zero)
         417 => x"00000513",   -- D27 3040: li a0,0
         418 => x"00800593",   -- D27 3044: li a1,8
         419 => x"034000EF",   -- D27 3048: jal 52
         420 => x"00000513",   -- D27 304C: li a0,0
         421 => x"00800593",   -- D27 3050: li a1,8
         422 => x"0A0000EF",   -- D27 3054: jal 160
         423 => x"02A02023",   -- D27 3058: sw a0,20(zero)
         424 => x"40355293",   -- D27 305C: srai t0,a0,3
         425 => x"02502223",   -- D27 3060: sw t0,24(zero)
         426 => x"00002283",   -- D27 3064: lw t0,0(zero)
         427 => x"02502423",   -- D27 3068: sw t0,28(zero)
         428 => x"01C02283",   -- D27 306C: lw t0,1c(zero)
         429 => x"02502623",   -- D27 3070: sw t0,2c(zero)
         430 => x"00A00893",   -- D27 3074: li a7,10
         431 => x"00000073",   -- D27 3078: ecall
         432 => x"FF010113",   -- D27 307C: ordena: addi sp,sp,-16
         433 => x"00112623",   -- D27 3080: sw ra,c(sp)
         434 => x"00812423",   -- D27 3084: sw s0,8(sp)
         435 => x"00912223",   -- D27 3088: sw s1,4(sp)
         436 => x"01212023",   -- D27 308C: sw s2,0(sp)
         437 => x"00050413",   -- D27 3090: mv s0,a0
         438 => x"FFF58493",   -- D27 3094: addi s1,a1,-1
         439 => x"00249493",   -- D27 3098: slli s1,s1,2
         440 => x"009404B3",   -- D27 309C: add s1,s0,s1
         441 => x"00040913",   -- D27 30A0: fora: mv s2,s0
         442 => x"00092283",   -- D27 30A4: dentro: lw t0,0(s2)
         443 => x"00492303",   -- D27 30A8: lw t1,4(s2)
         444 => x"00535663",   -- D27 30AC: bge t1,t0,12
         445 => x"00090513",   -- D27 30B0: mv a0,s2
         446 => x"02C000EF",   -- D27 30B4: jal 44
         447 => x"00490913",   -- D27 30B8: ok: addi s2,s2,4
         448 => x"FE9944E3",   -- D27 30BC: blt s2,s1,-24
         449 => x"FFC48493",   -- D27 30C0: addi s1,s1,-4
         450 => x"FC944EE3",   -- D27 30C4: blt s0,s1,-36
         451 => x"00012903",   -- D27 30C8: lw s2,0(sp)
         452 => x"00412483",   -- D27 30CC: lw s1,4(sp)
         453 => x"00812403",   -- D27 30D0: lw s0,8(sp)
         454 => x"00C12083",   -- D27 30D4: lw ra,c(sp)
         455 => x"01010113",   -- D27 30D8: addi sp,sp,16
         456 => x"00008067",   -- D27 30DC: jr ra
         457 => x"00052283",   -- D27 30E0: troca: lw t0,0(a0)
         458 => x"00452303",   -- D27 30E4: lw t1,4(a0)
         459 => x"00652023",   -- D27 30E8: sw t1,0(a0)
         460 => x"00552223",   -- D27 30EC: sw t0,4(a0)
         461 => x"00008067",   -- D27 30F0: jr ra
         462 => x"00000293",   -- D27 30F4: soma: li t0,0
         463 => x"00052303",   -- D27 30F8: laco: lw t1,0(a0)
         464 => x"006282B3",   -- D27 30FC: add t0,t0,t1
         465 => x"00450513",   -- D27 3100: addi a0,a0,4
         466 => x"FFF58593",   -- D27 3104: addi a1,a1,-1
         467 => x"FE0598E3",   -- D27 3108: bne a1,zero,-16
         468 => x"00028513",   -- D27 310C: mv a0,t0
         469 => x"00008067",   -- D27 3110: jr ra
         470 => x"435352B7",   -- T30 3000: main: lui t0,0x43535
         471 => x"95228293",   -- T30 3004: addi t0,t0,-0x6ae
         472 => x"00502023",   -- T30 3008: sw t0,0(zero)
         473 => x"000A52B7",   -- T30 300C: lui t0,0xa5
         474 => x"62D28293",   -- T30 3010: addi t0,t0,0x62d
         475 => x"00502223",   -- T30 3014: sw t0,4(zero)
         476 => x"203D22B7",   -- T30 3018: lui t0,0x203d2
         477 => x"06E28293",   -- T30 301C: addi t0,t0,0x6e
         478 => x"00502423",   -- T30 3020: sw t0,8(zero)
         479 => x"00400893",   -- T30 3024: li a7,4
         480 => x"00000513",   -- T30 3028: li a0,0
         481 => x"00000073",   -- T30 302C: ecall
         482 => x"00100893",   -- T30 3030: li a7,1
         483 => x"FD600513",   -- T30 3034: li a0,-42
         484 => x"00000073",   -- T30 3038: ecall
         485 => x"00B00893",   -- T30 303C: li a7,11
         486 => x"02000513",   -- T30 3040: li a0,32
         487 => x"00000073",   -- T30 3044: ecall
         488 => x"00100893",   -- T30 3048: li a7,1
         489 => x"00000513",   -- T30 304C: li a0,0
         490 => x"00000073",   -- T30 3050: ecall
         491 => x"00B00893",   -- T30 3054: li a7,11
         492 => x"02000513",   -- T30 3058: li a0,32
         493 => x"00000073",   -- T30 305C: ecall
         494 => x"00100893",   -- T30 3060: li a7,1
         495 => x"80000537",   -- T30 3064: lui a0,0x80000
         496 => x"00000073",   -- T30 3068: ecall
         497 => x"00B00893",   -- T30 306C: li a7,11
         498 => x"00A00513",   -- T30 3070: li a0,10
         499 => x"00000073",   -- T30 3074: ecall
         500 => x"00400893",   -- T30 3078: li a7,4
         501 => x"00800513",   -- T30 307C: li a0,8
         502 => x"00000073",   -- T30 3080: ecall
         503 => x"00500893",   -- T30 3084: li a7,5
         504 => x"00000073",   -- T30 3088: ecall
         505 => x"00050413",   -- T30 308C: mv s0,a0
         506 => x"00100493",   -- T30 3090: li s1,1
         507 => x"02944263",   -- T30 3094: laco: blt s0,s1,36
         508 => x"02948533",   -- T30 3098: mul a0,s1,s1
         509 => x"00100893",   -- T30 309C: li a7,1
         510 => x"00000073",   -- T30 30A0: ecall
         511 => x"00B00893",   -- T30 30A4: li a7,11
         512 => x"02000513",   -- T30 30A8: li a0,32
         513 => x"00000073",   -- T30 30AC: ecall
         514 => x"00148493",   -- T30 30B0: addi s1,s1,1
         515 => x"FE1FF06F",   -- T30 30B4: j -32
         516 => x"00B00893",   -- T30 30B8: fim: li a7,11
         517 => x"00A00513",   -- T30 30BC: li a0,10
         518 => x"00000073",   -- T30 30C0: ecall
         519 => x"00A00893",   -- T30 30C4: li a7,10
         520 => x"00000073",   -- T30 30C8: ecall
         521 => x"FF800293",   -- T31 3000: li t0,-8
         522 => x"02100313",   -- T31 3004: li t1,33
         523 => x"006293B3",   -- T31 3008: sll t2,t0,t1
         524 => x"0062DE33",   -- T31 300C: srl t3,t0,t1
         525 => x"4062DEB3",   -- T31 3010: sra t4,t0,t1
         526 => x"01F29F13",   -- T31 3014: slli t5,t0,31
         527 => x"41F2DF93",   -- T31 3018: srai t6,t0,31
         528 => x"0002D413",   -- T31 301C: srli s0,t0,0
         529 => x"FFF33493",   -- T31 3020: sltiu s1,t1,-1
         530 => x"FFF34513",   -- T31 3024: xori a0,t1,-1
         531 => x"800005B7",   -- T31 3028: lui a1,0x80000
         532 => x"02B59633",   -- T31 302C: mulh a2,a1,a1
         533 => x"0255A6B3",   -- T31 3030: mulhsu a3,a1,t0
         534 => x"0255B733",   -- T31 3034: mulhu a4,a1,t0
         535 => x"00501123",   -- T31 3038: sh t0,2(zero)
         536 => x"00205783",   -- T31 303C: lhu a5,2(zero)
         537 => x"00201803",   -- T31 3040: lh a6,2(zero)
         538 => x"0052D463",   -- T31 3044: bge t0,t0,8
         539 => x"00100893",   -- T31 3048: li a7,1
         540 => x"0062D463",   -- T31 304C: l1: bge t0,t1,8
         541 => x"00200913",   -- T31 3050: li s2,2
         542 => x"00536463",   -- T31 3054: l2: bltu t1,t0,8
         543 => x"00300993",   -- T31 3058: li s3,3
         544 => x"00537463",   -- T31 305C: l3: bgeu t1,t0,8
         545 => x"00400A13",   -- T31 3060: li s4,4
         546 => x"00001A97",   -- T31 3064: l4: auipc s5,0x1
         547 => x"0FF0000F",   -- T31 3068: fence
         548 => x"01C3CB33",   -- T31 306C: xor s6,t2,t3
         549 => x"0062BBB3",   -- T31 3070: sltu s7,t0,t1
         550 => x"00533C33",   -- T31 3074: sltu s8,t1,t0
         551 => x"00000073",   -- T31 3078: ecall
         552 => x"00500C93",   -- T31 307C: li s9,5
        others => x"00000013");
    type demo_tab_t is array(0 to 31) of integer range 0 to 1023;
    --   0..15                            0    1    2    3    4    5    6    7    8    9   10   11   12   13   14   15
    --  16..31                           16   17   18   19   20   21   22   23   24   25   26   27   28   29   30   31
    constant DEMO_BASE : demo_tab_t := (   0,   0,   7,  14,  21,  28,  35,  43,  53,  65,  80,  88,  95, 105, 129, 154,
                                         163, 173, 189, 213, 226, 241, 282, 302, 330, 353, 375, 401,   0,   0, 470, 521);
    constant DEMO_LEN  : demo_tab_t := (   0,   7,   7,   7,   7,   7,   8,  10,  12,  15,   8,   7,  10,  24,  25,   9,
                                          10,  16,  24,  13,  15,  41,  20,  28,  23,  22,  26,  69,   0,   0,  51,  32);

    -- Comprimento que cabe na memória de instruções (IMEM_BITS pequeno corta)
    function demo_len_fit(n : integer) return integer is
    begin
        if DEMO_LEN(n) > 2**IMEM_BITS then return 2**IMEM_BITS;
        else                               return DEMO_LEN(n);
        end if;
    end function;

begin

    -- ══════════════════════════════════════════════════════════════════════════
    -- Sincronizadores: KEY[3:0], SW[2] e SW[10:6]
    -- ══════════════════════════════════════════════════════════════════════════
    process(CLOCK_50)
    begin
        if rising_edge(CLOCK_50) then
            key_s0    <= KEY;
            key_s     <= key_s0;
            mode_s0   <= SW(10 downto 6) & SW(2);
            mode_s1   <= mode_s0;
            mode_prev <= mode_s1;
            -- Pulso de 1 ciclo quando SW[2] muda, ou quando SW[10:6] muda com
            -- o modo demo ligado (a demo nova é carregada). Com SW[2]=0 o
            -- número da demo não interessa: mexer em SW[10:6] não reinicia
            -- o programa digitado (até a entrega 46 reiniciava).
            if mode_s1(0) /= mode_prev(0) or
               (mode_s1(0) = '1' and mode_s1(5 downto 1) /= mode_prev(5 downto 1)) then
                mode_rst <= '1';
            else
                mode_rst <= '0';
            end if;
        end if;
    end process;

    -- ══════════════════════════════════════════════════════════════════════════
    -- KEY[0] → prog_rst (ativo enquanto pressionado + DEB_CYCLES após soltar)
    -- Também segura o reset por DEB_CYCLES após a configuração da FPGA.
    -- ══════════════════════════════════════════════════════════════════════════
    process(CLOCK_50)
        variable cnt0 : natural range 0 to DEB_CYCLES := DEB_CYCLES;
    begin
        if rising_edge(CLOCK_50) then
            if key_s(0) = '0' then
                cnt0     := DEB_CYCLES;
                prog_rst <= '1';
            elsif cnt0 > 0 then
                cnt0     := cnt0 - 1;
                prog_rst <= '1';
            else
                prog_rst <= '0';
            end if;
        end if;
    end process;

    -- ══════════════════════════════════════════════════════════════════════════
    -- KEY[1] → key1_rst (mesmo padrão; reinicia só a CPU)
    -- ══════════════════════════════════════════════════════════════════════════
    process(CLOCK_50)
        variable cnt1 : natural range 0 to DEB_CYCLES := DEB_CYCLES;
    begin
        if rising_edge(CLOCK_50) then
            if key_s(1) = '0' then
                cnt1     := DEB_CYCLES;
                key1_rst <= '1';
            elsif cnt1 > 0 then
                cnt1     := cnt1 - 1;
                key1_rst <= '1';
            else
                key1_rst <= '0';
            end if;
        end if;
    end process;

    kbd_reset  <= prog_rst;
    cpu_rst    <= prog_rst or key1_rst or mode_rst or edit_rst or ld_busy;
    demo_on    <= mode_s1(0);
    proc_reset <= cpu_rst;

    -- ══════════════════════════════════════════════════════════════════════════
    -- KEY[3] → key3_deb (aceita novo nível após DEB_CYCLES de estabilidade)
    -- ══════════════════════════════════════════════════════════════════════════
    process(CLOCK_50, prog_rst)
        variable cnt3 : natural range 0 to DEB_CYCLES := 0;
    begin
        if prog_rst = '1' then
            cnt3     := 0;
            key3_deb <= '1';
        elsif rising_edge(CLOCK_50) then
            if key_s(3) = key3_deb then
                cnt3 := 0;
            elsif cnt3 = DEB_CYCLES then
                key3_deb <= key_s(3);
                cnt3     := 0;
            else
                cnt3 := cnt3 + 1;
            end if;
        end if;
    end process;

    -- ══════════════════════════════════════════════════════════════════════════
    -- Geração de proc_clk
    --   SW[1]='0'              → clock parado
    --   SW[1]='1' + SW[0]='1' → RUN: 50 MHz / (2 × (RUN_HALF+1)) = 10 Hz
    --                          + SW[5]='1' → TURBO: 50 MHz / (2 × TURBO_HALF)
    --   SW[1]='1' + SW[0]='0' → STEP: 1 pulso por pressão de KEY[3]
    --   proc_halt='1'          → nenhuma borda nova (RUN e STEP)
    -- ══════════════════════════════════════════════════════════════════════════
    process(CLOCK_50, cpu_rst)
        variable half : natural range 0 to RUN_HALF + TURBO_HALF;
    begin
        if cpu_rst = '1' then
            proc_clk_r <= '0';
            run_cnt    <= 0;
            key3_prev  <= '1';
            sys_go     <= '0';
            step_pend  <= '0';
        elsif rising_edge(CLOCK_50) then
            key3_prev <= key3_deb;
            sys_go    <= '0';

            if SW(1) = '0' or proc_halt = '1' then
                proc_clk_r <= '0';
                run_cnt    <= 0;
                step_pend  <= '0';

            elsif SW(0) = '1' then
                -- RUN (10 Hz) ou TURBO. ">=" (e não "=") para trocar de
                -- velocidade no meio de uma contagem longa sem esperar.
                if SW(5) = '1' then
                    half := TURBO_HALF - 1;
                else
                    half := RUN_HALF;
                end if;
                if run_cnt >= half then
                    if proc_clk_r = '0' and sys_hold = '1' then
                        -- a próxima borda executaria um ecall de serviço:
                        -- espera o serviço terminar (run_cnt fica parado)
                        sys_go <= '1';
                    else
                        run_cnt    <= 0;
                        proc_clk_r <= not proc_clk_r;
                    end if;
                else
                    run_cnt <= run_cnt + 1;
                end if;

            else
                -- STEP: 1 ciclo de CLOCK_50 em '1' por pressão. Num ecall de
                -- serviço, a pressão primeiro dispara o serviço; o pulso sai
                -- quando ele termina.
                if key3_deb = '0' and key3_prev = '1' then
                    if sys_hold = '1' then
                        sys_go     <= '1';
                        step_pend  <= '1';
                        proc_clk_r <= '0';
                    else
                        proc_clk_r <= '1';
                    end if;
                elsif step_pend = '1' then
                    if sys_hold = '1' then
                        sys_go     <= '1';
                        proc_clk_r <= '0';
                    else
                        step_pend  <= '0';
                        proc_clk_r <= '1';
                    end if;
                else
                    proc_clk_r <= '0';
                end if;
            end if;
        end if;
    end process;

    proc_clk <= proc_clk_r;

    -- ══════════════════════════════════════════════════════════════════════════
    -- PS/2 → parser
    -- ══════════════════════════════════════════════════════════════════════════
    u_ps2rx  : ps2_receiver    port map(CLOCK_50, kbd_reset, PS2_CLK, PS2_DAT, scan_code_s, ps2_dvalid);
    u_ps2asc : ps2_to_ascii    port map(CLOCK_50, kbd_reset, scan_code_s, ps2_dvalid, ascii_char_s, ascii_val_s,
                                        nav_up, nav_down, nav_home, nav_end, nav_pgup, nav_pgdn);
    u_kbdbuf : keyboard_buffer port map(CLOCK_50, kbd_reset, ascii_char_s, ascii_val_s, line_buf_s, line_len_s, parse_en_s,
                                        kbd_buf_s, kbd_len_s);
    parse_en_asm <= parse_en_s and not input_mode;          -- na espera do a7 = 5, o ENTER é do número
    u_parser : asm_parser      port map(CLOCK_50, kbd_reset, line_buf_s, line_len_s, parse_en_asm, instr_out_s, instr_valid_s, parse_err_s);

    -- ══════════════════════════════════════════════════════════════════════════
    -- Ponteiro de escrita, cursor de edição e WE da imem
    --   Só grava no modo teclado. A linha vai para o slot edit_ptr:
    --     edit_ptr = write_addr_s -> acrescenta (write_addr_s + 1); com 1024
    --                                instruções é rejeitada (Err:1 no VGA)
    --     edit_ptr < write_addr_s -> sobrescreve (só com a CPU desligada);
    --                                reinicia a CPU com edit_rst
    --   Com a CPU ligada ou em demo, edit_ptr acompanha write_addr_s, então o
    --   comportamento é exatamente o de antes (sempre acrescenta).
    -- ══════════════════════════════════════════════════════════════════════════
    edit_on    <= (not SW(1)) and (not SW(2));
    edit_ovr   <= '1' when edit_on = '1' and edit_ptr < write_addr_s else '0';
    imem_full  <= write_addr_s(IMEM_BITS);            -- 2**IMEM_BITS instruções
    imem_we    <= instr_valid_s and (not SW(2)) and (edit_ovr or not imem_full);
    -- porta de escrita da memória: carregador de demo ou linha do teclado
    ram_we     <= ld_we or imem_we;
    ram_waddr  <= ld_addr when ld_we = '1' else STD_LOGIC_VECTOR(edit_ptr(IMEM_BITS-1 downto 0));
    ram_wdata  <= ld_data when ld_we = '1' else instr_out_s;

    process(CLOCK_50, prog_rst)
        variable lim : UNSIGNED(IMEM_BITS downto 0);  -- última posição do cursor
    begin
        if prog_rst = '1' then
            write_addr_s <= (others => '0');
            edit_ptr     <= (others => '0');
            edit_rst     <= '0';
        elsif rising_edge(CLOCK_50) then
            edit_rst <= '0';
            -- fim do programa; com a memória cheia, a última linha
            if write_addr_s(IMEM_BITS) = '1' then
                lim := to_unsigned(2**IMEM_BITS - 1, IMEM_BITS + 1);
            else
                lim := write_addr_s;
            end if;

            if ld_fin = '1' then
                -- demo carregada: o programa tem DEMO_LEN instruções
                write_addr_s <= to_unsigned(demo_len_fit(ld_sel), IMEM_BITS + 1);
                edit_ptr     <= to_unsigned(demo_len_fit(ld_sel), IMEM_BITS + 1);
            elsif imem_we = '1' then
                if edit_ovr = '1' then
                    edit_ptr <= edit_ptr + 1;            -- desce uma linha
                    edit_rst <= '1';                     -- programa mudou
                else
                    write_addr_s <= write_addr_s + 1;    -- acrescentou
                    edit_ptr     <= write_addr_s + 1;
                end if;
            elsif edit_on = '0' then
                edit_ptr <= write_addr_s;                -- CPU ligada / demo
            elsif edit_ptr > lim then
                edit_ptr <= lim;
            elsif nav_up = '1' then
                if edit_ptr > 0 then edit_ptr <= edit_ptr - 1; end if;
            elsif nav_down = '1' then
                if edit_ptr < lim then edit_ptr <= edit_ptr + 1; end if;
            elsif nav_home = '1' then
                edit_ptr <= (others => '0');
            elsif nav_end = '1' then
                edit_ptr <= lim;
            elsif nav_pgup = '1' then            -- uma janela do painel (16)
                if edit_ptr > 16 then edit_ptr <= edit_ptr - 16;
                else                  edit_ptr <= (others => '0'); end if;
            elsif nav_pgdn = '1' then
                if to_integer(edit_ptr) + 16 < to_integer(lim) then
                    edit_ptr <= edit_ptr + 16;
                else
                    edit_ptr <= lim;
                end if;
            end if;
        end if;
    end process;

    -- ── Resultado da última linha, persistente até a próxima ───────────────
    process(CLOCK_50, prog_rst)
    begin
        if prog_rst = '1' then
            ok_hold  <= '0';
            err_hold <= '0';
        elsif rising_edge(CLOCK_50) then
            if imem_we = '1' or sys_okin = '1' then
                ok_hold  <= '1';
                err_hold <= '0';
            elsif parse_err_s = '1' or instr_valid_s = '1' or sys_err = '1' then
                -- erro de parse, memória cheia ou digitado em modo demo
                ok_hold  <= '0';
                err_hold <= '1';
            end if;
        end if;
    end process;

    -- ══════════════════════════════════════════════════════════════════════════
    -- Carregador de demo
    --   Com SW[2]=1, copia DEMO_LEN(n) palavras da ROM para a memória de
    --   instruções (1 por ciclo de CLOCK_50, < 1 us) e no fim ajusta
    --   write_addr_s. Dispara quando SW[2] liga, quando SW[10:6] muda com
    --   SW[2]=1 e quando KEY[0] é solto com SW[2]=1 (inclui ligar a placa).
    --   Enquanto copia, a CPU fica em reset (cpu_rst inclui ld_busy).
    -- ══════════════════════════════════════════════════════════════════════════
    process(CLOCK_50)
    begin
        if rising_edge(CLOCK_50) then
            ld_we         <= '0';
            ld_fin        <= '0';
            prog_rst_prev <= prog_rst;
            if prog_rst = '1' then
                ld_busy <= '0';
            elsif ld_busy = '0' then
                if demo_on = '1' and (mode_s1 /= mode_prev or prog_rst_prev = '1') then
                    ld_busy <= '1';
                    ld_idx  <= 0;
                    ld_sel  <= to_integer(unsigned(mode_s1(5 downto 1)));
                end if;
            elsif ld_idx = demo_len_fit(ld_sel) then
                ld_busy <= '0';
                ld_fin  <= '1';
            else
                ld_we   <= '1';
                ld_addr <= STD_LOGIC_VECTOR(to_unsigned(ld_idx, IMEM_BITS));
                ld_data <= DEMO_ROM(DEMO_BASE(ld_sel) + ld_idx);
                ld_idx  <= ld_idx + 1;
            end if;
        end if;
    end process;

    -- ══════════════════════════════════════════════════════════════════════════
    -- Memória de instruções: 2**IMEM_BITS palavras em registradores
    --   (leitura combinacional; ver imem_writable.vhd)
    --   KEY[0] não apaga o conteúdo: zera write_addr_s, e nada acima dele
    --   fica visível ou executável.
    -- ══════════════════════════════════════════════════════════════════════════
    u_imem : imem_writable
        generic map(ABITS => IMEM_BITS)
        port map(clk   => CLOCK_50,
                 we    => ram_we,
                 waddr => ram_waddr,
                 wdata => ram_wdata,
                 raddr => proc_pc(IMEM_BITS + 1 downto 2),
                 rdata => proc_instr,
                 vaddr => STD_LOGIC_VECTOR(view_idx),
                 vdata => view_word);

    -- A CPU sempre executa a memória de instruções (demos são copiadas para ela)
    proc_instr_mux <= proc_instr;

    -- ══════════════════════════════════════════════════════════════════════════
    -- Processador RISC-V
    -- ══════════════════════════════════════════════════════════════════════════
    u_cpu : riscvsingle
        generic map(TEXT_BASE => TEXT_BASE, SP_INIT => SP_INIT)
        port map(proc_clk, proc_reset, proc_pc,
                 proc_instr_mux, proc_memwrite,
                 proc_alu, proc_wdata, proc_rdata,
                 sys_we, sys_wd, sys_a0, sys_a7);

    -- ══════════════════════════════════════════════════════════════════════════
    -- Memória de dados: 32 palavras (endereço = ALUResult[6:2]; em execução,
    -- endereços maiores dão a volta módulo 128 bytes — na digitação o parser
    -- já rejeita endereço inválido quando a base é x0), escrita em proc_clk
    --   00-3F: dados do programa (painel "Memoria de Dados")
    --   40-7F: pilha; desce a partir de STACK_TOP = 0x80 (painel "Pilha")
    --   sw (funct3 010): palavra inteira
    --   sh (funct3 001): meia-palavra; endereço(1) escolhe bits 15:0 ou 31:16
    --   sb (funct3 000): byte; endereço(1:0) escolhe o byte (little-endian:
    --                    endereço 0 = bits 7:0, 3 = bits 31:24)
    --   O controlador do Harris & Harris já ativa MemWrite para todo opcode de
    --   store (0100011); aqui só se escolhe quais bytes da palavra mudam.
    -- ══════════════════════════════════════════════════════════════════════════
    process(proc_clk, cpu_rst)
        -- palavra antiga + dado novo nas posições certas
        impure function st_merge(old : STD_LOGIC_VECTOR(31 downto 0))
            return STD_LOGIC_VECTOR is
            variable w : STD_LOGIC_VECTOR(31 downto 0);
        begin
            w := old;
            case proc_instr_mux(14 downto 12) is
                when "000" =>                                         -- sb
                    case proc_alu(1 downto 0) is
                        when "00"   => w(7  downto 0)  := proc_wdata(7 downto 0);
                        when "01"   => w(15 downto 8)  := proc_wdata(7 downto 0);
                        when "10"   => w(23 downto 16) := proc_wdata(7 downto 0);
                        when others => w(31 downto 24) := proc_wdata(7 downto 0);
                    end case;
                when "001" =>                                         -- sh
                    if proc_alu(1) = '0' then
                        w(15 downto 0)  := proc_wdata(15 downto 0);
                    else
                        w(31 downto 16) := proc_wdata(15 downto 0);
                    end if;
                when others =>                                        -- sw
                    w := proc_wdata;
            end case;
            return w;
        end function;
    begin
        if cpu_rst = '1' then
            dmem_00 <= (others => '0'); dmem_01 <= (others => '0');
            dmem_02 <= (others => '0'); dmem_03 <= (others => '0');
            dmem_04 <= (others => '0'); dmem_05 <= (others => '0');
            dmem_06 <= (others => '0'); dmem_07 <= (others => '0');
            dmem_08 <= (others => '0'); dmem_09 <= (others => '0');
            dmem_10 <= (others => '0'); dmem_11 <= (others => '0');
            dmem_12 <= (others => '0'); dmem_13 <= (others => '0');
            dmem_14 <= (others => '0'); dmem_15 <= (others => '0');
            dmem_16 <= (others => '0'); dmem_17 <= (others => '0');
            dmem_18 <= (others => '0'); dmem_19 <= (others => '0');
            dmem_20 <= (others => '0'); dmem_21 <= (others => '0');
            dmem_22 <= (others => '0'); dmem_23 <= (others => '0');
            dmem_24 <= (others => '0'); dmem_25 <= (others => '0');
            dmem_26 <= (others => '0'); dmem_27 <= (others => '0');
            dmem_28 <= (others => '0'); dmem_29 <= (others => '0');
            dmem_30 <= (others => '0'); dmem_31 <= (others => '0');
        elsif rising_edge(proc_clk) then
            if proc_memwrite = '1' then
                case proc_alu(6 downto 2) is
                    when "00000"  => dmem_00 <= st_merge(dmem_00);
                    when "00001"  => dmem_01 <= st_merge(dmem_01);
                    when "00010"  => dmem_02 <= st_merge(dmem_02);
                    when "00011"  => dmem_03 <= st_merge(dmem_03);
                    when "00100"  => dmem_04 <= st_merge(dmem_04);
                    when "00101"  => dmem_05 <= st_merge(dmem_05);
                    when "00110"  => dmem_06 <= st_merge(dmem_06);
                    when "00111"  => dmem_07 <= st_merge(dmem_07);
                    when "01000"  => dmem_08 <= st_merge(dmem_08);
                    when "01001"  => dmem_09 <= st_merge(dmem_09);
                    when "01010"  => dmem_10 <= st_merge(dmem_10);
                    when "01011"  => dmem_11 <= st_merge(dmem_11);
                    when "01100"  => dmem_12 <= st_merge(dmem_12);
                    when "01101"  => dmem_13 <= st_merge(dmem_13);
                    when "01110"  => dmem_14 <= st_merge(dmem_14);
                    when "01111"  => dmem_15 <= st_merge(dmem_15);
                    when "10000"  => dmem_16 <= st_merge(dmem_16);
                    when "10001"  => dmem_17 <= st_merge(dmem_17);
                    when "10010"  => dmem_18 <= st_merge(dmem_18);
                    when "10011"  => dmem_19 <= st_merge(dmem_19);
                    when "10100"  => dmem_20 <= st_merge(dmem_20);
                    when "10101"  => dmem_21 <= st_merge(dmem_21);
                    when "10110"  => dmem_22 <= st_merge(dmem_22);
                    when "10111"  => dmem_23 <= st_merge(dmem_23);
                    when "11000"  => dmem_24 <= st_merge(dmem_24);
                    when "11001"  => dmem_25 <= st_merge(dmem_25);
                    when "11010"  => dmem_26 <= st_merge(dmem_26);
                    when "11011"  => dmem_27 <= st_merge(dmem_27);
                    when "11100"  => dmem_28 <= st_merge(dmem_28);
                    when "11101"  => dmem_29 <= st_merge(dmem_29);
                    when "11110"  => dmem_30 <= st_merge(dmem_30);
                    when others   => dmem_31 <= st_merge(dmem_31);
                end case;
            end if;
        end if;
    end process;

    process(proc_alu, dmem_00, dmem_01, dmem_02, dmem_03,
                      dmem_04, dmem_05, dmem_06, dmem_07,
                      dmem_08, dmem_09, dmem_10, dmem_11,
                      dmem_12, dmem_13, dmem_14, dmem_15,
                      dmem_16, dmem_17, dmem_18, dmem_19,
                      dmem_20, dmem_21, dmem_22, dmem_23,
                      dmem_24, dmem_25, dmem_26, dmem_27,
                      dmem_28, dmem_29, dmem_30, dmem_31)
    begin
        case proc_alu(6 downto 2) is
            when "00000"  => proc_rword <= dmem_00;
            when "00001"  => proc_rword <= dmem_01;
            when "00010"  => proc_rword <= dmem_02;
            when "00011"  => proc_rword <= dmem_03;
            when "00100"  => proc_rword <= dmem_04;
            when "00101"  => proc_rword <= dmem_05;
            when "00110"  => proc_rword <= dmem_06;
            when "00111"  => proc_rword <= dmem_07;
            when "01000"  => proc_rword <= dmem_08;
            when "01001"  => proc_rword <= dmem_09;
            when "01010"  => proc_rword <= dmem_10;
            when "01011"  => proc_rword <= dmem_11;
            when "01100"  => proc_rword <= dmem_12;
            when "01101"  => proc_rword <= dmem_13;
            when "01110"  => proc_rword <= dmem_14;
            when "01111"  => proc_rword <= dmem_15;
            when "10000"  => proc_rword <= dmem_16;
            when "10001"  => proc_rword <= dmem_17;
            when "10010"  => proc_rword <= dmem_18;
            when "10011"  => proc_rword <= dmem_19;
            when "10100"  => proc_rword <= dmem_20;
            when "10101"  => proc_rword <= dmem_21;
            when "10110"  => proc_rword <= dmem_22;
            when "10111"  => proc_rword <= dmem_23;
            when "11000"  => proc_rword <= dmem_24;
            when "11001"  => proc_rword <= dmem_25;
            when "11010"  => proc_rword <= dmem_26;
            when "11011"  => proc_rword <= dmem_27;
            when "11100"  => proc_rword <= dmem_28;
            when "11101"  => proc_rword <= dmem_29;
            when "11110"  => proc_rword <= dmem_30;
            when others   => proc_rword <= dmem_31;
        end case;
    end process;

    -- ══════════════════════════════════════════════════════════════════════════
    -- Leitura de byte / meia-palavra (funct3 da instrução de load)
    --   lw  (010): palavra inteira
    --   lh  (001): meia-palavra escolhida por endereço(1), com extensão de sinal
    --   lb  (000): byte escolhido por endereço(1:0), com extensão de sinal
    --   lhu (101) / lbu (100): o mesmo, completando com zeros (sem sinal)
    --   Little-endian: endereço 0 = bits 7:0. Para instruções que não são load
    --   o valor não é usado (a CPU só escolhe ReadData em loads).
    -- ══════════════════════════════════════════════════════════════════════════
    process(proc_rword, proc_alu, proc_instr_mux)
        variable b8  : STD_LOGIC_VECTOR(7 downto 0);
        variable h16 : STD_LOGIC_VECTOR(15 downto 0);
    begin
        case proc_alu(1 downto 0) is
            when "00"   => b8 := proc_rword(7  downto 0);
            when "01"   => b8 := proc_rword(15 downto 8);
            when "10"   => b8 := proc_rword(23 downto 16);
            when others => b8 := proc_rword(31 downto 24);
        end case;
        if proc_alu(1) = '0' then h16 := proc_rword(15 downto 0);
        else                      h16 := proc_rword(31 downto 16);
        end if;
        case proc_instr_mux(14 downto 12) is
            when "000"  => proc_rdata <= (31 downto 8  => b8(7))  & b8;    -- lb
            when "001"  => proc_rdata <= (31 downto 16 => h16(15)) & h16;  -- lh
            when "100"  => proc_rdata <= (31 downto 8  => '0')    & b8;    -- lbu
            when "101"  => proc_rdata <= (31 downto 16 => '0')    & h16;   -- lhu
            when others => proc_rdata <= proc_rword;                        -- lw
        end case;
    end process;

    -- ══════════════════════════════════════════════════════════════════════════
    -- Shadow register (domínio CLOCK_50 + latch pipeline)
    --   1) Latch: registra os sinais combinacionais da CPU a cada ciclo, ou
    --      seja, os valores PRÉ-BORDA de proc_clk_r.
    --   2) Shadow: no ciclo seguinte à subida de proc_clk_r, usa os valores
    --      latched (instrução que acabou de executar).
    -- ══════════════════════════════════════════════════════════════════════════
    process(CLOCK_50, cpu_rst)
    begin
        if cpu_rst = '1' then
            instr_latch     <= (others => '0');
            alu_latch       <= (others => '0');
            pc_latch        <= (others => '0');
            rdata_latch     <= (others => '0');
            memw_latch      <= '0';
            shadow_clk_prev <= '0';
        elsif rising_edge(CLOCK_50) then
            instr_latch     <= proc_instr_mux;
            alu_latch       <= proc_alu;
            pc_latch        <= proc_pc;
            rdata_latch     <= proc_rdata;
            memw_latch      <= proc_memwrite;
            shadow_clk_prev <= proc_clk_r;
        end if;
    end process;

    process(CLOCK_50, cpu_rst)
        variable op     : STD_LOGIC_VECTOR(6 downto 0);
        variable rd_idx : integer range 0 to 31;
        variable wr_val : STD_LOGIC_VECTOR(31 downto 0);
    begin
        if cpu_rst = '1' then
            shadow_regs    <= (others => (others => '0'));
            shadow_regs(2) <= STD_LOGIC_VECTOR(to_unsigned(SP_INIT, 32));     -- sp
            hl_reg      <= (others => '0');
            hl_mem      <= (others => '0');
        elsif rising_edge(CLOCK_50) then
            if proc_clk_r = '1' and shadow_clk_prev = '0' then
                -- store: destaca a palavra da memória que mudou
                --   (sb/sh mudam só parte dela; o destaque é da palavra)
                if memw_latch = '1' then
                    hl_mem <= '1' & alu_latch(6 downto 2);
                end if;
                op     := instr_latch(6 downto 0);
                rd_idx := to_integer(unsigned(instr_latch(11 downto 7)));

                if op = "0110011" or op = "0010011" or
                   op = "0000011" or op = "1101111" or
                   op = "1100111" or op = "0110111" or op = "0010111"
                then
                    if op = "1101111" or op = "1100111" then
                        wr_val := STD_LOGIC_VECTOR(unsigned(pc_latch) + 4); -- JAL/JALR
                    elsif op = "0110111" then
                        wr_val := instr_latch(31 downto 12) & x"000";       -- LUI
                    elsif op = "0010111" then                               -- AUIPC
                        wr_val := instr_latch(31 downto 12) & x"000";
                        wr_val := STD_LOGIC_VECTOR(unsigned(pc_latch) + unsigned(wr_val));
                    elsif op = "0000011" then
                        wr_val := rdata_latch;   -- loads (já estendido)
                    else
                        wr_val := alu_latch;     -- tipo R / tipo I (inclui mul*)
                    end if;

                    if rd_idx >= 1 and rd_idx <= 31 then
                        shadow_regs(rd_idx) <= wr_val;
                        hl_reg <= '1' & instr_latch(11 downto 7);   -- destaque
                    end if;
                elsif instr_latch = x"00000073" and sys_we = '1' then
                    shadow_regs(10) <= sys_wd;                      -- ecall a7 = 5: a0
                    hl_reg <= "101010";
                end if;
            end if;
        end if;
    end process;

    -- ══════════════════════════════════════════════════════════════════════════
    -- Contador de passos (instruções executadas desde o último reset da CPU)
    --   Mesma detecção de borda do shadow: proc_clk_r acabou de subir.
    --   Incremento BCD dígito a dígito (9 -> 0 e vai-um), sem divisão: os
    --   dígitos saem prontos para o VGA.
    -- ══════════════════════════════════════════════════════════════════════════
    process(CLOCK_50, cpu_rst)
        variable v     : STD_LOGIC_VECTOR(31 downto 0);
        variable carry : boolean;
    begin
        if cpu_rst = '1' then
            steps_bcd <= (others => '0');
        elsif rising_edge(CLOCK_50) then
            if proc_clk_r = '1' and shadow_clk_prev = '0' then
                v     := steps_bcd;
                carry := true;
                for i in 0 to 7 loop
                    if carry then
                        if v(4*i+3 downto 4*i) = "1001" then
                            v(4*i+3 downto 4*i) := "0000";      -- 9 -> 0, vai-um
                        else
                            v(4*i+3 downto 4*i) :=
                                STD_LOGIC_VECTOR(unsigned(v(4*i+3 downto 4*i)) + 1);
                            carry := false;
                        end if;
                    end if;
                end loop;
                steps_bcd <= v;
            end if;
        end if;
    end process;

    process(shadow_regs)
    begin
        for i in 0 to 31 loop
            regs_flat(i*32+31 downto i*32) <= shadow_regs(i);
        end loop;
    end process;

    dmem_flat(  31 downto    0) <= dmem_00; dmem_flat(  63 downto   32) <= dmem_01;
    dmem_flat(  95 downto   64) <= dmem_02; dmem_flat( 127 downto   96) <= dmem_03;
    dmem_flat( 159 downto  128) <= dmem_04; dmem_flat( 191 downto  160) <= dmem_05;
    dmem_flat( 223 downto  192) <= dmem_06; dmem_flat( 255 downto  224) <= dmem_07;
    dmem_flat( 287 downto  256) <= dmem_08; dmem_flat( 319 downto  288) <= dmem_09;
    dmem_flat( 351 downto  320) <= dmem_10; dmem_flat( 383 downto  352) <= dmem_11;
    dmem_flat( 415 downto  384) <= dmem_12; dmem_flat( 447 downto  416) <= dmem_13;
    dmem_flat( 479 downto  448) <= dmem_14; dmem_flat( 511 downto  480) <= dmem_15;
    dmem_flat( 543 downto  512) <= dmem_16; dmem_flat( 575 downto  544) <= dmem_17;
    dmem_flat( 607 downto  576) <= dmem_18; dmem_flat( 639 downto  608) <= dmem_19;
    dmem_flat( 671 downto  640) <= dmem_20; dmem_flat( 703 downto  672) <= dmem_21;
    dmem_flat( 735 downto  704) <= dmem_22; dmem_flat( 767 downto  736) <= dmem_23;
    dmem_flat( 799 downto  768) <= dmem_24; dmem_flat( 831 downto  800) <= dmem_25;
    dmem_flat( 863 downto  832) <= dmem_26; dmem_flat( 895 downto  864) <= dmem_27;
    dmem_flat( 927 downto  896) <= dmem_28; dmem_flat( 959 downto  928) <= dmem_29;
    dmem_flat( 991 downto  960) <= dmem_30; dmem_flat(1023 downto  992) <= dmem_31;

    -- ══════════════════════════════════════════════════════════════════════════
    -- Serviços do ecall (entrega 50)
    --   O ecall chega ao top como qualquer instrução. Se a7 for 1, 4, 5 ou
    --   11, ele não para a CPU: o gerador de clock segura a borda que o
    --   executaria (sys_hold) e pede o serviço (sys_go). Quando o serviço
    --   termina (sys_done), a borda sai e o ecall executa como NOP
    --   (PC + 4, 1 passo). No a7 = 5, a mesma borda grava em a0 o número
    --   digitado (sys_we/sys_wd, porta extra do banco de registradores).
    --   Números como no RARS; a7 = 10 e os outros continuam parando a CPU.
    -- ══════════════════════════════════════════════════════════════════════════
    is_ecall   <= '1' when proc_instr_mux = x"00000073" else '0';
    svc_ok     <= '1' when sys_a7 = x"00000001" or sys_a7 = x"00000004" or
                           sys_a7 = x"00000005" or sys_a7 = x"0000000B" else '0';
    sys_hold   <= is_ecall and svc_ok and not sys_done;
    sys_wait   <= '1' when sys_st = SY_WAIT else '0';
    input_mode <= sys_wait and SW(1);

    -- byte str_addr da memória de dados (string do a7 = 4)
    process(str_addr, dmem_00, dmem_01, dmem_02, dmem_03,
                      dmem_04, dmem_05, dmem_06, dmem_07,
                      dmem_08, dmem_09, dmem_10, dmem_11,
                      dmem_12, dmem_13, dmem_14, dmem_15,
                      dmem_16, dmem_17, dmem_18, dmem_19,
                      dmem_20, dmem_21, dmem_22, dmem_23,
                      dmem_24, dmem_25, dmem_26, dmem_27,
                      dmem_28, dmem_29, dmem_30, dmem_31)
    begin
        case str_addr(6 downto 2) is
            when "00000"  => str_word <= dmem_00;
            when "00001"  => str_word <= dmem_01;
            when "00010"  => str_word <= dmem_02;
            when "00011"  => str_word <= dmem_03;
            when "00100"  => str_word <= dmem_04;
            when "00101"  => str_word <= dmem_05;
            when "00110"  => str_word <= dmem_06;
            when "00111"  => str_word <= dmem_07;
            when "01000"  => str_word <= dmem_08;
            when "01001"  => str_word <= dmem_09;
            when "01010"  => str_word <= dmem_10;
            when "01011"  => str_word <= dmem_11;
            when "01100"  => str_word <= dmem_12;
            when "01101"  => str_word <= dmem_13;
            when "01110"  => str_word <= dmem_14;
            when "01111"  => str_word <= dmem_15;
            when "10000"  => str_word <= dmem_16;
            when "10001"  => str_word <= dmem_17;
            when "10010"  => str_word <= dmem_18;
            when "10011"  => str_word <= dmem_19;
            when "10100"  => str_word <= dmem_20;
            when "10101"  => str_word <= dmem_21;
            when "10110"  => str_word <= dmem_22;
            when "10111"  => str_word <= dmem_23;
            when "11000"  => str_word <= dmem_24;
            when "11001"  => str_word <= dmem_25;
            when "11010"  => str_word <= dmem_26;
            when "11011"  => str_word <= dmem_27;
            when "11100"  => str_word <= dmem_28;
            when "11101"  => str_word <= dmem_29;
            when "11110"  => str_word <= dmem_30;
            when others   => str_word <= dmem_31;
        end case;
    end process;
    with str_addr(1 downto 0) select
        str_byte <= str_word(7  downto 0)  when "00",
                    str_word(15 downto 8)  when "01",
                    str_word(23 downto 16) when "10",
                    str_word(31 downto 24) when others;

    process(CLOCK_50, cpu_rst)
        type pow_t is array(0 to 9) of UNSIGNED(31 downto 0);
        constant POW10 : pow_t := (
            to_unsigned(1, 32),          to_unsigned(10, 32),
            to_unsigned(100, 32),        to_unsigned(1000, 32),
            to_unsigned(10000, 32),      to_unsigned(100000, 32),
            to_unsigned(1000000, 32),    to_unsigned(10000000, 32),
            to_unsigned(100000000, 32),  to_unsigned(1000000000, 32));
        variable c   : UNSIGNED(7 downto 0);
        variable v   : UNSIGNED(31 downto 0);
        -- começa a imprimir v como inteiro com sinal (o '-' sai agora)
        procedure start_int(x : UNSIGNED(31 downto 0); echo : STD_LOGIC) is
        begin
            if x(31) = '1' then
                con_ch  <= x"2D";  con_put <= '1';           -- '-'
                num_mag <= (not x) + 1;                      -- -2^31 também cabe
            else
                num_mag <= x;
            end if;
            num_k       <= 9;
            num_dig     <= (others => '0');
            num_started <= '0';
            num_echo    <= echo;
            sys_st      <= SY_INT;
        end procedure;
    begin
        if cpu_rst = '1' then
            sys_st   <= SY_IDLE;
            sys_done <= '0';
            sys_we   <= '0';
            sys_wd   <= (others => '0');
            con_put  <= '0';
            sys_err  <= '0';
            sys_okin <= '0';
        elsif rising_edge(CLOCK_50) then
            con_put  <= '0';
            sys_err  <= '0';
            sys_okin <= '0';
            -- a CPU acabou de executar uma instrução (a mesma detecção do
            -- shadow): o próximo ecall é outro serviço
            if proc_clk_r = '1' and shadow_clk_prev = '0' then
                sys_done <= '0';
                sys_we   <= '0';
            end if;

            case sys_st is
                when SY_IDLE =>
                    if sys_go = '1' and sys_done = '0' and is_ecall = '1' and svc_ok = '1' then
                        if sys_a7(3 downto 0) = "1011" then          -- 11: caractere
                            con_ch  <= sys_a0(7 downto 0);
                            con_put <= '1';
                            sys_st  <= SY_FIN;
                        elsif sys_a7(3 downto 0) = "0001" then       -- 1: inteiro
                            start_int(UNSIGNED(sys_a0), '0');
                        elsif sys_a7(3 downto 0) = "0100" then       -- 4: string
                            str_addr <= UNSIGNED(sys_a0(6 downto 0));
                            str_cnt  <= 0;
                            sys_st   <= SY_STR;
                        else                                          -- 5: lê inteiro
                            sys_st   <= SY_WAIT;
                        end if;
                    end if;

                when SY_INT =>
                    -- um dígito por potência de 10, por subtrações sucessivas
                    -- (no máximo 9 por dígito): ~100 ciclos para 10 dígitos
                    if num_mag >= POW10(num_k) then
                        num_mag <= num_mag - POW10(num_k);
                        num_dig <= num_dig + 1;
                    else
                        if num_dig /= 0 or num_started = '1' or num_k = 0 then
                            con_ch      <= STD_LOGIC_VECTOR(to_unsigned(48, 8) + resize(num_dig, 8));
                            con_put     <= '1';
                            num_started <= '1';
                        end if;
                        num_dig <= (others => '0');
                        if num_k = 0 then
                            if num_echo = '1' then sys_st <= SY_NL; else sys_st <= SY_FIN; end if;
                        else
                            num_k <= num_k - 1;
                        end if;
                    end if;

                when SY_NL =>                                       -- fim do eco
                    con_ch  <= x"0A";
                    con_put <= '1';
                    sys_st  <= SY_FIN;

                when SY_STR =>
                    if str_byte = x"00" or str_cnt = 128 then
                        sys_st <= SY_FIN;
                    else
                        con_ch   <= str_byte;
                        con_put  <= '1';
                        str_addr <= str_addr + 1;
                        str_cnt  <= str_cnt + 1;
                    end if;

                when SY_WAIT =>
                    -- espera um ENTER com a CPU ligada (com SW[1]=0 o ENTER
                    -- volta a ser da edição do programa)
                    if parse_en_s = '1' and SW(1) = '1' then
                        in_i   <= 0;
                        in_acc <= (others => '0');
                        in_neg <= '0';
                        in_ph  <= 0;
                        in_bad <= '0';
                        sys_st <= SY_PARSE;
                    end if;

                when SY_PARSE =>
                    -- [espaços] [+|-] dígitos [espaços]; um caractere por ciclo
                    if in_i = 20 or in_i >= to_integer(line_len_s) then
                        if in_bad = '1' or in_ph < 2 then
                            sys_err <= '1';                            -- Err:1, continua esperando
                            sys_st  <= SY_WAIT;
                        else
                            if in_neg = '1' then v := (not in_acc) + 1; else v := in_acc; end if;
                            sys_wd   <= STD_LOGIC_VECTOR(v);
                            sys_we   <= '1';                           -- grava a0 na borda do ecall
                            sys_okin <= '1';
                            start_int(v, '1');                         -- eco do número + '\n'
                        end if;
                    else
                        c := (others => '0');                        -- caractere in_i da linha
                        for i in 0 to 19 loop
                            if i = in_i then c := UNSIGNED(line_buf_s(159 - 8*i downto 152 - 8*i)); end if;
                        end loop;
                        if c = 32 then
                            if in_ph = 1 then in_bad <= '1';
                            elsif in_ph = 2 then in_ph <= 3;
                            end if;
                        elsif (c = 45 or c = 43) and in_ph = 0 then    -- '-' / '+'
                            if c = 45 then in_neg <= '1'; end if;
                            in_ph <= 1;
                        elsif c >= 48 and c <= 57 and in_ph <= 2 then
                            in_acc <= resize(in_acc * 10, 32) + resize(c - 48, 32);
                            in_ph  <= 2;
                        else
                            in_bad <= '1';
                        end if;
                        in_i <= in_i + 1;
                    end if;

                when SY_FIN =>
                    sys_done <= '1';
                    sys_st   <= SY_IDLE;
            end case;
        end if;
    end process;

    u_con : console_buf
        generic map(ROWS => 6, COLS => 48)
        port map(clk => CLOCK_50, rst => cpu_rst, put => con_put, ch => con_ch, flat => con_flat);

    -- ══════════════════════════════════════════════════════════════════════════
    -- Halt — NÃO pegajoso, recalculado a cada ciclo
    --   PC fora da memória, ou PC além da última instrução gravada → para.
    --   PC desalinhado (jalr) ou apontando para ecall/ebreak → para.
    --   Com write_addr_s = 0 (programa vazio), PC=0 já está "além" → parado.
    --   Vale também no modo demo (a demo é um programa carregado como outro).
    -- ══════════════════════════════════════════════════════════════════════════
    process(CLOCK_50, cpu_rst)
    begin
        if cpu_rst = '1' then
            proc_halt <= '1';
        elsif rising_edge(CLOCK_50) then
            if unsigned(proc_pc(31 downto IMEM_BITS + 2)) /=
               to_unsigned(TEXT_BASE, 32)(31 downto IMEM_BITS + 2) then
                proc_halt <= '1';                  -- fora da área do programa
            elsif proc_pc(1 downto 0) /= "00" then
                proc_halt <= '1';                  -- jalr para endereço desalinhado
            elsif ('0' & unsigned(proc_pc(IMEM_BITS + 1 downto 2))) >= write_addr_s then
                proc_halt <= '1';
            elsif proc_instr_mux(6 downto 0) = "1110011" and
                  not (is_ecall = '1' and svc_ok = '1') then
                proc_halt <= '1';                  -- ebreak, ecall a7 = 10 ou desconhecido
            else
                proc_halt <= '0';
            end if;
        end if;
    end process;

    -- ══════════════════════════════════════════════════════════════════════════
    -- 7 segmentos: desligados (tudo que mostravam já está no VGA).
    -- Na DE2-115 os segmentos acendem em '0'; "1111111" = apagado.
    -- ══════════════════════════════════════════════════════════════════════════
    HEX0 <= (others => '1'); HEX1 <= (others => '1');
    HEX2 <= (others => '1'); HEX3 <= (others => '1');
    HEX4 <= (others => '1'); HEX5 <= (others => '1');
    HEX6 <= (others => '1'); HEX7 <= (others => '1');

    -- ══════════════════════════════════════════════════════════════════════════
    -- LCD 16x2 (HD44780): título fixo
    --   linha 1: "  PROCESSADOR   "   linha 2: "RISC-V MONOCICLO"
    --   Reinicia junto com KEY[0] (prog_rst), o que também serve para
    --   recuperar o LCD se ele ligar com lixo na tela.
    -- ══════════════════════════════════════════════════════════════════════════
    u_lcd : lcd_controller
        port map(clk      => CLOCK_50,
                 reset    => prog_rst,
                 line1    => LCD_L1,
                 line2    => LCD_L2,
                 LCD_DATA => LCD_DATA,
                 LCD_EN   => LCD_EN,
                 LCD_RS   => LCD_RS,
                 LCD_RW   => LCD_RW,
                 LCD_ON   => LCD_ON,
                 LCD_BLON => LCD_BLON);

    -- ══════════════════════════════════════════════════════════════════════════
    -- LEDs: apagados (as informações estão no VGA)
    -- ══════════════════════════════════════════════════════════════════════════
    LEDR     <= (others => '0');
    LEDG     <= (others => '0');
    turbo_on <= SW(5) and SW(0);

    -- ══════════════════════════════════════════════════════════════════════════
    -- VGA
    -- ══════════════════════════════════════════════════════════════════════════
    u_vga : vga_display
        generic map(IMEM_BITS => IMEM_BITS, TEXT_BASE => TEXT_BASE, STACK_TOP => STACK_TOP)
        port map(
            clk_50     => CLOCK_50,
            reset      => kbd_reset,
            proc_pc    => proc_pc,
            proc_instr => proc_instr_mux,
            proc_halt  => proc_halt,
            write_addr => write_addr_s,
            steps_bcd  => steps_bcd,
            turbo      => turbo_on,
            view_idx   => view_idx,
            view_word  => view_word,
            view_count => write_addr_s,
            edit_on    => edit_on,
            edit_ptr   => edit_ptr,
            parse_err  => err_hold,
            diag_mode  => SW(2),
            demo_sel   => SW(10 downto 6),
            speed_sel  => SW(1 downto 0),
            regs       => regs_flat,
            dmem       => dmem_flat,
            reg_hex    => SW(3),
            abi_names  => SW(4),
            hl_reg     => hl_reg,
            hl_mem     => hl_mem,
            kbd_line   => kbd_buf_s,
            kbd_len    => kbd_len_s,
            con_flat   => con_flat,
            in_wait    => input_mode,
            VGA_CLK    => VGA_CLK,
            VGA_HS     => VGA_HS,
            VGA_VS     => VGA_VS,
            VGA_BLANK_N=> VGA_BLANK_N,
            VGA_SYNC_N => VGA_SYNC_N,
            VGA_R      => VGA_R,
            VGA_G      => VGA_G,
            VGA_B      => VGA_B
        );

end architecture;