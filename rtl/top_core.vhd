-- top_core.vhd : inti desain Catur 800x600 @ 60 Hz dengan Mouse PS/2 + kontrol board Basys 3 adaptif.
--   SW0  (sw_menu)   : buka/tutup Menu Pengaturan 9 item (panah < > muncul pada baris aktif).
--   SW12 (sw_undo)   : Undo langkah (juga BTNL saat mouse tersambung).
--   SW13 (sw_remis)  : Tawaran Remis (juga BTNR saat mouse tersambung).
--   SW14 (sw_resign) : Menyerah (juga BTND saat mouse tersambung).
--   SW15 (sw_rst)    : Reset permainan cepat (juga tombol [MAIN LAGI] / BTNC saat Game Over).
--   Fault tolerance  : bila mouse_ready = '0', BTNU/D/L/R/C otomatis mengambil alih kursor & menu.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.chess_pkg.all;

entity top_core is
    generic (
        DEBOUNCE      : integer := 1_000_000;
        TICK_CLKS     : integer := 100_000_000;
        PS2_INIT_WAIT : integer := 1_000_000;
        PS2_INHIBIT   : integer := 12_000;
        SIM_BYPASS    : boolean := false
    );
    port (
        clk       : in    std_logic;
        sw_menu   : in    std_logic;
        sw_undo   : in    std_logic;
        sw_remis  : in    std_logic;
        sw_resign : in    std_logic;
        sw_rst    : in    std_logic;
        btnU, btnD, btnL, btnR, btnC : in std_logic;
        PS2Clk    : inout std_logic;
        PS2Data   : inout std_logic;
        led       : out   std_logic_vector(15 downto 0);
        seg       : out   std_logic_vector(6 downto 0);
        dp        : out   std_logic;
        an        : out   std_logic_vector(3 downto 0);
        vgaRed, vgaGreen, vgaBlue : out std_logic_vector(3 downto 0);
        Hsync, Vsync : out std_logic;
        dbg       : out   dbg_t
    );
end top_core;

architecture rtl of top_core is
    -- ---- sinkronisasi switch ----
    signal sw_vec, sw_s0, sw_s1, sw_s2 : std_logic_vector(4 downto 0) := (others => '0');
    signal menu_open : std_logic;
    signal sw_undo_edge, sw_remis_edge, sw_resign_edge, sw_rst_edge : std_logic;

    -- ---- pengaturan & aksi dari menu_ctrl ----
    signal rst, hint_en, cpu_en, cpu_lvl, anim_en, replay_en, paused, seg_cursor : std_logic;
    signal preset   : std_logic_vector(2 downto 0);
    signal theme    : std_logic_vector(1 downto 0);
    signal menu_idx : unsigned(3 downto 0);
    signal pause_toggle, rst_req : std_logic;

    -- ---- mouse PS/2 ----
    signal mouse_x, mouse_y : unsigned(10 downto 0);
    signal mouse_sq         : std_logic_vector(5 downto 0);
    signal mouse_inb, mouse_moved : std_logic;
    signal click_l, click_r, click_m, btn_l, btn_r : std_logic;
    signal scroll_up, scroll_dn, has_wheel, mouse_ready : std_logic;

    -- ---- tombol ----
    signal pu, pd, pl, pr, pc : std_logic;
    signal lu, ld, ll, lr, lc : std_logic;

    -- ---- clock VGA 40 MHz + timing 800x600 ----
    signal pix_clk, pix_ce, hs, vs : std_logic;

    -- ---- mesin catur + kontrol ----
    signal busy, turn, last_valid, cmd_gen, cmd_move, cmd_undo, sel_valid, undo_avail : std_logic;
    signal board     : board_t;
    signal status, undo_cnt : std_logic_vector(1 downto 0);
    signal dest_mask : std_logic_vector(63 downto 0);
    signal last_from, last_to, king_sq, cmd_from, cmd_to, cursor, sel_sq : std_logic_vector(5 downto 0);
    signal cmd_promo, promo_choice, result, prompt : std_logic_vector(1 downto 0);
    signal promo_active, ctl_idle, ev_move, ev_undo : std_logic;
    signal o_rights  : std_logic_vector(3 downto 0);
    signal o_epv     : std_logic;
    signal o_eps, o_ksqw, o_ksqb : std_logic_vector(5 downto 0);

    -- perintah ke mesin utama
    type cst_t is (C_IDLE, C_THINK, C_GENP, C_GENW1, C_GENW2, C_MOVP, C_MOVW1, C_MOVW2);
    signal cst     : cst_t := C_IDLE;
    signal mv_from, mv_to : std_logic_vector(5 downto 0) := (others => '0');
    signal c_gen, c_move, cpu_own, m_gen, m_move : std_logic;
    signal m_from, m_to : std_logic_vector(5 downto 0);
    signal m_promo : std_logic_vector(1 downto 0);

    signal w_time, b_time : std_logic_vector(15 downto 0);
    signal unlimited : std_logic;
    signal timeout : std_logic_vector(1 downto 0);
    signal over_top, clk_over : std_logic;

    -- ---- lawan komputer ----
    signal s_load, s_gen, s_smake, s_sunmake, s_chk, s_busy, s_turn, s_incheck : std_logic;
    signal s_from, s_to : std_logic_vector(5 downto 0);
    signal s_mask   : std_logic_vector(63 downto 0);
    signal s_board  : board_t;
    signal s_status, s_uc : std_logic_vector(1 downto 0);
    signal s_lv, s_ua, s_em, s_eu, s_epv : std_logic;
    signal s_l1, s_l2, s_ksq, s_eps, s_kw, s_kb : std_logic_vector(5 downto 0);
    signal s_rt : std_logic_vector(3 downto 0);
    signal cpu_start : std_logic := '0';
    signal cpu_done, cpu_busy : std_logic;
    signal cpu_bf, cpu_bt : std_logic_vector(5 downto 0);
    signal cpu_score : signed(15 downto 0);
    signal cpu_depth : std_logic_vector(2 downto 0);
    signal cpu_cond  : std_logic;
    signal play_ok, hb_ok, undo_ok, offer_ok : std_logic;
    signal modal_busy, btn_shortcut, btn_cursor_ok : std_logic;
    signal undo_edge_eff, offer_edge_eff, resign_edge_eff : std_logic;

    -- ---- popup Game Over ----
    signal popup_hide  : std_logic := '0';
    signal go_active, go_rst_hit, go_chk_hit, go_rst_trig : std_logic;
    signal go_white_won, go_black_won, go_is_draw : std_logic;

    -- ---- riwayat + replay ----
    signal h_count : std_logic_vector(9 downto 0);
    signal r_addr  : std_logic_vector(8 downto 0);
    signal r_data  : std_logic_vector(13 downto 0);
    signal tk_cnt  : integer range 0 to TICK_CLKS := 0;
    signal tk      : std_logic := '0';
    signal r_board : board_t;
    signal r_k     : std_logic_vector(9 downto 0);
    signal r_lv, r_auto, rp_ev : std_logic;
    signal r_lf, r_lt, rp_from, rp_to : std_logic_vector(5 downto 0);
    signal rp_piece : std_logic_vector(3 downto 0);
    signal rk_bcd, rc_bcd : std_logic_vector(11 downto 0);

    -- ---- animasi ----
    signal an_ev, an_on : std_logic;
    signal an_f, an_t, an_dst : std_logic_vector(5 downto 0);
    signal an_p, an_piece : std_logic_vector(3 downto 0);
    signal an_x, an_y, an_xe, an_ye : unsigned(10 downto 0);

    -- ---- VGA & bidak dimakan ----
    signal vx, vy : unsigned(10 downto 0);
    signal v_board : board_t;
    signal v_turn, v_sel_valid, v_last_valid, v_promo_active, v_show_cursor : std_logic;
    signal v_status, v_timeout, v_result, v_prompt : std_logic_vector(1 downto 0);
    signal v_last_from, v_last_to : std_logic_vector(5 downto 0);
    signal cap_by_w, cap_by_b : std_logic_vector(44 downto 0);
    signal w_adv, b_adv : unsigned(5 downto 0);

    -- ---- LED & 7-segmen ----
    signal led_cnt    : unsigned(24 downto 0) := (others => '0');
    signal cur_time   : std_logic_vector(15 downto 0);
    signal show_clock : std_logic;
    signal c3, c2, c1, c0 : std_logic_vector(4 downto 0);
    signal dpon : std_logic_vector(3 downto 0);

    function b2s(b : boolean) return std_logic is
    begin
        if b then return '1'; else return '0'; end if;
    end function;
    function ch5(s : std_logic_vector(3 downto 0)) return std_logic_vector is
    begin
        return '0' & s;
    end function;
    function add5(base : integer; v : std_logic_vector(2 downto 0)) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(base, 5) + resize(unsigned(v), 5));
    end function;
begin
    -- Sinkronisasi 2-FF untuk switch Basys 3
    sw_vec <= sw_rst & sw_resign & sw_remis & sw_undo & sw_menu;
    process (clk)
    begin
        if rising_edge(clk) then
            sw_s0 <= sw_vec;
            sw_s1 <= sw_s0;
            sw_s2 <= sw_s1;
            led_cnt <= led_cnt + 1;
        end if;
    end process;
    menu_open      <= sw_s1(0);
    sw_undo_edge   <= sw_s1(1) and not sw_s2(1);
    sw_remis_edge  <= sw_s1(2) and not sw_s2(2);
    sw_resign_edge <= sw_s1(3) and not sw_s2(3);
    sw_rst_edge    <= sw_s1(4) and not sw_s2(4);

    -- Tombol Basys 3
    d_u : entity work.debounce generic map (DEBOUNCE) port map (clk => clk, din => btnU, level => lu, pulse => pu);
    d_d : entity work.debounce generic map (DEBOUNCE) port map (clk => clk, din => btnD, level => ld, pulse => pd);
    d_l : entity work.debounce generic map (DEBOUNCE) port map (clk => clk, din => btnL, level => ll, pulse => pl);
    d_r : entity work.debounce generic map (DEBOUNCE) port map (clk => clk, din => btnR, level => lr, pulse => pr);
    d_c : entity work.debounce generic map (DEBOUNCE) port map (clk => clk, din => btnC, level => lc, pulse => pc);

    -- Pengendali mouse PS/2 (tidak di-reset oleh game_rst)
    u_ps2 : entity work.ps2_mouse
        generic map (INIT_WAIT_CLKS => PS2_INIT_WAIT, INHIBIT_CLKS => PS2_INHIBIT)
        port map (clk => clk, rst => '0', ps2_clk => PS2Clk, ps2_data => PS2Data,
                  mouse_x => mouse_x, mouse_y => mouse_y, mouse_sq => mouse_sq, mouse_inb => mouse_inb,
                  moved => mouse_moved, click_l => click_l, click_r => click_r, click_m => click_m,
                  btn_l => btn_l, btn_r => btn_r, scroll_up => scroll_up, scroll_dn => scroll_dn,
                  has_wheel => has_wheel, ready => mouse_ready);

    -- Hitbox popup Game Over & pemicu reset
    go_active   <= '1' when over_top = '1' and menu_open = '0' and replay_en = '0' else '0';
    go_rst_hit  <= '1' when click_l = '1' and mouse_x >= GO_RST_X0 and mouse_x <= GO_RST_X1 and
                            mouse_y >= GO_BTN_Y0 and mouse_y <= GO_BTN_Y1 else '0';
    go_chk_hit  <= '1' when click_l = '1' and mouse_x >= GO_CHK_X0 and mouse_x <= GO_CHK_X1 and
                            mouse_y >= GO_BTN_Y0 and mouse_y <= GO_BTN_Y1 else '0';
    go_rst_trig <= '1' when go_active = '1' and popup_hide = '0' and (pc = '1' or go_rst_hit = '1') else '0';
    rst_req     <= sw_rst_edge or go_rst_trig;

    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' or over_top = '0' then
                popup_hide <= '0';
            elsif go_active = '1' then
                if popup_hide = '0' and (go_chk_hit = '1' or click_r = '1' or pd = '1') then
                    popup_hide <= '1';
                elsif popup_hide = '1' and (pd = '1' or click_r = '1') then
                    popup_hide <= '0';
                end if;
            end if;
        end if;
    end process;

    -- Pengendali menu pengaturan 9 item (panah < > saat diklik)
    modal_busy   <= '1' when prompt /= "00" or promo_active = '1' else '0';
    btn_shortcut <= '1' when mouse_ready = '1' and menu_open = '0' and replay_en = '0' and
                             over_top = '0' and modal_busy = '0' else '0';
    pause_toggle <= pu and btn_shortcut;

    u_menu : entity work.menu_ctrl
        port map (clk => clk, menu_open => menu_open,
                  nav_up => pu or scroll_up, nav_dn => pd or scroll_dn,
                  act_next => pc or pr, act_prev => pl,
                  m_click_l => click_l, m_x => mouse_x, m_y => mouse_y,
                  pause_toggle => pause_toggle, rst_req => rst_req,
                  game_started => last_valid,
                  menu_idx => menu_idx, cpu_en => cpu_en, cpu_lvl => cpu_lvl,
                  preset => preset, theme => theme, hint_en => hint_en, anim_en => anim_en,
                  paused => paused, seg_cursor => seg_cursor, replay_en => replay_en,
                  game_rst => rst);

    -- ---- mesin catur utama ----
    c_gen   <= '1' when cst = C_GENP else '0';
    c_move  <= '1' when cst = C_MOVP else '0';
    cpu_own <= '0' when cst = C_IDLE else '1';
    m_gen   <= cmd_gen or c_gen;
    m_move  <= cmd_move or c_move;
    m_from  <= mv_from when cpu_own = '1' else cmd_from;
    m_to    <= mv_to   when cpu_own = '1' else cmd_to;
    m_promo <= "00"    when cpu_own = '1' else cmd_promo;

    u_eng : entity work.chess_engine
        port map (clk => clk, rst => rst, cmd_gen => m_gen, cmd_move => m_move, cmd_eval => '0', cmd_undo => cmd_undo,
                  cmd_from => m_from, cmd_to => m_to, cmd_promo => m_promo,
                  cmd_load => '0', ld_board => (others => '0'), ld_turn => '0', ld_rights => "0000", ld_epv => '0',
                  ld_eps => "000000", ld_ksqw => "000000", ld_ksqb => "000000",
                  cmd_smake => '0', cmd_sunmake => '0', cmd_chk => '0',
                  busy => busy, board => board, turn => turn, status => status, dest_mask => dest_mask,
                  last_valid => last_valid, last_from => last_from, last_to => last_to, king_sq => king_sq,
                  undo_avail => undo_avail, undo_cnt => undo_cnt, ev_move => ev_move, ev_undo => ev_undo,
                  o_rights => o_rights, o_epv => o_epv, o_eps => o_eps, o_ksqw => o_ksqw, o_ksqb => o_ksqb,
                  chk_out => open);

    clk_over <= '1' when status = "10" or status = "11" or result /= "00" else '0';
    over_top <= '1' when status = "10" or status = "11" or timeout /= "00" or result /= "00" else '0';

    -- ---- lawan komputer: mesin pencari kedua + pengendali ----
    u_srch : entity work.chess_engine
        port map (clk => clk, rst => rst, cmd_gen => s_gen, cmd_move => '0', cmd_eval => '0', cmd_undo => '0',
                  cmd_from => s_from, cmd_to => s_to, cmd_promo => "00",
                  cmd_load => s_load, ld_board => board, ld_turn => turn, ld_rights => o_rights, ld_epv => o_epv,
                  ld_eps => o_eps, ld_ksqw => o_ksqw, ld_ksqb => o_ksqb,
                  cmd_smake => s_smake, cmd_sunmake => s_sunmake, cmd_chk => s_chk,
                  busy => s_busy, board => s_board, turn => s_turn, status => s_status, dest_mask => s_mask,
                  last_valid => s_lv, last_from => s_l1, last_to => s_l2, king_sq => s_ksq,
                  undo_avail => s_ua, undo_cnt => s_uc, ev_move => s_em, ev_undo => s_eu,
                  o_rights => s_rt, o_epv => s_epv, o_eps => s_eps, o_ksqw => s_kw, o_ksqb => s_kb,
                  chk_out => s_incheck);

    cpu_depth <= "100" when cpu_lvl = '1' else "010";
    u_cpu : entity work.cpu_player
        port map (clk => clk, rst => rst, start => cpu_start, depth => cpu_depth, noise_en => not cpu_lvl,
                  e_load => s_load, e_gen => s_gen, e_smake => s_smake, e_sunmake => s_sunmake, e_chk => s_chk,
                  e_from => s_from, e_to => s_to, e_busy => s_busy, e_mask => s_mask, e_board => s_board,
                  e_turn => s_turn, e_incheck => s_incheck,
                  done => cpu_done, bm_from => cpu_bf, bm_to => cpu_bt, bm_score => cpu_score, busy => cpu_busy);

    cpu_cond <= '1' when cpu_en = '1' and turn = '1' and over_top = '0' and ctl_idle = '1' and paused = '0' and
                         replay_en = '0' and menu_open = '0' and busy = '0' and cpu_busy = '0' else '0';
    process (clk)
    begin
        if rising_edge(clk) then
            cpu_start <= '0';
            if rst = '1' then
                cst <= C_IDLE;
            else
                case cst is
                    when C_IDLE =>
                        if cpu_cond = '1' then cpu_start <= '1'; cst <= C_THINK; end if;
                    when C_THINK =>
                        if cpu_done = '1' then
                            mv_from <= cpu_bf;  mv_to <= cpu_bt;
                            if over_top = '1' then cst <= C_IDLE; else cst <= C_GENP; end if;
                        end if;
                    when C_GENP  => cst <= C_GENW1;
                    when C_GENW1 => cst <= C_GENW2;
                    when C_GENW2 => if busy = '0' then cst <= C_MOVP; end if;
                    when C_MOVP  => cst <= C_MOVW1;
                    when C_MOVW1 => cst <= C_MOVW2;
                    when C_MOVW2 => if busy = '0' then cst <= C_IDLE; end if;
                end case;
            end if;
        end if;
    end process;

    -- ---- pengendalian aksi board & fault tolerance mouse ----
    play_ok  <= '1' when replay_en = '0' and not (cpu_en = '1' and over_top = '0' and (turn = '1' or cpu_own = '1')) else '0';
    hb_ok    <= play_ok and not menu_open;
    undo_ok  <= '1' when replay_en = '0' and not (cpu_en = '1' and cpu_own = '1') else '0';
    offer_ok <= '1' when replay_en = '0' and cpu_en = '0' else '0';

    btn_cursor_ok   <= hb_ok and ((not mouse_ready) or modal_busy);
    undo_edge_eff   <= (sw_undo_edge   or (pl and btn_shortcut)) and undo_ok;
    offer_edge_eff  <= (sw_remis_edge  or (pr and btn_shortcut)) and offer_ok;
    resign_edge_eff <= (sw_resign_edge or (pd and btn_shortcut)) and play_ok;

    -- ---- jam catur ----
    u_clk : entity work.chess_clock
        generic map (TICK_CLKS => TICK_CLKS)
        port map (clk => clk, rst => rst, preset => preset, turn => turn, started => last_valid,
                  paused => paused or replay_en or menu_open,
                  game_over => clk_over,
                  w_time => w_time, b_time => b_time, unlimited => unlimited, timeout => timeout);

    u_ctl : entity work.game_ctrl
        port map (clk => clk, rst => rst,
                  b_up => pu and btn_cursor_ok, b_dn => pd and btn_cursor_ok,
                  b_lf => pl and btn_cursor_ok, b_rt => pr and btn_cursor_ok, b_ct => pc and btn_cursor_ok,
                  m_move_sq => mouse_moved and mouse_inb and hb_ok and (not over_top),
                  m_sq => mouse_sq,
                  m_x => mouse_x, m_y => mouse_y, m_inb => mouse_inb,
                  m_click_l => click_l and hb_ok and (not over_top),
                  m_click_r => click_r and hb_ok and (not over_top),
                  m_sc_up => scroll_up and hb_ok and (not over_top),
                  m_sc_dn => scroll_dn and hb_ok and (not over_top),
                  busy => busy, board => board, turn => turn, status => status, timeout => timeout,
                  undo_edge => undo_edge_eff,
                  resign_edge => resign_edge_eff, offer_edge => offer_edge_eff,
                  dest_mask => dest_mask, cpu_en => cpu_en, undo_cnt => undo_cnt,
                  cmd_gen => cmd_gen, cmd_move => cmd_move, cmd_undo => cmd_undo, cmd_from => cmd_from, cmd_to => cmd_to,
                  cmd_promo => cmd_promo,
                  cursor => cursor, sel_valid => sel_valid, sel_sq => sel_sq,
                  promo_active => promo_active, ctl_idle => ctl_idle, promo_choice => promo_choice,
                  result => result, prompt => prompt);

    u_hist : entity work.hist
        port map (clk => clk, rst => rst, push => ev_move, pdata => m_promo & m_to & m_from, pop => ev_undo,
                  count => h_count, raddr => r_addr, rdata => r_data);

    process (clk)
    begin
        if rising_edge(clk) then
            tk <= '0';
            if tk_cnt = TICK_CLKS - 1 then tk_cnt <= 0; tk <= '1'; else tk_cnt <= tk_cnt + 1; end if;
        end if;
    end process;

    u_rp : entity work.replay
        port map (clk => clk, rst => rst, active => replay_en, tick => tk,
                  step_f => (pr or scroll_dn) and not menu_open,
                  step_b => (pl or scroll_up) and not menu_open,
                  to_start => (pd or click_r) and not menu_open,
                  to_end => pu and not menu_open,
                  toggle_auto => (pc or click_l) and not menu_open,
                  count => h_count, raddr => r_addr, rdata => r_data,
                  rboard => r_board, rk => r_k, rl_valid => r_lv, rl_from => r_lf, rl_to => r_lt, auto_play => r_auto,
                  ev => rp_ev, ev_from => rp_from, ev_to => rp_to, ev_piece => rp_piece);
    u_b1 : entity work.bin2bcd port map (clk => clk, bin => r_k(8 downto 0), bcd => rk_bcd);
    u_b2 : entity work.bin2bcd port map (clk => clk, bin => h_count(8 downto 0), bcd => rc_bcd);

    -- ---- animasi ----
    an_ev <= rp_ev when replay_en = '1' else (ev_move and not replay_en);
    an_f  <= rp_from when replay_en = '1' else m_from;
    an_t  <= rp_to   when replay_en = '1' else m_to;
    an_p  <= rp_piece when replay_en = '1' else get_sq(board, m_from);
    u_an : entity work.anim
        port map (clk => clk, rst => rst, vs => vs, en => anim_en, ev => an_ev, ev_from => an_f, ev_to => an_t,
                  ev_piece => an_p, anim_on => an_on, x => an_x, y => an_y, xe => an_xe, ye => an_ye,
                  piece => an_piece, dst => an_dst);

    -- ---- VGA 800x600 @ 60 Hz & penghitung bidak dimakan ----
    u_mmcm : entity work.clk_vga_mmcm
        generic map (SIM_BYPASS => SIM_BYPASS)
        port map (clk_in => clk, pix_clk => pix_clk, pix_ce => pix_ce, locked => open);

    u_tim : entity work.vga_timing
        port map (pix_clk => pix_clk, pix_ce => pix_ce, x => vx, y => vy, hs => hs, vs => vs);

    v_board        <= r_board when replay_en = '1' else board;
    v_turn         <= r_k(0) when replay_en = '1' else turn;
    v_status       <= "00" when replay_en = '1' else status;
    v_sel_valid    <= sel_valid and not replay_en;
    v_last_valid   <= r_lv when replay_en = '1' else last_valid;
    v_last_from    <= r_lf when replay_en = '1' else last_from;
    v_last_to      <= r_lt when replay_en = '1' else last_to;
    v_timeout      <= "00" when replay_en = '1' else timeout;
    v_result       <= "00" when replay_en = '1' else result;
    v_prompt       <= "00" when replay_en = '1' else prompt;
    v_promo_active <= promo_active and not replay_en;
    v_show_cursor  <= not replay_en;

    u_cap : entity work.captured_calc
        port map (clk => clk, board => v_board,
                  cap_by_w => cap_by_w, cap_by_b => cap_by_b, w_adv => w_adv, b_adv => b_adv);

    u_rnd : entity work.vga_render
        port map (pix_clk => pix_clk, pix_ce => pix_ce, x => vx, y => vy, hs_in => hs, vs_in => vs,
                  board => v_board, turn => v_turn, status => v_status, king_sq => king_sq,
                  cursor => cursor, sel_valid => v_sel_valid, sel_sq => sel_sq, dest_mask => dest_mask,
                  hint_en => hint_en, last_valid => v_last_valid, last_from => v_last_from, last_to => v_last_to,
                  theme => theme, w_time => w_time, b_time => b_time, unlimited => unlimited,
                  paused => paused or replay_en or menu_open, timeout => v_timeout, result => v_result, prompt => v_prompt,
                  promo_active => v_promo_active, promo_choice => promo_choice,
                  show_cursor => v_show_cursor, popup_hide => popup_hide,
                  cpu_en => cpu_en, cpu_think => cpu_own, cpu_lvl => cpu_lvl,
                  replay => replay_en, r_auto => r_auto, rk_bcd => rk_bcd, rc_bcd => rc_bcd,
                  an_on => an_on, an_x => an_x, an_y => an_y, an_xe => an_xe, an_ye => an_ye,
                  an_piece => an_piece, an_dst => an_dst,
                  menu_open => menu_open, menu_idx => menu_idx, preset => preset,
                  anim_en => anim_en, seg_cursor => seg_cursor,
                  mouse_x => mouse_x, mouse_y => mouse_y, mouse_en => mouse_ready,
                  cap_by_w => cap_by_w, cap_by_b => cap_by_b, w_adv => w_adv, b_adv => b_adv,
                  vga_r => vgaRed, vga_g => vgaGreen, vga_b => vgaBlue, hsync => Hsync, vsync => Vsync);

    -- ---- LED & 7-segmen ----
    go_white_won <= '1' when (status = "10" and turn = '1') or timeout = "10" or result = "10" else '0';
    go_black_won <= '1' when (status = "10" and turn = '0') or timeout = "01" or result = "01" else '0';
    go_is_draw   <= '1' when (status = "11" or result = "11") and go_white_won = '0' and go_black_won = '0' else '0';

    process (all)
    begin
        if over_top = '1' and replay_en = '0' then
            if go_is_draw = '1' then
                if led_cnt(24) = '0' then led <= x"AAAA"; else led <= x"5555"; end if;
            elsif cpu_en = '1' and go_black_won = '1' then
                if led_cnt(23) = '0' then led <= x"FFFF"; else led <= x"0000"; end if;
            else
                if led_cnt(24) = '0' then led <= x"F0F0"; else led <= x"0F0F"; end if;
            end if;
        else
            led <= an_on & replay_en & cpu_own & promo_active &
                   b2s(result /= "00") & b2s(prompt /= "00") & undo_avail & b2s(timeout /= "00") &
                   paused & sel_valid & busy &
                   b2s(status = "11") & b2s(status = "10") & b2s(status = "01") & turn & (not turn);
        end if;
    end process;

    cur_time   <= b_time when turn = '1' else w_time;
    show_clock <= '1' when unlimited = '0' and seg_cursor = '0' else '0';

    process (all)
    begin
        if over_top = '1' and replay_en = '0' then
            dpon <= "0000";
            if go_is_draw = '1' then
                -- drAU
                c3 <= "01101"; c2 <= "11000"; c1 <= "01010"; c0 <= "10110";
            elsif cpu_en = '1' then
                if go_white_won = '1' then
                    -- _UIn
                    c3 <= "11111"; c2 <= "10110"; c1 <= "11010"; c0 <= "10111";
                else
                    -- LoSE
                    c3 <= "10011"; c2 <= "10100"; c1 <= "10101"; c0 <= "01110";
                end if;
            else
                if go_white_won = '1' then
                    -- P1__
                    c3 <= "11001"; c2 <= "00001"; c1 <= "11111"; c0 <= "11111";
                else
                    -- P2__
                    c3 <= "11001"; c2 <= "00010"; c1 <= "11111"; c0 <= "11111";
                end if;
            end if;
        else
            if show_clock = '1' then
                c3 <= ch5(cur_time(15 downto 12));
                c2 <= ch5(cur_time(11 downto 8));
                c1 <= ch5(cur_time(7 downto 4));
                c0 <= ch5(cur_time(3 downto 0));
                dpon <= "0100";
            else
                c3 <= add5(10, cursor(2 downto 0));
                c2 <= add5(1, cursor(5 downto 3));
                if sel_valid = '1' then
                    c1 <= add5(10, sel_sq(2 downto 0));
                    c0 <= add5(1, sel_sq(5 downto 3));
                else
                    c1 <= "10010";
                    c0 <= "10010";
                end if;
                dpon <= "0000";
            end if;
        end if;
    end process;

    u_seg : entity work.seg7_driver
        port map (clk => clk, c3 => c3, c2 => c2, c1 => c1, c0 => c0, dpon => dpon, dp => dp, seg => seg, an => an);

    -- ---- port pengamatan ----
    dbg.board <= board;  dbg.turn <= turn;  dbg.status <= status;  dbg.busy <= busy;
    dbg.cursor <= cursor;  dbg.sel_valid <= sel_valid;  dbg.sel_sq <= sel_sq;  dbg.dest_mask <= dest_mask;
    dbg.last_valid <= last_valid;  dbg.last_from <= last_from;  dbg.last_to <= last_to;
    dbg.rights <= o_rights;  dbg.ep_valid <= o_epv;  dbg.ep_sq <= o_eps;  dbg.ksq_w <= o_ksqw;  dbg.ksq_b <= o_ksqb;
    dbg.undo_avail <= undo_avail;  dbg.promo_active <= promo_active;  dbg.promo_choice <= promo_choice;
    dbg.prompt <= prompt;  dbg.result <= result;  dbg.timeout <= timeout;
    dbg.w_time <= w_time;  dbg.b_time <= b_time;  dbg.unlimited <= unlimited;  dbg.show_clock <= show_clock;
    dbg.h_count <= h_count;  dbg.r_k <= r_k;  dbg.r_board <= r_board;  dbg.r_auto <= r_auto;
    dbg.cst <= std_logic_vector(to_unsigned(cst_t'pos(cst), 3));
    dbg.cpu_start <= cpu_start;  dbg.cpu_done <= cpu_done;  dbg.cpu_bf <= cpu_bf;  dbg.cpu_bt <= cpu_bt;
    dbg.cpu_score <= cpu_score;  dbg.cpu_lvl <= cpu_lvl;
    dbg.an_on <= an_on;  dbg.an_x <= an_x;  dbg.an_y <= an_y;  dbg.an_piece <= an_piece;  dbg.an_dst <= an_dst;  dbg.pix_ce <= pix_ce;
    dbg.mouse_x <= mouse_x;  dbg.mouse_y <= mouse_y;  dbg.mouse_sq <= mouse_sq;  dbg.mouse_inb <= mouse_inb;
    dbg.mouse_ready <= mouse_ready;  dbg.has_wheel <= has_wheel;
    dbg.menu_open <= menu_open;  dbg.menu_idx <= menu_idx;  dbg.theme <= theme;
    dbg.hint_en <= hint_en;  dbg.anim_en <= anim_en;  dbg.paused <= paused;
    dbg.seg_cursor <= seg_cursor;  dbg.replay_en <= replay_en;  dbg.cpu_en <= cpu_en;  dbg.preset <= preset;
    dbg.popup_hide <= popup_hide;  dbg.over_top <= over_top;
    dbg.cap_by_w <= cap_by_w;  dbg.cap_by_b <= cap_by_b;  dbg.w_adv <= w_adv;  dbg.b_adv <= b_adv;
end rtl;
