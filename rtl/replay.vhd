-- replay.vhd : memutar ulang permainan dari riwayat langkah.
--   active (sw9) = 1 : papan replay mulai dari posisi awal, memutar tiap langkah otomatis (tick 1 detik)
--   step_f / step_b  : maju / mundur satu langkah (menghentikan putar otomatis)
--   to_start / to_end: loncat ke awal / akhir
--   toggle_auto      : putar otomatis hidup/mati
-- Mundur = ulang dari awal sampai langkah target (instan, maks 511 x 3 clock).
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.chess_pkg.all;

entity replay is
    port (
        clk, rst, active : in std_logic;
        tick             : in std_logic;                        -- 1 denyut per detik
        step_f, step_b, to_start, to_end, toggle_auto : in std_logic;
        count            : in  std_logic_vector(9 downto 0);
        raddr            : out std_logic_vector(8 downto 0);
        rdata            : in  std_logic_vector(13 downto 0);
        rboard           : out board_t;
        rk               : out std_logic_vector(9 downto 0);    -- jumlah langkah yang sudah diputar
        rl_valid         : out std_logic;
        rl_from, rl_to   : out std_logic_vector(5 downto 0);
        auto_play        : out std_logic;
        -- event animasi
        ev               : out std_logic;
        ev_from, ev_to   : out std_logic_vector(5 downto 0);
        ev_piece         : out std_logic_vector(3 downto 0)
    );
end replay;

architecture rtl of replay is
    signal rboard_r : board_t := INIT_BOARD;
    signal rk_r     : unsigned(9 downto 0) := (others => '0');
    signal target   : unsigned(9 downto 0) := (others => '0');
    signal st       : unsigned(1 downto 0) := (others => '0');
    signal back     : std_logic := '0';                         -- sedang mengulang dari awal karena mundur
    signal auto_r   : std_logic := '1';
    signal rlv_r    : std_logic := '0';
    signal rlf_r, rlt_r : std_logic_vector(5 downto 0) := (others => '0');
    signal ev_r     : std_logic := '0';
    signal evf_r, evt_r : std_logic_vector(5 downto 0) := (others => '0');
    signal evp_r    : std_logic_vector(3 downto 0) := (others => '0');
    signal cnt_u    : unsigned(9 downto 0);
begin
    cnt_u    <= unsigned(count);
    raddr    <= std_logic_vector(rk_r(8 downto 0));
    rboard   <= rboard_r;  rk <= std_logic_vector(rk_r);
    rl_valid <= rlv_r;  rl_from <= rlf_r;  rl_to <= rlt_r;
    auto_play <= auto_r;
    ev <= ev_r;  ev_from <= evf_r;  ev_to <= evt_r;  ev_piece <= evp_r;

    process (clk)
        variable ptype : std_logic_vector(2 downto 0);
    begin
        if rising_edge(clk) then
            ev_r <= '0';
            if rst = '1' or active = '0' then
                rboard_r <= INIT_BOARD;  rk_r <= (others => '0');  target <= (others => '0');
                auto_r <= '1';  rlv_r <= '0';  rlf_r <= (others => '0');  rlt_r <= (others => '0');
                st <= (others => '0');  back <= '0';
                evf_r <= (others => '0');  evt_r <= (others => '0');  evp_r <= (others => '0');
            else
                -- ---- kontrol ----
                if step_f = '1' then
                    if target < cnt_u then target <= target + 1; end if;
                    auto_r <= '0';
                elsif step_b = '1' then
                    if target /= 0 then target <= target - 1; end if;
                    auto_r <= '0';
                elsif to_start = '1' then
                    target <= (others => '0');  auto_r <= '0';
                elsif to_end = '1' then
                    target <= cnt_u;  auto_r <= '0';
                elsif toggle_auto = '1' then
                    auto_r <= not auto_r;
                    if auto_r = '0' and target >= cnt_u then target <= (others => '0'); end if;
                elsif tick = '1' and auto_r = '1' then
                    if target < cnt_u then target <= target + 1; else auto_r <= '0'; end if;
                end if;
                -- ---- mesin pemutar ----
                case to_integer(st) is
                when 0 =>
                    if rk_r > target then
                        rboard_r <= INIT_BOARD;  rk_r <= (others => '0');  rlv_r <= '0';  back <= '1';
                    elsif rk_r < target then
                        st <= to_unsigned(1, 2);
                    else
                        back <= '0';
                    end if;
                when 1 =>
                    st <= to_unsigned(2, 2);                    -- tunggu data BRAM
                when 2 =>
                    ptype := std_logic_vector(to_unsigned(5, 3) - resize(unsigned(rdata(13 downto 12)), 3));
                    rboard_r <= apply_full(rboard_r, rdata(5 downto 0), rdata(11 downto 6), ptype, '1');
                    rk_r     <= rk_r + 1;
                    rlv_r    <= '1';  rlf_r <= rdata(5 downto 0);  rlt_r <= rdata(11 downto 6);
                    if back = '0' and (rk_r + 1 = target) then
                        ev_r  <= '1';  evf_r <= rdata(5 downto 0);  evt_r <= rdata(11 downto 6);
                        evp_r <= get_sq(rboard_r, rdata(5 downto 0));
                    end if;
                    st <= (others => '0');
                when others =>
                    st <= (others => '0');
                end case;
            end if;
        end if;
    end process;
end rtl;
