-- tb_menu_ctrl.vhd : uji unit menu_ctrl 9 item (klik baris pilih saja, klik < / > ubah nilai, tanpa hover-override).
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_menu_ctrl is
end tb_menu_ctrl;

architecture sim of tb_menu_ctrl is
    signal clk, menu_open : std_logic := '0';
    signal nav_up, nav_dn, act_next, act_prev, m_click_l : std_logic := '0';
    signal m_x, m_y : unsigned(10 downto 0) := (others => '0');
    signal pause_toggle, rst_req, game_started : std_logic := '0';
    signal menu_idx : unsigned(3 downto 0);
    signal cpu_en, cpu_lvl, hint_en, anim_en, paused, seg_cursor, replay_en, game_rst : std_logic;
    signal preset : std_logic_vector(2 downto 0);
    signal theme  : std_logic_vector(1 downto 0);
    signal fin : boolean := false;
begin
    clk <= not clk after 5 ns when not fin;

    dut : entity work.menu_ctrl
        port map (
            clk => clk, menu_open => menu_open,
            nav_up => nav_up, nav_dn => nav_dn, act_next => act_next, act_prev => act_prev,
            m_click_l => m_click_l, m_x => m_x, m_y => m_y,
            pause_toggle => pause_toggle, rst_req => rst_req, game_started => game_started,
            menu_idx => menu_idx, cpu_en => cpu_en, cpu_lvl => cpu_lvl,
            preset => preset, theme => theme, hint_en => hint_en, anim_en => anim_en,
            paused => paused, seg_cursor => seg_cursor, replay_en => replay_en, game_rst => game_rst
        );

    main : process
        procedure check(c : boolean; msg : string) is
        begin
            if not c then
                report "GAGAL tb_menu_ctrl: " & msg severity failure;
            end if;
        end procedure;

        procedure step(nu, nd, an, ap, mc : std_logic; x, y : integer; pt, rr : std_logic) is
        begin
            nav_up <= nu; nav_dn <= nd; act_next <= an; act_prev <= ap;
            m_click_l <= mc; m_x <= to_unsigned(x, 11); m_y <= to_unsigned(y, 11);
            pause_toggle <= pt; rst_req <= rr;
            wait until rising_edge(clk);
            nav_up <= '0'; nav_dn <= '0'; act_next <= '0'; act_prev <= '0';
            m_click_l <= '0'; pause_toggle <= '0'; rst_req <= '0';
            wait for 1 ns;
        end procedure;
    begin
        -- Startup reset 4 clock
        wait for 1 ns;
        check(game_rst = '1', "game_rst startup harus aktif");
        for k in 0 to 4 loop wait until rising_edge(clk); end loop;
        wait for 1 ns;
        check(game_rst = '0', "game_rst startup harus selesai");

        -- Menu tertutup: input menu diabaikan, pause_toggle bekerja
        menu_open <= '0';
        step('0', '1', '1', '0', '1', 460, 264, '0', '0');
        check(menu_idx = 0 and cpu_en = '0' and theme = "00", "Input saat menu tertutup harus diabaikan");
        step('0', '0', '0', '0', '0', 0, 0, '1', '0');
        check(paused = '1', "pause_toggle shortcut harus ubah paused");
        step('0', '0', '0', '0', '0', 0, 0, '1', '0');
        check(paused = '0', "pause_toggle kedua kembalikan paused ke 0");

        -- Buka menu
        menu_open <= '1';

        -- Hover mouse tanpa klik TIDAK boleh menggeser menu_idx
        step('0', '0', '0', '0', '0', 460, 264, '0', '0');
        check(menu_idx = 0, "Hover tanpa klik tidak boleh ubah menu_idx");

        -- Klik baris 3 (TEMA, y=264) tepat di posisi '>' (460): pertama kali HANYA sorot baris 3
        step('0', '0', '0', '0', '1', 460, 264, '0', '0');
        check(menu_idx = 3 and theme = "00", "Klik baris baru hanya sorot baris dan tampilkan < > tanpa ubah nilai");

        -- Klik '>' pada baris aktif (3): tema maju "00" -> "01"
        step('0', '0', '0', '0', '1', 460, 264, '0', '0');
        check(theme = "01", "Klik > harus memajukan tema ke 01");

        -- Klik '<' (x=304) pada baris aktif (3): tema mundur "01" -> "00" -> "11"
        step('0', '0', '0', '0', '1', 304, 264, '0', '0');
        check(theme = "00", "Klik < harus mundurkan tema ke 00");
        step('0', '0', '0', '0', '1', 304, 264, '0', '0');
        check(theme = "11", "Klik < dari 00 wrap ke 11");

        -- Uji wrap tombol pada 9 item (0..8)
        step('0', '0', '0', '0', '1', 200, 216, '0', '0'); -- klik baris 0
        check(menu_idx = 0, "Klik label baris 0 harus sorot 0");
        step('1', '0', '0', '0', '0', 0, 0, '0', '0');
        check(menu_idx = 8, "nav_up di 0 wrap ke 8");
        step('0', '0', '1', '0', '0', 0, 0, '0', '0'); -- item 8 (REPLAY) ON
        check(replay_en = '1', "REPLAY toggle ke 1");

        -- Uji WAKTU auto-reset saat game_started = '0'
        step('0', '0', '0', '0', '1', 200, 248, '0', '0'); -- pilih baris 2 (WAKTU)
        check(menu_idx = 2, "Sorot WAKTU");
        game_started <= '0';
        step('0', '0', '0', '0', '1', 460, 248, '0', '0'); -- klik '>' pada baris 2
        check(preset = "001" and game_rst = '1', "Ubah WAKTU sebelum main harus memicu game_rst");
        for k in 0 to 4 loop wait until rising_edge(clk); end loop;
        wait for 1 ns;
        game_started <= '1';
        step('0', '0', '0', '0', '1', 460, 248, '0', '0');
        check(preset = "010" and game_rst = '0', "Ubah WAKTU setelah mulai tidak auto-reset");

        -- Uji rst_req (menutup replay_en & paused, mempertahankan theme & preset)
        menu_open <= '0';
        step('0', '0', '0', '0', '0', 0, 0, '0', '1');
        check(game_rst = '1' and replay_en = '0' and theme = "11" and preset = "010",
              "rst_req harus reset permainan sambil mempertahankan preferensi");

        report "PASS tb_menu_ctrl";
        fin <= true;
        wait;
    end process;
end sim;
