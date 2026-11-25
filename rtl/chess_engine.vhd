-- =============================================================================
-- chess_engine.vhd   (v4)
-- Papan, giliran, validasi langkah legal, skak / skakmat / pat.
--
-- Perintah (pulsa 1 clock, hanya diterima saat busy = '0' dan game belum selesai):
--   cmd_gen  + cmd_from        : hitung semua tujuan legal bidak di cmd_from -> dest_mask
--   cmd_move + cmd_from/to     : jalankan langkah (harus yang tadi dihitung cmd_gen)
--                                cmd_promo memilih bidak promosi: 0 ratu, 1 benteng, 2 gajah, 3 kuda
--   cmd_eval                   : hitung ulang status (skak/skakmat/pat) pemain yang jalan
--   cmd_undo                   : batalkan langkah terakhir (undo 2 tingkat)
--   Perintah simulasi (dipakai instance kedua oleh pemain komputer):
--   cmd_load                   : isi posisi dari ld_* (tanpa evaluasi status)
--   cmd_smake + cmd_from/to    : jalankan langkah (promosi -> ratu) dan simpan keadaan di tumpukan
--   cmd_sunmake                : kembali ke keadaan sebelum cmd_smake terakhir
--   cmd_chk                    : apakah raja pemain yang jalan sedang diserang -> chk_out
--
-- Aturan : gerakan semua bidak, tidak boleh membiarkan raja sendiri terkena skak,
--          skak, skakmat, pat, rokade (kedua sisi), en passant, promosi pilihan.
-- Belum  : remis otomatis (50 langkah, pengulangan, materi kurang).
--
-- Cara kerja: satu unit pseudo_legal dipakai berulang oleh FSM.
--   legal(from,to) = pseudo_legal(from,to) DAN setelah langkah itu raja sendiri
--   tidak diserang bidak lawan (dicek dengan memindai 64 kotak).
--   Rokade dicek terpisah (state C_*): raja tidak sedang skak, kotak yang dilewati
--   dan kotak tujuan tidak diserang, kotak di antara kosong, hak rokade masih ada.
-- =============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.chess_pkg.all;

entity chess_engine is
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        cmd_gen    : in  std_logic;
        cmd_move   : in  std_logic;
        cmd_eval   : in  std_logic;
        cmd_undo   : in  std_logic;
        cmd_from   : in  std_logic_vector(5 downto 0);
        cmd_to     : in  std_logic_vector(5 downto 0);
        cmd_promo  : in  std_logic_vector(1 downto 0);
        -- perintah simulasi (pencarian komputer)
        cmd_load   : in  std_logic;
        ld_board   : in  board_t;
        ld_turn    : in  std_logic;
        ld_rights  : in  std_logic_vector(3 downto 0);
        ld_epv     : in  std_logic;
        ld_eps     : in  std_logic_vector(5 downto 0);
        ld_ksqw    : in  std_logic_vector(5 downto 0);
        ld_ksqb    : in  std_logic_vector(5 downto 0);
        cmd_smake  : in  std_logic;
        cmd_sunmake: in  std_logic;
        cmd_chk    : in  std_logic;
        busy       : out std_logic;
        board      : out board_t := INIT_BOARD;
        turn       : out std_logic := '0';                         -- 0 = putih jalan, 1 = hitam jalan
        status     : out std_logic_vector(1 downto 0) := "00";     -- 0 normal, 1 skak, 2 skakmat, 3 pat
        dest_mask  : out std_logic_vector(63 downto 0) := (others => '0');
        last_valid : out std_logic := '0';
        last_from  : out std_logic_vector(5 downto 0) := (others => '0');
        last_to    : out std_logic_vector(5 downto 0) := (others => '0');
        king_sq    : out std_logic_vector(5 downto 0);             -- kotak raja pemain yang sedang jalan
        undo_avail : out std_logic := '0';
        undo_cnt   : out std_logic_vector(1 downto 0) := "00";
        ev_move    : out std_logic;                                -- langkah nyata diterima
        ev_undo    : out std_logic;                                -- undo dijalankan
        o_rights   : out std_logic_vector(3 downto 0);
        o_epv      : out std_logic;
        o_eps      : out std_logic_vector(5 downto 0);
        o_ksqw     : out std_logic_vector(5 downto 0);
        o_ksqb     : out std_logic_vector(5 downto 0);
        chk_out    : out std_logic                                 -- hasil cmd_chk
    );
end chess_engine;

architecture rtl of chess_engine is
    type state_t is (IDLE, G_INIT, G_REQ, G_WAIT, H_APPLY, A_REQ, A_WAIT, A_NEXT, G_AFTER, G_NEXT,
                     G_DONE, E_START, E_CHK, E_FIN, C_START, C_CHK0, C_TRANS, C_DEST, C_FIN, C_NEXT, CK_FIN);
    signal st : state_t := IDLE;

    constant SNW : integer := 293;
    subtype snap_t is std_logic_vector(SNW - 1 downto 0);
    type sstk_t is array (0 to 5) of snap_t;

    signal wb         : board_t := INIT_BOARD;     -- papan kerja (nyata atau hipotetis)
    signal gen_from, gen_to, atk_src, ksq_t : std_logic_vector(5 downto 0) := (others => '0');
    signal mode_eval, atk_hit, atk_color, in_check, any_legal : std_logic := '0';
    signal ret        : state_t := IDLE;
    signal mask_valid : std_logic := '0';
    signal mask_from  : std_logic_vector(5 downto 0) := (others => '0');
    signal ksq_w      : std_logic_vector(5 downto 0) := "000100";   -- e1
    signal ksq_b      : std_logic_vector(5 downto 0) := "111100";   -- e8
    signal c_side     : std_logic := '0';          -- rokade yang diuji: 0 sisi raja (pendek), 1 sisi ratu (panjang)
    signal rights     : std_logic_vector(3 downto 0) := "1111";     -- {wK, wQ, bK, bQ}
    signal ep_valid   : std_logic := '0';
    signal ep_sq      : std_logic_vector(5 downto 0) := (others => '0');
    signal pv0, pv1   : snap_t := (others => '0');                  -- keadaan sebelum 2 langkah terakhir
    signal sstk       : sstk_t := (others => (others => '0'));      -- tumpukan keadaan pencarian komputer
    signal sp         : unsigned(2 downto 0) := (others => '0');
    signal snap_cur   : snap_t;

    signal pl_start, pl_done, pl_ok : std_logic;
    signal pl_src, pl_dst : std_logic_vector(5 downto 0);
    signal pl_piece   : std_logic_vector(3 downto 0);

    signal pc_from_cmd, pc_gen : std_logic_vector(3 downto 0);
    signal hb         : std_logic_vector(5 downto 0);
    signal rook_v     : std_logic_vector(3 downto 0);
    signal q_a, q_b, q_c, q_d, q_f, q_g, q_h : std_logic_vector(3 downto 0);
    signal cs_k, cs_q, castle_home : std_logic;
    signal cx_transit, cx_dest : std_logic_vector(5 downto 0);
    signal game_over, accept_gen, accept_move, cmd_sim : std_logic;
    signal mv_is_pawn2 : std_logic;
    signal mv_mid     : unsigned(6 downto 0);
    signal busy_i     : std_logic;
    signal in_check_i : std_logic;
begin
    -- ---------------- unit pseudo_legal ----------------
    pl_start <= '1' when st = G_REQ or st = A_REQ else '0';
    pl_src   <= atk_src when st = A_REQ else gen_from;
    pl_dst   <= ksq_t   when st = A_REQ else gen_to;
    u_pl : entity work.pseudo_legal
        port map (clk => clk, board => wb, start => pl_start, src => pl_src, dst => pl_dst,
                  ep_valid => ep_valid, ep_sq => ep_sq,
                  done => pl_done, ok => pl_ok, src_piece => pl_piece);

    -- ---------------- sinyal turunan ----------------
    busy_i   <= '0' when st = IDLE else '1';
    busy     <= busy_i;
    o_rights <= rights;  o_epv <= ep_valid;  o_eps <= ep_sq;
    o_ksqw   <= ksq_w;   o_ksqb <= ksq_b;
    chk_out  <= in_check;
    king_sq  <= ksq_b when turn = '1' else ksq_w;
    snap_cur <= rights & ep_sq & last_to & last_from & ksq_b & ksq_w & ep_valid & last_valid & turn & board;

    game_over <= '1' when status = "10" or status = "11" else '0';

    pc_from_cmd <= get_sq(board, cmd_from);
    pc_gen      <= get_sq(board, gen_from);

    -- syarat statis rokade (papan nyata)
    hb     <= "111000" when turn = '1' else "000000";          -- kotak a-file baris asal raja
    rook_v <= x"C" when turn = '1' else x"4";
    q_a <= get_sq(board, std_logic_vector(unsigned(hb) + 0));
    q_b <= get_sq(board, std_logic_vector(unsigned(hb) + 1));
    q_c <= get_sq(board, std_logic_vector(unsigned(hb) + 2));
    q_d <= get_sq(board, std_logic_vector(unsigned(hb) + 3));
    q_f <= get_sq(board, std_logic_vector(unsigned(hb) + 5));
    q_g <= get_sq(board, std_logic_vector(unsigned(hb) + 6));
    q_h <= get_sq(board, std_logic_vector(unsigned(hb) + 7));
    cs_k <= '1' when ((turn = '1' and rights(1) = '1') or (turn = '0' and rights(3) = '1')) and
                     q_h = rook_v and q_f = x"0" and q_g = x"0" else '0';
    cs_q <= '1' when ((turn = '1' and rights(0) = '1') or (turn = '0' and rights(2) = '1')) and
                     q_a = rook_v and q_b = x"0" and q_c = x"0" and q_d = x"0" else '0';
    castle_home <= '1' when pc_gen(2 downto 0) = "110" and
                            ((turn = '1' and gen_from = "111100") or (turn = '0' and gen_from = "000100")) else '0';
    cx_transit <= std_logic_vector(unsigned(hb) + 3) when c_side = '1' else std_logic_vector(unsigned(hb) + 5);
    cx_dest    <= std_logic_vector(unsigned(hb) + 2) when c_side = '1' else std_logic_vector(unsigned(hb) + 6);

    accept_gen  <= cmd_gen and not game_over;
    accept_move <= '1' when cmd_move = '1' and game_over = '0' and mask_valid = '1' and
                            mask_from = cmd_from and dest_mask(to_integer(unsigned(cmd_to))) = '1' else '0';
    cmd_sim     <= cmd_load or cmd_smake or cmd_sunmake or cmd_chk;
    ev_move <= '1' when st = IDLE and cmd_sim = '0' and accept_gen = '0' and
                        not (cmd_undo = '1' and undo_avail = '1') and accept_move = '1' else '0';
    ev_undo <= '1' when st = IDLE and cmd_sim = '0' and accept_gen = '0' and
                        cmd_undo = '1' and undo_avail = '1' else '0';

    mv_is_pawn2 <= '1' when pc_from_cmd(2 downto 0) = "001" and
                            ((unsigned(cmd_from) > unsigned(cmd_to) and unsigned(cmd_from) - unsigned(cmd_to) = 16) or
                             (unsigned(cmd_from) <= unsigned(cmd_to) and unsigned(cmd_to) - unsigned(cmd_from) = 16))
                   else '0';
    mv_mid <= shift_right(('0' & unsigned(cmd_from)) + ('0' & unsigned(cmd_to)), 1);

    -- ---------------- FSM utama ----------------
    process (clk)
        variable snap : snap_t;
        variable pc   : std_logic_vector(3 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                st <= IDLE;  board <= INIT_BOARD;  wb <= INIT_BOARD;  turn <= '0';
                status <= "00";  dest_mask <= (others => '0');  mask_valid <= '0';  mask_from <= (others => '0');
                last_valid <= '0';  last_from <= (others => '0');  last_to <= (others => '0');
                ksq_w <= "000100";  ksq_b <= "111100";
                gen_from <= (others => '0');  gen_to <= (others => '0');
                atk_src <= (others => '0');   ksq_t <= (others => '0');
                mode_eval <= '0';  atk_hit <= '0';  atk_color <= '0';
                in_check <= '0';  any_legal <= '0';  ret <= IDLE;  c_side <= '0';
                rights <= "1111";  ep_valid <= '0';  ep_sq <= (others => '0');
                undo_avail <= '0';  undo_cnt <= "00";  sp <= (others => '0');
                pv0 <= (others => '0');  pv1 <= (others => '0');
            else
                case st is
                -- -------------------------------------------------------------
                when IDLE =>
                    if cmd_load = '1' then
                        board <= ld_board;  turn <= ld_turn;  rights <= ld_rights;
                        ep_valid <= ld_epv;  ep_sq <= ld_eps;  ksq_w <= ld_ksqw;  ksq_b <= ld_ksqb;
                        status <= "00";  dest_mask <= (others => '0');  mask_valid <= '0';
                        last_valid <= '0';  undo_avail <= '0';  undo_cnt <= "00";  sp <= (others => '0');
                    elsif cmd_smake = '1' then
                        sstk(to_integer(sp)) <= snap_cur;  sp <= sp + 1;
                        board <= apply_full(board, cmd_from, cmd_to, "101", '1');
                        if pc_from_cmd(2 downto 0) = "110" then
                            if pc_from_cmd(3) = '1' then ksq_b <= cmd_to; else ksq_w <= cmd_to; end if;
                        end if;
                        rights   <= rights and rmask(cmd_from) and rmask(cmd_to);
                        ep_valid <= mv_is_pawn2;
                        ep_sq    <= std_logic_vector(mv_mid(5 downto 0));
                        turn <= not turn;
                        dest_mask <= (others => '0');  mask_valid <= '0';
                    elsif cmd_sunmake = '1' then
                        snap := sstk(to_integer(sp - 1));
                        rights <= snap(292 downto 289);  ep_sq <= snap(288 downto 283);
                        last_to <= snap(282 downto 277); last_from <= snap(276 downto 271);
                        ksq_b <= snap(270 downto 265);   ksq_w <= snap(264 downto 259);
                        ep_valid <= snap(258);  last_valid <= snap(257);  turn <= snap(256);
                        board <= snap(255 downto 0);
                        sp <= sp - 1;
                        dest_mask <= (others => '0');  mask_valid <= '0';
                    elsif cmd_chk = '1' then
                        wb        <= board;
                        ksq_t     <= ksq_b when turn = '1' else ksq_w;
                        atk_color <= turn;
                        atk_src   <= (others => '0');
                        atk_hit   <= '0';
                        ret       <= CK_FIN;
                        st        <= A_REQ;
                    elsif accept_gen = '1' then
                        gen_from   <= cmd_from;
                        mask_from  <= cmd_from;
                        mask_valid <= '0';
                        mode_eval  <= '0';
                        st <= G_INIT;
                    elsif cmd_undo = '1' and undo_avail = '1' then
                        rights <= pv0(292 downto 289);  ep_sq <= pv0(288 downto 283);
                        last_to <= pv0(282 downto 277); last_from <= pv0(276 downto 271);
                        ksq_b <= pv0(270 downto 265);   ksq_w <= pv0(264 downto 259);
                        ep_valid <= pv0(258);  last_valid <= pv0(257);  turn <= pv0(256);
                        board <= pv0(255 downto 0);
                        pv0 <= pv1;
                        undo_cnt <= std_logic_vector(unsigned(undo_cnt) - 1);
                        if undo_cnt /= "01" then undo_avail <= '1'; else undo_avail <= '0'; end if;
                        status <= "00";  dest_mask <= (others => '0');  mask_valid <= '0';
                        st <= E_START;
                    elsif accept_move = '1' then
                        pv1 <= pv0;  pv0 <= snap_cur;
                        if undo_cnt = "10" then undo_cnt <= "10"; else undo_cnt <= std_logic_vector(unsigned(undo_cnt) + 1); end if;
                        undo_avail <= '1';
                        board <= apply_full(board, cmd_from, cmd_to,
                                            std_logic_vector(to_unsigned(5, 3) - resize(unsigned(cmd_promo), 3)), '1');
                        if pc_from_cmd(2 downto 0) = "110" then
                            if pc_from_cmd(3) = '1' then ksq_b <= cmd_to; else ksq_w <= cmd_to; end if;
                        end if;
                        rights   <= rights and rmask(cmd_from) and rmask(cmd_to);
                        ep_valid <= mv_is_pawn2;
                        ep_sq    <= std_logic_vector(mv_mid(5 downto 0));
                        last_valid <= '1';  last_from <= cmd_from;  last_to <= cmd_to;
                        turn <= not turn;
                        status <= "00";
                        dest_mask <= (others => '0');  mask_valid <= '0';
                        st <= E_START;
                    elsif cmd_eval = '1' then
                        st <= E_START;
                    end if;
                -- ---------------- hitung tujuan legal untuk gen_from ----------
                when G_INIT =>
                    dest_mask <= (others => '0');
                    gen_to    <= (others => '0');
                    if pc_gen(2 downto 0) /= "000" and pc_gen(3) = turn then st <= G_REQ;
                    else st <= G_DONE;
                    end if;
                when G_REQ =>
                    wb <= board;                                    -- uji geometri di papan nyata
                    st <= G_WAIT;
                when G_WAIT =>
                    if pl_done = '1' then
                        if pl_ok = '1' then st <= H_APPLY; else st <= G_NEXT; end if;
                    end if;
                when H_APPLY =>                                     -- papan hipotetis setelah langkah
                    wb <= apply_full(board, gen_from, gen_to, "101", '0');
                    if pc_gen(2 downto 0) = "110" then ksq_t <= gen_to;
                    elsif turn = '1' then ksq_t <= ksq_b;
                    else ksq_t <= ksq_w;
                    end if;
                    atk_src   <= (others => '0');
                    atk_hit   <= '0';
                    atk_color <= turn;
                    ret       <= G_AFTER;
                    st        <= A_REQ;
                -- ---------------- pemindaian serangan ke ksq_t -----------------
                when A_REQ =>
                    st <= A_WAIT;
                when A_WAIT =>
                    if pl_done = '1' then
                        if pl_ok = '1' and pl_piece(2 downto 0) /= "000" and pl_piece(3) /= atk_color then
                            atk_hit <= '1';
                            st <= ret;
                        else
                            st <= A_NEXT;
                        end if;
                    end if;
                when A_NEXT =>
                    if atk_src = "111111" then st <= ret;
                    else atk_src <= std_logic_vector(unsigned(atk_src) + 1); st <= A_REQ;
                    end if;
                -- ---------------------------------------------------------------
                when G_AFTER =>
                    if atk_hit = '0' then dest_mask(to_integer(unsigned(gen_to))) <= '1'; end if;
                    st <= G_NEXT;
                when G_NEXT =>
                    if gen_to = "111111" then
                        -- rokade hanya dihitung untuk cmd_gen (di evaluasi, gerakan raja biasa
                        -- ke kotak yang dilewati sudah cukup membuktikan ada langkah legal)
                        if mode_eval = '0' and castle_home = '1' and (cs_k = '1' or cs_q = '1') then st <= C_START;
                        else st <= G_DONE;
                        end if;
                    else
                        gen_to <= std_logic_vector(unsigned(gen_to) + 1);  st <= G_REQ;
                    end if;
                -- ---------------- rokade ---------------------------------------
                when C_START =>                                     -- 1) raja tidak boleh sedang skak
                    wb        <= board;
                    ksq_t     <= gen_from;
                    atk_color <= turn;
                    atk_src   <= (others => '0');
                    atk_hit   <= '0';
                    ret       <= C_CHK0;
                    st        <= A_REQ;
                when C_CHK0 =>
                    if atk_hit = '1' then st <= G_DONE;
                    else
                        if cs_k = '1' then c_side <= '0'; else c_side <= '1'; end if;
                        st <= C_TRANS;
                    end if;
                when C_TRANS =>                                     -- 2) kotak yang dilewati raja tidak boleh diserang
                    wb        <= apply_full(board, gen_from, cx_transit, "101", '0');
                    ksq_t     <= cx_transit;
                    atk_src   <= (others => '0');
                    atk_hit   <= '0';
                    ret       <= C_DEST;
                    st        <= A_REQ;
                when C_DEST =>                                      -- 3) kotak tujuan (papan setelah rokade) tidak diserang
                    if atk_hit = '1' then st <= C_NEXT;
                    else
                        wb        <= apply_full(board, gen_from, cx_dest, "101", '0');
                        ksq_t     <= cx_dest;
                        atk_src   <= (others => '0');
                        atk_hit   <= '0';
                        ret       <= C_FIN;
                        st        <= A_REQ;
                    end if;
                when C_FIN =>
                    if atk_hit = '0' then dest_mask(to_integer(unsigned(cx_dest))) <= '1'; end if;
                    st <= C_NEXT;
                when C_NEXT =>
                    if c_side = '0' and cs_q = '1' then c_side <= '1'; st <= C_TRANS;
                    else st <= G_DONE;
                    end if;
                -- ---------------------------------------------------------------
                when G_DONE =>
                    if mode_eval = '0' then
                        mask_valid <= '1';
                        st <= IDLE;
                    elsif dest_mask /= x"0000000000000000" then
                        any_legal <= '1';
                        st <= E_FIN;
                    elsif gen_from = "111111" then
                        st <= E_FIN;
                    else
                        gen_from <= std_logic_vector(unsigned(gen_from) + 1);
                        st <= G_INIT;
                    end if;
                -- ---------------- evaluasi status ------------------------------
                when E_START =>
                    wb        <= board;
                    if turn = '1' then ksq_t <= ksq_b; else ksq_t <= ksq_w; end if;
                    atk_color <= turn;
                    atk_src   <= (others => '0');
                    atk_hit   <= '0';
                    ret       <= E_CHK;
                    st        <= A_REQ;
                when E_CHK =>
                    in_check  <= atk_hit;
                    any_legal <= '0';
                    gen_from  <= (others => '0');
                    mode_eval <= '1';
                    st        <= G_INIT;
                when E_FIN =>
                    if any_legal = '1' then
                        if in_check = '1' then status <= "01"; else status <= "00"; end if;
                    else
                        if in_check = '1' then status <= "10"; else status <= "11"; end if;
                    end if;
                    dest_mask  <= (others => '0');
                    mask_valid <= '0';
                    st         <= IDLE;
                when CK_FIN =>
                    in_check <= atk_hit;
                    st       <= IDLE;
                end case;
            end if;
        end if;
    end process;
end rtl;
