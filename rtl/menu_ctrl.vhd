-- menu_ctrl.vhd : Pengelola 9 opsi pengaturan via SW0 (menu_open).
--   Panah < dan > hanya muncul pada baris aktif yang sedang dipilih/diklik.
--   Klik baris belum aktif -> sorot baris itu saja (tidak langsung mengubah nilai, bebas hover-override).
--   Klik < pada baris aktif -> nilai sebelumnya; klik > atau nilai -> nilai berikutnya/toggle.
--   Daftar 9 item (menu_idx 0..8):
--     0 MODE     : 2 PEMAIN / KOMPUTER (cpu_en)
--     1 CPU LVL  : TINGKAT 1 / TINGKAT 2 (cpu_lvl)
--     2 WAKTU    : OFF, 1M, 3M, 5M, 10M, 15M, 30M, 60M (preset 0..7)
--     3 TEMA     : KLASIK, HIJAU, BIRU, ABU (theme 0..3)
--     4 HINT     : ON / OFF (hint_en)
--     5 ANIMASI  : ON / OFF (anim_en)
--     6 JEDA JAM : ON / OFF (paused)
--     7 7-SEGMEN : JAM / KURSOR (seg_cursor)
--     8 REPLAY   : ON / OFF (replay_en)
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.chess_pkg.all;

entity menu_ctrl is
    port (
        clk          : in  std_logic;
        menu_open    : in  std_logic;
        nav_up       : in  std_logic;
        nav_dn       : in  std_logic;
        act_next     : in  std_logic;
        act_prev     : in  std_logic;
        m_click_l    : in  std_logic;
        m_x, m_y     : in  unsigned(10 downto 0);
        pause_toggle : in  std_logic;
        rst_req      : in  std_logic;
        game_started : in  std_logic;
        menu_idx     : out unsigned(3 downto 0) := (others => '0');
        cpu_en       : out std_logic := '0';
        cpu_lvl      : out std_logic := '0';
        preset       : out std_logic_vector(2 downto 0) := "000";
        theme        : out std_logic_vector(1 downto 0) := "00";
        hint_en      : out std_logic := '1';
        anim_en      : out std_logic := '1';
        paused       : out std_logic := '0';
        seg_cursor   : out std_logic := '0';
        replay_en    : out std_logic := '0';
        game_rst     : out std_logic := '0'
    );
end menu_ctrl;

architecture rtl of menu_ctrl is
    constant MAX_IDX : integer := 8;

    signal idx_r        : unsigned(3 downto 0) := (others => '0');
    signal cpu_en_r     : std_logic := '0';
    signal cpu_lvl_r    : std_logic := '0';
    signal preset_r     : std_logic_vector(2 downto 0) := "000";
    signal theme_r      : std_logic_vector(1 downto 0) := "00";
    signal hint_en_r    : std_logic := '1';
    signal anim_en_r    : std_logic := '1';
    signal paused_r     : std_logic := '0';
    signal seg_cursor_r : std_logic := '0';
    signal replay_en_r  : std_logic := '0';
    signal rst_cnt      : unsigned(2 downto 0) := to_unsigned(4, 3); -- reset awal 4 clock saat startup
begin
    menu_idx   <= idx_r;
    cpu_en     <= cpu_en_r;
    cpu_lvl    <= cpu_lvl_r;
    preset     <= preset_r;
    theme      <= theme_r;
    hint_en    <= hint_en_r;
    anim_en    <= anim_en_r;
    paused     <= paused_r;
    seg_cursor <= seg_cursor_r;
    replay_en  <= replay_en_r;
    game_rst   <= '1' when rst_cnt /= 0 else '0';

    process (clk)
        variable trig_next, trig_prev, do_act : std_logic;
        variable rel_y       : unsigned(10 downto 0);
        variable clicked_row : unsigned(3 downto 0);
    begin
        if rising_edge(clk) then
            if rst_cnt /= 0 then
                rst_cnt <= rst_cnt - 1;
            end if;

            -- Reset eksplisit dari SW15 atau tombol [MAIN LAGI]
            if rst_req = '1' then
                rst_cnt     <= to_unsigned(4, 3);
                replay_en_r <= '0';
                paused_r    <= '0';
            elsif menu_open = '0' and pause_toggle = '1' then
                paused_r <= not paused_r;
            end if;

            if menu_open = '1' then
                trig_next := act_next;
                trig_prev := act_prev;

                -- Navigasi tombol/scroll
                if nav_up = '1' and nav_dn = '0' then
                    if idx_r = 0 then
                        idx_r <= to_unsigned(MAX_IDX, 4);
                    else
                        idx_r <= idx_r - 1;
                    end if;
                elsif nav_dn = '1' and nav_up = '0' then
                    if idx_r = MAX_IDX then
                        idx_r <= (others => '0');
                    else
                        idx_r <= idx_r + 1;
                    end if;
                end if;

                -- Klik langsung pada baris menu (tanpa hover-override)
                if m_click_l = '1' and m_y >= MENU_IY0 and m_y <= MENU_IY1 and
                   m_x >= MENU_TX0 and m_x <= MENU_TX1 then
                    rel_y := m_y - MENU_IY0;
                    clicked_row := rel_y(7 downto 4);
                    if clicked_row <= MAX_IDX then
                        if clicked_row /= idx_r then
                            idx_r <= clicked_row; -- klik baris baru: sorot saja & munculkan < >
                        else
                            if m_x >= MENU_PRVX0 and m_x <= MENU_PRVX1 then
                                trig_prev := '1';
                            elsif m_x >= MENU_VALX0 and m_x <= MENU_NXTX1 then
                                trig_next := '1';
                            end if;
                        end if;
                    end if;
                end if;

                do_act := trig_next or trig_prev;
                case to_integer(idx_r) is
                    when 0 =>
                        if do_act = '1' then cpu_en_r <= not cpu_en_r; end if;
                    when 1 =>
                        if do_act = '1' then cpu_lvl_r <= not cpu_lvl_r; end if;
                    when 2 =>
                        if trig_next = '1' then
                            preset_r <= std_logic_vector(unsigned(preset_r) + 1);
                            if game_started = '0' then rst_cnt <= to_unsigned(4, 3); end if;
                        elsif trig_prev = '1' then
                            preset_r <= std_logic_vector(unsigned(preset_r) - 1);
                            if game_started = '0' then rst_cnt <= to_unsigned(4, 3); end if;
                        end if;
                    when 3 =>
                        if trig_next = '1' then
                            theme_r <= std_logic_vector(unsigned(theme_r) + 1);
                        elsif trig_prev = '1' then
                            theme_r <= std_logic_vector(unsigned(theme_r) - 1);
                        end if;
                    when 4 =>
                        if do_act = '1' then hint_en_r <= not hint_en_r; end if;
                    when 5 =>
                        if do_act = '1' then anim_en_r <= not anim_en_r; end if;
                    when 6 =>
                        if do_act = '1' then paused_r <= not paused_r; end if;
                    when 7 =>
                        if do_act = '1' then seg_cursor_r <= not seg_cursor_r; end if;
                    when 8 =>
                        if do_act = '1' then replay_en_r <= not replay_en_r; end if;
                    when others =>
                        null;
                end case;
            end if;
        end if;
    end process;
end rtl;
