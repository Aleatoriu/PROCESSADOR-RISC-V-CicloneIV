library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity vga_display is
    generic(IMEM_BITS : positive := 7;            -- memória de 2**IMEM_BITS instruções
            TEXT_BASE : natural  := 16#3000#;     -- endereço da 1ª instrução
            STACK_TOP : natural  := 16#80#);      -- sp no reset (fim da pilha)
    port(
        clk_50      : in  STD_LOGIC;
        reset       : in  STD_LOGIC;
        -- Estado do processador
        proc_pc     : in  STD_LOGIC_VECTOR(31 downto 0);
        proc_instr  : in  STD_LOGIC_VECTOR(31 downto 0);
        proc_halt   : in  STD_LOGIC;
        write_addr  : in  UNSIGNED(IMEM_BITS downto 0);   -- instruções gravadas
        steps_bcd   : in  STD_LOGIC_VECTOR(31 downto 0); -- passos, 8 dígitos BCD
        turbo       : in  STD_LOGIC;              -- TURBO ativo (SW[5] e SW[0])
        -- Painel "Programa": pede o slot view_idx, recebe a palavra em view_word
        view_idx    : out UNSIGNED(IMEM_BITS-1 downto 0) := (others => '0');
        view_word   : in  STD_LOGIC_VECTOR(31 downto 0);
        view_count  : in  UNSIGNED(IMEM_BITS downto 0);   -- instruções válidas
        -- Edição: cursor (slot do próximo ENTER) quando a CPU está desligada
        edit_on     : in  STD_LOGIC;
        edit_ptr    : in  UNSIGNED(IMEM_BITS downto 0);
        parse_err   : in  STD_LOGIC;
        diag_mode   : in  STD_LOGIC;                      -- SW[2]: modo demo
        demo_sel    : in  STD_LOGIC_VECTOR(4 downto 0);   -- SW[10:6]: número da demo
        speed_sel   : in  STD_LOGIC_VECTOR(1 downto 0);
        -- Registradores shadow x0-x31 (pacote: reg_n*32 +31 downto reg_n*32)
        regs        : in  STD_LOGIC_VECTOR(1023 downto 0);
        -- Memória de dados — 32 palavras (pacote: slot*32 +31 downto slot*32)
        --   0-15 = dados (00-3C), 16-31 = pilha (40-7C)
        dmem        : in  STD_LOGIC_VECTOR(1023 downto 0);
        -- Base dos registradores (SW[3]): '0' decimal com sinal, '1' hex
        reg_hex     : in  STD_LOGIC;
        -- Nomes dos registradores (SW[4]): '0' x0..x31, '1' nomes da ABI
        abi_names   : in  STD_LOGIC;
        -- Destaque: último registrador / palavra de memória escritos
        --   hl_reg(5) = válido, hl_reg(4:0) = registrador
        --   hl_mem(5) = válido, hl_mem(4:0) = palavra (endereço / 4)
        hl_reg      : in  STD_LOGIC_VECTOR(5 downto 0);
        hl_mem      : in  STD_LOGIC_VECTOR(5 downto 0);
        -- Entrada do teclado (eco na tela VGA)
        kbd_line    : in  STD_LOGIC_VECTOR(159 downto 0);  -- 20 chars digitados
        kbd_len     : in  UNSIGNED(4 downto 0);            -- 0..20 = coluna do cursor
        -- Saída dos ecall (entrega 50): 6 linhas de 48 caracteres, nas
        -- linhas 26-31 da coluna da esquerda (abaixo da memória de dados)
        --   linha r, coluna c em (r*48+c)*8+7 .. (r*48+c)*8
        con_flat    : in  STD_LOGIC_VECTOR(6*48*8-1 downto 0) := (others => '0');
        in_wait     : in  STD_LOGIC := '0';                -- ecall a7=5 esperando o número
        -- Saídas VGA
        VGA_CLK     : out STD_LOGIC;
        VGA_HS      : out STD_LOGIC;
        VGA_VS      : out STD_LOGIC;
        VGA_BLANK_N : out STD_LOGIC;
        VGA_SYNC_N  : out STD_LOGIC;
        VGA_R       : out STD_LOGIC_VECTOR(7 downto 0);
        VGA_G       : out STD_LOGIC_VECTOR(7 downto 0);
        VGA_B       : out STD_LOGIC_VECTOR(7 downto 0)
    );
end entity;

architecture rtl of vga_display is

    -- ─────────────────────────────────────────────────────────────────────────
    -- Componente de temporização VGA
    -- ─────────────────────────────────────────────────────────────────────────
    component vga_sync is
        port(
            clk_50    : in  STD_LOGIC;
            reset     : in  STD_LOGIC;
            pixel_clk : out STD_LOGIC;
            h_count   : out UNSIGNED(9 downto 0);
            v_count   : out UNSIGNED(9 downto 0);
            video_on  : out STD_LOGIC;
            h_sync    : out STD_LOGIC;
            v_sync    : out STD_LOGIC
        );
    end component;

    -- ─────────────────────────────────────────────────────────────────────────
    -- Paleta de cores (10 bits por canal)
    -- ─────────────────────────────────────────────────────────────────────────
    -- ADV7123: 8 bits por canal (R[7:0], G[7:0], B[7:0])
    -- Fundo: azul escuro
    constant BG_R : STD_LOGIC_VECTOR(7 downto 0) := x"00";
    constant BG_G : STD_LOGIC_VECTOR(7 downto 0) := x"00";
    constant BG_B : STD_LOGIC_VECTOR(7 downto 0) := x"28";  -- azul escuro
    -- Branco
    constant WH_R : STD_LOGIC_VECTOR(7 downto 0) := x"FF";
    constant WH_G : STD_LOGIC_VECTOR(7 downto 0) := x"FF";
    constant WH_B : STD_LOGIC_VECTOR(7 downto 0) := x"FF";
    -- Amarelo (cabeçalho)
    constant YL_R : STD_LOGIC_VECTOR(7 downto 0) := x"FF";
    constant YL_G : STD_LOGIC_VECTOR(7 downto 0) := x"FF";
    constant YL_B : STD_LOGIC_VECTOR(7 downto 0) := x"00";
    -- Ciano (separadores)
    constant CY_R : STD_LOGIC_VECTOR(7 downto 0) := x"00";
    constant CY_G : STD_LOGIC_VECTOR(7 downto 0) := x"FF";
    constant CY_B : STD_LOGIC_VECTOR(7 downto 0) := x"FF";
    -- Verde (valores de registradores)
    constant GN_R : STD_LOGIC_VECTOR(7 downto 0) := x"00";
    constant GN_G : STD_LOGIC_VECTOR(7 downto 0) := x"E0";
    constant GN_B : STD_LOGIC_VECTOR(7 downto 0) := x"00";
    -- Vermelho (parado/halt)
    constant GY_R : STD_LOGIC_VECTOR(7 downto 0) := x"70";   -- cinza: pilha livre
    constant GY_G : STD_LOGIC_VECTOR(7 downto 0) := x"70";
    constant GY_B : STD_LOGIC_VECTOR(7 downto 0) := x"80";

    constant RD_R : STD_LOGIC_VECTOR(7 downto 0) := x"FF";
    constant RD_G : STD_LOGIC_VECTOR(7 downto 0) := x"00";
    constant RD_B : STD_LOGIC_VECTOR(7 downto 0) := x"00";

    -- ─────────────────────────────────────────────────────────────────────────
    -- ROM de fonte 8x8 — ASCII 0x00-0x7F (128 chars × 8 linhas = 1024 bytes)
    -- ─────────────────────────────────────────────────────────────────────────
    type font_t is array(0 to 1023) of STD_LOGIC_VECTOR(7 downto 0);

    function init_font return font_t is
        variable f : font_t := (others => x"00");
    begin
        -- 0x21 !
        f(264):=x"18";f(265):=x"3C";f(266):=x"3C";f(267):=x"18";
        f(268):=x"18";f(270):=x"18";
        -- 0x22 "
        f(272):=x"66";f(273):=x"66";f(274):=x"24";
        -- 0x23 #
        f(280):=x"6C";f(281):=x"6C";f(282):=x"FE";f(283):=x"6C";
        f(284):=x"FE";f(285):=x"6C";f(286):=x"6C";
        -- 0x24 $
        f(288):=x"10";f(289):=x"38";f(290):=x"50";f(291):=x"38";
        f(292):=x"14";f(293):=x"28";f(294):=x"7C";f(295):=x"10";
        -- 0x25 %
        f(296):=x"64";f(297):=x"66";f(298):=x"0C";f(299):=x"18";
        f(300):=x"30";f(301):=x"66";f(302):=x"4C";
        -- 0x26 &
        f(304):=x"38";f(305):=x"6C";f(306):=x"6C";f(307):=x"38";
        f(308):=x"6D";f(309):=x"66";f(310):=x"3B";
        -- 0x27 '
        f(312):=x"18";f(313):=x"18";f(314):=x"10";
        -- 0x28 (
        f(320):=x"0C";f(321):=x"18";f(322):=x"30";f(323):=x"30";
        f(324):=x"30";f(325):=x"18";f(326):=x"0C";
        -- 0x29 )
        f(328):=x"30";f(329):=x"18";f(330):=x"0C";f(331):=x"0C";
        f(332):=x"0C";f(333):=x"18";f(334):=x"30";
        -- 0x2A *
        f(336):=x"00";f(337):=x"66";f(338):=x"3C";f(339):=x"FF";
        f(340):=x"3C";f(341):=x"66";
        -- 0x2B +
        f(345):=x"18";f(346):=x"18";f(347):=x"7E";f(348):=x"18";f(349):=x"18";
        -- 0x2C ,
        f(356):=x"18";f(357):=x"18";f(358):=x"10";
        -- 0x2D -
        f(363):=x"7E";
        -- 0x2E .
        f(373):=x"18";f(374):=x"18";
        -- 0x2F /
        f(376):=x"02";f(377):=x"06";f(378):=x"0C";f(379):=x"18";
        f(380):=x"30";f(381):=x"60";f(382):=x"40";
        -- 0x30 0
        f(384):=x"3C";f(385):=x"66";f(386):=x"6E";f(387):=x"76";
        f(388):=x"66";f(389):=x"66";f(390):=x"3C";
        -- 0x31 1
        f(392):=x"18";f(393):=x"38";f(394):=x"18";f(395):=x"18";
        f(396):=x"18";f(397):=x"18";f(398):=x"7E";
        -- 0x32 2
        f(400):=x"3C";f(401):=x"66";f(402):=x"06";f(403):=x"1C";
        f(404):=x"30";f(405):=x"60";f(406):=x"7E";
        -- 0x33 3
        f(408):=x"3C";f(409):=x"66";f(410):=x"06";f(411):=x"1C";
        f(412):=x"06";f(413):=x"66";f(414):=x"3C";
        -- 0x34 4
        f(416):=x"0E";f(417):=x"1E";f(418):=x"36";f(419):=x"66";
        f(420):=x"7F";f(421):=x"06";f(422):=x"06";
        -- 0x35 5
        f(424):=x"7E";f(425):=x"60";f(426):=x"7C";f(427):=x"06";
        f(428):=x"06";f(429):=x"66";f(430):=x"3C";
        -- 0x36 6
        f(432):=x"1C";f(433):=x"30";f(434):=x"60";f(435):=x"7C";
        f(436):=x"66";f(437):=x"66";f(438):=x"3C";
        -- 0x37 7
        f(440):=x"7E";f(441):=x"06";f(442):=x"0C";f(443):=x"18";
        f(444):=x"30";f(445):=x"30";f(446):=x"30";
        -- 0x38 8
        f(448):=x"3C";f(449):=x"66";f(450):=x"66";f(451):=x"3C";
        f(452):=x"66";f(453):=x"66";f(454):=x"3C";
        -- 0x39 9
        f(456):=x"3C";f(457):=x"66";f(458):=x"66";f(459):=x"3E";
        f(460):=x"06";f(461):=x"0C";f(462):=x"38";
        -- 0x3A :
        f(465):=x"18";f(466):=x"18";f(468):=x"18";f(469):=x"18";
        -- 0x3B ;
        f(473):=x"18";f(474):=x"18";f(476):=x"18";f(477):=x"18";f(478):=x"10";
        -- 0x3C <
        f(480):=x"06";f(481):=x"0C";f(482):=x"18";f(483):=x"30";
        f(484):=x"18";f(485):=x"0C";f(486):=x"06";
        -- 0x3D =
        f(490):=x"7E";f(492):=x"7E";
        -- 0x3E >
        f(496):=x"60";f(497):=x"30";f(498):=x"18";f(499):=x"0C";
        f(500):=x"18";f(501):=x"30";f(502):=x"60";
        -- 0x3F ?
        f(504):=x"3C";f(505):=x"66";f(506):=x"06";f(507):=x"0C";
        f(508):=x"18";f(510):=x"18";
        -- 0x40 @
        f(512):=x"7C";f(513):=x"82";f(514):=x"9E";f(515):=x"A6";
        f(516):=x"9C";f(517):=x"80";f(518):=x"7C";
        -- 0x41 A
        f(520):=x"18";f(521):=x"3C";f(522):=x"66";f(523):=x"66";
        f(524):=x"7E";f(525):=x"66";f(526):=x"66";
        -- 0x42 B
        f(528):=x"7C";f(529):=x"66";f(530):=x"66";f(531):=x"7C";
        f(532):=x"66";f(533):=x"66";f(534):=x"7C";
        -- 0x43 C
        f(536):=x"3C";f(537):=x"66";f(538):=x"60";f(539):=x"60";
        f(540):=x"60";f(541):=x"66";f(542):=x"3C";
        -- 0x44 D
        f(544):=x"78";f(545):=x"6C";f(546):=x"66";f(547):=x"66";
        f(548):=x"66";f(549):=x"6C";f(550):=x"78";
        -- 0x45 E
        f(552):=x"7E";f(553):=x"60";f(554):=x"60";f(555):=x"78";
        f(556):=x"60";f(557):=x"60";f(558):=x"7E";
        -- 0x46 F
        f(560):=x"7E";f(561):=x"60";f(562):=x"60";f(563):=x"78";
        f(564):=x"60";f(565):=x"60";f(566):=x"60";
        -- 0x47 G
        f(568):=x"3C";f(569):=x"66";f(570):=x"60";f(571):=x"6E";
        f(572):=x"66";f(573):=x"66";f(574):=x"3C";
        -- 0x48 H
        f(576):=x"66";f(577):=x"66";f(578):=x"66";f(579):=x"7E";
        f(580):=x"66";f(581):=x"66";f(582):=x"66";
        -- 0x49 I
        f(584):=x"3C";f(585):=x"18";f(586):=x"18";f(587):=x"18";
        f(588):=x"18";f(589):=x"18";f(590):=x"3C";
        -- 0x4A J
        f(592):=x"1E";f(593):=x"06";f(594):=x"06";f(595):=x"06";
        f(596):=x"66";f(597):=x"66";f(598):=x"3C";
        -- 0x4B K
        f(600):=x"66";f(601):=x"6C";f(602):=x"78";f(603):=x"70";
        f(604):=x"78";f(605):=x"6C";f(606):=x"66";
        -- 0x4C L
        f(608):=x"60";f(609):=x"60";f(610):=x"60";f(611):=x"60";
        f(612):=x"60";f(613):=x"60";f(614):=x"7E";
        -- 0x4D M
        f(616):=x"C6";f(617):=x"EE";f(618):=x"FE";f(619):=x"D6";
        f(620):=x"C6";f(621):=x"C6";f(622):=x"C6";
        -- 0x4E N
        f(624):=x"C6";f(625):=x"E6";f(626):=x"F6";f(627):=x"DE";
        f(628):=x"CE";f(629):=x"C6";f(630):=x"C6";
        -- 0x4F O
        f(632):=x"3C";f(633):=x"66";f(634):=x"66";f(635):=x"66";
        f(636):=x"66";f(637):=x"66";f(638):=x"3C";
        -- 0x50 P
        f(640):=x"7C";f(641):=x"66";f(642):=x"66";f(643):=x"7C";
        f(644):=x"60";f(645):=x"60";f(646):=x"60";
        -- 0x51 Q
        f(648):=x"3C";f(649):=x"66";f(650):=x"66";f(651):=x"66";
        f(652):=x"6A";f(653):=x"6C";f(654):=x"36";
        -- 0x52 R
        f(656):=x"7C";f(657):=x"66";f(658):=x"66";f(659):=x"7C";
        f(660):=x"78";f(661):=x"6C";f(662):=x"66";
        -- 0x53 S
        f(664):=x"3C";f(665):=x"66";f(666):=x"60";f(667):=x"3C";
        f(668):=x"06";f(669):=x"66";f(670):=x"3C";
        -- 0x54 T
        f(672):=x"7E";f(673):=x"18";f(674):=x"18";f(675):=x"18";
        f(676):=x"18";f(677):=x"18";f(678):=x"18";
        -- 0x55 U
        f(680):=x"66";f(681):=x"66";f(682):=x"66";f(683):=x"66";
        f(684):=x"66";f(685):=x"66";f(686):=x"3C";
        -- 0x56 V
        f(688):=x"66";f(689):=x"66";f(690):=x"66";f(691):=x"66";
        f(692):=x"66";f(693):=x"3C";f(694):=x"18";
        -- 0x57 W
        f(696):=x"C6";f(697):=x"C6";f(698):=x"C6";f(699):=x"D6";
        f(700):=x"FE";f(701):=x"EE";f(702):=x"C6";
        -- 0x58 X
        f(704):=x"C6";f(705):=x"C6";f(706):=x"6C";f(707):=x"38";
        f(708):=x"6C";f(709):=x"C6";f(710):=x"C6";
        -- 0x59 Y
        f(712):=x"66";f(713):=x"66";f(714):=x"66";f(715):=x"3C";
        f(716):=x"18";f(717):=x"18";f(718):=x"18";
        -- 0x5A Z
        f(720):=x"7E";f(721):=x"06";f(722):=x"0C";f(723):=x"18";
        f(724):=x"30";f(725):=x"60";f(726):=x"7E";
        -- 0x5B [
        f(728):=x"3C";f(729):=x"30";f(730):=x"30";f(731):=x"30";
        f(732):=x"30";f(733):=x"30";f(734):=x"3C";
        -- 0x5C backslash
        f(736):=x"40";f(737):=x"60";f(738):=x"30";f(739):=x"18";
        f(740):=x"0C";f(741):=x"06";f(742):=x"02";
        -- 0x5D ]
        f(744):=x"3C";f(745):=x"0C";f(746):=x"0C";f(747):=x"0C";
        f(748):=x"0C";f(749):=x"0C";f(750):=x"3C";
        -- 0x5E ^
        f(752):=x"18";f(753):=x"3C";f(754):=x"66";
        -- 0x5F _
        f(766):=x"7E";
        -- 0x60 `
        f(768):=x"30";f(769):=x"18";f(770):=x"0C";
        -- 0x61 a
        f(778):=x"3C";f(779):=x"06";f(780):=x"3E";f(781):=x"66";f(782):=x"3B";
        -- 0x62 b
        f(784):=x"60";f(785):=x"60";f(786):=x"7C";f(787):=x"66";
        f(788):=x"66";f(789):=x"66";f(790):=x"7C";
        -- 0x63 c
        f(794):=x"3C";f(795):=x"66";f(796):=x"60";f(797):=x"66";f(798):=x"3C";
        -- 0x64 d
        f(800):=x"06";f(801):=x"06";f(802):=x"3E";f(803):=x"66";
        f(804):=x"66";f(805):=x"66";f(806):=x"3B";
        -- 0x65 e
        f(810):=x"3C";f(811):=x"66";f(812):=x"7E";f(813):=x"60";f(814):=x"3C";
        -- 0x66 f
        f(816):=x"0E";f(817):=x"18";f(818):=x"18";f(819):=x"3E";
        f(820):=x"18";f(821):=x"18";f(822):=x"18";
        -- 0x67 g
        f(826):=x"3B";f(827):=x"66";f(828):=x"66";f(829):=x"3E";f(830):=x"06";f(831):=x"3C";
        -- 0x68 h
        f(832):=x"60";f(833):=x"60";f(834):=x"7C";f(835):=x"66";
        f(836):=x"66";f(837):=x"66";f(838):=x"66";
        -- 0x69 i
        f(840):=x"18";f(842):=x"38";f(843):=x"18";
        f(844):=x"18";f(845):=x"18";f(846):=x"3C";
        -- 0x6A j
        f(850):=x"06";f(852):=x"06";f(853):=x"06";f(854):=x"66";f(855):=x"3C";
        -- 0x6B k
        f(856):=x"60";f(857):=x"60";f(858):=x"66";f(859):=x"6C";
        f(860):=x"78";f(861):=x"6C";f(862):=x"66";
        -- 0x6C l
        f(864):=x"38";f(865):=x"18";f(866):=x"18";f(867):=x"18";
        f(868):=x"18";f(869):=x"18";f(870):=x"3C";
        -- 0x6D m
        f(874):=x"EC";f(875):=x"FE";f(876):=x"D6";f(877):=x"C6";f(878):=x"C6";
        -- 0x6E n
        f(882):=x"7C";f(883):=x"66";f(884):=x"66";f(885):=x"66";f(886):=x"66";
        -- 0x6F o
        f(890):=x"3C";f(891):=x"66";f(892):=x"66";f(893):=x"66";f(894):=x"3C";
        -- 0x70 p
        f(898):=x"7C";f(899):=x"66";f(900):=x"66";f(901):=x"7C";f(902):=x"60";f(903):=x"60";
        -- 0x71 q
        f(906):=x"3B";f(907):=x"66";f(908):=x"66";f(909):=x"3E";f(910):=x"06";f(911):=x"06";
        -- 0x72 r
        f(914):=x"6C";f(915):=x"76";f(916):=x"60";f(917):=x"60";f(918):=x"60";
        -- 0x73 s
        f(922):=x"3E";f(923):=x"60";f(924):=x"3C";f(925):=x"06";f(926):=x"7C";
        -- 0x74 t
        f(928):=x"30";f(929):=x"30";f(930):=x"7C";f(931):=x"30";
        f(932):=x"30";f(933):=x"30";f(934):=x"1C";
        -- 0x75 u
        f(938):=x"66";f(939):=x"66";f(940):=x"66";f(941):=x"66";f(942):=x"3B";
        -- 0x76 v
        f(946):=x"66";f(947):=x"66";f(948):=x"66";f(949):=x"3C";f(950):=x"18";
        -- 0x77 w
        f(954):=x"C6";f(955):=x"C6";f(956):=x"D6";f(957):=x"FE";f(958):=x"6C";
        -- 0x78 x
        f(962):=x"66";f(963):=x"3C";f(964):=x"18";f(965):=x"3C";f(966):=x"66";
        -- 0x79 y
        f(970):=x"66";f(971):=x"66";f(972):=x"66";f(973):=x"3E";f(974):=x"06";f(975):=x"3C";
        -- 0x7A z
        f(978):=x"7E";f(979):=x"0C";f(980):=x"18";f(981):=x"30";f(982):=x"7E";
        -- 0x7B {
        f(984):=x"0E";f(985):=x"18";f(986):=x"18";f(987):=x"70";
        f(988):=x"18";f(989):=x"18";f(990):=x"0E";
        -- 0x7C |
        f(992):=x"18";f(993):=x"18";f(994):=x"18";
        f(996):=x"18";f(997):=x"18";f(998):=x"18";
        -- 0x7D }
        f(1000):=x"70";f(1001):=x"18";f(1002):=x"18";f(1003):=x"0E";
        f(1004):=x"18";f(1005):=x"18";f(1006):=x"70";
        -- 0x7E ~
        f(1008):=x"76";f(1009):=x"DC";
        return f;
    end function;

    constant FONT : font_t := init_font;

    -- ─────────────────────────────────────────────────────────────────────────
    -- Funções auxiliares
    -- ─────────────────────────────────────────────────────────────────────────

    -- Nibble (4 bits) → código ASCII do dígito hex
    function nib_hex(n : STD_LOGIC_VECTOR(3 downto 0)) return integer is
    begin
        if unsigned(n) < 10 then return 48 + to_integer(unsigned(n));
        else                     return 55 + to_integer(unsigned(n));
        end if;
    end function;

    -- Extrai registrador n (0-31) do vetor empacotado (32 regs × 32 bits)
    function get_reg(rv : STD_LOGIC_VECTOR(1023 downto 0); n : integer)
            return STD_LOGIC_VECTOR is
    begin
        case n is
            when 0  => return x"00000000";
            when 1  => return rv(63   downto 32);
            when 2  => return rv(95   downto 64);
            when 3  => return rv(127  downto 96);
            when 4  => return rv(159  downto 128);
            when 5  => return rv(191  downto 160);
            when 6  => return rv(223  downto 192);
            when 7  => return rv(255  downto 224);
            when 8  => return rv(287  downto 256);
            when 9  => return rv(319  downto 288);
            when 10 => return rv(351  downto 320);
            when 11 => return rv(383  downto 352);
            when 12 => return rv(415  downto 384);
            when 13 => return rv(447  downto 416);
            when 14 => return rv(479  downto 448);
            when 15 => return rv(511  downto 480);
            when 16 => return rv(543  downto 512);
            when 17 => return rv(575  downto 544);
            when 18 => return rv(607  downto 576);
            when 19 => return rv(639  downto 608);
            when 20 => return rv(671  downto 640);
            when 21 => return rv(703  downto 672);
            when 22 => return rv(735  downto 704);
            when 23 => return rv(767  downto 736);
            when 24 => return rv(799  downto 768);
            when 25 => return rv(831  downto 800);
            when 26 => return rv(863  downto 832);
            when 27 => return rv(895  downto 864);
            when 28 => return rv(927  downto 896);
            when 29 => return rv(959  downto 928);
            when 30 => return rv(991  downto 960);
            when 31 => return rv(1023 downto 992);
            when others => return x"00000000";
        end case;
    end function;

    -- Extrai palavra de memória n (0-15)
    -- caractere da saída (ecall) na posição n = linha*48 + coluna. Laço com
    -- fatias constantes em vez de uma fatia de índice variável, que o Quartus
    -- não aceita em todos os casos (vira um mux de 288 entradas).
    function get_con(cf : STD_LOGIC_VECTOR(6*48*8-1 downto 0); n : integer)
            return integer is
        variable r : integer range 0 to 255 := 32;
    begin
        for i in 0 to 6*48-1 loop
            if i = n then r := to_integer(unsigned(cf(i*8+7 downto i*8))); end if;
        end loop;
        return r;
    end function;

    function get_mem(dv : STD_LOGIC_VECTOR(1023 downto 0); n : integer)
            return STD_LOGIC_VECTOR is
    begin
        case n is
            when 0  => return dv(31   downto 0);
            when 1  => return dv(63   downto 32);
            when 2  => return dv(95   downto 64);
            when 3  => return dv(127  downto 96);
            when 4  => return dv(159  downto 128);
            when 5  => return dv(191  downto 160);
            when 6  => return dv(223  downto 192);
            when 7  => return dv(255  downto 224);
            when 8  => return dv(287  downto 256);
            when 9  => return dv(319  downto 288);
            when 10 => return dv(351  downto 320);
            when 11 => return dv(383  downto 352);
            when 12 => return dv(415  downto 384);
            when 13 => return dv(447  downto 416);
            when 14 => return dv(479  downto 448);
            when 15 => return dv(511  downto 480);
            when 16 => return dv(543  downto 512);
            when 17 => return dv(575  downto 544);
            when 18 => return dv(607  downto 576);
            when 19 => return dv(639  downto 608);
            when 20 => return dv(671  downto 640);
            when 21 => return dv(703  downto 672);
            when 22 => return dv(735  downto 704);
            when 23 => return dv(767  downto 736);
            when 24 => return dv(799  downto 768);
            when 25 => return dv(831  downto 800);
            when 26 => return dv(863  downto 832);
            when 27 => return dv(895  downto 864);
            when 28 => return dv(927  downto 896);
            when 29 => return dv(959  downto 928);
            when 30 => return dv(991  downto 960);
            when 31 => return dv(1023 downto 992);
            when others => return x"00000000";
        end case;
    end function;

    -- Dezena / unidade de um número de registrador (0..31), sem divisão
    function reg_tens(r : integer range 0 to 31) return integer is
    begin
        if    r >= 30 then return 3;
        elsif r >= 20 then return 2;
        elsif r >= 10 then return 1;
        else               return 0;
        end if;
    end function;

    -- i-ésimo dígito hex (0 = mais significativo) de uma palavra
    function hex_at(w : STD_LOGIC_VECTOR(31 downto 0); i : integer range 0 to 7)
            return integer is
    begin
        case i is
            when 0      => return nib_hex(w(31 downto 28));
            when 1      => return nib_hex(w(27 downto 24));
            when 2      => return nib_hex(w(23 downto 20));
            when 3      => return nib_hex(w(19 downto 16));
            when 4      => return nib_hex(w(15 downto 12));
            when 5      => return nib_hex(w(11 downto 8));
            when 6      => return nib_hex(w(7  downto 4));
            when others => return nib_hex(w(3  downto 0));
        end case;
    end function;


    -- Nomes das demos (SW[10:6]), 15 caracteres, mostrados na linha "Demo"
    type dname_t  is array(0 to 14) of integer range 0 to 127;
    type dnames_t is array(0 to 31) of dname_t;
    constant DEMO_NAMES : dnames_t := (
        (40,118,97,122,105,111,41,32,32,32,32,32,32,32,32),   -- (vazio)
        (68,49,32,83,111,109,97,32,101,32,115,117,98,32,32),   -- D1 Soma e sub
        (68,50,32,76,111,103,105,99,97,32,32,32,32,32,32),   -- D2 Logica
        (68,51,32,68,101,115,108,111,99,97,109,101,110,116,111),   -- D3 Deslocamento
        (68,52,32,67,111,109,112,97,114,97,99,97,111,32,32),   -- D4 Comparacao
        (68,53,32,108,117,105,32,101,32,97,117,105,112,99,32),   -- D5 lui e auipc
        (68,54,32,77,117,108,116,105,112,108,105,99,97,32,32),   -- D6 Multiplica
        (68,55,32,86,97,114,32,109,101,109,111,114,105,97,32),   -- D7 Var memoria
        (68,56,32,86,101,116,111,114,32,98,97,115,101,32,32),   -- D8 Vetor base
        (68,57,32,66,121,116,101,115,32,115,98,32,108,98,32),   -- D9 Bytes sb lb
        (68,49,48,32,105,102,32,101,108,115,101,32,32,32,32),   -- D10 if else
        (68,49,49,32,76,97,99,111,32,102,111,114,32,32,32),   -- D11 Laco for
        (68,49,50,32,70,105,98,111,110,97,99,99,105,32,32),   -- D12 Fibonacci
        (68,49,51,32,77,97,105,111,114,32,109,101,110,111,114),   -- D13 Maior menor
        (68,49,52,32,79,114,100,101,110,97,99,97,111,32,32),   -- D14 Ordenacao
        (68,49,53,32,84,85,82,66,79,32,32,32,32,32,32),   -- D15 TURBO
        (68,49,54,32,70,117,110,99,97,111,32,106,97,108,32),   -- D16 Funcao jal
        (68,49,55,32,83,101,109,32,112,105,108,104,97,32,32),   -- D17 Sem pilha
        (68,49,56,32,80,105,108,104,97,32,115,97,108,118,97),   -- D18 Pilha salva
        (68,49,57,32,67,111,110,118,101,110,99,97,111,32,32),   -- D19 Convencao
        (68,50,48,32,65,114,101,97,32,40,114,97,41,32,32),   -- D20 Area (ra)
        (68,50,49,32,102,49,32,102,50,32,32,32,32,32,32),   -- D21 f1 f2
        (68,50,50,32,82,101,99,117,114,115,97,111,32,32,32),   -- D22 Recursao
        (68,50,51,32,80,111,110,116,101,105,114,111,32,32,32),   -- D23 Ponteiro
        (68,50,52,32,86,101,116,111,114,32,108,111,99,97,108),   -- D24 Vetor local
        (68,50,53,32,70,105,98,32,114,101,99,117,114,115,32),   -- D25 Fib recurs
        (68,50,54,32,69,115,116,111,117,114,111,32,32,32,32),   -- D26 Estouro
        (68,50,55,32,70,73,78,65,76,32,32,32,32,32,32),   -- D27 FINAL
        (40,118,97,122,105,111,41,32,32,32,32,32,32,32,32),   -- (vazio)
        (40,118,97,122,105,111,41,32,32,32,32,32,32,32,32),   -- (vazio)
        (84,51,48,32,101,99,97,108,108,32,69,47,83,32,32),   -- T30 ecall E/S
        (84,51,49,32,84,101,115,116,101,32,82,86,51,50,32));   -- T31 Teste RV32

    -- Nomes da ABI (SW[4]=1): até 4 letras, completados com espaço
    type abin_t  is array(0 to 3) of integer range 0 to 127;
    type abit_t  is array(0 to 31) of abin_t;
    constant ABI_NAME : abit_t := (
        (122,101,114,111),   -- x0 zero
        (114,97,32,32),   -- x1 ra
        (115,112,32,32),   -- x2 sp
        (103,112,32,32),   -- x3 gp
        (116,112,32,32),   -- x4 tp
        (116,48,32,32),   -- x5 t0
        (116,49,32,32),   -- x6 t1
        (116,50,32,32),   -- x7 t2
        (115,48,32,32),   -- x8 s0
        (115,49,32,32),   -- x9 s1
        (97,48,32,32),   -- x10 a0
        (97,49,32,32),   -- x11 a1
        (97,50,32,32),   -- x12 a2
        (97,51,32,32),   -- x13 a3
        (97,52,32,32),   -- x14 a4
        (97,53,32,32),   -- x15 a5
        (97,54,32,32),   -- x16 a6
        (97,55,32,32),   -- x17 a7
        (115,50,32,32),   -- x18 s2
        (115,51,32,32),   -- x19 s3
        (115,52,32,32),   -- x20 s4
        (115,53,32,32),   -- x21 s5
        (115,54,32,32),   -- x22 s6
        (115,55,32,32),   -- x23 s7
        (115,56,32,32),   -- x24 s8
        (115,57,32,32),   -- x25 s9
        (115,49,48,32),   -- x26 s10
        (115,49,49,32),   -- x27 s11
        (116,51,32,32),   -- x28 t3
        (116,52,32,32),   -- x29 t4
        (116,53,32,32),   -- x30 t5
        (116,54,32,32));   -- x31 t6
    type abil_t is array(0 to 31) of integer range 2 to 4;
    constant ABI_LEN : abil_t := (4,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,3,3,2,2,2,2);

    -- ─────────────────────────────────────────────────────────────────────────
    -- Sinais internos
    -- ─────────────────────────────────────────────────────────────────────────
    signal pclk          : STD_LOGIC;
    signal hc, vc        : UNSIGNED(9 downto 0);
    signal vid_on        : STD_LOGIC;
    signal hs_s, vs_s    : STD_LOGIC;

    signal hs_r, vs_r    : STD_LOGIC := '1';
    signal bl_r          : STD_LOGIC := '0';
    signal r_r, g_r, b_r : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');

    -- Cursor piscante para entrada de teclado (0.5 Hz blink via CLOCK_50)
    signal blink_cnt  : UNSIGNED(24 downto 0) := (others => '0');
    -- Dígitos do contador de instruções, registrados no clock de pixel
    signal wa_hund    : integer range 0 to 9 := 0;
    signal wa_tens    : integer range 0 to 9 := 0;
    signal wa_units   : integer range 0 to 9 := 0;
    signal cursor_on  : STD_LOGIC := '1';
    signal cur_col    : integer range 4 to 24 := 4;   -- coluna do cursor do teclado

    -- ─────────────────────────────────────────────────────────────────────────
    -- Painel "Programa" (colunas 43-79, altura inteira da tela)
    --   Grade vertical própria, mais apertada que o resto da tela:
    --   linhas de PAN_PITCH px (8 de glifo + 6 vazias) em vez de 16.
    --   Linha 0 = título; linhas 1..32 = janela de 32 instruções a partir de
    --   pan_top (rola com o cursor de edição ou com o PC) -> 33 x 14 = 462 px.
    --   Texto nas colunas 44-78: "AAA>" (endereço de 3 dígitos + marcador)
    --   + até 31 caracteres, mais do que a instrução mais longa (21).
    -- ─────────────────────────────────────────────────────────────────────────
    constant NMAX      : integer := 2**IMEM_BITS;   -- instruções na memória
    constant PAN_COL0  : integer := 51;  -- coluna do divisor vertical
    constant PAN_LAST  : integer := 78;  -- última coluna de texto (79 = margem)
    constant PAN_PITCH : integer := 14;  -- px por linha do painel
    constant L_PITCH   : integer := 12;  -- px por linha da coluna da esquerda
                                         -- (entrega 50: eram 16; 480/12 = 40
                                         -- linhas, para caber a saída do ecall)
    constant PAN_N     : integer := 16;  -- linhas de instrução visíveis
    -- Pilha, abaixo do programa na mesma coluna: título na linha PAN_N+1 e
    -- as 16 palavras 7C..40 (de cima para baixo) nas linhas PAN_N+2..PAN_N+17
    constant STK_T     : integer := PAN_N + 1;
    constant STK_N     : integer := 16;
    constant PAN_W     : integer := PAN_LAST - PAN_COL0;  -- 27 caracteres

    subtype ch_t is integer range 0 to 127;
    type lbuf_t is array(0 to 35) of ch_t;
    signal lb       : lbuf_t := (others => 32);   -- texto da linha do painel
    signal lb_pc    : STD_LOGIC := '0';           -- esta linha = instrução do PC
    signal lb_sel   : STD_LOGIC := '0';           -- esta linha = cursor de edição
    -- linha da pilha: palavra em uso (endereço >= sp), seta do sp, destaque
    signal lb_alloc : STD_LOGIC := '0';
    signal lb_arrow : STD_LOGIC := '0';
    signal lb_hl    : STD_LOGIC := '0';

    -- Posição vertical na grade do painel (acompanha vc)
    signal pan_row  : integer range 0 to 63 := 0;            -- 0 = título
    signal l_row    : integer range 0 to 63 := 0;            -- linha de texto (esquerda)
    signal l_line   : integer range 0 to L_PITCH - 1 := 0;   -- 0-7 glifo, 8-11 vazio
    signal pan_line : integer range 0 to PAN_PITCH - 1 := 0; -- 0-7 glifo

    -- Pipeline de 2 estágios: A = caractere/cor (2 px antes),
    -- B = bit do glifo (1 px antes); o processo principal só escolhe.
    signal pa_on    : STD_LOGIC := '0';
    signal pa_bar   : STD_LOGIC := '0';           -- divisor vertical
    signal pa_cc    : ch_t := 32;
    signal pa_clr   : integer range 0 to 7 := 0;
    signal pa_bit   : integer range 0 to 7 := 0;
    signal pa_inv   : STD_LOGIC := '0';           -- vídeo inverso (cursor)
    signal pan_on   : STD_LOGIC := '0';
    signal pan_pix  : STD_LOGIC := '0';
    signal pan_clr  : integer range 0 to 7 := 0;  -- 0 branco 1 ciano 2 amarelo 3 verde 4 cinza 5 vermelho

    -- Estado congelado por quadro (capturado no retraço vertical)
    signal pan_cnt  : integer range 0 to NMAX := 0;     -- instruções válidas
    signal pan_pci  : integer range 0 to NMAX - 1 := 0; -- slot do PC
    signal pan_pcv  : STD_LOGIC := '0';                 -- PC dentro da memória
    signal pan_edit : STD_LOGIC := '0';                 -- modo edição
    signal pan_eptr : integer range 0 to NMAX := 0;     -- slot do cursor de edição
    signal pan_top  : integer range 0 to NMAX := 0;     -- 1ª linha da janela
    signal pan_abi  : STD_LOGIC := '0';                 -- nomes da ABI no painel
    signal stk_sp   : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');  -- sp do quadro
    signal stk_bad  : STD_LOGIC := '0';                 -- sp fora de 40..STACK_TOP
    -- título "-- Programa ----- PPP-UUU de NNN --": 9 dígitos decimais
    type dig9_t is array(0 to 8) of integer range 0 to 9;
    signal pan_dig  : dig9_t := (others => 0);

    -- Registradores: texto dos 3 valores da próxima linha da tela.
    --   O conversor monta, no vazio de 8 px de cada linha de texto (onde a
    --   área da esquerda não desenha nada), o texto dos 3 registradores da
    --   linha seguinte: 11 caracteres por valor, decimal com sinal alinhado
    --   à direita ou 8 dígitos hex. Assim o caminho do pixel só lê um
    --   caractere pronto, sem divisão nem mux de 32 registradores.
    type fld_t    is array(0 to 10) of ch_t;
    type rowtxt_t is array(0 to 2) of fld_t;
    signal rt      : rowtxt_t := (others => (others => 32));
    type cst_t is (C_IDLE, C_LOAD, C_SHIFT, C_STORE);
    signal cs      : cst_t := C_IDLE;
    signal c_j     : integer range 0 to 2 := 0;       -- coluna (0..2)
    signal c_row   : integer range 0 to 31 := 0;      -- linha de texto alvo
    signal c_i     : integer range 0 to 31 := 0;      -- bit do double dabble
    signal c_bcd   : UNSIGNED(39 downto 0) := (others => '0');   -- 10 dígitos
    signal c_mag   : UNSIGNED(31 downto 0) := (others => '0');   -- |valor|
    signal c_neg   : STD_LOGIC := '0';
    signal c_raw   : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal c_hex   : STD_LOGIC := '0';

    -- Desmontador sequencial
    type dst_t is (D_IDLE, D_FETCH, D_DECODE, D_BCD, D_EMIT);
    signal ds       : dst_t := D_IDLE;
    type tok_t is (K_END, K_MNEM, K_SP, K_COMMA, K_LPAR, K_RPAR,
                   K_RD, K_RS1, K_RS2, K_IMM, K_HEX);
    type fmt_t is array(0 to 8) of tok_t;         -- posição 8 é sempre K_END
    constant F_R   : fmt_t := (K_MNEM,K_SP,K_RD,K_COMMA,K_RS1,K_COMMA,K_RS2,K_END,K_END);
    constant F_I   : fmt_t := (K_MNEM,K_SP,K_RD,K_COMMA,K_RS1,K_COMMA,K_IMM,K_END,K_END);
    constant F_RI  : fmt_t := (K_MNEM,K_SP,K_RD,K_COMMA,K_IMM,K_END,K_END,K_END,K_END); -- li, jal
    constant F_MV  : fmt_t := (K_MNEM,K_SP,K_RD,K_COMMA,K_RS1,K_END,K_END,K_END,K_END);
    constant F_LW  : fmt_t := (K_MNEM,K_SP,K_RD,K_COMMA,K_IMM,K_LPAR,K_RS1,K_RPAR,K_END);
    constant F_SW  : fmt_t := (K_MNEM,K_SP,K_RS2,K_COMMA,K_IMM,K_LPAR,K_RS1,K_RPAR,K_END);
    constant F_B   : fmt_t := (K_MNEM,K_SP,K_RS1,K_COMMA,K_RS2,K_COMMA,K_IMM,K_END,K_END);
    constant F_UNK : fmt_t := (K_MNEM,K_SP,K_HEX,K_END,K_END,K_END,K_END,K_END,K_END);
    constant F_RET : fmt_t := (K_MNEM,K_END,K_END,K_END,K_END,K_END,K_END,K_END,K_END); -- ret

    type mn_t is array(0 to 5) of ch_t;           -- mnemônico (ASCII, até 6 letras)
    constant MN_ADD  : mn_t := (97,100,100,32,32,32);   -- add
    constant MN_SUB  : mn_t := (115,117,98,32,32,32);   -- sub
    constant MN_AND  : mn_t := (97,110,100,32,32,32);   -- and
    constant MN_OR   : mn_t := (111,114,32,32,32,32);   -- or
    constant MN_SLT  : mn_t := (115,108,116,32,32,32);  -- slt
    constant MN_ADDI : mn_t := (97,100,100,105,32,32);  -- addi
    constant MN_ANDI : mn_t := (97,110,100,105,32,32);  -- andi
    constant MN_ORI  : mn_t := (111,114,105,32,32,32);  -- ori
    constant MN_SLTI : mn_t := (115,108,116,105,32,32); -- slti
    constant MN_LI   : mn_t := (108,105,32,32,32,32);   -- li
    constant MN_MV   : mn_t := (109,118,32,32,32,32);   -- mv
    constant MN_LW   : mn_t := (108,119,32,32,32,32);   -- lw
    constant MN_SW   : mn_t := (115,119,32,32,32,32);   -- sw
    constant MN_SH   : mn_t := (115,104,32,32,32,32);   -- sh
    constant MN_SB   : mn_t := (115,98,32,32,32,32);    -- sb
    constant MN_MUL  : mn_t := (109,117,108,32,32,32);  -- mul
    constant MN_BNE  : mn_t := (98,110,101,32,32,32);   -- bne
    constant MN_BLT  : mn_t := (98,108,116,32,32,32);   -- blt
    constant MN_LB   : mn_t := (108,98,32,32,32,32);    -- lb
    constant MN_LH   : mn_t := (108,104,32,32,32,32);   -- lh
    constant MN_JALR : mn_t := (106,97,108,114,32,32);  -- jalr
    constant MN_LUI  : mn_t := (108,117,105,32,32,32);  -- lui
    constant MN_RET  : mn_t := (114,101,116,32,32,32);  -- ret
    constant MN_BEQ  : mn_t := (98,101,113,32,32,32);   -- beq
    constant MN_JAL  : mn_t := (106,97,108,32,32,32);   -- jal
    constant MN_XOR   : mn_t := (120,111,114,32,32,32);  -- xor
    constant MN_SLL   : mn_t := (115,108,108,32,32,32);  -- sll
    constant MN_SRL   : mn_t := (115,114,108,32,32,32);  -- srl
    constant MN_SRA   : mn_t := (115,114,97,32,32,32);  -- sra
    constant MN_SLTU  : mn_t := (115,108,116,117,32,32);  -- sltu
    constant MN_MULH  : mn_t := (109,117,108,104,32,32);  -- mulh
    constant MN_MULHSU: mn_t := (109,117,108,104,115,117);  -- mulhsu
    constant MN_MULHU : mn_t := (109,117,108,104,117,32);  -- mulhu
    constant MN_XORI  : mn_t := (120,111,114,105,32,32);  -- xori
    constant MN_SLTIU : mn_t := (115,108,116,105,117,32);  -- sltiu
    constant MN_SLLI  : mn_t := (115,108,108,105,32,32);  -- slli
    constant MN_SRLI  : mn_t := (115,114,108,105,32,32);  -- srli
    constant MN_SRAI  : mn_t := (115,114,97,105,32,32);  -- srai
    constant MN_LBU   : mn_t := (108,98,117,32,32,32);  -- lbu
    constant MN_LHU   : mn_t := (108,104,117,32,32,32);  -- lhu
    constant MN_BGE   : mn_t := (98,103,101,32,32,32);  -- bge
    constant MN_BLTU  : mn_t := (98,108,116,117,32,32);  -- bltu
    constant MN_BGEU  : mn_t := (98,103,101,117,32,32);  -- bgeu
    constant MN_AUIPC : mn_t := (97,117,105,112,99,32);  -- auipc
    constant MN_FENCE : mn_t := (102,101,110,99,101,32);  -- fence
    constant MN_ECALL : mn_t := (101,99,97,108,108,32);  -- ecall
    constant MN_EBREAK: mn_t := (101,98,114,101,97,107);  -- ebreak
    constant MN_UNK  : mn_t := (63,32,32,32,32,32);     -- ?

    signal d_fmt    : fmt_t := F_UNK;
    signal d_tk     : integer range 0 to 8 := 0;  -- token atual
    signal d_sub    : integer range 0 to 7 := 0;  -- caractere dentro do token
    signal d_wp     : integer range 0 to 36 := 0; -- próxima posição em lb
    signal d_mn     : mn_t := MN_UNK;
    signal d_mlen   : integer range 1 to 6 := 1;
    signal d_idx    : integer range 0 to NMAX - 1 := 0;
    signal d_w      : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal d_rd, d_rs1, d_rs2 : integer range 0 to 31 := 0;
    signal d_neg    : boolean := false;
    signal d_abs    : integer range 0 to 1048576 := 0;
    type dig_t is array(0 to 6) of integer range 0 to 15;
    signal d_dig    : dig_t := (others => 0);     -- |imediato| em decimal ou hex
    signal d_hex    : boolean := false;           -- lw/sw/sh/sb/jalr/lui: número em hex
    signal d_0x     : boolean := false;           -- lui: escreve "0x" antes
    signal d_k      : integer range 0 to 6 := 0;
    signal d_lead   : boolean := true;            -- ainda em zeros à esquerda
    -- Formatação (tenta a mais folgada que caiba nos 18 caracteres):
    --   0: mnemônico com 4 colunas + ", "   "addi x10, x10, 4"
    --   1: mnemônico com 4 colunas + ","    "addi x31,x31,-2048"
    --      (mnemônicos de 5-6 letras ocupam as suas letras)
    --   2: compacto                          "sw x31,-2048(x31)"
    --   3: compacto começando na coluna do marcador '>' (a linha do PC
    --      continua amarela). Só "sltiu x31,x31,-2048" (19 caracteres)
    --      precisa disso.
    signal d_lvl    : integer range 0 to 3 := 0;
    type pow_t is array(0 to 6) of integer range 1 to 1000000;
    constant POW10  : pow_t := (1, 10, 100, 1000, 10000, 100000, 1000000);

begin

    u_sync : vga_sync
        port map(clk_50, reset, pclk, hc, vc, vid_on, hs_s, vs_s);

    -- Dígitos do contador de instruções (0..2**IMEM_BITS), fora do caminho do pixel
    process(pclk)
        variable w : integer range 0 to NMAX;
    begin
        if rising_edge(pclk) then
            w := to_integer(write_addr);
            wa_hund  <= (w / 100) mod 10;
            wa_tens  <= (w / 10) mod 10;
            wa_units <= w mod 10;
        end if;
    end process;

    -- Coluna do cursor do teclado, registrada fora do caminho do pixel
    process(pclk)
    begin
        if rising_edge(pclk) then
            cur_col <= 4 + to_integer(kbd_len);
        end if;
    end process;

    -- Cursor piscante: toggle a cada 25M ciclos de CLOCK_50 ≈ 0.5 s
    process(clk_50)
    begin
        if rising_edge(clk_50) then
            if blink_cnt = 24999999 then
                blink_cnt <= (others => '0');
                cursor_on <= not cursor_on;
            else
                blink_cnt <= blink_cnt + 1;
            end if;
        end if;
    end process;

    -- ─────────────────────────────────────────────────────────────────────────
    -- Registradores em decimal: conversor binário -> decimal (double dabble)
    --   Dispara no começo do vazio (linha de pixel 8) da linha de texto cy e
    --   prepara a linha cy+1 (5..15 = registradores). Para cada um dos 3
    --   registradores: carrega |valor| (complemento de 2 se negativo), faz 32
    --   passos de "soma 3 nos dígitos >= 5 e desloca" (1 por ciclo) e monta
    --   os 11 caracteres. 3 x 34 ciclos ~ 4 us; o vazio dura 4 x 32 us.
    --   O maior texto é -2147483648 (11 caracteres).
    -- ─────────────────────────────────────────────────────────────────────────
    process(pclk)
        variable nr   : integer range 0 to 63;
        variable idx  : integer range 0 to 63;
        variable v    : STD_LOGIC_VECTOR(31 downto 0);
        variable b    : UNSIGNED(39 downto 0);
        variable f    : fld_t;
        variable hi   : integer range 0 to 9;
        variable dg   : integer range 0 to 15;
    begin
        if rising_edge(pclk) then
            if hc = 0 and vc < 480 and l_line = 8 then
                nr := l_row + 1;
                if nr >= 5 and nr <= 15 then
                    c_row <= nr;
                    c_j   <= 0;
                    c_hex <= reg_hex;
                    cs    <= C_LOAD;
                else
                    cs    <= C_IDLE;
                end if;
            else
                case cs is
                    when C_IDLE =>
                        null;

                    when C_LOAD =>
                        idx := c_j * 11 + c_row - 5;
                        if idx > 31 then                    -- não existe (x32)
                            rt(c_j) <= (others => 32);
                            cs <= C_IDLE;                   -- é sempre a coluna 2
                        else
                            v := get_reg(regs, idx);
                            c_raw <= v;
                            c_neg <= v(31);
                            if v(31) = '1' then
                                c_mag <= unsigned(not v) + 1;   -- -2^31 dá 2^31
                            else
                                c_mag <= unsigned(v);
                            end if;
                            c_bcd <= (others => '0');
                            c_i   <= 0;
                            cs    <= C_SHIFT;
                        end if;

                    when C_SHIFT =>
                        b := c_bcd;
                        for d in 0 to 9 loop
                            if b(4*d+3 downto 4*d) >= 5 then
                                b(4*d+3 downto 4*d) := b(4*d+3 downto 4*d) + 3;
                            end if;
                        end loop;
                        c_bcd <= b(38 downto 0) & c_mag(31);
                        c_mag <= c_mag(30 downto 0) & '0';
                        if c_i = 31 then cs <= C_STORE; else c_i <= c_i + 1; end if;

                    when C_STORE =>
                        if c_hex = '1' then
                            -- hexadecimal: 8 dígitos à esquerda, 3 espaços
                            for p in 0 to 7 loop
                                f(p) := nib_hex(c_raw(31 - 4*p downto 28 - 4*p));
                            end loop;
                            f(8) := 32; f(9) := 32; f(10) := 32;
                        else
                            -- decimal com sinal, alinhado à direita:
                            -- posição p (1..10) mostra o dígito 10-p
                            hi := 0;
                            for d in 1 to 9 loop
                                if c_bcd(4*d+3 downto 4*d) /= 0 then hi := d; end if;
                            end loop;
                            if c_neg = '1' and hi = 9 then f(0) := 45; else f(0) := 32; end if;
                            for p in 1 to 10 loop
                                dg := to_integer(c_bcd(4*(10-p)+3 downto 4*(10-p)));
                                if 10 - p <= hi then
                                    f(p) := 48 + dg;
                                elsif c_neg = '1' and 10 - p = hi + 1 then
                                    f(p) := 45;                 -- '-'
                                else
                                    f(p) := 32;
                                end if;
                            end loop;
                        end if;
                        rt(c_j) <= f;
                        if c_j = 2 then
                            cs <= C_IDLE;
                        else
                            c_j <= c_j + 1;
                            cs  <= C_LOAD;
                        end if;
                end case;
            end if;
        end if;
    end process;

    -- ─────────────────────────────────────────────────────────────────────────
    -- Painel "Programa" — 0) grade vertical própria (PAN_PITCH px por linha)
    --   Atualiza junto com vc (na borda em que hc = 799, o vga_sync avança vc).
    --   H_TOTAL = 800 e V_TOTAL = 525 vêm do vga_sync.
    -- ─────────────────────────────────────────────────────────────────────────
    process(pclk, reset)
    begin
        if reset = '1' then
            pan_row  <= 0;
            pan_line <= 0;
            l_row    <= 0;
            l_line   <= 0;
        elsif rising_edge(pclk) then
            if hc = 799 then
                if vc = 524 then
                    pan_row  <= 0;
                    pan_line <= 0;
                    l_row    <= 0;
                    l_line   <= 0;
                else
                    if pan_line = PAN_PITCH - 1 then
                        pan_line <= 0;
                        if pan_row < 63 then pan_row <= pan_row + 1; end if;
                    else
                        pan_line <= pan_line + 1;
                    end if;
                    -- mesma ideia para a coluna da esquerda (L_PITCH px)
                    if l_line = L_PITCH - 1 then
                        l_line <= 0;
                        if l_row < 63 then l_row <= l_row + 1; end if;
                    else
                        l_line <= l_line + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- ─────────────────────────────────────────────────────────────────────────
    -- Painel "Programa" — 1) estado do quadro, capturado no retraço vertical
    -- ─────────────────────────────────────────────────────────────────────────
    --   Janela de rolagem (pan_top): o foco é o cursor de edição (CPU
    --   desligada) ou o PC (CPU ligada). Como num editor, a janela só anda
    --   quando o foco chega a menos de 4 linhas da borda, e nunca passa do
    --   fim do programa (a última linha visível é a última instrução, ou a
    --   linha nova do cursor no fim).
    process(pclk)
        variable cnt, eptr, top, mx : integer range 0 to NMAX;
        variable foc  : integer range 0 to NMAX;
        variable pcv  : boolean;
        variable fst, lst : integer range 0 to NMAX;
    begin
        if rising_edge(pclk) then
            if vc = 480 and hc = 0 then
                cnt  := to_integer(view_count);
                eptr := to_integer(edit_ptr);
                pcv  := unsigned(proc_pc(31 downto IMEM_BITS + 2)) =
                        to_unsigned(TEXT_BASE, 32)(31 downto IMEM_BITS + 2);
                pan_cnt  <= cnt;
                pan_pci  <= to_integer(unsigned(proc_pc(IMEM_BITS + 1 downto 2)));
                if pcv then pan_pcv <= '1'; else pan_pcv <= '0'; end if;
                pan_edit <= edit_on;
                pan_eptr <= eptr;
                pan_abi  <= abi_names;
                stk_sp   <= regs(95 downto 64);                  -- x2 = sp
                if unsigned(regs(95 downto 64)) < 16#40# or
                   unsigned(regs(95 downto 64)) > STACK_TOP or regs(65 downto 64) /= "00" then
                    stk_bad <= '1';
                else
                    stk_bad <= '0';
                end if;

                top := pan_top;
                if edit_on = '1' or pcv then
                    if edit_on = '1' then
                        foc := eptr;
                    else
                        foc := to_integer(unsigned(proc_pc(IMEM_BITS + 1 downto 2)));
                    end if;
                    if foc < top + 4 then
                        if foc >= 4 then top := foc - 4; else top := 0; end if;
                    elsif foc > top + PAN_N - 5 then
                        top := foc - (PAN_N - 5);
                    end if;
                end if;
                -- última linha que pode aparecer
                if cnt > 0 then mx := cnt - 1; else mx := 0; end if;
                if edit_on = '1' and eptr > mx then mx := eptr; end if;
                if top + PAN_N - 1 > mx then
                    if mx >= PAN_N - 1 then top := mx - (PAN_N - 1); else top := 0; end if;
                end if;
                pan_top <= top;

                -- título: primeira e última linha visíveis (1, 2, ...) e total
                if cnt = 0 then
                    fst := 0; lst := 0;
                else
                    fst := top + 1;
                    if top + PAN_N < cnt then lst := top + PAN_N; else lst := cnt; end if;
                end if;
                pan_dig(0) <= (fst / 100) mod 10; pan_dig(1) <= (fst / 10) mod 10; pan_dig(2) <= fst mod 10;
                pan_dig(3) <= (lst / 100) mod 10; pan_dig(4) <= (lst / 10) mod 10; pan_dig(5) <= lst mod 10;
                pan_dig(6) <= (cnt / 100) mod 10; pan_dig(7) <= (cnt / 10) mod 10; pan_dig(8) <= cnt mod 10;
            end if;
        end if;
    end process;

    -- ─────────────────────────────────────────────────────────────────────────
    -- Painel "Programa" — 2) desmontador sequencial
    --   Dispara no início do vazio (linha de pixel 8) da linha P do painel e
    --   monta em lb o texto da linha P+1. O vazio não desenha glifos, então
    --   reescrever lb aqui não aparece na tela. Leva < 150 ciclos; o vazio
    --   tem (PAN_PITCH - 8) x 800 = 4800.
    -- ─────────────────────────────────────────────────────────────────────────
    process(pclk)
        variable trow : integer range 0 to 127;
        variable slot : integer range 0 to NMAX + 127;
        variable a16  : UNSIGNED(15 downto 0);
        variable sw_i : integer range 0 to 31;             -- palavra da pilha
        variable sv   : STD_LOGIC_VECTOR(31 downto 0);
        variable w       : STD_LOGIC_VECTOR(31 downto 0);
        variable op      : STD_LOGIC_VECTOR(6 downto 0);
        variable f3      : STD_LOGIC_VECTOR(2 downto 0);
        variable f7      : STD_LOGIC_VECTOR(6 downto 0);
        variable rdv, rs1v : integer range 0 to 31;
        variable imm     : integer range -1048576 to 1048575;
        variable v12     : STD_LOGIC_VECTOR(11 downto 0);   -- imediato S
        variable v13     : STD_LOGIC_VECTOR(12 downto 0);   -- imediato B
        variable v21     : STD_LOGIC_VECTOR(20 downto 0);   -- imediato J
        variable fmt     : fmt_t;
        variable mnv     : mn_t;
        variable ml      : integer range 1 to 6;
        variable put, adv : boolean;
        variable ch      : ch_t;
        variable rg      : integer range 0 to 31;
        variable u21     : UNSIGNED(20 downto 0);
    begin
        if rising_edge(pclk) then
            if hc = 0 and pan_line = 8 then
                -- ── início do vazio: prepara a próxima linha do painel ─────
                trow := pan_row + 1;
                ds <= D_IDLE;
                lb_alloc <= '0'; lb_arrow <= '0'; lb_hl <= '0';
                if trow >= 1 and trow <= PAN_N then
                    lb     <= (others => 32);
                    lb_pc  <= '0';
                    lb_sel <= '0';
                    slot   := pan_top + trow - 1;
                    if pan_edit = '1' and slot = pan_eptr then
                        lb_sel <= '1';                  -- cursor de edição
                    end if;
                    if slot < pan_cnt then
                        d_idx    <= slot;
                        view_idx <= to_unsigned(slot, IMEM_BITS);
                        ds       <= D_FETCH;
                    elsif pan_edit = '1' and slot = pan_eptr then
                        -- cursor no fim: linha nova ainda vazia, só o endereço
                        a16   := to_unsigned(TEXT_BASE + slot * 4, 16);
                        lb(0) <= nib_hex(STD_LOGIC_VECTOR(a16(15 downto 12)));
                        lb(1) <= nib_hex(STD_LOGIC_VECTOR(a16(11 downto 8)));
                        lb(2) <= nib_hex(STD_LOGIC_VECTOR(a16(7 downto 4)));
                        lb(3) <= nib_hex(STD_LOGIC_VECTOR(a16(3 downto 0)));
                    elsif pan_cnt = 0 and trow = 1 then
                        -- programa vazio: "    (vazio)"
                        lb <= (32,32,32,32,40,118,97,122,105,111,41, others => 32);
                    end if;
                elsif trow >= STK_T + 1 and trow <= STK_T + STK_N then
                    -- ── pilha: "[007C]=HHHHHHHH <- sp", da palavra 31 (7C) à 16 (40)
                    lb     <= (others => 32);
                    lb_pc  <= '0';
                    lb_sel <= '0';
                    sw_i := 31 - (trow - STK_T - 1);
                    sv   := get_mem(dmem, sw_i);
                    a16  := to_unsigned(sw_i * 4, 16);
                    lb(0) <= 91;                                          -- [
                    lb(1) <= 48; lb(2) <= 48;                             -- 00
                    lb(3) <= nib_hex(STD_LOGIC_VECTOR(a16(7 downto 4)));
                    lb(4) <= nib_hex(STD_LOGIC_VECTOR(a16(3 downto 0)));
                    lb(5) <= 93;                                          -- ]
                    lb(6) <= 61;                                          -- =
                    for i in 0 to 7 loop
                        lb(7 + i) <= nib_hex(sv(31 - 4*i downto 28 - 4*i));
                    end loop;
                    -- em uso: entre sp e o topo (STACK_TOP), só com o sp dentro
                    -- da área da pilha; livre: abaixo do sp, ou sp fora da área
                    -- (pilha ainda não iniciada, ou x2 usado como dado)
                    if stk_bad = '0' and stk_sp /= x"00000000" and
                       unsigned(stk_sp) <= to_unsigned(sw_i * 4, 32) and sw_i * 4 < STACK_TOP then
                        lb_alloc <= '1';
                    end if;
                    if unsigned(stk_sp) = to_unsigned(sw_i * 4, 32) then
                        lb_arrow <= '1';
                        lb(16) <= 60; lb(17) <= 45;                       -- <-
                        lb(19) <= 115; lb(20) <= 112;                     -- sp
                    end if;
                    if hl_mem(5) = '1' and to_integer(unsigned(hl_mem(4 downto 0))) = sw_i then
                        lb_hl <= '1';                                     -- último store
                    end if;
                end if;

            else
                case ds is
                    when D_IDLE =>
                        null;

                    when D_FETCH =>
                        -- view_idx foi registrado no ciclo anterior
                        d_w <= view_word;
                        ds  <= D_DECODE;

                    when D_DECODE =>
                        w    := d_w;
                        op   := w(6 downto 0);
                        f3   := w(14 downto 12);
                        f7   := w(31 downto 25);
                        rdv  := to_integer(unsigned(w(11 downto 7)));
                        rs1v := to_integer(unsigned(w(19 downto 15)));
                        imm  := 0;
                        fmt  := F_UNK; mnv := MN_UNK; ml := 1;
                        case op is
                            when "0110011" =>                       -- tipo R
                                if f7 = "0000000" and f3 = "000" then fmt := F_R; mnv := MN_ADD; ml := 3;
                                elsif f7 = "0100000" and f3 = "000" then fmt := F_R; mnv := MN_SUB; ml := 3;
                                elsif f7 = "0000000" and f3 = "111" then fmt := F_R; mnv := MN_AND; ml := 3;
                                elsif f7 = "0000000" and f3 = "110" then fmt := F_R; mnv := MN_OR;  ml := 2;
                                elsif f7 = "0000000" and f3 = "010" then fmt := F_R; mnv := MN_SLT; ml := 3;
                                elsif f7 = "0000000" and f3 = "100" then fmt := F_R; mnv := MN_XOR; ml := 3;
                                elsif f7 = "0000000" and f3 = "001" then fmt := F_R; mnv := MN_SLL; ml := 3;
                                elsif f7 = "0000000" and f3 = "101" then fmt := F_R; mnv := MN_SRL; ml := 3;
                                elsif f7 = "0100000" and f3 = "101" then fmt := F_R; mnv := MN_SRA; ml := 3;
                                elsif f7 = "0000000" and f3 = "011" then fmt := F_R; mnv := MN_SLTU; ml := 4;
                                elsif f7 = "0000001" and f3 = "000" then fmt := F_R; mnv := MN_MUL; ml := 3;
                                elsif f7 = "0000001" and f3 = "001" then fmt := F_R; mnv := MN_MULH; ml := 4;
                                elsif f7 = "0000001" and f3 = "010" then fmt := F_R; mnv := MN_MULHSU; ml := 6;
                                elsif f7 = "0000001" and f3 = "011" then fmt := F_R; mnv := MN_MULHU; ml := 5;
                                end if;
                            when "0010011" =>                       -- tipo I (ULA)
                                imm := to_integer(signed(w(31 downto 20)));
                                if f3 = "000" then
                                    if rs1v = 0 and rdv /= 0 then
                                        fmt := F_RI; mnv := MN_LI; ml := 2;
                                    elsif imm = 0 and rs1v /= 0 and rdv /= 0 then
                                        fmt := F_MV; mnv := MN_MV; ml := 2;
                                    else
                                        fmt := F_I;  mnv := MN_ADDI; ml := 4;
                                    end if;
                                elsif f3 = "111" then fmt := F_I; mnv := MN_ANDI; ml := 4;
                                elsif f3 = "110" then fmt := F_I; mnv := MN_ORI;  ml := 3;
                                elsif f3 = "010" then fmt := F_I; mnv := MN_SLTI; ml := 4;
                                elsif f3 = "100" then fmt := F_I; mnv := MN_XORI; ml := 4;
                                elsif f3 = "011" then fmt := F_I; mnv := MN_SLTIU; ml := 5;
                                elsif f3 = "001" and f7 = "0000000" then
                                    imm := to_integer(unsigned(w(24 downto 20)));   -- shamt
                                    fmt := F_I; mnv := MN_SLLI; ml := 4;
                                elsif f3 = "101" and f7 = "0000000" then
                                    imm := to_integer(unsigned(w(24 downto 20)));
                                    fmt := F_I; mnv := MN_SRLI; ml := 4;
                                elsif f3 = "101" and f7 = "0100000" then
                                    imm := to_integer(unsigned(w(24 downto 20)));
                                    fmt := F_I; mnv := MN_SRAI; ml := 4;
                                end if;
                            when "0000011" =>                       -- lw / lh / lb
                                imm := to_integer(signed(w(31 downto 20)));
                                if    f3 = "010" then fmt := F_LW; mnv := MN_LW; ml := 2;
                                elsif f3 = "001" then fmt := F_LW; mnv := MN_LH; ml := 2;
                                elsif f3 = "000" then fmt := F_LW; mnv := MN_LB; ml := 2;
                                elsif f3 = "100" then fmt := F_LW; mnv := MN_LBU; ml := 3;
                                elsif f3 = "101" then fmt := F_LW; mnv := MN_LHU; ml := 3;
                                end if;
                            when "0100011" =>                       -- sw / sh / sb
                                v12 := w(31 downto 25) & w(11 downto 7);
                                if f3 = "010" then
                                    imm := to_integer(signed(v12));
                                    fmt := F_SW; mnv := MN_SW; ml := 2;
                                elsif f3 = "001" then
                                    imm := to_integer(signed(v12));
                                    fmt := F_SW; mnv := MN_SH; ml := 2;
                                elsif f3 = "000" then
                                    imm := to_integer(signed(v12));
                                    fmt := F_SW; mnv := MN_SB; ml := 2;
                                end if;
                            when "1100011" =>                       -- beq / bne / blt
                                v13 := w(31) & w(7) & w(30 downto 25) & w(11 downto 8) & '0';
                                imm := to_integer(signed(v13));
                                if    f3 = "000" then fmt := F_B; mnv := MN_BEQ; ml := 3;
                                elsif f3 = "001" then fmt := F_B; mnv := MN_BNE; ml := 3;
                                elsif f3 = "100" then fmt := F_B; mnv := MN_BLT; ml := 3;
                                elsif f3 = "101" then fmt := F_B; mnv := MN_BGE; ml := 3;
                                elsif f3 = "110" then fmt := F_B; mnv := MN_BLTU; ml := 4;
                                elsif f3 = "111" then fmt := F_B; mnv := MN_BGEU; ml := 4;
                                end if;
                            when "1100111" =>                       -- jalr / ret
                                imm := to_integer(signed(w(31 downto 20)));
                                if f3 = "000" then
                                    if rdv = 0 and rs1v = 1 and imm = 0 then
                                        fmt := F_RET; mnv := MN_RET; ml := 3;
                                    else
                                        fmt := F_LW; mnv := MN_JALR; ml := 4;   -- rd, desl(rs1)
                                    end if;
                                end if;
                            when "0110111" =>                       -- lui
                                imm := to_integer(unsigned(w(31 downto 12)));
                                fmt := F_RI; mnv := MN_LUI; ml := 3;
                            when "0010111" =>                       -- auipc
                                imm := to_integer(unsigned(w(31 downto 12)));
                                fmt := F_RI; mnv := MN_AUIPC; ml := 5;
                            when "0001111" =>                       -- fence
                                if f3 = "000" then
                                    fmt := F_RET; mnv := MN_FENCE; ml := 5;
                                end if;
                            when "1110011" =>                       -- ecall / ebreak
                                if w = x"00000073" then
                                    fmt := F_RET; mnv := MN_ECALL; ml := 5;
                                elsif w = x"00100073" then
                                    fmt := F_RET; mnv := MN_EBREAK; ml := 6;
                                end if;
                            when "1101111" =>                       -- jal
                                v21 := w(31) & w(19 downto 12) & w(20) & w(30 downto 21) & '0';
                                imm := to_integer(signed(v21));
                                fmt := F_RI; mnv := MN_JAL; ml := 3;
                            when others =>
                                null;
                        end case;
                        if fmt = F_UNK then imm := 0; end if;

                        d_fmt  <= fmt;
                        d_mn   <= mnv;
                        d_mlen <= ml;
                        d_rd   <= rdv;
                        d_rs1  <= rs1v;
                        d_rs2  <= to_integer(unsigned(w(24 downto 20)));
                        d_neg  <= imm < 0;
                        d_abs  <= abs(imm);
                        d_dig  <= (others => 0);
                        -- memória e jalr: deslocamento em hexadecimal, como é
                        -- digitado; lui/auipc: imediato em hex com "0x"
                        d_hex  <= (op = "0000011" or op = "0100011" or op = "1100111" or
                                   op = "0110111" or op = "0010111") and fmt /= F_UNK;
                        d_0x   <= op = "0110111" or op = "0010111";
                        d_k    <= 6;
                        -- "AAAA>" : endereço (TEXT_BASE + 4*linha) + marcador do PC
                        a16   := to_unsigned(TEXT_BASE + d_idx * 4, 16);
                        lb(0) <= nib_hex(STD_LOGIC_VECTOR(a16(15 downto 12)));
                        lb(1) <= nib_hex(STD_LOGIC_VECTOR(a16(11 downto 8)));
                        lb(2) <= nib_hex(STD_LOGIC_VECTOR(a16(7 downto 4)));
                        lb(3) <= nib_hex(STD_LOGIC_VECTOR(a16(3 downto 0)));
                        if pan_pcv = '1' and d_idx = pan_pci then
                            lb(4) <= 62; lb_pc <= '1';      -- '>'
                        else
                            lb(4) <= 32; lb_pc <= '0';
                        end if;
                        d_wp  <= 5;
                        d_tk  <= 0;
                        d_sub <= 0;
                        d_lvl <= 0;
                        ds    <= D_BCD;

                    when D_BCD =>
                        -- |imediato| -> dígitos: hex direto dos bits (memória)
                        -- ou 7 dígitos decimais por subtrações (demais)
                        if d_hex then
                            u21 := to_unsigned(d_abs, 21);
                            d_dig(0) <= to_integer(u21(3 downto 0));
                            d_dig(1) <= to_integer(u21(7 downto 4));
                            d_dig(2) <= to_integer(u21(11 downto 8));
                            d_dig(3) <= to_integer(u21(15 downto 12));
                            d_dig(4) <= to_integer(u21(19 downto 16));
                            d_k      <= 0;
                            ds       <= D_EMIT;
                        elsif d_abs >= POW10(d_k) then
                            d_abs      <= d_abs - POW10(d_k);
                            d_dig(d_k) <= d_dig(d_k) + 1;
                        elsif d_k = 0 then
                            ds <= D_EMIT;
                        else
                            d_k <= d_k - 1;
                        end if;

                    when D_EMIT =>
                        -- um caractere por ciclo, conforme o formato
                        put := false; adv := false; ch := 32;
                        case d_fmt(d_tk) is
                            when K_END =>
                                ds <= D_IDLE;
                            when K_MNEM =>
                                -- níveis 0 e 1: pelo menos 4 colunas (d_mn já vem
                                -- completado com espaços); níveis 2 e 3: só as letras
                                put := true; ch := d_mn(d_sub);
                                if (d_lvl < 2 and d_sub >= 3 and d_sub >= d_mlen - 1) or
                                   (d_lvl >= 2 and d_sub = d_mlen - 1) then
                                    adv := true;
                                else
                                    d_sub <= d_sub + 1;
                                end if;
                            when K_SP    => put := true; ch := 32; adv := true;
                            when K_COMMA =>
                                put := true;
                                if d_sub = 0 then
                                    ch := 44;                       -- ','
                                    if d_lvl = 0 then d_sub <= 1; else adv := true; end if;
                                else
                                    ch := 32; adv := true;          -- ' ' depois da vírgula
                                end if;
                            when K_LPAR  => put := true; ch := 40; adv := true;
                            when K_RPAR  => put := true; ch := 41; adv := true;
                            when K_RD | K_RS1 | K_RS2 =>
                                if d_fmt(d_tk) = K_RD then rg := d_rd;
                                elsif d_fmt(d_tk) = K_RS1 then rg := d_rs1;
                                else rg := d_rs2; end if;
                                put := true;
                                if pan_abi = '1' then               -- nome da ABI
                                    ch := ABI_NAME(rg)(d_sub);
                                    if d_sub >= ABI_LEN(rg) - 1 then adv := true;
                                    else d_sub <= d_sub + 1; end if;
                                elsif d_sub = 0 then
                                    ch := 120;                      -- 'x'
                                    if rg >= 10 then d_sub <= 1; else d_sub <= 2; end if;
                                elsif d_sub = 1 then
                                    ch := 48 + reg_tens(rg); d_sub <= 2;
                                else
                                    ch := 48 + rg - 10 * reg_tens(rg); adv := true;
                                end if;
                            when K_IMM =>
                                if d_sub = 0 then
                                    if d_neg then put := true; ch := 45; end if;  -- '-'
                                    d_k <= 6; d_lead <= true;
                                    if d_0x then d_sub <= 1; else d_sub <= 3; end if;
                                elsif d_sub = 1 then
                                    put := true; ch := 48; d_sub <= 2;            -- '0'
                                elsif d_sub = 2 then
                                    put := true; ch := 120; d_sub <= 3;           -- 'x'
                                else
                                    if d_k = 0 or d_dig(d_k) /= 0 or not d_lead then
                                        put := true; d_lead <= false;
                                        if d_dig(d_k) < 10 then ch := 48 + d_dig(d_k);   -- 0-9
                                        else                    ch := 87 + d_dig(d_k);   -- a-f
                                        end if;
                                    end if;
                                    if d_k = 0 then adv := true; else d_k <= d_k - 1; end if;
                                end if;
                            when K_HEX =>
                                put := true; ch := hex_at(d_w, d_sub);
                                if d_sub = 7 then adv := true;
                                else d_sub <= d_sub + 1; end if;
                        end case;
                        if adv then
                            d_tk  <= d_tk + 1;
                            d_sub <= 0;
                        end if;
                        if put then
                            if d_wp <= PAN_W - 1 then           -- lb(26) = coluna 78
                                lb(d_wp) <= ch;
                                d_wp     <= d_wp + 1;
                            elsif d_lvl < 3 then
                                -- não coube: recomeça o texto num formato
                                -- mais compacto (o endereço fica; no nível 3
                                -- o texto ocupa também a coluna do marcador)
                                for i in 5 to 35 loop lb(i) <= 32; end loop;
                                d_lvl <= d_lvl + 1;
                                d_tk  <= 0;
                                d_sub <= 0;
                                if d_lvl = 2 then d_wp <= 4; else d_wp <= 5; end if;
                            end if;
                        end if;
                end case;
            end if;
        end if;
    end process;

    -- ─────────────────────────────────────────────────────────────────────────
    -- Painel "Programa" — 3A) caractere e cor do pixel hc+2
    -- ─────────────────────────────────────────────────────────────────────────
    process(pclk)
        variable x2  : UNSIGNED(9 downto 0);
        variable ncx : integer range 0 to 127;
        variable k   : integer range 0 to 127;
    begin
        if rising_edge(pclk) then
            x2  := hc + 2;
            ncx := to_integer(x2(9 downto 3));
            pa_bit <= to_integer(x2(2 downto 0));
            pa_on  <= '0';
            pa_bar <= '0';
            pa_inv <= '0';
            pa_cc  <= 32;
            pa_clr <= 0;
            if ncx >= PAN_COL0 and ncx <= 79 then
                pa_on <= '1';
                if ncx = PAN_COL0 then
                    pa_bar <= '1'; pa_clr <= 1;               -- divisor contínuo
                elsif pan_row = 0 then
                    -- título: "- Programa PPP-UUU de NNN -"
                    --   PPP-UUU = linhas visíveis (1 = primeira), NNN = total
                    pa_clr <= 1;
                    k := ncx - (PAN_COL0 + 1);
                    case k is
                        when 0  => pa_cc <= 45;       -- -
                        when 2  => pa_cc <= 80;       -- P
                        when 3  => pa_cc <= 114;      -- r
                        when 4  => pa_cc <= 111;      -- o
                        when 5  => pa_cc <= 103;      -- g
                        when 6  => pa_cc <= 114;      -- r
                        when 7  => pa_cc <= 97;       -- a
                        when 8  => pa_cc <= 109;      -- m
                        when 9  => pa_cc <= 97;       -- a
                        when 11 => pa_cc <= 48 + pan_dig(0);
                        when 12 => pa_cc <= 48 + pan_dig(1);
                        when 13 => pa_cc <= 48 + pan_dig(2);
                        when 14 => pa_cc <= 45;       -- -
                        when 15 => pa_cc <= 48 + pan_dig(3);
                        when 16 => pa_cc <= 48 + pan_dig(4);
                        when 17 => pa_cc <= 48 + pan_dig(5);
                        when 19 => pa_cc <= 100;      -- d
                        when 20 => pa_cc <= 101;      -- e
                        when 22 => pa_cc <= 48 + pan_dig(6);
                        when 23 => pa_cc <= 48 + pan_dig(7);
                        when 24 => pa_cc <= 48 + pan_dig(8);
                        when 26 => pa_cc <= 45;       -- -
                        when others => pa_cc <= 32;   -- inclui a margem (79)
                    end case;
                elsif pan_row = STK_T then
                    -- título da pilha: "- Pilha (sp=HHHHHHHH) -----"
                    --   sp em vermelho se estiver fora da área da pilha
                    pa_clr <= 1;
                    k := ncx - (PAN_COL0 + 1);
                    case k is
                        when 0  => pa_cc <= 45;       -- -
                        when 2  => pa_cc <= 80;       -- P
                        when 3  => pa_cc <= 105;      -- i
                        when 4  => pa_cc <= 108;      -- l
                        when 5  => pa_cc <= 104;      -- h
                        when 6  => pa_cc <= 97;       -- a
                        when 8  => pa_cc <= 40;       -- (
                        when 9  => pa_cc <= 115;      -- s
                        when 10 => pa_cc <= 112;      -- p
                        when 11 => pa_cc <= 61;       -- =
                        when 12 to 19 =>
                            pa_cc <= hex_at(stk_sp, k - 12);
                            -- cinza: sp = 0 (pilha não iniciada); amarelo: sp na
                            -- área da pilha; vermelho: sp fora dela
                            if stk_sp = x"00000000" then pa_clr <= 4;
                            elsif stk_bad = '1' then pa_clr <= 5;
                            else pa_clr <= 2; end if;
                        when 20 => pa_cc <= 41;       -- )
                        when 22 to 26 => pa_cc <= 45; -- -----
                        when others => pa_cc <= 32;
                    end case;
                elsif pan_row > STK_T and pan_row <= STK_T + STK_N and ncx <= PAN_LAST then
                    -- palavra da pilha: endereço branco, valor verde (em uso,
                    -- endereço >= sp) ou cinza (livre), seta amarela; o último
                    -- store fica em vídeo inverso amarelo, como na memória
                    k := ncx - (PAN_COL0 + 1);
                    pa_cc <= lb(k);
                    if k <= 6 then
                        pa_clr <= 0;
                    elsif k <= 14 then
                        if lb_hl = '1' then
                            pa_clr <= 2; pa_inv <= '1';
                        elsif lb_alloc = '1' then
                            pa_clr <= 3;
                        else
                            pa_clr <= 4;
                        end if;
                    else
                        pa_clr <= 2;                          -- "<- sp"
                    end if;
                elsif pan_row <= PAN_N and ncx <= PAN_LAST then
                    k := ncx - (PAN_COL0 + 1);
                    pa_cc  <= lb(k);
                    pa_inv <= lb_sel;
                    if lb_sel = '1' then
                        -- cursor: barra inteira numa cor só (texto vazado)
                        if lb_pc = '1' then pa_clr <= 2; else pa_clr <= 0; end if;
                    elsif k <= 3 then
                        pa_clr <= 1;                          -- endereço
                    elsif lb_pc = '1' then
                        pa_clr <= 2;                          -- linha do PC
                    else
                        pa_clr <= 0;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- ─────────────────────────────────────────────────────────────────────────
    -- Painel "Programa" — 3B) bit do glifo do pixel hc+1
    --   Segunda cópia da ROM de fonte, só para o painel: o caminho do pixel
    --   principal não passa por ela.
    -- ─────────────────────────────────────────────────────────────────────────
    process(pclk)
        variable prow : STD_LOGIC_VECTOR(7 downto 0);
    begin
        if rising_edge(pclk) then
            pan_on  <= pa_on;
            pan_clr <= pa_clr;
            pan_pix <= '0';
            if pa_bar = '1' then
                if pa_bit = 3 or pa_bit = 4 then pan_pix <= '1'; end if;
            elsif pan_line < 8 then
                prow    := FONT(pa_cc * 8 + pan_line);
                pan_pix <= prow(7 - pa_bit) xor pa_inv;   -- inverso no cursor
            end if;
        end if;
    end process;

    -- ─────────────────────────────────────────────────────────────────────────
    -- Processo principal: geração de pixels (registrado em pixel_clk)
    -- ─────────────────────────────────────────────────────────────────────────
    process(pclk, reset)
        variable cx, cy, fr_i   : integer;
        variable cc             : integer;
        variable fr, fg, fb     : STD_LOGIC_VECTOR(7 downto 0);
        variable col_n, col_off : integer;
        variable reg_n, mem_n   : integer;
        variable rv             : STD_LOGIC_VECTOR(31 downto 0);
        variable nib            : STD_LOGIC_VECTOR(3 downto 0);
        variable prow           : STD_LOGIC_VECTOR(7 downto 0);
        variable pixel          : STD_LOGIC;
        variable inv            : boolean;     -- destaque: vídeo inverso
    begin
        if reset = '1' then
            hs_r <= '1'; vs_r <= '1'; bl_r <= '0';
            r_r  <= (others => '0');
            g_r  <= (others => '0');
            b_r  <= (others => '0');
        elsif rising_edge(pclk) then

            -- Posição no grid de caracteres
            -- hc(9:3) = hc/8 → coluna de char 0-79
            -- l_row          → linha de char 0-39 (12 px/linha = 8 glifo + 4 vazio;
            --                  até a entrega 49 eram 16 px e 30 linhas)
            -- l_line 0-7     → linha dentro da fonte; 8-11 = vazio
            cx   := to_integer(hc(9 downto 3));
            cy   := l_row;
            fr_i := l_line mod 8;

            -- Padrão: espaço, cor branca (8-bit por canal)
            cc := 32;
            fr := WH_R; fg := WH_G; fb := WH_B;
            inv := false;

            -- ═════════════════════════════════════════════════════════════════
            --  Layout por linha (cy)
            -- ═════════════════════════════════════════════════════════════════

            if cy = 0 then
                -- ── Linha 0: Cabeçalho compacto (colunas 2-40) ─────────────
                --    "RISC-V Monociclo  DE2-115  Visualizador"
                fr := YL_R; fg := YL_G; fb := YL_B;
                case cx is
                    when 2  => cc := 82 ; -- R
                    when 3  => cc := 73 ; -- I
                    when 4  => cc := 83 ; -- S
                    when 5  => cc := 67 ; -- C
                    when 6  => cc := 45 ; -- -
                    when 7  => cc := 86 ; -- V
                    when 9  => cc := 77 ; -- M
                    when 10 => cc := 111; -- o
                    when 11 => cc := 110; -- n
                    when 12 => cc := 111; -- o
                    when 13 => cc := 99 ; -- c
                    when 14 => cc := 105; -- i
                    when 15 => cc := 99 ; -- c
                    when 16 => cc := 108; -- l
                    when 17 => cc := 111; -- o
                    when 20 => cc := 68 ; -- D
                    when 21 => cc := 69 ; -- E
                    when 22 => cc := 50 ; -- 2
                    when 23 => cc := 45 ; -- -
                    when 24 => cc := 49 ; -- 1
                    when 25 => cc := 49 ; -- 1
                    when 26 => cc := 53 ; -- 5
                    when 29 => cc := 86 ; -- V
                    when 30 => cc := 105; -- i
                    when 31 => cc := 115; -- s
                    when 32 => cc := 117; -- u
                    when 33 => cc := 97 ; -- a
                    when 34 => cc := 108; -- l
                    when 35 => cc := 105; -- i
                    when 36 => cc := 122; -- z
                    when 37 => cc := 97 ; -- a
                    when 38 => cc := 100; -- d
                    when 39 => cc := 111; -- o
                    when 40 => cc := 114; -- r
                    when others => cc := 32;
                end case;

            elsif cy = 1 then
                -- ── Linha 1: "PC:XXXXXXXX  Instr:XXXXXXXX" (colunas 2-28) ──
                if cx >= 5 and cx <= 12 then
                    fr := CY_R; fg := CY_G; fb := CY_B;
                    case cx is
                        when 5   => nib := proc_pc(31 downto 28);
                        when 6   => nib := proc_pc(27 downto 24);
                        when 7   => nib := proc_pc(23 downto 20);
                        when 8   => nib := proc_pc(19 downto 16);
                        when 9   => nib := proc_pc(15 downto 12);
                        when 10  => nib := proc_pc(11 downto 8);
                        when 11  => nib := proc_pc(7 downto 4);
                        when 12  => nib := proc_pc(3 downto 0);
                        when others => nib := "0000";
                    end case;
                    cc := nib_hex(nib);
                elsif cx >= 21 and cx <= 28 then
                    fr := CY_R; fg := CY_G; fb := CY_B;
                    case cx is
                        when 21  => nib := proc_instr(31 downto 28);
                        when 22  => nib := proc_instr(27 downto 24);
                        when 23  => nib := proc_instr(23 downto 20);
                        when 24  => nib := proc_instr(19 downto 16);
                        when 25  => nib := proc_instr(15 downto 12);
                        when 26  => nib := proc_instr(11 downto 8);
                        when 27  => nib := proc_instr(7 downto 4);
                        when 28  => nib := proc_instr(3 downto 0);
                        when others => nib := "0000";
                    end case;
                    cc := nib_hex(nib);
                else
                    case cx is
                    when 2   => cc := 80 ;  -- P
                    when 3   => cc := 67 ;  -- C
                    when 4   => cc := 58 ;  -- :
                    when 15  => cc := 73 ;  -- I
                    when 16  => cc := 110;  -- n
                    when 17  => cc := 115;  -- s
                    when 18  => cc := 116;  -- t
                    when 19  => cc := 114;  -- r
                    when 20  => cc := 58 ;  -- :
                        when others => cc := 32;
                    end case;
                end if;

            elsif cy = 2 then
                -- ── Linha 2: "[RODANDO]  Passos:NNNNNNNN" (colunas 2-27) ───
                if cx >= 2 and cx <= 10 then
                    if speed_sel(1) = '0' then
                        fr := YL_R; fg := YL_G; fb := YL_B;
                        case cx is                    -- "[PAUSADO]" (CPU desligada)
                            when 2   => cc := 91 ;  -- [
                            when 3   => cc := 80 ;  -- P
                            when 4   => cc := 65 ;  -- A
                            when 5   => cc := 85 ;  -- U
                            when 6   => cc := 83 ;  -- S
                            when 7   => cc := 65 ;  -- A
                            when 8   => cc := 68 ;  -- D
                            when 9   => cc := 79 ;  -- O
                            when 10  => cc := 93 ;  -- ]
                            when others => cc := 32;
                        end case;
                    elsif in_wait = '1' then
                        fr := CY_R; fg := CY_G; fb := CY_B;
                        case cx is                    -- "[ENTRADA]" (ecall a7=5)
                            when 2   => cc := 91 ;  -- [
                            when 3   => cc := 69 ;  -- E
                            when 4   => cc := 78 ;  -- N
                            when 5   => cc := 84 ;  -- T
                            when 6   => cc := 82 ;  -- R
                            when 7   => cc := 65 ;  -- A
                            when 8   => cc := 68 ;  -- D
                            when 9   => cc := 65 ;  -- A
                            when 10  => cc := 93 ;  -- ]
                            when others => cc := 32;
                        end case;
                    elsif proc_halt = '1' then
                        fr := RD_R; fg := RD_G; fb := RD_B;
                        case cx is                    -- "[PARADO] "
                            when 2   => cc := 91 ;  -- [
                            when 3   => cc := 80 ;  -- P
                            when 4   => cc := 65 ;  -- A
                            when 5   => cc := 82 ;  -- R
                            when 6   => cc := 65 ;  -- A
                            when 7   => cc := 68 ;  -- D
                            when 8   => cc := 79 ;  -- O
                            when 9   => cc := 93 ;  -- ]
                            when others => cc := 32;
                        end case;
                    else
                        fr := GN_R; fg := GN_G; fb := GN_B;
                        case cx is                    -- "[RODANDO]"
                            when 2   => cc := 91 ;  -- [
                            when 3   => cc := 82 ;  -- R
                            when 4   => cc := 79 ;  -- O
                            when 5   => cc := 68 ;  -- D
                            when 6   => cc := 65 ;  -- A
                            when 7   => cc := 78 ;  -- N
                            when 8   => cc := 68 ;  -- D
                            when 9   => cc := 79 ;  -- O
                            when 10  => cc := 93 ;  -- ]
                            when others => cc := 32;
                        end case;
                    end if;
                elsif cx >= 20 and cx <= 27 then
                    fr := CY_R; fg := CY_G; fb := CY_B;
                    case cx is
                        when 20  => nib := steps_bcd(31 downto 28);
                        when 21  => nib := steps_bcd(27 downto 24);
                        when 22  => nib := steps_bcd(23 downto 20);
                        when 23  => nib := steps_bcd(19 downto 16);
                        when 24  => nib := steps_bcd(15 downto 12);
                        when 25  => nib := steps_bcd(11 downto 8);
                        when 26  => nib := steps_bcd(7 downto 4);
                        when 27  => nib := steps_bcd(3 downto 0);
                        when others => nib := "0000";
                    end case;
                    cc := nib_hex(nib);               -- dígito BCD 0-9
                else
                    case cx is
                    when 13  => cc := 80 ;  -- P
                    when 14  => cc := 97 ;  -- a
                    when 15  => cc := 115;  -- s
                    when 16  => cc := 115;  -- s
                    when 17  => cc := 111;  -- o
                    when 18  => cc := 115;  -- s
                    when 19  => cc := 58 ;  -- :
                        when others => cc := 32;
                    end case;
                end if;

            elsif cy = 4 then
                -- ── Linha 4: Separador Registradores ─────────────────────
                fr := CY_R; fg := CY_G; fb := CY_B;
                case cx is
                    when 2   => cc := 45 ;  -- -
                    when 3   => cc := 45 ;  -- -
                    when 5   => cc := 82 ;  -- R
                    when 6   => cc := 101;  -- e
                    when 7   => cc := 103;  -- g
                    when 8   => cc := 105;  -- i
                    when 9   => cc := 115;  -- s
                    when 10  => cc := 116;  -- t
                    when 11  => cc := 114;  -- r
                    when 12  => cc := 97 ;  -- a
                    when 13  => cc := 100;  -- d
                    when 14  => cc := 111;  -- o
                    when 15  => cc := 114;  -- r
                    when 16  => cc := 101;  -- e
                    when 17  => cc := 115;  -- s
                    -- base: "(dec)" ou "(hex)" (SW[3])
                    when 19  => cc := 40;   -- (
                    when 20  =>
                        if reg_hex = '1' then cc := 104; else cc := 100; end if;  -- h / d
                    when 21  => cc := 101;  -- e
                    when 22  =>
                        if reg_hex = '1' then cc := 120; else cc := 99; end if;   -- x / c
                    when 23  => cc := 41;   -- )
                    when 25 to 79 => cc := 45;
                    when others => cc := 32;
                end case;

            elsif cy >= 5 and cy <= 15 then
                -- ── Linhas 5-15: 32 registradores em 3 colunas de 11 ─────
                --   coluna 1: x00-x10, coluna 2: x11-x21, coluna 3: x22-x31
                --   Valor: 11 caracteres prontos em rt (decimal com sinal
                --   alinhado à direita, ou 8 dígitos hex), montados pelo
                --   conversor no vazio da linha anterior.
                --   Cada coluna: rótulo de 4 caracteres alinhado à direita
                --   (" x05" ou, com SW[4]=1, "  t0", "zero", " s11"), '=' e o
                --   valor; 16 caracteres por coluna, nas colunas 2, 18 e 34.
                --   Nada fica na coluna 1: monitores analógicos costumam cortar
                --   os primeiros pixels, e o "z" de "zero" sumia (entrega 47).
                --   Entre duas colunas sobra pelo menos um espaço, porque só
                --   a primeira coluna tem rótulo de 4 letras ("zero").
                if cx >= 2 and cx <= 49 then
                    col_n   := (cx - 2) / 16;
                    col_off := (cx - 2) mod 16;
                    reg_n   := col_n * 11 + (cy - 5);
                    fr := WH_R; fg := WH_G; fb := WH_B;
                    if reg_n > 31 or col_off > 15 then
                        cc := 32;
                    else
                        case col_off is
                            when 0 to 3 =>
                                cc := 32;
                                if abi_names = '1' then
                                    if col_off >= 4 - ABI_LEN(reg_n) then
                                        cc := ABI_NAME(reg_n)(col_off - (4 - ABI_LEN(reg_n)));
                                    end if;
                                elsif col_off = 1 then
                                    cc := 120;                      -- 'x'
                                elsif col_off = 2 then
                                    if    reg_n < 10 then cc := 48; -- x00..x09
                                    elsif reg_n < 20 then cc := 49;
                                    elsif reg_n < 30 then cc := 50;
                                    else                  cc := 51;
                                    end if;
                                elsif col_off = 3 then
                                    cc := 48 + (reg_n mod 10);
                                end if;
                            when 4 => cc := 61;                     -- '='
                            when others =>
                                cc := rt(col_n)(col_off - 5);
                                fr := GN_R; fg := GN_G; fb := GN_B;
                                -- destaque: último registrador escrito
                                if hl_reg(5) = '1' and
                                   reg_n = to_integer(unsigned(hl_reg(4 downto 0))) and
                                   (reg_hex = '0' or col_off <= 12) then
                                    inv := true;
                                    fr := YL_R; fg := YL_G; fb := YL_B;
                                end if;
                        end case;
                    end if;
                else
                    cc := 32; fr := WH_R; fg := WH_G; fb := WH_B;
                end if;

            elsif cy = 17 then
                -- ── Linha 17: Separador Memória ───────────────────────────
                fr := CY_R; fg := CY_G; fb := CY_B;
                case cx is
                    when 2   => cc := 45 ;  -- -
                    when 3   => cc := 45 ;  -- -
                    when 5   => cc := 77 ;  -- M
                    when 6   => cc := 101;  -- e
                    when 7   => cc := 109;  -- m
                    when 8   => cc := 111;  -- o
                    when 9   => cc := 114;  -- r
                    when 10  => cc := 105;  -- i
                    when 11  => cc := 97 ;  -- a
                    when 13  => cc := 100;  -- d
                    when 14  => cc := 101;  -- e
                    when 16  => cc := 68 ;  -- D
                    when 17  => cc := 97 ;  -- a
                    when 18  => cc := 100;  -- d
                    when 19  => cc := 111;  -- o
                    when 20  => cc := 115;  -- s
                    when 22  => cc := 40;   -- (
                    when 23  => cc := 104;  -- h
                    when 24  => cc := 101;  -- e
                    when 25  => cc := 120;  -- x
                    when 26  => cc := 41;   -- )
                    when 28 to 79 => cc := 45;
                    when others => cc := 32;
                end case;

            elsif cy >= 18 and cy <= 23 then
                -- ── Linhas 18-23: 16 palavras em 3 colunas ───────────────
                -- Formato por slot: "[HHHH]=HHHHHHHH", nas colunas 2, 18 e 34
                -- (as mesmas dos registradores), em ordem de linha. O endereço
                -- tem 4 dígitos, como os do programa: [0030] é o dado 0x30,
                -- 3030 é uma instrução (entrega 48; antes era "[30]").
                if cx >= 2 and cx <= 49 then
                    col_n   := (cx - 2) / 16;
                    col_off := (cx - 2) mod 16;
                    mem_n   := (cy - 18) * 3 + col_n;
                    rv      := get_mem(dmem, mem_n);
                    fr := WH_R; fg := WH_G; fb := WH_B;
                    if mem_n > 15 then
                        cc := 32;
                    else
                        case col_off is
                            when 0 => cc := 91;                     -- '['
                            when 1 | 2 => cc := 48;                 -- "00"
                            when 3 => nib := std_logic_vector(to_unsigned(mem_n / 4, 4));
                                      cc  := nib_hex(nib);
                            when 4 => nib := std_logic_vector(to_unsigned((mem_n mod 4) * 4, 4));
                                      cc  := nib_hex(nib);
                            when 5 => cc := 93;                     -- ']'
                            when 6 => cc := 61;                     -- '='
                            when 7 to 14 =>
                                case col_off is
                                    when 7      => nib := rv(31 downto 28);
                                    when 8      => nib := rv(27 downto 24);
                                    when 9      => nib := rv(23 downto 20);
                                    when 10     => nib := rv(19 downto 16);
                                    when 11     => nib := rv(15 downto 12);
                                    when 12     => nib := rv(11 downto 8);
                                    when 13     => nib := rv(7  downto 4);
                                    when others => nib := rv(3  downto 0);
                                end case;
                                cc := nib_hex(nib);
                                fr := GN_R; fg := GN_G; fb := GN_B;
                                -- destaque: última palavra escrita
                                if hl_mem(5) = '1' and
                                   mem_n = to_integer(unsigned(hl_mem(4 downto 0))) then
                                    inv := true;
                                    fr := YL_R; fg := YL_G; fb := YL_B;
                                end if;
                            when others => cc := 32;
                        end case;
                    end if;
                else
                    cc := 32; fr := WH_R; fg := WH_G; fb := WH_B;
                end if;

            elsif cy = 25 then
                -- ── Linha 25: separador da saída (ecall) ──────────────
                fr := CY_R; fg := CY_G; fb := CY_B;
                case cx is
                    when 2   => cc := 45 ;  -- -
                    when 3   => cc := 45 ;  -- -
                    when 5   => cc := 83 ;  -- S
                    when 6   => cc := 97 ;  -- a
                    when 7   => cc := 105;  -- i
                    when 8   => cc := 100;  -- d
                    when 9   => cc := 97 ;  -- a
                    when 11  => cc := 40 ;  -- (
                    when 12  => cc := 99 ;  -- c
                    when 13  => cc := 111;  -- o
                    when 14  => cc := 110;  -- n
                    when 15  => cc := 115;  -- s
                    when 16  => cc := 111;  -- o
                    when 17  => cc := 108;  -- l
                    when 18  => cc := 101;  -- e
                    when 19  => cc := 41 ;  -- )
                    when 21 to 79 => cc := 45;
                    when others => cc := 32;
                end case;

            elsif cy >= 26 and cy <= 31 then
                -- ── Linhas 26-31: o que os ecall imprimiram ──
                if cx >= 2 and cx <= 49 then
                    cc := get_con(con_flat, (cy - 26) * 48 + (cx - 2));
                    if cc < 32 or cc > 126 then cc := 32; end if;
                else
                    cc := 32;
                end if;
                fr := WH_R; fg := WH_G; fb := WH_B;

            elsif cy = 33 then
                -- ── Linha 33: Separador Status ────────────────────────────
                fr := CY_R; fg := CY_G; fb := CY_B;
                case cx is
                    when 2   => cc := 45 ;  -- -
                    when 3   => cc := 45 ;  -- -
                    when 5   => cc := 83 ;  -- S
                    when 6   => cc := 116;  -- t
                    when 7   => cc := 97 ;  -- a
                    when 8   => cc := 116;  -- t
                    when 9   => cc := 117;  -- u
                    when 10  => cc := 115;  -- s
                    when 12 to 79 => cc := 45;
                    when others => cc := 32;
                end case;

            elsif cy = 34 then
                -- ── Linha 34: "Inst:NNN  RUN    CPU:ON  TECL  Err:0" ──────
                -- speed_sel[0] = SW[0]: RUN(1)/STEP(0); TURBO com SW[5]
                -- speed_sel[1] = SW[1]: CPU ON(1)/OF(0)
                -- diag_mode    = SW[2]: DEMO(1)/TECL(0)
                fr := WH_R; fg := WH_G; fb := WH_B;
                case cx is
                    when 2   => cc := 73 ;  -- I
                    when 3   => cc := 110;  -- n
                    when 4   => cc := 115;  -- s
                    when 5   => cc := 116;  -- t
                    when 6   => cc := 58 ;  -- :
                    when 7  => cc := 48 + wa_hund;
                    when 8  => cc := 48 + wa_tens;
                    when 9  => cc := 48 + wa_units;
                    -- "RUN" / "STEP" / "TURBO" (cx 12-16)
                    when 12 | 13 | 14 | 15 | 16 =>
                        if speed_sel(0) = '1' and turbo = '1' then
                            fr := RD_R; fg := RD_G; fb := RD_B;   -- TURBO em vermelho
                            case cx is
                                when 12     => cc := 84;  -- T
                                when 13     => cc := 85;  -- U
                                when 14     => cc := 82;  -- R
                                when 15     => cc := 66;  -- B
                                when others => cc := 79;  -- O
                            end case;
                        elsif speed_sel(0) = '1' then
                            fr := GN_R; fg := GN_G; fb := GN_B;
                            case cx is
                                when 12     => cc := 82;  -- R
                                when 13     => cc := 85;  -- U
                                when 14     => cc := 78;  -- N
                                when others => cc := 32;
                            end case;
                        else
                            fr := YL_R; fg := YL_G; fb := YL_B;
                            case cx is
                                when 12     => cc := 83;  -- S
                                when 13     => cc := 84;  -- T
                                when 14     => cc := 69;  -- E
                                when 15     => cc := 80;  -- P
                                when others => cc := 32;
                            end case;
                        end if;
                    when 18  => cc := 67 ;  -- C
                    when 19  => cc := 80 ;  -- P
                    when 20  => cc := 85 ;  -- U
                    when 21  => cc := 58 ;  -- :
                    when 22 =>
                        cc := 79;  -- O
                        if speed_sel(1) = '1' then fr := GN_R; fg := GN_G; fb := GN_B;
                                              else fr := RD_R; fg := RD_G; fb := RD_B; end if;
                    when 23 =>
                        if speed_sel(1) = '1' then cc := 78;  -- N (ON)
                                              else cc := 70;  -- F (OFF)
                        end if;
                        if speed_sel(1) = '1' then fr := GN_R; fg := GN_G; fb := GN_B;
                                              else fr := RD_R; fg := RD_G; fb := RD_B; end if;
                    when 24 =>
                        if speed_sel(1) = '1' then cc := 32;  -- "ON "
                                              else cc := 70;  -- segundo F de "OFF"
                        end if;
                        fr := RD_R; fg := RD_G; fb := RD_B;
                    -- "DEMO" ou "TECL" (cx 26-29)
                    when 26 to 29 =>
                        if diag_mode = '1' then
                            fr := YL_R; fg := YL_G; fb := YL_B;
                            case cx is
                                when 26 => cc := 68;  -- D
                                when 27 => cc := 69;  -- E
                                when 28 => cc := 77;  -- M
                                when others => cc := 79;  -- O
                            end case;
                        else
                            case cx is
                                when 26 => cc := 84;  -- T
                                when 27 => cc := 69;  -- E
                                when 28 => cc := 67;  -- C
                                when others => cc := 76;  -- L
                            end case;
                        end if;
                    when 32  => cc := 69 ;  -- E
                    when 33  => cc := 114;  -- r
                    when 34  => cc := 114;  -- r
                    when 35  => cc := 58 ;  -- :
                    when 36 =>
                        if parse_err = '1' then cc := 49; fr := RD_R; fg := RD_G; fb := RD_B;
                                           else cc := 48; end if;
                    when others => cc := 32;
                end case;

            elsif cy = 35 then
                -- ── Linha 35: demo escolhida em SW[9:6] ────────────────────
                --   "Demo 09: D9 Fatorial" — amarela com o modo demo ligado
                --   (SW[2]=1, a demo está carregada), branca desligado.
                if diag_mode = '1' then
                    fr := YL_R; fg := YL_G; fb := YL_B;
                else
                    fr := WH_R; fg := WH_G; fb := WH_B;
                end if;
                case cx is
                    when 2   => cc := 68 ;  -- D
                    when 3   => cc := 101;  -- e
                    when 4   => cc := 109;  -- m
                    when 5   => cc := 111;  -- o
                    when 7  =>
                        cc := 48 + to_integer(unsigned(demo_sel)) / 10;
                    when 8  =>
                        cc := 48 + to_integer(unsigned(demo_sel)) mod 10;
                    when 9  => cc := 58;  -- :
                    when 11 to 25 =>
                        cc := DEMO_NAMES(to_integer(unsigned(demo_sel)))(cx - 11);
                    when others => cc := 32;
                end case;

            elsif cy = 36 then
                -- ── Linha 36: Separador — Entrada de Teclado ─────────────
                fr := CY_R; fg := CY_G; fb := CY_B;
                case cx is
                    when 2   => cc := 45 ;  -- -
                    when 3   => cc := 45 ;  -- -
                    when 5   => cc := 69 ;  -- E
                    when 6   => cc := 110;  -- n
                    when 7   => cc := 116;  -- t
                    when 8   => cc := 114;  -- r
                    when 9   => cc := 97 ;  -- a
                    when 10  => cc := 100;  -- d
                    when 11  => cc := 97 ;  -- a
                    when 13  => cc := 100;  -- d
                    when 14  => cc := 101;  -- e
                    when 16  => cc := 84 ;  -- T
                    when 17  => cc := 101;  -- e
                    when 18  => cc := 99 ;  -- c
                    when 19  => cc := 108;  -- l
                    when 20  => cc := 97 ;  -- a
                    when 21  => cc := 100;  -- d
                    when 22  => cc := 111;  -- o
                    when 24 to 79 => cc := 45;
                    when others => cc := 32;
                end case;

            elsif cy = 37 then
                -- ── Linha 37: eco da linha sendo digitada (20 chars) ───────
                -- "  > XXXXXXXXXXXXXXXXXXXX_" — o cursor fica na coluna
                -- 4 + kbd_len, logo depois do último caractere digitado
                -- (coluna 24 quando o buffer de 20 está cheio).
                fr := WH_R; fg := WH_G; fb := WH_B;
                if cx = 2 then
                    if in_wait = '1' then
                        cc := 63;   -- '?': o ecall a7=5 espera um número
                    else
                        cc := 62;   -- '>'
                    end if;
                    fr := CY_R; fg := CY_G; fb := CY_B;
                elsif cx = cur_col and cursor_on = '1' then
                    cc := 95;   -- '_' piscando
                    fr := CY_R; fg := CY_G; fb := CY_B;
                elsif cx >= 4 and cx <= 23 then
                    case cx is
                        when 4  => cc := to_integer(unsigned(kbd_line(159 downto 152)));
                        when 5  => cc := to_integer(unsigned(kbd_line(151 downto 144)));
                        when 6  => cc := to_integer(unsigned(kbd_line(143 downto 136)));
                        when 7  => cc := to_integer(unsigned(kbd_line(135 downto 128)));
                        when 8  => cc := to_integer(unsigned(kbd_line(127 downto 120)));
                        when 9  => cc := to_integer(unsigned(kbd_line(119 downto 112)));
                        when 10 => cc := to_integer(unsigned(kbd_line(111 downto 104)));
                        when 11 => cc := to_integer(unsigned(kbd_line(103 downto  96)));
                        when 12 => cc := to_integer(unsigned(kbd_line( 95 downto  88)));
                        when 13 => cc := to_integer(unsigned(kbd_line( 87 downto  80)));
                        when 14 => cc := to_integer(unsigned(kbd_line( 79 downto  72)));
                        when 15 => cc := to_integer(unsigned(kbd_line( 71 downto  64)));
                        when 16 => cc := to_integer(unsigned(kbd_line( 63 downto  56)));
                        when 17 => cc := to_integer(unsigned(kbd_line( 55 downto  48)));
                        when 18 => cc := to_integer(unsigned(kbd_line( 47 downto  40)));
                        when 19 => cc := to_integer(unsigned(kbd_line( 39 downto  32)));
                        when 20 => cc := to_integer(unsigned(kbd_line( 31 downto  24)));
                        when 21 => cc := to_integer(unsigned(kbd_line( 23 downto  16)));
                        when 22 => cc := to_integer(unsigned(kbd_line( 15 downto   8)));
                        when 23 => cc := to_integer(unsigned(kbd_line(  7 downto   0)));
                        when others => cc := 32;
                    end case;
                    if cc < 32 or cc > 126 then cc := 32; end if;
                else
                    cc := 32;
                end if;
            end if;

            -- ─────────────────────────────────────────────────────────────
            -- Consulta à ROM de fonte + saída de cor
            -- ─────────────────────────────────────────────────────────────
            if l_line < 8 then
                -- Dentro do glifo (linhas 0-7 da célula de 12 px)
                prow  := FONT(cc * 8 + fr_i);
                pixel := prow(7 - to_integer(hc(2 downto 0)));
                if inv then pixel := not pixel; end if;   -- barra amarela
            else
                -- Vazio inferior (linhas 8-11): fundo
                pixel := '0';
            end if;

            -- Painel "Programa": pixel e cor já prontos (pipeline próprio)
            if pan_on = '1' then
                pixel := pan_pix;
                case pan_clr is
                    when 1      => fr := CY_R; fg := CY_G; fb := CY_B;
                    when 2      => fr := YL_R; fg := YL_G; fb := YL_B;
                    when 3      => fr := GN_R; fg := GN_G; fb := GN_B;
                    when 4      => fr := GY_R; fg := GY_G; fb := GY_B;
                    when 5      => fr := RD_R; fg := RD_G; fb := RD_B;
                    when others => fr := WH_R; fg := WH_G; fb := WH_B;
                end case;
            end if;

            -- Sincronismo registrado (alinhado com 1 ciclo de latência dos dados)
            hs_r <= hs_s;
            vs_r <= vs_s;
            bl_r <= vid_on;

            if vid_on = '1' then
                if pixel = '1' then
                    r_r <= fr; g_r <= fg; b_r <= fb;
                else
                    r_r <= BG_R; g_r <= BG_G; b_r <= BG_B;
                end if;
            else
                r_r <= (others => '0');
                g_r <= (others => '0');
                b_r <= (others => '0');
            end if;

        end if;
    end process;

    -- Saídas VGA
    VGA_CLK     <= pclk;
    VGA_HS      <= hs_r;
    VGA_VS      <= vs_r;
    VGA_BLANK_N <= bl_r;
    VGA_SYNC_N  <= '0';
    VGA_R       <= r_r;
    VGA_G       <= g_r;
    VGA_B       <= b_r;

end architecture;