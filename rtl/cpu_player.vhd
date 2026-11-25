-- =============================================================================
-- cpu_player.vhd : pencari langkah untuk lawan komputer (negamax + alpha-beta).
--
-- Memakai chess_engine kedua (mesin pencari) lewat perintah load / gen / smake / sunmake / chk:
--   1. start -> posisi mesin utama disalin ke mesin pencari (cmd_load, lewat jalur ld_* di top)
--   2. tiap simpul: untuk tiap kotak asal 0..63, cmd_gen memberi semua tujuan legal (dest_mask);
--      tiap tujuan dijalankan (smake), dicari lebih dalam, lalu dibatalkan (sunmake)
--   3. daun (kedalaman habis): evaluasi statis = materi + bonus posisi sederhana
--   4. simpul tanpa langkah legal: skakmat = -(MATE - kedalaman), pat = 0
-- Urutan langkah: kotak asal naik, tujuan naik. Promosi selalu jadi ratu.
-- Selesai: done = 1 clock, bm_from/bm_to = langkah terbaik, bm_score = nilainya (sudut pandang
-- pemain yang jalan, satuan sentipion).
-- Evaluasi (dari sudut pandang putih, lalu dinegasikan bila hitam yang jalan), c = kedekatan ke
-- pusat (0..6):   pion 100 + 6*(maju)   kuda 320 + 6c   gajah 330 + 3c   benteng 500   ratu 900
--                 raja -4c
-- =============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.chess_pkg.all;

entity cpu_player is
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        start     : in  std_logic;
        depth     : in  std_logic_vector(2 downto 0);   -- jumlah ply (1..5)
        noise_en  : in  std_logic;                      -- tambah acak kecil pada nilai langkah akar (variasi)
        -- ke mesin pencari
        e_load    : out std_logic := '0';
        e_gen     : out std_logic := '0';
        e_smake   : out std_logic := '0';
        e_sunmake : out std_logic := '0';
        e_chk     : out std_logic := '0';
        e_from    : out std_logic_vector(5 downto 0) := (others => '0');
        e_to      : out std_logic_vector(5 downto 0) := (others => '0');
        e_busy    : in  std_logic;
        e_mask    : in  std_logic_vector(63 downto 0);
        e_board   : in  board_t;
        e_turn    : in  std_logic;
        e_incheck : in  std_logic;
        -- hasil
        done      : out std_logic := '0';
        bm_from   : out std_logic_vector(5 downto 0) := (others => '0');
        bm_to     : out std_logic_vector(5 downto 0) := (others => '0');
        bm_score  : out signed(15 downto 0) := (others => '0');
        busy      : out std_logic
    );
end cpu_player;

architecture rtl of cpu_player is
    constant INF  : signed(15 downto 0) := to_signed(32000, 16);
    constant MATE : signed(15 downto 0) := to_signed(30000, 16);

    type state_t is (ST_IDLE, ST_LOAD1, ST_LOAD2, ST_LOAD3, ST_ENTER, ST_GEN1, ST_GEN2, ST_GEN3, ST_PICK,
                     ST_MAKE1, ST_MAKE2, ST_MAKE3, ST_EV, ST_NODEEND, ST_CHK1, ST_CHK2, ST_CHK3, ST_RET,
                     ST_UNMK1, ST_UNMK2, ST_UNMK3, ST_DONE);
    signal st : state_t := ST_IDLE;

    type s16_arr  is array (0 to 7) of signed(15 downto 0);
    type sq_arr   is array (0 to 7) of std_logic_vector(5 downto 0);
    type m64_arr  is array (0 to 7) of std_logic_vector(63 downto 0);

    signal d, depth_r : unsigned(2 downto 0) := (others => '0');
    signal alpha_a, beta_a, best_a : s16_arr := (others => (others => '0'));
    signal mfrom_a, mto_a : sq_arr  := (others => (others => '0'));
    signal mmask_a        : m64_arr := (others => (others => '0'));
    signal any_a          : std_logic_vector(7 downto 0) := (others => '0');
    signal retval, acc    : signed(15 downto 0) := (others => '0');
    signal sq             : unsigned(5 downto 0) := (others => '0');
    signal lfsr           : std_logic_vector(15 downto 0) := x"ACE1";
    signal done_r         : std_logic := '0';

    -- indeks bit terendah yang bernilai 1 (0 bila tidak ada)
    function ctz64(m : std_logic_vector(63 downto 0)) return std_logic_vector is
        variable r : integer := 0;
    begin
        for i in 63 downto 0 loop
            if m(i) = '1' then r := i; end if;
        end loop;
        return std_logic_vector(to_unsigned(r, 6));
    end function;

    -- nilai bidak di kotak s dari sudut pandang putih (bidak hitam negatif)
    function pval(p : std_logic_vector(3 downto 0); s : unsigned(5 downto 0)) return signed is
        variable f, r, rr, cf, cr : integer;
        variable c, v : integer;
    begin
        f := to_integer(s(2 downto 0));  r := to_integer(s(5 downto 3));
        if p(3) = '1' then rr := 7 - r; else rr := r; end if;
        if f < 4 then cf := f; else cf := 7 - f; end if;
        if r < 4 then cr := r; else cr := 7 - r; end if;
        c := cf + cr;
        case p(2 downto 0) is
            when "001"  => v := 100 + 6 * (rr - 1);
            when "010"  => v := 320 + 6 * c;
            when "011"  => v := 330 + 3 * c;
            when "100"  => v := 500;
            when "101"  => v := 900;
            when "110"  => v := -4 * c;
            when others => v := 0;
        end case;
        if p(3) = '1' then v := -v; end if;
        return to_signed(v, 16);
    end function;

    signal ev_piece : std_logic_vector(3 downto 0);
    signal ev_delta : signed(15 downto 0);
begin
    busy <= '0' when st = ST_IDLE else '1';
    done <= done_r;

    ev_piece <= get_sq(e_board, std_logic_vector(sq));
    ev_delta <= pval(ev_piece, sq);

    process (clk)
        variable v, na, vq : signed(15 downto 0);
        variable t         : std_logic_vector(5 downto 0);
        variable di        : integer;
    begin
        if rising_edge(clk) then
            lfsr <= lfsr(14 downto 0) & (lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10));
            di := to_integer(d);
            if rst = '1' then
                st <= ST_IDLE;  d <= (others => '0');  depth_r <= to_unsigned(2, 3);  done_r <= '0';
                e_load <= '0';  e_gen <= '0';  e_smake <= '0';  e_sunmake <= '0';  e_chk <= '0';
                e_from <= (others => '0');  e_to <= (others => '0');
                bm_from <= (others => '0');  bm_to <= (others => '0');  bm_score <= (others => '0');
                retval <= (others => '0');  acc <= (others => '0');  sq <= (others => '0');
                lfsr <= x"ACE1";
            else
                e_load <= '0';  e_gen <= '0';  e_smake <= '0';  e_sunmake <= '0';  e_chk <= '0';
                done_r <= '0';
                case st is
                when ST_IDLE =>
                    if start = '1' then depth_r <= unsigned(depth); st <= ST_LOAD1; end if;
                when ST_LOAD1 => e_load <= '1'; st <= ST_LOAD2;
                when ST_LOAD2 => st <= ST_LOAD3;
                when ST_LOAD3 =>
                    d <= (others => '0');  alpha_a(0) <= -INF;  beta_a(0) <= INF;
                    bm_from <= (others => '0');  bm_to <= (others => '0');
                    st <= ST_ENTER;
                -- ---------------- masuk simpul pada ply d ----------------
                when ST_ENTER =>
                    if d = depth_r then
                        sq <= (others => '0');  acc <= (others => '0');  st <= ST_EV;
                    else
                        best_a(di) <= -INF;  any_a(di) <= '0';  mfrom_a(di) <= (others => '0');
                        mmask_a(di) <= (others => '0');
                        st <= ST_GEN1;
                    end if;
                -- ---------------- bangkitkan tujuan dari kotak mfrom ----------------
                when ST_GEN1 => e_gen <= '1';  e_from <= mfrom_a(di);  st <= ST_GEN2;
                when ST_GEN2 => st <= ST_GEN3;
                when ST_GEN3 =>
                    if e_busy = '0' then mmask_a(di) <= e_mask;  st <= ST_PICK; end if;
                when ST_PICK =>
                    if mmask_a(di) = x"0000000000000000" then
                        if mfrom_a(di) = "111111" then st <= ST_NODEEND;
                        else mfrom_a(di) <= std_logic_vector(unsigned(mfrom_a(di)) + 1);  st <= ST_GEN1;
                        end if;
                    else
                        t := ctz64(mmask_a(di));
                        mto_a(di)   <= t;
                        mmask_a(di) <= mmask_a(di) and std_logic_vector(unsigned(mmask_a(di)) - 1);
                        any_a(di)   <= '1';
                        st <= ST_MAKE1;
                    end if;
                -- ---------------- jalankan langkah, turun ----------------
                when ST_MAKE1 =>
                    e_smake <= '1';  e_from <= mfrom_a(di);  e_to <= mto_a(di);  st <= ST_MAKE2;
                when ST_MAKE2 => st <= ST_MAKE3;
                when ST_MAKE3 =>
                    alpha_a(to_integer(d + 1)) <= -beta_a(di);
                    beta_a(to_integer(d + 1))  <= -alpha_a(di);
                    d  <= d + 1;
                    st <= ST_ENTER;
                -- ---------------- daun: evaluasi statis ----------------
                when ST_EV =>
                    acc <= acc + ev_delta;
                    if sq = 63 then
                        if e_turn = '1' then retval <= -(acc + ev_delta); else retval <= acc + ev_delta; end if;
                        st <= ST_RET;
                    else
                        sq <= sq + 1;
                    end if;
                -- ---------------- semua langkah simpul sudah dicoba ----------------
                when ST_NODEEND =>
                    if any_a(di) = '1' then retval <= best_a(di);  st <= ST_RET;
                    else st <= ST_CHK1;
                    end if;
                when ST_CHK1 => e_chk <= '1';  st <= ST_CHK2;
                when ST_CHK2 => st <= ST_CHK3;
                when ST_CHK3 =>
                    if e_busy = '0' then
                        if e_incheck = '1' then retval <= -(MATE - signed(resize(d, 16)));
                        else retval <= (others => '0');
                        end if;
                        st <= ST_RET;
                    end if;
                -- ---------------- kembali ke simpul induk ----------------
                when ST_RET =>
                    if d = 0 then bm_score <= retval;  st <= ST_DONE;
                    else d <= d - 1;  st <= ST_UNMK1;
                    end if;
                when ST_UNMK1 => e_sunmake <= '1';  st <= ST_UNMK2;
                when ST_UNMK2 => st <= ST_UNMK3;
                when ST_UNMK3 =>
                    v := -retval;
                    if d = 0 and noise_en = '1' then v := v + signed(resize(unsigned(lfsr(3 downto 0)), 16)); end if;
                    if v > best_a(di) then
                        best_a(di) <= v;
                        if d = 0 then bm_from <= mfrom_a(0);  bm_to <= mto_a(0); end if;
                    end if;
                    -- Dengan acak: jendela akar tidak boleh ikut terdorong oleh nilai acak. Pakai nilai asli - 16
                    -- supaya semua langkah yang selisihnya < 16 dari terbaik dihitung eksak (acak hanya 0..15).
                    if d = 0 and noise_en = '1' then vq := (-retval) - to_signed(16, 16); else vq := v; end if;
                    if vq > alpha_a(di) then na := vq; else na := alpha_a(di); end if;
                    alpha_a(di) <= na;
                    if na >= beta_a(di) then st <= ST_NODEEND; else st <= ST_PICK; end if;
                when ST_DONE =>
                    done_r <= '1';  st <= ST_IDLE;
                end case;
            end if;
        end if;
    end process;
end rtl;
