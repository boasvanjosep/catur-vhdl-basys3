-- vga_render.vhd : Renderer VGA 800x600 @ 60 Hz dengan tata letak user-friendly:
--   - Papan 512x512 (petak 64x64, sprite 20x20 diperbesar 3x) + label koordinat A-H dan 1-8.
--   - Panel kanan 4 kartu: Giliran/Mode/Status, Jam Catur, Bidak Dimakan + selisih poin,
--     dan Status Mouse + Legenda Kontrol Board dinamis.
--   - Popup tengah: Menu Pengaturan (panah < > hanya pada baris aktif), Promosi 4 ikon,
--     Konfirmasi [ YA ] / [ TIDAK ], dan Notifikasi Menang/Kalah/Seri + [MAIN LAGI] / [CEK PAPAN].
--   - Pointer panah mouse 12x12 di lapisan teratas saat mouse tersambung.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.chess_pkg.all;

entity vga_render is
    port (
        pix_clk, pix_ce : in std_logic;
        x, y        : in unsigned(10 downto 0);
        hs_in, vs_in: in std_logic;
        -- keadaan permainan
        board       : in board_t;
        turn        : in std_logic;
        status      : in std_logic_vector(1 downto 0);
        king_sq     : in std_logic_vector(5 downto 0);
        cursor      : in std_logic_vector(5 downto 0);
        sel_valid   : in std_logic;
        sel_sq      : in std_logic_vector(5 downto 0);
        dest_mask   : in std_logic_vector(63 downto 0);
        hint_en     : in std_logic;
        last_valid  : in std_logic;
        last_from, last_to : in std_logic_vector(5 downto 0);
        theme       : in std_logic_vector(1 downto 0);
        w_time, b_time : in std_logic_vector(15 downto 0);
        unlimited   : in std_logic;
        paused      : in std_logic;
        timeout     : in std_logic_vector(1 downto 0);
        result      : in std_logic_vector(1 downto 0);
        prompt      : in std_logic_vector(1 downto 0);
        promo_active: in std_logic;
        promo_choice: in std_logic_vector(1 downto 0);
        show_cursor : in std_logic;
        popup_hide  : in std_logic;
        -- lawan komputer
        cpu_en, cpu_think, cpu_lvl : in std_logic;
        -- replay
        replay      : in std_logic;
        r_auto      : in std_logic;
        rk_bcd, rc_bcd : in std_logic_vector(11 downto 0);
        -- animasi bidak melayang
        an_on       : in std_logic;
        an_x, an_y, an_xe, an_ye : in unsigned(10 downto 0);
        an_piece    : in std_logic_vector(3 downto 0);
        an_dst      : in std_logic_vector(5 downto 0);
        -- menu & mouse
        menu_open   : in std_logic;
        menu_idx    : in unsigned(3 downto 0);
        preset      : in std_logic_vector(2 downto 0);
        anim_en     : in std_logic;
        seg_cursor  : in std_logic;
        mouse_x, mouse_y : in unsigned(10 downto 0);
        mouse_en    : in std_logic;
        -- bidak dimakan
        cap_by_w, cap_by_b : in std_logic_vector(44 downto 0);
        w_adv, b_adv       : in unsigned(5 downto 0);
        -- keluaran VGA
        vga_r, vga_g, vga_b : out std_logic_vector(3 downto 0);
        hsync, vsync        : out std_logic
    );
end vga_render;

architecture rtl of vga_render is
    subtype slv8   is std_logic_vector(7 downto 0);
    subtype slv112 is std_logic_vector(111 downto 0); -- 14 karakter
    subtype slv192 is std_logic_vector(191 downto 0); -- 24 karakter

    -- ---------------- Sinyal tersinkron ke domain pix_clk ----------------
    signal r_board      : board_t := INIT_BOARD;
    signal r_turn, r_sel_valid, r_hint_en, r_last_valid, r_unlimited, r_paused : std_logic := '0';
    signal r_promo_active, r_show_cursor, r_popup_hide : std_logic := '0';
    signal r_cpu_en, r_cpu_think, r_cpu_lvl, r_replay, r_r_auto, r_an_on : std_logic := '0';
    signal r_menu_open, r_anim_en, r_seg_cursor, r_mouse_en : std_logic := '0';
    signal r_status, r_theme, r_timeout, r_result, r_prompt, r_promo_choice : std_logic_vector(1 downto 0) := "00";
    signal r_king_sq, r_cursor, r_sel_sq, r_last_from, r_last_to, r_an_dst : std_logic_vector(5 downto 0) := (others => '0');
    signal r_dest_mask  : std_logic_vector(63 downto 0) := (others => '0');
    signal r_w_time, r_b_time : std_logic_vector(15 downto 0) := (others => '0');
    signal r_rk_bcd, r_rc_bcd : std_logic_vector(11 downto 0) := (others => '0');
    signal r_an_x, r_an_y, r_an_xe, r_an_ye : unsigned(10 downto 0) := (others => '0');
    signal r_an_piece   : std_logic_vector(3 downto 0) := (others => '0');
    signal r_menu_idx   : unsigned(3 downto 0) := (others => '0');
    signal r_preset     : std_logic_vector(2 downto 0) := "000";
    signal r_mouse_x, r_mouse_y : unsigned(10 downto 0) := (others => '0');
    signal r_cap_by_w, r_cap_by_b : std_logic_vector(44 downto 0) := (others => '0');
    signal r_w_adv, r_b_adv : unsigned(5 downto 0) := (others => '0');
    signal frame_cnt    : unsigned(5 downto 0) := (others => '0');
    signal vs_prev      : std_logic := '0';

    -- ---------------- Font 5x7 ----------------
    function cid(ch : slv8) return integer is
    begin
        case character'val(to_integer(unsigned(ch))) is
            when 'G' => return 1;   when 'I' => return 2;   when 'L' => return 3;   when 'R' => return 4;
            when 'A' => return 5;   when 'N' => return 6;   when 'P' => return 7;   when 'U' => return 8;
            when 'T' => return 9;   when 'H' => return 10;  when 'M' => return 11;  when 'K' => return 12;
            when 'S' => return 13;  when 'E' => return 14;  when 'W' => return 15;  when 'B' => return 16;
            when 'J' => return 17;  when 'D' => return 18;  when ':' => return 19;  when '-' => return 30;
            when '/' => return 35;
            when 'O' => return 31;  when 'Y' => return 32;  when 'C' => return 33;  when '?' => return 34;
            when '0' => return 20;  when '1' => return 21;  when '2' => return 22;  when '3' => return 23;
            when '4' => return 24;  when '5' => return 25;  when '6' => return 26;  when '7' => return 27;
            when '8' => return 28;  when '9' => return 29;
            when 'F' => return 36;  when 'V' => return 37;  when '>' => return 38;
            when '<' => return 39;  when '[' => return 40;  when ']' => return 41;
            when '!' => return 42;  when '+' => return 43;  when '.' => return 44;
            when others => return 0;
        end case;
    end function;

    function glyph(g : integer) return std_logic_vector is
    begin
        case g is
            when 1 => return "01110" & "10001" & "10000" & "10111" & "10001" & "10001" & "01111";  -- G
            when 2 => return "01110" & "00100" & "00100" & "00100" & "00100" & "00100" & "01110";  -- I
            when 3 => return "10000" & "10000" & "10000" & "10000" & "10000" & "10000" & "11111";  -- L
            when 4 => return "11110" & "10001" & "10001" & "11110" & "10100" & "10010" & "10001";  -- R
            when 5 => return "01110" & "10001" & "10001" & "11111" & "10001" & "10001" & "10001";  -- A
            when 6 => return "10001" & "10001" & "11001" & "10101" & "10011" & "10001" & "10001";  -- N
            when 7 => return "11110" & "10001" & "10001" & "11110" & "10000" & "10000" & "10000";  -- P
            when 8 => return "10001" & "10001" & "10001" & "10001" & "10001" & "10001" & "01110";  -- U
            when 9 => return "11111" & "00100" & "00100" & "00100" & "00100" & "00100" & "00100";  -- T
            when 10 => return "10001" & "10001" & "10001" & "11111" & "10001" & "10001" & "10001";  -- H
            when 11 => return "10001" & "11011" & "10101" & "10101" & "10001" & "10001" & "10001";  -- M
            when 12 => return "10001" & "10010" & "10100" & "11000" & "10100" & "10010" & "10001";  -- K
            when 13 => return "01111" & "10000" & "10000" & "01110" & "00001" & "00001" & "11110";  -- S
            when 14 => return "11111" & "10000" & "10000" & "11110" & "10000" & "10000" & "11111";  -- E
            when 15 => return "10001" & "10001" & "10001" & "10101" & "10101" & "11011" & "10001";  -- W
            when 16 => return "11110" & "10001" & "10001" & "11110" & "10001" & "10001" & "11110";  -- B
            when 17 => return "00111" & "00010" & "00010" & "00010" & "00010" & "10010" & "01100";  -- J
            when 18 => return "11110" & "10001" & "10001" & "10001" & "10001" & "10001" & "11110";  -- D
            when 19 => return "00000" & "00100" & "00100" & "00000" & "00100" & "00100" & "00000";  -- :
            when 20 => return "01110" & "10001" & "10011" & "10101" & "11001" & "10001" & "01110";  -- 0
            when 21 => return "00100" & "01100" & "00100" & "00100" & "00100" & "00100" & "01110";  -- 1
            when 22 => return "01110" & "10001" & "00001" & "00010" & "00100" & "01000" & "11111";  -- 2
            when 23 => return "11110" & "00001" & "00001" & "01110" & "00001" & "00001" & "11110";  -- 3
            when 24 => return "00010" & "00110" & "01010" & "10010" & "11111" & "00010" & "00010";  -- 4
            when 25 => return "11111" & "10000" & "11110" & "00001" & "00001" & "10001" & "01110";  -- 5
            when 26 => return "00110" & "01000" & "10000" & "11110" & "10001" & "10001" & "01110";  -- 6
            when 27 => return "11111" & "00001" & "00010" & "00100" & "01000" & "01000" & "01000";  -- 7
            when 28 => return "01110" & "10001" & "10001" & "01110" & "10001" & "10001" & "01110";  -- 8
            when 29 => return "01110" & "10001" & "10001" & "01111" & "00001" & "00010" & "01100";  -- 9
            when 30 => return "00000" & "00000" & "00000" & "11111" & "00000" & "00000" & "00000";  -- -
            when 31 => return "01110" & "10001" & "10001" & "10001" & "10001" & "10001" & "01110";  -- O
            when 32 => return "10001" & "10001" & "01010" & "00100" & "00100" & "00100" & "00100";  -- Y
            when 33 => return "01110" & "10001" & "10000" & "10000" & "10000" & "10001" & "01110";  -- C
            when 34 => return "01110" & "10001" & "00001" & "00010" & "00100" & "00000" & "00100";  -- ?
            when 35 => return "00001" & "00010" & "00010" & "00100" & "01000" & "01000" & "10000";  -- /
            when 36 => return "11111" & "10000" & "10000" & "11110" & "10000" & "10000" & "10000";  -- F
            when 37 => return "10001" & "10001" & "10001" & "10001" & "10001" & "01010" & "00100";  -- V
            when 38 => return "10000" & "01000" & "00100" & "00010" & "00100" & "01000" & "10000";  -- >
            when 39 => return "00010" & "00100" & "01000" & "10000" & "01000" & "00100" & "00010";  -- <
            when 40 => return "01110" & "01000" & "01000" & "01000" & "01000" & "01000" & "01110";  -- [
            when 41 => return "01110" & "00010" & "00010" & "00010" & "00010" & "00010" & "01110";  -- ]
            when 42 => return "00100" & "00100" & "00100" & "00100" & "00100" & "00000" & "00100";  -- !
            when 43 => return "00000" & "00100" & "00100" & "11111" & "00100" & "00100" & "00000";  -- +
            when 44 => return "00000" & "00000" & "00000" & "00000" & "00000" & "01100" & "01100";  -- .
            when others => return "00000" & "00000" & "00000" & "00000" & "00000" & "00000" & "00000";
        end case;
    end function;

    function b8(c : character) return slv8 is
    begin
        return std_logic_vector(to_unsigned(character'pos(c), 8));
    end function;

    function s14(s : string) return slv112 is
        variable r : slv112;
    begin
        for i in 1 to 14 loop
            r(111 - 8 * (i - 1) downto 104 - 8 * (i - 1)) := b8(s(i));
        end loop;
        return r;
    end function;

    function s24(s : string) return slv192 is
        variable r : slv192;
    begin
        for i in 1 to 24 loop
            r(191 - 8 * (i - 1) downto 184 - 8 * (i - 1)) := b8(s(i));
        end loop;
        return r;
    end function;

    -- Konversi selisih poin (0..39) menjadi "+N " atau "+NN"
    function adv_str(v : unsigned(5 downto 0)) return std_logic_vector is
        variable iv, tens, ones : integer;
        variable r : std_logic_vector(23 downto 0);
    begin
        iv := to_integer(v);
        if iv <= 0 then
            return b8(' ') & b8(' ') & b8(' ');
        elsif iv < 10 then
            return b8('+') & std_logic_vector(to_unsigned(48 + iv, 8)) & b8(' ');
        else
            tens := iv / 10;
            ones := iv - tens * 10;
            return b8('+') & std_logic_vector(to_unsigned(48 + tens, 8)) & std_logic_vector(to_unsigned(48 + ones, 8));
        end if;
    end function;

    -- Pembagi 20 tanpa divider untuk tray bidak dimakan (0..159 -> 0..7)
    function idx20(v : unsigned(7 downto 0)) return unsigned is
        variable n : integer := 0;
    begin
        for k in 1 to 7 loop
            if v >= to_unsigned(20 * k, 8) then n := n + 1; end if;
        end loop;
        return to_unsigned(n, 3);
    end function;

    -- Sprite panah mouse 12x12 (2 bit/piksel: 00 transparan, 01 hitam, 10 putih)
    function mouse_px(row, col : integer) return std_logic_vector is
        subtype mrow_t is std_logic_vector(23 downto 0);
        type mrom_t is array (0 to 11) of mrow_t;
        constant MROM : mrom_t := (
            "010000000000000000000000",
            "010100000000000000000000",
            "011001000000000000000000",
            "011010010000000000000000",
            "011010100100000000000000",
            "011010101001000000000000",
            "011010101010010000000000",
            "011010101010100100000000",
            "011010101001010101000000",
            "011001101001000000000000",
            "010100011010010000000000",
            "010000000101010000000000"
        );
        variable rbits : mrow_t;
        variable idx   : integer;
    begin
        rbits := MROM(row);
        idx   := 11 - col;
        return rbits(idx * 2 + 1 downto idx * 2);
    end function;

    -- Konstanta teks 14 karakter (panel kanan)
    constant P_BLANK     : slv112 := s14("              ");
    constant P_GILIRAN   : slv112 := s14("GILIRAN :     ");
    constant P_PUTIH     : slv112 := s14("  PUTIH       ");
    constant P_HITAM     : slv112 := s14("  HITAM       ");
    constant P_M2P       : slv112 := s14("MODE: 2 PEMAIN");
    constant P_MCPU1     : slv112 := s14("MODE: CPU LV 1");
    constant P_MCPU2     : slv112 := s14("MODE: CPU LV 2");
    constant P_REPLAY    : slv112 := s14("REPLAY AKTIF  ");
    constant P_WHABIS    : slv112 := s14("WAKTU HABIS!  ");
    constant P_MENYERAH  : slv112 := s14("MENYERAH!     ");
    constant P_REMIS     : slv112 := s14("REMIS SEPAKAT ");
    constant P_SKAK      : slv112 := s14("!! SKAK! !!   ");
    constant P_SKAKMAT   : slv112 := s14("SKAKMAT!      ");
    constant P_PAT       : slv112 := s14("PAT - SERI!   ");
    constant P_BERPIKIR  : slv112 := s14("CPU BERPIKIR..");
    constant P_JALAN     : slv112 := s14("PERMAINAN JLN ");
    constant P_PMENANG   : slv112 := s14("PUTIH MENANG! ");
    constant P_HMENANG   : slv112 := s14("HITAM MENANG! ");
    constant P_SERI      : slv112 := s14("SERI          ");
    constant P_JEDA      : slv112 := s14("JAM DIJEDA    ");
    constant P_MOUSE_OK  : slv112 := s14("MOUSE: OK     ");
    constant P_MOUSE_OFF : slv112 := s14("MOUSE: OFF    ");

    -- Konstanta teks 24 karakter (judul atas & modal tengah)
    constant T_HEADER    : slv192 := s24("   CATUR FPGA BASYS 3   ");
    constant M_BLANK     : slv192 := s24("                        ");
    constant M_TITLE     : slv192 := s24("    MENU PENGATURAN     ");
    constant M_SEP       : slv192 := s24("------------------------");
    constant M_HELP1     : slv192 := s24("KLIK BARIS -> KLIK </>  ");
    constant M_HELP2     : slv192 := s24("SW0 OFF: TUTUP MENU     ");

    constant PRM_TITLE   : slv192 := s24("   PILIH BIDAK PROMOSI  ");
    constant PRM_LABELS  : slv192 := s24("  RATU  BENT GAJ   KUDA ");
    constant PRM_HELP    : slv192 := s24("KLIK BIDAK / BATAL:KANAN");

    constant CFM_REMIS   : slv192 := s24("    TAWARAN REMIS?      ");
    constant CFM_RESIGN  : slv192 := s24("    YAKIN MENYERAH?     ");
    constant CFM_BTNS    : slv192 := s24("    [ YA ]   [ TIDAK ]  ");

    constant GO_R_MAT    : slv192 := s24("       SKAKMAT!         ");
    constant GO_R_TO     : slv192 := s24("     WAKTU HABIS!       ");
    constant GO_R_RES    : slv192 := s24("       MENYERAH         ");
    constant GO_R_DRW    : slv192 := s24("     PERMAINAN SERI     ");
    constant GO_W_YOU    : slv192 := s24("     ANDA MENANG!       ");
    constant GO_L_YOU    : slv192 := s24("      ANDA KALAH!       ");
    constant GO_W_WHT    : slv192 := s24("     PUTIH MENANG!      ");
    constant GO_W_BLK    : slv192 := s24("     HITAM MENANG!      ");
    constant GO_W_PAT    : slv192 := s24("       PAT - SERI       ");
    constant GO_W_REM    : slv192 := s24("     REMIS SEPAKAT      ");
    constant GO_BTNS     : slv192 := s24(" [MAIN LAGI] [CEK PAPAN]");

    constant P_PUTIH_PFX : std_logic_vector(63 downto 0) :=
        b8('P') & b8('U') & b8('T') & b8('I') & b8('H') & b8(' ') & b8(' ') & b8(' ');
    constant P_HITAM_PFX : std_logic_vector(63 downto 0) :=
        b8('H') & b8('I') & b8('T') & b8('A') & b8('M') & b8(' ') & b8(' ') & b8(' ');
    constant P_DMKP_PFX  : std_logic_vector(87 downto 0) :=
        b8('D') & b8('I') & b8('M') & b8('A') & b8('K') & b8('A') & b8('N') & b8(' ') & b8('P') & b8(' ') & b8(' ');
    constant P_DMKH_PFX  : std_logic_vector(87 downto 0) :=
        b8('D') & b8('I') & b8('M') & b8('A') & b8('K') & b8('A') & b8('N') & b8(' ') & b8('H') & b8(' ') & b8(' ');

    -- Status turunan permainan & mode modal
    signal to_any, res_resign, res_draw, g_over, over_ui : std_logic;
    signal white_won, black_won, is_draw : std_logic;
    signal modal_mode : std_logic_vector(2 downto 0); -- 0=none, 1=menu, 2=promo, 3=confirm, 4=gameover
    signal pstr_c     : slv112;
    signal mstr_c     : slv192;
    signal p_wt, p_bt, p_rnum, p_cw, p_cb : slv112;

    -- Pipeline P1
    signal x1, y1 : unsigned(10 downto 0) := (others => '0');
    signal hs1, vs1, act1, inb1, inm1, mbdr1, msel1 : std_logic := '0';
    signal mmode1 : std_logic_vector(2 downto 0) := "000";
    signal fidx1, ridx1 : unsigned(2 downto 0) := (others => '0');
    signal swa1, swb1, ov1 : std_logic := '0';
    signal ox1, oy1 : unsigned(10 downto 0) := (others => '0');
    signal pstr1 : slv112 := (others => '0');
    signal mstr1 : slv192 := (others => '0');
    signal card_bdr1, btn_hl1 : std_logic := '0';
    signal cap_w1, cap_b1 : std_logic := '0';
    signal cap_sx1, cap_sy1 : unsigned(4 downto 0) := (others => '0');
    signal cap_slot1 : integer range 0 to 15 := 0;
    signal prm_box1 : std_logic := '0';
    signal prm_idx1 : unsigned(1 downto 0) := "00";
    signal prm_sel1, prm_bdr1 : std_logic := '0';
    signal prm_px1, prm_py1 : unsigned(5 downto 0) := (others => '0');
    signal lbl_ch1 : slv8 := (others => '0');
    signal lbl_en1 : std_logic := '0';

    -- Pipeline P2
    signal x2, y2 : unsigned(10 downto 0) := (others => '0');
    signal hs2, vs2, act2, inb2, inm2, mbdr2, msel2 : std_logic := '0';
    signal mmode2 : std_logic_vector(2 downto 0) := "000";
    signal card_bdr2, btn_hl2, swa2, swb2, ov2, prm_box2, prm_sel2, prm_bdr2 : std_logic := '0';
    signal fidx2, rank2 : unsigned(2 downto 0) := (others => '0');
    signal xin2, yin2, oxin2, oyin2 : unsigned(5 downto 0) := (others => '0');
    signal piece2 : std_logic_vector(3 downto 0) := (others => '0');
    signal gid2 : integer range 0 to 63 := 0;
    signal line2 : unsigned(5 downto 0) := (others => '0');
    signal cap2 : std_logic := '0';
    signal cap_sx2, cap_sy2 : unsigned(4 downto 0) := (others => '0');

    -- Pipeline P3
    signal x3, y3 : unsigned(10 downto 0) := (others => '0');
    signal hs3, vs3, act3, inb3, inm3, mbdr3, msel3 : std_logic := '0';
    signal mmode3 : std_logic_vector(2 downto 0) := "000";
    signal card_bdr3, btn_hl3, swa3, swb3, ov3, cap3, prm_box3, prm_sel3, prm_bdr3 : std_logic := '0';
    signal sx3, sy3, osx3, osy3 : unsigned(4 downto 0) := (others => '0');
    signal sp_ok3, ov_ok3 : std_logic := '0';
    signal piece3 : std_logic_vector(3 downto 0) := (others => '0');
    signal dark3, cur3, sel3, hint3, last3, chk3, edge4_3, ring_3, dot3 : std_logic := '0';
    signal glyph_row3 : std_logic_vector(4 downto 0) := (others => '0');
    signal gcol3 : unsigned(2 downto 0) := (others => '0');
    signal gvalid3 : std_logic := '0';
    signal line3 : unsigned(5 downto 0) := (others => '0');

    -- Pipeline P4
    signal x4, y4 : unsigned(10 downto 0) := (others => '0');
    signal hs4, vs4, act4, inb4, inm4, mbdr4, msel4 : std_logic := '0';
    signal mmode4 : std_logic_vector(2 downto 0) := "000";
    signal card_bdr4, btn_hl4, swa4, swb4, ov4, sp_ok4, ov_ok4, cap4, prm_box4, prm_sel4, prm_bdr4 : std_logic := '0';
    signal sx4, osx4 : unsigned(4 downto 0) := (others => '0');
    signal piece4 : std_logic_vector(3 downto 0) := (others => '0');
    signal dark4, cur4, sel4, hint4, last4, chk4, edge4_4, ring4, dot4, ton4 : std_logic := '0';
    signal line4 : unsigned(5 downto 0) := (others => '0');
    signal rom_bits, orom_bits, rb4, orb4 : std_logic_vector(39 downto 0) := (others => '0');

    -- Pipeline P5
    signal hs5, vs5, act5, inb5, inm5, mbdr5, msel5 : std_logic := '0';
    signal mmode5 : std_logic_vector(2 downto 0) := "000";
    signal card_bdr5, btn_hl5, swa5, swb5, ov5, cap5, prm_box5, prm_sel5, prm_bdr5 : std_logic := '0';
    signal px5, opx5, mpix5 : std_logic_vector(1 downto 0) := "00";
    signal piece5 : std_logic_vector(3 downto 0) := (others => '0');
    signal dark5, cur5, sel5, hint5, last5, chk5, edge4_5, ring5, dot5, ton5 : std_logic := '0';
    signal line5 : unsigned(5 downto 0) := (others => '0');

    -- Pipeline P6
    signal c_light, c_dark : std_logic_vector(11 downto 0);
    signal hsync_r, vsync_r : std_logic := '0';
    signal rgb : std_logic_vector(11 downto 0) := (others => '0');
begin
    hsync <= hsync_r;  vsync <= vsync_r;
    vga_r <= rgb(11 downto 8);  vga_g <= rgb(7 downto 4);  vga_b <= rgb(3 downto 0);

    -- Sinkronisasi sinyal kontrol ke domain pix_clk
    process (pix_clk)
    begin
        if rising_edge(pix_clk) then
            r_board        <= board;
            r_turn         <= turn;
            r_status       <= status;
            r_king_sq      <= king_sq;
            r_cursor       <= cursor;
            r_sel_valid    <= sel_valid;
            r_sel_sq       <= sel_sq;
            r_dest_mask    <= dest_mask;
            r_hint_en      <= hint_en;
            r_last_valid   <= last_valid;
            r_last_from    <= last_from;
            r_last_to      <= last_to;
            r_theme        <= theme;
            r_w_time       <= w_time;
            r_b_time       <= b_time;
            r_unlimited    <= unlimited;
            r_paused       <= paused;
            r_timeout      <= timeout;
            r_result       <= result;
            r_prompt       <= prompt;
            r_promo_active <= promo_active;
            r_promo_choice <= promo_choice;
            r_show_cursor  <= show_cursor;
            r_popup_hide   <= popup_hide;
            r_cpu_en       <= cpu_en;
            r_cpu_think    <= cpu_think;
            r_cpu_lvl      <= cpu_lvl;
            r_replay       <= replay;
            r_r_auto       <= r_auto;
            r_rk_bcd       <= rk_bcd;
            r_rc_bcd       <= rc_bcd;
            r_an_on        <= an_on;
            r_an_x         <= an_x;
            r_an_y         <= an_y;
            r_an_xe        <= an_xe;
            r_an_ye        <= an_ye;
            r_an_piece     <= an_piece;
            r_an_dst       <= an_dst;
            r_menu_open    <= menu_open;
            r_menu_idx     <= menu_idx;
            r_preset       <= preset;
            r_anim_en      <= anim_en;
            r_seg_cursor   <= seg_cursor;
            r_mouse_x      <= mouse_x;
            r_mouse_y      <= mouse_y;
            r_mouse_en     <= mouse_en;
            r_cap_by_w     <= cap_by_w;
            r_cap_by_b     <= cap_by_b;
            r_w_adv        <= w_adv;
            r_b_adv        <= b_adv;

            vs_prev <= vs_in;
            if vs_prev = '0' and vs_in = '1' then
                frame_cnt <= frame_cnt + 1;
            end if;
        end if;
    end process;

    -- Turunan status & pemenang
    to_any     <= '1' when r_timeout /= "00" else '0';
    res_resign <= '1' when r_result = "01" or r_result = "10" else '0';
    res_draw   <= '1' when r_result = "11" else '0';
    g_over     <= '1' when r_status = "10" or r_status = "11" or r_timeout /= "00" or r_result /= "00" else '0';
    over_ui    <= g_over and (not r_replay);

    white_won <= '1' when (r_status = "10" and r_turn = '1') or r_timeout = "10" or r_result = "10" else '0';
    black_won <= '1' when (r_status = "10" and r_turn = '0') or r_timeout = "01" or r_result = "01" else '0';
    is_draw   <= '1' when (r_status = "11" or r_result = "11") and white_won = '0' and black_won = '0' else '0';

    modal_mode <= "001" when r_menu_open = '1' else
                  "010" when r_promo_active = '1' and r_replay = '0' else
                  "011" when r_prompt /= "00" and r_replay = '0' else
                  "100" when over_ui = '1' and r_popup_hide = '0' else
                  "000";

    -- String dinamis panel kanan
    p_wt <= s14("PUTIH   --:-- ") when r_unlimited = '1' else
            P_PUTIH_PFX &
            x"3" & r_w_time(15 downto 12) & x"3" & r_w_time(11 downto 8) & b8(':') &
            x"3" & r_w_time(7 downto 4)   & x"3" & r_w_time(3 downto 0)  & b8(' ');
    p_bt <= s14("HITAM   --:-- ") when r_unlimited = '1' else
            P_HITAM_PFX &
            x"3" & r_b_time(15 downto 12) & x"3" & r_b_time(11 downto 8) & b8(':') &
            x"3" & r_b_time(7 downto 4)   & x"3" & r_b_time(3 downto 0)  & b8(' ');
    p_rnum <= x"3" & r_rk_bcd(11 downto 8) & x"3" & r_rk_bcd(7 downto 4) & x"3" & r_rk_bcd(3 downto 0) & b8('/') &
              x"3" & r_rc_bcd(11 downto 8) & x"3" & r_rc_bcd(7 downto 4) & x"3" & r_rc_bcd(3 downto 0) &
              b8(' ') & b8(' ') & b8('O') & b8('T') & b8('O') & b8(' ') & b8(' ') when r_r_auto = '1' else
              x"3" & r_rk_bcd(11 downto 8) & x"3" & r_rk_bcd(7 downto 4) & x"3" & r_rk_bcd(3 downto 0) & b8('/') &
              x"3" & r_rc_bcd(11 downto 8) & x"3" & r_rc_bcd(7 downto 4) & x"3" & r_rc_bcd(3 downto 0) &
              b8(' ') & b8(' ') & b8('M') & b8('A') & b8('N') & b8(' ') & b8(' ');
    p_cw <= P_DMKP_PFX & adv_str(r_w_adv);
    p_cb <= P_DMKH_PFX & adv_str(r_b_adv);

    -- Pemilihan string 14-karakter panel kanan berdasar y[9:4]
    process (all)
    begin
        case to_integer(y(9 downto 4)) is
            when 1  => pstr_c <= P_GILIRAN;
            when 2  => if r_turn = '1' then pstr_c <= P_HITAM; else pstr_c <= P_PUTIH; end if;
            when 4  =>
                if r_cpu_en = '0' then pstr_c <= P_M2P;
                elsif r_cpu_lvl = '1' then pstr_c <= P_MCPU2;
                else pstr_c <= P_MCPU1;
                end if;
            when 6  =>
                if r_replay = '1' then pstr_c <= P_REPLAY;
                elsif to_any = '1' then pstr_c <= P_WHABIS;
                elsif res_resign = '1' then pstr_c <= P_MENYERAH;
                elsif res_draw = '1' then pstr_c <= P_REMIS;
                elsif r_status = "01" then
                    if frame_cnt(4) = '0' then pstr_c <= P_SKAK; else pstr_c <= P_BLANK; end if;
                elsif r_status = "10" then pstr_c <= P_SKAKMAT;
                elsif r_status = "11" then pstr_c <= P_PAT;
                elsif r_cpu_en = '1' and r_cpu_think = '1' then pstr_c <= P_BERPIKIR;
                else pstr_c <= P_JALAN;
                end if;
            when 7  =>
                if r_replay = '1' then pstr_c <= p_rnum;
                elsif white_won = '1' then pstr_c <= P_PMENANG;
                elsif black_won = '1' then pstr_c <= P_HMENANG;
                elsif is_draw = '1' then pstr_c <= P_SERI;
                elsif r_paused = '1' then pstr_c <= P_JEDA;
                else pstr_c <= P_BLANK;
                end if;
            when 11 => pstr_c <= p_wt;
            when 13 => pstr_c <= p_bt;
            when 17 => pstr_c <= p_cw;
            when 21 => pstr_c <= p_cb;
            when 28 => if r_mouse_en = '1' then pstr_c <= P_MOUSE_OK; else pstr_c <= P_MOUSE_OFF; end if;
            when 30 =>
                if r_replay = '1' then pstr_c <= s14("KONTROL REPLAY");
                elsif r_mouse_en = '1' then pstr_c <= s14("KONTROL BOARD ");
                else pstr_c <= s14("TANPA MOUSE   ");
                end if;
            when 31 => pstr_c <= s14("SW0 : MENU    ");
            when 32 =>
                if r_replay = '1' then pstr_c <= s14("L/R : GESER   ");
                elsif r_mouse_en = '1' then pstr_c <= s14("BTNL: UNDO    ");
                else pstr_c <= s14("BTN : KURSOR  ");
                end if;
            when 33 =>
                if r_replay = '1' then pstr_c <= s14("BTNC: OTO/MAN ");
                elsif r_mouse_en = '1' then pstr_c <= s14("BTNR: REMIS   ");
                else pstr_c <= s14("SW12: UNDO    ");
                end if;
            when 34 =>
                if r_replay = '1' then pstr_c <= s14("BTNU: AKHIR   ");
                elsif r_mouse_en = '1' then pstr_c <= s14("BTND: MENYERAH");
                else pstr_c <= s14("SW13: REMIS   ");
                end if;
            when 35 =>
                if r_replay = '1' then pstr_c <= s14("BTND: AWAL    ");
                elsif r_mouse_en = '1' then pstr_c <= s14("BTNU: JEDA JAM");
                else pstr_c <= s14("SW14: MENYERAH");
                end if;
            when 36 =>
                if r_replay = '1' then pstr_c <= P_BLANK;
                else pstr_c <= s14("SW15: RESET   ");
                end if;
            when others => pstr_c <= P_BLANK;
        end case;
    end process;

    -- Pemilihan string 24-karakter popup tengah berdasar modal_mode & y[9:4]
    process (all)
        variable row_i : integer;
        variable pfx   : string(1 to 2);
        variable lbl   : string(1 to 10);
        variable al, ar: string(1 to 1);
        variable val   : string(1 to 8);
    begin
        row_i := to_integer(y(9 downto 4));
        mstr_c <= M_BLANK;

        case modal_mode is
        when "001" => -- Menu Pengaturan (panah < > hanya pada baris aktif)
            if row_i = 11 then
                mstr_c <= M_TITLE;
            elsif row_i = 12 or row_i = 22 then
                mstr_c <= M_SEP;
            elsif row_i = 23 then
                mstr_c <= M_HELP1;
            elsif row_i = 24 then
                mstr_c <= M_HELP2;
            elsif row_i >= 13 and row_i <= 21 then
                if row_i - 13 = to_integer(r_menu_idx) then
                    pfx := "> "; al := "<"; ar := ">";
                else
                    pfx := "  "; al := " "; ar := " ";
                end if;
                case row_i - 13 is
                    when 0 =>
                        lbl := "MODE    : ";
                        if r_cpu_en = '1' then val := "KOMPUTER"; else val := "2 PEMAIN"; end if;
                    when 1 =>
                        lbl := "CPU LVL : ";
                        if r_cpu_lvl = '1' then val := "TINGKAT2"; else val := "TINGKAT1"; end if;
                    when 2 =>
                        lbl := "WAKTU   : ";
                        case r_preset is
                            when "001"  => val := "1 MENIT ";
                            when "010"  => val := "3 MENIT ";
                            when "011"  => val := "5 MENIT ";
                            when "100"  => val := "10 MENIT";
                            when "101"  => val := "15 MENIT";
                            when "110"  => val := "30 MENIT";
                            when "111"  => val := "60 MENIT";
                            when others => val := "OFF     ";
                        end case;
                    when 3 =>
                        lbl := "TEMA    : ";
                        case r_theme is
                            when "01"   => val := "HIJAU   ";
                            when "10"   => val := "BIRU    ";
                            when "11"   => val := "ABU-ABU ";
                            when others => val := "KLASIK  ";
                        end case;
                    when 4 =>
                        lbl := "HINT    : ";
                        if r_hint_en = '1' then val := "ON      "; else val := "OFF     "; end if;
                    when 5 =>
                        lbl := "ANIMASI : ";
                        if r_anim_en = '1' then val := "ON      "; else val := "OFF     "; end if;
                    when 6 =>
                        lbl := "JEDA JAM: ";
                        if r_paused = '1' then val := "ON      "; else val := "OFF     "; end if;
                    when 7 =>
                        lbl := "7-SEGMEN: ";
                        if r_seg_cursor = '1' then val := "KURSOR  "; else val := "JAM     "; end if;
                    when 8 =>
                        lbl := "REPLAY  : ";
                        if r_replay = '1' then val := "ON      "; else val := "OFF     "; end if;
                    when others =>
                        lbl := "          "; val := "        ";
                end case;
                mstr_c <= s24(pfx & lbl & al & " " & val & " " & ar);
            end if;

        when "010" => -- Popup Promosi
            if row_i = 14 then mstr_c <= PRM_TITLE;
            elsif row_i = 21 then mstr_c <= PRM_LABELS;
            elsif row_i = 23 then mstr_c <= PRM_HELP;
            end if;

        when "011" => -- Popup Konfirmasi
            if row_i = 15 then
                if r_prompt = "01" then mstr_c <= CFM_REMIS; else mstr_c <= CFM_RESIGN; end if;
            elsif row_i = 17 then
                mstr_c <= CFM_BTNS;
            end if;

        when "100" => -- Popup Game Over
            if row_i = 14 then
                if is_draw = '1' then mstr_c <= GO_R_DRW;
                elsif to_any = '1' then mstr_c <= GO_R_TO;
                elsif res_resign = '1' then mstr_c <= GO_R_RES;
                else mstr_c <= GO_R_MAT;
                end if;
            elsif row_i = 16 then
                if r_status = "11" then mstr_c <= GO_W_PAT;
                elsif r_result = "11" then mstr_c <= GO_W_REM;
                elsif r_cpu_en = '1' then
                    if white_won = '1' then mstr_c <= GO_W_YOU; else mstr_c <= GO_L_YOU; end if;
                else
                    if white_won = '1' then mstr_c <= GO_W_WHT; else mstr_c <= GO_W_BLK; end if;
                end if;
            elsif row_i = 20 then
                mstr_c <= GO_BTNS;
            end if;

        when others =>
            mstr_c <= M_BLANK;
        end case;
    end process;

    -- ============ P1 : wilayah layar, kotak papan, tray dimakan, modal ============
    process (pix_clk)
        variable in_m, mbdr, msel : std_logic;
        variable cbdr, bhl, prm_b, prm_s : std_logic;
        variable pidx : unsigned(1 downto 0);
        variable px_in, py_in : unsigned(5 downto 0);
        variable cw, cb : std_logic;
        variable c_dx, c_dy : unsigned(7 downto 0);
        variable c_col : unsigned(2 downto 0);
        variable c_row : integer range 0 to 1;
        variable l_en  : std_logic;
        variable l_ch  : slv8;
        variable row_n, col_n : integer;
        variable bx1_v, by1_v : unsigned(10 downto 0);
    begin
        if rising_edge(pix_clk) then
            if pix_ce = '1' then
                x1 <= x;  y1 <= y;  hs1 <= hs_in;  vs1 <= vs_in;
                if x < SCR_W and y < SCR_H then act1 <= '1'; else act1 <= '0'; end if;

                if x >= BOARD_X0 and x < BOARD_X0 + BOARD_SZ and
                   y >= BOARD_Y0 and y < BOARD_Y0 + BOARD_SZ then
                    inb1  <= '1';
                    bx1_v := x - BOARD_X0;
                    by1_v := y - BOARD_Y0;
                    fidx1 <= bx1_v(8 downto 6);
                    ridx1 <= by1_v(8 downto 6);
                else
                    inb1  <= '0';
                    fidx1 <= (others => '0');
                    ridx1 <= (others => '0');
                end if;

                -- Label koordinat papan 1..8 (kiri) dan A..H (bawah)
                l_en := '0'; l_ch := b8(' ');
                row_n := to_integer(y(9 downto 4));
                col_n := to_integer(x(10 downto 4));
                if col_n = 1 and row_n >= 5 and row_n <= 33 and ((row_n - 5) mod 4) = 0 then
                    l_en := '1';
                    l_ch := std_logic_vector(to_unsigned(56 - ((row_n - 5) / 4), 8)); -- '8'..'1'
                elsif row_n = 35 and col_n >= 4 and col_n <= 32 and ((col_n - 4) mod 4) = 0 then
                    l_en := '1';
                    l_ch := std_logic_vector(to_unsigned(65 + ((col_n - 4) / 4), 8)); -- 'A'..'H'
                end if;
                lbl_en1 <= l_en;
                lbl_ch1 <= l_ch;

                -- Bingkai 4 kartu panel kanan
                cbdr := '0';
                if (x >= 552 and x < 792 and y >= 8 and y < 156) and
                   (x < 554 or x >= 790 or y < 10 or y >= 154) then cbdr := '1'; end if;
                if (x >= 552 and x < 792 and y >= 164 and y < 252) and
                   (x < 554 or x >= 790 or y < 166 or y >= 250) then cbdr := '1'; end if;
                if (x >= 552 and x < 792 and y >= 260 and y < 428) and
                   (x < 554 or x >= 790 or y < 262 or y >= 426) then cbdr := '1'; end if;
                if (x >= 552 and x < 792 and y >= 436 and y < 596) and
                   (x < 554 or x >= 790 or y < 438 or y >= 594) then cbdr := '1'; end if;
                card_bdr1 <= cbdr;

                -- Contoh kotak warna giliran di kartu 1
                if x >= 728 and x < 772 and y >= 16 and y < 48 then swa1 <= '1'; else swa1 <= '0'; end if;
                if x < 731 or x >= 769 or y < 19 or y >= 45 then swb1 <= '1'; else swb1 <= '0'; end if;

                -- Tray bidak dimakan (2 area 160x40)
                cw := '0'; cb := '0';
                c_col := "000"; c_row := 0; c_dx := (others => '0'); c_dy := (others => '0');
                if x >= 560 and x < 720 and y >= 292 and y < 332 then
                    cw := '1';
                    c_dx := resize(x - 560, 8);
                    c_col := idx20(c_dx);
                    if y >= 312 then c_row := 1; c_dy := resize(y - 312, 8);
                    else c_row := 0; c_dy := resize(y - 292, 8);
                    end if;
                elsif x >= 560 and x < 720 and y >= 356 and y < 396 then
                    cb := '1';
                    c_dx := resize(x - 560, 8);
                    c_col := idx20(c_dx);
                    if y >= 376 then c_row := 1; c_dy := resize(y - 376, 8);
                    else c_row := 0; c_dy := resize(y - 356, 8);
                    end if;
                end if;
                cap_w1    <= cw;
                cap_b1    <= cb;
                cap_sx1   <= resize(c_dx - to_unsigned(20 * to_integer(c_col), 8), 5);
                cap_sy1   <= c_dy(4 downto 0);
                cap_slot1 <= c_row * 8 + to_integer(c_col);

                -- Overlay modal tengah
                in_m := '0'; mbdr := '0'; msel := '0'; bhl := '0';
                prm_b := '0'; prm_s := '0'; pidx := "00"; px_in := (others => '0'); py_in := (others => '0');
                case modal_mode is
                when "001" => -- Menu
                    if x >= MENU_X0 and x <= MENU_X1 and y >= MENU_Y0 and y <= MENU_Y1 then
                        in_m := '1';
                        if x < MENU_X0 + 2 or x > MENU_X1 - 2 or y < MENU_Y0 + 2 or y > MENU_Y1 - 2 then
                            mbdr := '1';
                        end if;
                        if x >= MENU_TX0 and x <= MENU_TX1 and y >= MENU_IY0 and y <= MENU_IY1 and
                           (row_n - 13) = to_integer(r_menu_idx) then
                            msel := '1';
                        end if;
                    end if;
                when "010" => -- Promosi
                    if x >= 80 and x <= 495 and y >= 208 and y <= 399 then
                        in_m := '1';
                        if x < 82 or x > 493 or y < 210 or y > 397 then mbdr := '1'; end if;
                        if y >= PRM_Y0 and y <= PRM_Y1 then
                            if x >= PRM_B0_X0 and x <= PRM_B0_X1 then
                                prm_b := '1'; pidx := "00"; px_in := resize(x - PRM_B0_X0, 6);
                            elsif x >= PRM_B1_X0 and x <= PRM_B1_X1 then
                                prm_b := '1'; pidx := "01"; px_in := resize(x - PRM_B1_X0, 6);
                            elsif x >= PRM_B2_X0 and x <= PRM_B2_X1 then
                                prm_b := '1'; pidx := "10"; px_in := resize(x - PRM_B2_X0, 6);
                            elsif x >= PRM_B3_X0 and x <= PRM_B3_X1 then
                                prm_b := '1'; pidx := "11"; px_in := resize(x - PRM_B3_X0, 6);
                            end if;
                            py_in := resize(y - PRM_Y0, 6);
                            if prm_b = '1' and pidx = unsigned(r_promo_choice) then prm_s := '1'; end if;
                        end if;
                    end if;
                when "011" => -- Konfirmasi
                    if x >= 80 and x <= 495 and y >= 224 and y <= 367 then
                        in_m := '1';
                        if x < 82 or x > 493 or y < 226 or y > 365 then mbdr := '1'; end if;
                        if y >= CFM_Y0 and y <= CFM_Y1 and
                           ((x >= CFM_YES_X0 and x <= CFM_YES_X1) or (x >= CFM_NO_X0 and x <= CFM_NO_X1)) then
                            bhl := '1';
                        end if;
                    end if;
                when "100" => -- Game Over
                    if x >= 80 and x <= 495 and y >= 208 and y <= 399 then
                        in_m := '1';
                        if x < 83 or x > 492 or y < 211 or y > 396 then mbdr := '1'; end if;
                        if y >= GO_BTN_Y0 and y <= GO_BTN_Y1 and
                           ((x >= GO_RST_X0 and x <= GO_RST_X1) or (x >= GO_CHK_X0 and x <= GO_CHK_X1)) then
                            bhl := '1';
                        end if;
                    end if;
                when others =>
                    null;
                end case;

                mmode1    <= modal_mode;
                inm1      <= in_m;
                mbdr1     <= mbdr;
                msel1     <= msel;
                btn_hl1   <= bhl;
                prm_box1  <= prm_b;
                prm_idx1  <= pidx;
                prm_sel1  <= prm_s;
                if prm_b = '1' and (px_in < 2 or px_in >= 62 or py_in < 2 or py_in >= 62) then
                    prm_bdr1 <= '1';
                else
                    prm_bdr1 <= '0';
                end if;
                prm_px1   <= px_in;
                prm_py1   <= py_in;

                pstr1 <= pstr_c;
                mstr1 <= mstr_c;

                if r_an_on = '1' and x >= r_an_x and x < r_an_xe and y >= r_an_y and y < r_an_ye then
                    ov1 <= '1';
                else
                    ov1 <= '0';
                end if;
                ox1 <= x - r_an_x;
                oy1 <= y - r_an_y;
            end if;
        end if;
    end process;

    -- ============ P2 : posisi dalam kotak, bidak, karakter teks ============
    process (pix_clk)
        variable ch  : slv8;
        variable ci  : integer;
        variable pt3 : std_logic_vector(2 downto 0);
        variable rank1 : unsigned(2 downto 0);
        variable bx2_v, by2_v : unsigned(10 downto 0);
        variable bx_in, by_in : unsigned(5 downto 0);
    begin
        if rising_edge(pix_clk) then
            if pix_ce = '1' then
                x2 <= x1;  y2 <= y1;  hs2 <= hs1;  vs2 <= vs1;  act2 <= act1;  inb2 <= inb1;
                mmode2 <= mmode1;  inm2 <= inm1;  mbdr2 <= mbdr1;  msel2 <= msel1;
                card_bdr2 <= card_bdr1;  btn_hl2 <= btn_hl1;  swa2 <= swa1;  swb2 <= swb1;
                prm_box2 <= prm_box1;  prm_sel2 <= prm_sel1;  prm_bdr2 <= prm_bdr1;
                fidx2 <= fidx1;
                rank1 := 7 - ridx1;
                rank2 <= rank1;

                bx2_v := x1 - BOARD_X0;
                by2_v := y1 - BOARD_Y0;
                bx_in := bx2_v(5 downto 0);
                by_in := by2_v(5 downto 0);
                ov2 <= ov1;  oxin2 <= ox1(5 downto 0);  oyin2 <= oy1(5 downto 0);

                -- Pemilihan sumber sprite untuk u_rom (Promosi / Tray Dimakan / Papan)
                cap2    <= cap_w1 or cap_b1;
                cap_sx2 <= cap_sx1;
                cap_sy2 <= cap_sy1;
                if prm_box1 = '1' then
                    xin2 <= prm_px1;
                    yin2 <= prm_py1;
                    case prm_idx1 is
                        when "00"   => pt3 := "101"; -- Ratu
                        when "01"   => pt3 := "100"; -- Benteng
                        when "10"   => pt3 := "011"; -- Gajah
                        when others => pt3 := "010"; -- Kuda
                    end case;
                    piece2 <= r_turn & pt3;
                elsif inm1 = '1' then
                    xin2   <= (others => '0');
                    yin2   <= (others => '0');
                    piece2 <= "0000";
                elsif cap_w1 = '1' then
                    xin2 <= (others => '0');
                    yin2 <= (others => '0');
                    if cap_slot1 < 15 then
                        pt3 := r_cap_by_w(cap_slot1 * 3 + 2 downto cap_slot1 * 3);
                    else
                        pt3 := "000";
                    end if;
                    piece2 <= '1' & pt3; -- bidak hitam dimakan Putih
                elsif cap_b1 = '1' then
                    xin2 <= (others => '0');
                    yin2 <= (others => '0');
                    if cap_slot1 < 15 then
                        pt3 := r_cap_by_b(cap_slot1 * 3 + 2 downto cap_slot1 * 3);
                    else
                        pt3 := "000";
                    end if;
                    piece2 <= '0' & pt3; -- bidak putih dimakan Hitam
                else
                    xin2 <= bx_in;
                    yin2 <= by_in;
                    if r_an_on = '1' and std_logic_vector(rank1 & fidx1) = r_an_dst then
                        piece2 <= "0000";
                    else
                        piece2 <= get_sq(r_board, std_logic_vector(rank1 & fidx1));
                    end if;
                end if;

                -- Pemilihan sumber karakter teks
                if inm1 = '1' and x1 >= MENU_TX0 and x1 <= MENU_TX1 then
                    ci := to_integer(x1(10 downto 4)) - 6;
                    ch := mstr1((23 - ci) * 8 + 7 downto (23 - ci) * 8);
                    gid2 <= cid(ch);
                elsif x1 >= 560 and x1 < 784 then
                    ci := to_integer(x1(10 downto 4)) - 35;
                    ch := pstr1((13 - ci) * 8 + 7 downto (13 - ci) * 8);
                    gid2 <= cid(ch);
                elsif lbl_en1 = '1' then
                    gid2 <= cid(lbl_ch1);
                elsif y1 >= 16 and y1 < 32 and x1 >= 32 and x1 < 416 then
                    ci := to_integer(x1(10 downto 4)) - 2;
                    ch := T_HEADER((23 - ci) * 8 + 7 downto (23 - ci) * 8);
                    gid2 <= cid(ch);
                else
                    gid2 <= 0;
                end if;
                line2 <= y1(9 downto 4);
            end if;
        end if;
    end process;

    -- ============ P3 : koordinat sprite & bendera kotak ============
    process (pix_clk)
        variable mx, my, omx, omy : unsigned(13 downto 0);
        variable sqi2  : std_logic_vector(5 downto 0);
        variable gl2   : std_logic_vector(34 downto 0);
        variable grow2 : unsigned(2 downto 0);
    begin
        if rising_edge(pix_clk) then
            if pix_ce = '1' then
                x3 <= x2;  y3 <= y2;  hs3 <= hs2;  vs3 <= vs2;  act3 <= act2;  inb3 <= inb2;
                mmode3 <= mmode2;  inm3 <= inm2;  mbdr3 <= mbdr2;  msel3 <= msel2;
                card_bdr3 <= card_bdr2;  btn_hl3 <= btn_hl2;  swa3 <= swa2;  swb3 <= swb2;
                prm_box3 <= prm_box2;  prm_sel3 <= prm_sel2;  prm_bdr3 <= prm_bdr2;
                piece3 <= piece2;  line3 <= line2;  cap3 <= cap2;  ov3 <= ov2;

                if cap2 = '1' then
                    sx3    <= cap_sx2;
                    sy3    <= cap_sy2;
                    sp_ok3 <= '1';
                elsif xin2 >= 2 and xin2 < 62 and yin2 >= 2 and yin2 < 62 then
                    mx := resize((xin2 - 2) * to_unsigned(171, 8), 14);
                    my := resize((yin2 - 2) * to_unsigned(171, 8), 14);
                    sx3    <= mx(13 downto 9);
                    sy3    <= my(13 downto 9);
                    sp_ok3 <= '1';
                else
                    sx3    <= (others => '0');
                    sy3    <= (others => '0');
                    sp_ok3 <= '0';
                end if;

                if oxin2 >= 2 and oxin2 < 62 and oyin2 >= 2 and oyin2 < 62 then
                    omx := resize((oxin2 - 2) * to_unsigned(171, 8), 14);
                    omy := resize((oyin2 - 2) * to_unsigned(171, 8), 14);
                    osx3   <= omx(13 downto 9);
                    osy3   <= omy(13 downto 9);
                    ov_ok3 <= '1';
                else
                    osx3   <= (others => '0');
                    osy3   <= (others => '0');
                    ov_ok3 <= '0';
                end if;

                dark3 <= not (fidx2(0) xor rank2(0));
                sqi2  := std_logic_vector(rank2 & fidx2);
                if r_show_cursor = '1' and sqi2 = r_cursor then cur3 <= '1'; else cur3 <= '0'; end if;
                if r_sel_valid = '1' and sqi2 = r_sel_sq then sel3 <= '1'; else sel3 <= '0'; end if;
                hint3 <= r_hint_en and r_sel_valid and r_dest_mask(to_integer(unsigned(sqi2)));
                if r_last_valid = '1' and (sqi2 = r_last_from or sqi2 = r_last_to) then last3 <= '1'; else last3 <= '0'; end if;
                if (r_status = "01" or r_status = "10") and sqi2 = r_king_sq then chk3 <= '1'; else chk3 <= '0'; end if;
                if xin2 < 4 or xin2 >= 60 or yin2 < 4 or yin2 >= 60 then edge4_3 <= '1'; else edge4_3 <= '0'; end if;
                if xin2 < 7 or xin2 >= 57 or yin2 < 7 or yin2 >= 57 then ring_3 <= '1'; else ring_3 <= '0'; end if;
                if xin2 >= 24 and xin2 < 40 and yin2 >= 24 and yin2 < 40 then dot3 <= '1'; else dot3 <= '0'; end if;

                gl2   := glyph(gid2);
                grow2 := y2(3 downto 1);
                if grow2 < 7 and x2(3 downto 1) < 5 then gvalid3 <= '1'; else gvalid3 <= '0'; end if;
                gcol3 <= x2(3 downto 1);
                if grow2 < 7 then
                    glyph_row3 <= gl2((6 - to_integer(grow2)) * 5 + 4 downto (6 - to_integer(grow2)) * 5);
                else
                    glyph_row3 <= (others => '0');
                end if;
            end if;
        end if;
    end process;

    -- ============ P4 : baris sprite dari ROM ============
    u_rom  : entity work.piece_rom port map (ptype => piece3(2 downto 0),   row => std_logic_vector(sy3),  bits => rom_bits);
    u_orom : entity work.piece_rom port map (ptype => r_an_piece(2 downto 0), row => std_logic_vector(osy3), bits => orom_bits);
    process (pix_clk)
    begin
        if rising_edge(pix_clk) then
            if pix_ce = '1' then
                x4 <= x3;  y4 <= y3;  hs4 <= hs3;  vs4 <= vs3;  act4 <= act3;  inb4 <= inb3;
                mmode4 <= mmode3;  inm4 <= inm3;  mbdr4 <= mbdr3;  msel4 <= msel3;
                card_bdr4 <= card_bdr3;  btn_hl4 <= btn_hl3;  swa4 <= swa3;  swb4 <= swb3;
                prm_box4 <= prm_box3;  prm_sel4 <= prm_sel3;  prm_bdr4 <= prm_bdr3;
                sx4 <= sx3;  piece4 <= piece3;  line4 <= line3;  cap4 <= cap3;
                dark4 <= dark3;  cur4 <= cur3;  sel4 <= sel3;  hint4 <= hint3;  last4 <= last3;
                chk4 <= chk3;  edge4_4 <= edge4_3;  ring4 <= ring_3;  dot4 <= dot3;
                rb4 <= rom_bits;  orb4 <= orom_bits;  ov4 <= ov3;  osx4 <= osx3;
                sp_ok4 <= sp_ok3;  ov_ok4 <= ov_ok3;
                if gvalid3 = '1' and glyph_row3(4 - to_integer(gcol3)) = '1' then ton4 <= '1'; else ton4 <= '0'; end if;
            end if;
        end if;
    end process;

    -- ============ P5 : piksel sprite & pointer mouse ============
    process (pix_clk)
        variable ix, mx_p, my_p : integer;
    begin
        if rising_edge(pix_clk) then
            if pix_ce = '1' then
                hs5 <= hs4;  vs5 <= vs4;  act5 <= act4;  inb5 <= inb4;
                mmode5 <= mmode4;  inm5 <= inm4;  mbdr5 <= mbdr4;  msel5 <= msel4;
                card_bdr5 <= card_bdr4;  btn_hl5 <= btn_hl4;  swa5 <= swa4;  swb5 <= swb4;
                prm_box5 <= prm_box4;  prm_sel5 <= prm_sel4;  prm_bdr5 <= prm_bdr4;
                piece5 <= piece4;  line5 <= line4;  cap5 <= cap4;
                dark5 <= dark4;  cur5 <= cur4;  sel5 <= sel4;  hint5 <= hint4;  last5 <= last4;
                chk5 <= chk4;  edge4_5 <= edge4_4;  ring5 <= ring4;  dot5 <= dot4;  ton5 <= ton4;
                ov5 <= ov4;

                ix := 19 - to_integer(osx4);
                if ov_ok4 = '0' or r_an_piece(2 downto 0) = "000" or ix < 0 then
                    opx5 <= "00";
                else
                    opx5 <= orb4(ix * 2 + 1 downto ix * 2);
                end if;

                ix := 19 - to_integer(sx4);
                if sp_ok4 = '0' or piece4(2 downto 0) = "000" or ix < 0 then
                    px5 <= "00";
                else
                    px5 <= rb4(ix * 2 + 1 downto ix * 2);
                end if;

                if r_mouse_en = '1' and x4 >= r_mouse_x and x4 < r_mouse_x + 12 and
                   y4 >= r_mouse_y and y4 < r_mouse_y + 12 then
                    mx_p := to_integer(x4 - r_mouse_x);
                    my_p := to_integer(y4 - r_mouse_y);
                    mpix5 <= mouse_px(my_p, mx_p);
                else
                    mpix5 <= "00";
                end if;
            end if;
        end if;
    end process;

    -- ============ P6 : warna akhir ============
    c_light <= x"EED" when r_theme = "01" else
               x"DEE" when r_theme = "10" else
               x"CCC" when r_theme = "11" else
               x"FDB";
    c_dark  <= x"795" when r_theme = "01" else
               x"8AA" when r_theme = "10" else
               x"777" when r_theme = "11" else
               x"B86";

    process (pix_clk)
        variable c        : std_logic_vector(11 downto 0);
        variable bdr_col  : std_logic_vector(11 downto 0);
        variable w_act, b_act : std_logic;
    begin
        if rising_edge(pix_clk) then
            if pix_ce = '1' then
                hsync_r <= hs5;  vsync_r <= vs5;
                w_act := '1' when r_turn = '0' and to_any = '0' and r_paused = '0' and g_over = '0' else '0';
                b_act := '1' when r_turn = '1' and to_any = '0' and r_paused = '0' and g_over = '0' else '0';

                if act5 = '0' then
                    c := x"000";
                elsif inm5 = '1' then
                    -- Modal tengah (Menu / Promosi / Konfirmasi / Game Over)
                    case mmode5 is
                    when "001" => -- Menu Pengaturan
                        if mbdr5 = '1' then
                            c := x"4CF";
                        elsif msel5 = '1' then
                            c := x"258";
                            if ton5 = '1' then c := x"FF4"; end if;
                        else
                            c := x"112";
                            if ton5 = '1' then
                                if line5 = 11 then c := x"4CF";
                                elsif line5 = 12 or line5 = 22 then c := x"678";
                                elsif line5 >= 23 then c := x"9AB";
                                else c := x"EEE";
                                end if;
                            end if;
                        end if;
                    when "010" => -- Modal Promosi 4 ikon
                        if mbdr5 = '1' then
                            c := x"FE6";
                        elsif prm_bdr5 = '1' then
                            if prm_sel5 = '1' then c := x"FF4"; else c := x"678"; end if;
                        elsif prm_box5 = '1' and px5 = "01" then
                            c := x"000";
                        elsif prm_box5 = '1' and px5 = "10" then
                            if r_turn = '1' then c := x"334"; else c := x"FFF"; end if;
                        elsif prm_box5 = '1' then
                            if prm_sel5 = '1' then c := x"358"; else c := x"234"; end if;
                        else
                            c := x"112";
                            if ton5 = '1' then
                                if line5 = 14 then c := x"FE6";
                                elsif line5 = 23 then c := x"9AB";
                                else c := x"FFF";
                                end if;
                            end if;
                        end if;
                    when "011" => -- Modal Konfirmasi
                        if mbdr5 = '1' then
                            c := x"F93";
                        elsif btn_hl5 = '1' then
                            c := x"246";
                            if ton5 = '1' then c := x"FF4"; end if;
                        else
                            c := x"112";
                            if ton5 = '1' then c := x"FFF"; end if;
                        end if;
                    when others => -- Modal Game Over
                        if is_draw = '1' then bdr_col := x"FD4";
                        elsif r_cpu_en = '1' and black_won = '1' then bdr_col := x"F33";
                        else bdr_col := x"4E6";
                        end if;

                        if mbdr5 = '1' then
                            c := bdr_col;
                        elsif btn_hl5 = '1' then
                            c := x"254";
                            if ton5 = '1' then c := x"FF6"; end if;
                        else
                            c := x"112";
                            if ton5 = '1' then
                                if line5 = 14 then c := x"CCC";
                                else c := bdr_col;
                                end if;
                            end if;
                        end if;
                    end case;
                elsif inb5 = '1' then
                    -- Papan catur 8x8
                    if dark5 = '1' then c := c_dark; else c := c_light; end if;
                    if last5 = '1' then
                        if dark5 = '1' then c := x"DC3"; else c := x"FF8"; end if;
                    end if;
                    if sel5 = '1' then c := x"B8F"; end if;
                    if chk5 = '1' then c := x"F44"; end if;
                    if hint5 = '1' and piece5(2 downto 0) = "000" and dot5 = '1' then c := x"252"; end if;
                    if hint5 = '1' and piece5(2 downto 0) /= "000" and ring5 = '1' then c := x"E43"; end if;
                    if px5 = "01" then c := x"000"; end if;
                    if px5 = "10" then
                        if piece5(3) = '1' then c := x"334"; else c := x"FFF"; end if;
                    end if;
                    if ov5 = '1' and opx5 = "01" then c := x"000"; end if;
                    if ov5 = '1' and opx5 = "10" then
                        if r_an_piece(3) = '1' then c := x"334"; else c := x"FFF"; end if;
                    end if;
                    if cur5 = '1' and edge4_5 = '1' then c := x"FC0"; end if;
                else
                    -- Latar gelap + panel kanan + margin label koordinat
                    c := x"182";
                    if card_bdr5 = '1' then
                        c := x"457";
                    elsif cap5 = '1' then
                        c := x"678";
                        if px5 = "01" then
                            c := x"000";
                        elsif px5 = "10" then
                            if piece5(3) = '1' then c := x"334"; else c := x"FFF"; end if;
                        end if;
                    elsif ton5 = '1' then
                        case to_integer(line5) is
                            when 1  => c := x"9BC";
                            when 2  => c := x"FFF";
                            when 4  => c := x"8CF";
                            when 6  =>
                                if r_status = "01" then c := x"F82";
                                elsif g_over = '1' then c := x"FE6";
                                else c := x"6F6";
                                end if;
                            when 7  => c := x"FE6";
                            when 11 =>
                                if r_timeout = "01" then c := x"F33";
                                elsif w_act = '1' then c := x"FE6";
                                else c := x"CCC";
                                end if;
                            when 13 =>
                                if r_timeout = "10" then c := x"F33";
                                elsif b_act = '1' then c := x"FE6";
                                else c := x"CCC";
                                end if;
                            when 17 | 21 => c := x"9DF";
                            when 28 => if r_mouse_en = '1' then c := x"4E6"; else c := x"FA2"; end if;
                            when 30 => c := x"FE6";
                            when 31 | 32 | 33 | 34 | 35 | 36 => c := x"CCD";
                            when others => c := x"CCD";
                        end case;
                    end if;
                    if swa5 = '1' then
                        if swb5 = '1' then c := x"FFF";
                        elsif r_turn = '1' then c := x"000";
                        else c := x"FFF";
                        end if;
                    end if;
                end if;

                -- Pointer panah mouse paling atas
                if act5 = '1' then
                    if mpix5 = "01" then c := x"000";
                    elsif mpix5 = "10" then c := x"FFF";
                    end if;
                end if;
                rgb <= c;
            end if;
        end if;
    end process;
end rtl;
