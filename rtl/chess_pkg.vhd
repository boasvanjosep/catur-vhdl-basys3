-- chess_pkg.vhd : tipe, konstanta geometri 800x600, dan fungsi bersama untuk desain catur.
--   Bidak 4 bit {warna, tipe[2:0]} : tipe 1 P, 2 N, 3 B, 4 R, 5 Q, 6 K ; warna 0 putih, 1 hitam ; 0 = kosong.
--   Indeks kotak = baris*8 + kolom (a1 = 0, h1 = 7, a8 = 56, h8 = 63).
--   Papan = 256 bit; bidak di kotak s berada pada bit [4s+3 : 4s].
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

package chess_pkg is
    subtype board_t is std_logic_vector(255 downto 0);
    subtype sq_t    is std_logic_vector(5 downto 0);
    subtype piece_t is std_logic_vector(3 downto 0);

    -- Geometri layar 800x600 @ 60 Hz dan hitbox UI bersama
    constant SCR_W    : integer := 800;
    constant SCR_H    : integer := 600;
    constant BOARD_X0 : integer := 32;
    constant BOARD_Y0 : integer := 48;
    constant BOARD_SZ : integer := 512;
    constant SQ_SZ    : integer := 64;

    -- Hitbox overlay menu pengaturan (9 item: baris y = 208..351, masing-masing 16 px)
    constant MENU_X0   : integer := 80;
    constant MENU_X1   : integer := 495;
    constant MENU_Y0   : integer := 160;
    constant MENU_Y1   : integer := 415;
    constant MENU_TX0  : integer := 96;
    constant MENU_TX1  : integer := 479;
    constant MENU_IY0  : integer := 208;
    constant MENU_IY1  : integer := 351;
    constant MENU_PRVX0: integer := 288;
    constant MENU_PRVX1: integer := 327;
    constant MENU_VALX0: integer := 328;
    constant MENU_VALX1: integer := 439;
    constant MENU_NXTX0: integer := 440;
    constant MENU_NXTX1: integer := 479;

    -- Hitbox tombol popup Game Over ([MAIN LAGI] & [CEK PAPAN])
    constant GO_BTN_Y0 : integer := 312;
    constant GO_BTN_Y1 : integer := 343;
    constant GO_RST_X0 : integer := 112;
    constant GO_RST_X1 : integer := 287;
    constant GO_CHK_X0 : integer := 304;
    constant GO_CHK_X1 : integer := 479;

    -- Hitbox 4 kotak ikon popup Promosi Pion
    constant PRM_Y0    : integer := 256;
    constant PRM_Y1    : integer := 319;
    constant PRM_B0_X0 : integer := 128;
    constant PRM_B0_X1 : integer := 191;
    constant PRM_B1_X0 : integer := 216;
    constant PRM_B1_X1 : integer := 279;
    constant PRM_B2_X0 : integer := 304;
    constant PRM_B2_X1 : integer := 367;
    constant PRM_B3_X0 : integer := 392;
    constant PRM_B3_X1 : integer := 455;

    -- Hitbox tombol popup Konfirmasi ([ YA ] & [ TIDAK ])
    constant CFM_Y0    : integer := 264;
    constant CFM_Y1    : integer := 295;
    constant CFM_YES_X0: integer := 152;
    constant CFM_YES_X1: integer := 255;
    constant CFM_NO_X0 : integer := 296;
    constant CFM_NO_X1 : integer := 447;

    -- posisi awal permainan
    constant INIT_BOARD : board_t :=
        x"CABEDBAC" & x"99999999" & x"00000000" & x"00000000" & x"00000000" & x"00000000" &
        x"11111111" & x"42365324";

    -- Rekaman sinyal pengamatan (debug) yang diekspor top_core untuk testbench
    type dbg_t is record
        board       : board_t;
        turn        : std_logic;
        status      : std_logic_vector(1 downto 0);
        busy        : std_logic;
        cursor      : std_logic_vector(5 downto 0);
        sel_valid   : std_logic;
        sel_sq      : std_logic_vector(5 downto 0);
        dest_mask   : std_logic_vector(63 downto 0);
        last_valid  : std_logic;
        last_from   : std_logic_vector(5 downto 0);
        last_to     : std_logic_vector(5 downto 0);
        rights      : std_logic_vector(3 downto 0);
        ep_valid    : std_logic;
        ep_sq       : std_logic_vector(5 downto 0);
        ksq_w       : std_logic_vector(5 downto 0);
        ksq_b       : std_logic_vector(5 downto 0);
        undo_avail  : std_logic;
        promo_active: std_logic;
        promo_choice: std_logic_vector(1 downto 0);
        prompt      : std_logic_vector(1 downto 0);
        result      : std_logic_vector(1 downto 0);
        timeout     : std_logic_vector(1 downto 0);
        w_time      : std_logic_vector(15 downto 0);
        b_time      : std_logic_vector(15 downto 0);
        unlimited   : std_logic;
        show_clock  : std_logic;
        h_count     : std_logic_vector(9 downto 0);
        r_k         : std_logic_vector(9 downto 0);
        r_board     : board_t;
        r_auto      : std_logic;
        cst         : std_logic_vector(2 downto 0);
        cpu_start   : std_logic;
        cpu_done    : std_logic;
        cpu_bf      : std_logic_vector(5 downto 0);
        cpu_bt      : std_logic_vector(5 downto 0);
        cpu_score   : signed(15 downto 0);
        cpu_lvl     : std_logic;
        an_on       : std_logic;
        an_x        : unsigned(10 downto 0);
        an_y        : unsigned(10 downto 0);
        an_piece    : std_logic_vector(3 downto 0);
        an_dst      : std_logic_vector(5 downto 0);
        pix_ce      : std_logic;
        -- pengamatan mouse, menu, popup, dan bidak dimakan
        mouse_x     : unsigned(10 downto 0);
        mouse_y     : unsigned(10 downto 0);
        mouse_sq    : std_logic_vector(5 downto 0);
        mouse_inb   : std_logic;
        mouse_ready : std_logic;
        has_wheel   : std_logic;
        menu_open   : std_logic;
        menu_idx    : unsigned(3 downto 0);
        theme       : std_logic_vector(1 downto 0);
        hint_en     : std_logic;
        anim_en     : std_logic;
        paused      : std_logic;
        seg_cursor  : std_logic;
        replay_en   : std_logic;
        cpu_en      : std_logic;
        preset      : std_logic_vector(2 downto 0);
        popup_hide  : std_logic;
        over_top    : std_logic;
        cap_by_w    : std_logic_vector(44 downto 0);
        cap_by_b    : std_logic_vector(44 downto 0);
        w_adv       : unsigned(5 downto 0);
        b_adv       : unsigned(5 downto 0);
    end record;

    function get_sq(b : board_t; s : sq_t) return piece_t;
    function put_sq(b : board_t; s : sq_t; p : piece_t) return board_t;
    function apply_full(b : board_t; f : sq_t; t : sq_t; ptype : std_logic_vector(2 downto 0);
                        do_promo : std_logic) return board_t;
    function rmask(s : sq_t) return std_logic_vector;
end package chess_pkg;

package body chess_pkg is

    function get_sq(b : board_t; s : sq_t) return piece_t is
        variable i : integer := to_integer(unsigned(s)) * 4;
    begin
        return b(i + 3 downto i);
    end function;

    function put_sq(b : board_t; s : sq_t; p : piece_t) return board_t is
        variable x : board_t := b;
        variable i : integer := to_integer(unsigned(s)) * 4;
    begin
        x(i + 3 downto i) := p;
        return x;
    end function;

    function apply_full(b : board_t; f : sq_t; t : sq_t; ptype : std_logic_vector(2 downto 0);
                        do_promo : std_logic) return board_t is
        variable x   : board_t := b;
        variable p   : piece_t;
        variable epi : sq_t;
        variable fr  : std_logic_vector(2 downto 0);
        variable fc, tc : std_logic_vector(2 downto 0);
        variable tr  : std_logic_vector(2 downto 0);
    begin
        p  := get_sq(b, f);
        fr := f(5 downto 3);  fc := f(2 downto 0);
        tr := t(5 downto 3);  tc := t(2 downto 0);
        if p(2 downto 0) = "001" and fc /= tc and get_sq(b, t) = "0000" then
            epi := fr & tc;
            x := put_sq(x, epi, "0000");
        end if;
        if p(2 downto 0) = "110" and fc = "100" and tc = "110" then
            x := put_sq(x, fr & "101", get_sq(b, fr & "111"));
            x := put_sq(x, fr & "111", "0000");
        elsif p(2 downto 0) = "110" and fc = "100" and tc = "010" then
            x := put_sq(x, fr & "011", get_sq(b, fr & "000"));
            x := put_sq(x, fr & "000", "0000");
        end if;
        if do_promo = '1' and p(2 downto 0) = "001" then
            if (p(3) = '1' and tr = "000") or (p(3) = '0' and tr = "111") then
                p(2 downto 0) := ptype;
            end if;
        end if;
        x := put_sq(x, t, p);
        x := put_sq(x, f, "0000");
        return x;
    end function;

    function rmask(s : sq_t) return std_logic_vector is
    begin
        case to_integer(unsigned(s)) is
            when 4      => return "0011";
            when 7      => return "0111";
            when 0      => return "1011";
            when 60     => return "1100";
            when 63     => return "1101";
            when 56     => return "1110";
            when others => return "1111";
        end case;
    end function;

end package body chess_pkg;
