-- =============================================================================
-- pseudo_legal.vhd
-- Cek "apakah bidak di src boleh bergerak ke dst" menurut gerakan bidak saja
-- (geometri + jalur tidak terhalang + tujuan bukan bidak sendiri).
-- Termasuk en passant (lewat ep_valid/ep_sq). TIDAK memeriksa rokade dan TIDAK memeriksa
-- apakah raja sendiri jadi terancam (itu tugas chess_engine).
--
-- Encoding bidak (4 bit): {warna, tipe[2:0]}
--   warna: 0 = putih, 1 = hitam
--   tipe : 0 kosong, 1 pion, 2 kuda, 3 gajah, 4 benteng, 5 ratu, 6 raja
-- Indeks kotak: sq = baris*8 + kolom (a1 = 0, h1 = 7, a8 = 56, h8 = 63)
--
-- Pipeline 6 tahap (tiap tahap logikanya pendek supaya muat di 100 MHz).
-- Pakai: tahan `board` stabil, beri pulsa `start` 1 clock bersama src/dst,
-- tunggu `done` (6 clock kemudian), baca `ok` dan `src_piece`.
-- =============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.chess_pkg.all;

entity pseudo_legal is
    port (
        clk       : in  std_logic;
        board     : in  board_t;
        start     : in  std_logic;
        src       : in  std_logic_vector(5 downto 0);
        dst       : in  std_logic_vector(5 downto 0);
        ep_valid  : in  std_logic;                       -- ada kotak en passant
        ep_sq     : in  std_logic_vector(5 downto 0);    -- kotak yang dilewati pion yang baru melangkah 2 petak
        done      : out std_logic;
        ok        : out std_logic;
        src_piece : out std_logic_vector(3 downto 0)
    );
end pseudo_legal;

architecture rtl of pseudo_legal is
    -- peta hunian (1 = ada bidak)
    signal occ_map : std_logic_vector(63 downto 0) := (others => '0');

    -- S0
    signal src_r, dst_r : std_logic_vector(5 downto 0) := (others => '0');
    signal v1 : std_logic := '0';

    -- S1
    signal ps1, pd1 : std_logic_vector(3 downto 0) := (others => '0');
    signal dx1, dy1 : std_logic_vector(3 downto 0) := (others => '0');
    signal sf1, sr1 : std_logic_vector(2 downto 0) := (others => '0');
    signal dst1     : std_logic_vector(5 downto 0) := (others => '0');
    signal v2       : std_logic := '0';

    -- S2
    signal ps2, pd2, dx2, dy2 : std_logic_vector(3 downto 0) := (others => '0');
    signal adx2, ady2, dist2, sf2, sr2 : unsigned(2 downto 0) := (others => '0');
    signal dst2 : std_logic_vector(5 downto 0) := (others => '0');
    signal sxp2, sxn2, syp2, syn2 : std_logic := '0';
    signal v3   : std_logic := '0';

    -- S3 (kombinasional dari register S2)
    signal t        : std_logic_vector(2 downto 0);
    signal c        : std_logic;
    signal d_empty, d_enemy, d_own, dx0, dy0, dy_f1, dy_f2, p_start : std_logic;
    signal ep_ok, pawn_ok, knight_ok, diag, orth, bishop_ok, rook_ok, queen_ok, king_ok : std_logic;
    signal geo3 : std_logic;

    type idx_arr_t is array (1 to 6) of std_logic_vector(5 downto 0);
    signal idx3  : idx_arr_t := (others => (others => '0'));
    signal act3  : std_logic_vector(6 downto 1) := (others => '0');
    signal geo3r : std_logic := '0';
    signal ps3   : std_logic_vector(3 downto 0) := (others => '0');
    signal v4    : std_logic := '0';

    -- S4
    signal blk4 : std_logic_vector(6 downto 1) := (others => '0');
    signal geo4 : std_logic := '0';
    signal ps4  : std_logic_vector(3 downto 0) := (others => '0');
    signal v5   : std_logic := '0';

    signal done_r, ok_r : std_logic := '0';
    signal sp_r : std_logic_vector(3 downto 0) := (others => '0');

    -- kotak ke-i di jalur: base + i (pos), base - i (neg), atau base
    function stepc(base : unsigned(2 downto 0); pos, neg : std_logic; i : integer) return std_logic_vector is
        variable ii : unsigned(2 downto 0) := to_unsigned(i, 3);
    begin
        if pos = '1' then return std_logic_vector(base + ii);
        elsif neg = '1' then return std_logic_vector(base - ii);
        else return std_logic_vector(base);
        end if;
    end function;

    function abs3(v : std_logic_vector(3 downto 0)) return unsigned is
    begin
        if v(3) = '1' then return (not unsigned(v(2 downto 0))) + 1;
        else return unsigned(v(2 downto 0));
        end if;
    end function;
begin
    done <= done_r;  ok <= ok_r;  src_piece <= sp_r;

    -- ---- peta hunian dihitung dari board ----
    process (clk)
    begin
        if rising_edge(clk) then
            for k in 0 to 63 loop
                occ_map(k) <= board(k * 4 + 2) or board(k * 4 + 1) or board(k * 4);
            end loop;
        end if;
    end process;

    -- ---- S0: tangkap src/dst ----
    process (clk)
    begin
        if rising_edge(clk) then
            v1 <= start;
            if start = '1' then src_r <= src; dst_r <= dst; end if;
        end if;
    end process;

    -- ---- S1: baca bidak + selisih koordinat ----
    process (clk)
    begin
        if rising_edge(clk) then
            v2   <= v1;
            ps1  <= get_sq(board, src_r);
            pd1  <= get_sq(board, dst_r);
            dx1  <= std_logic_vector(unsigned('0' & dst_r(2 downto 0)) - unsigned('0' & src_r(2 downto 0)));
            dy1  <= std_logic_vector(unsigned('0' & dst_r(5 downto 3)) - unsigned('0' & src_r(5 downto 3)));
            dst1 <= dst_r;
            sf1  <= src_r(2 downto 0);
            sr1  <= src_r(5 downto 3);
        end if;
    end process;

    -- ---- S2: nilai mutlak, tanda, jarak ----
    process (clk)
        variable ax, ay : unsigned(2 downto 0);
    begin
        if rising_edge(clk) then
            v3   <= v2;
            ps2  <= ps1;  pd2 <= pd1;  dx2 <= dx1;  dy2 <= dy1;
            sf2  <= unsigned(sf1);  sr2 <= unsigned(sr1);  dst2 <= dst1;
            ax := abs3(dx1);  ay := abs3(dy1);
            adx2 <= ax;  ady2 <= ay;
            sxn2 <= dx1(3);
            if dx1(3) = '0' and dx1(2 downto 0) /= "000" then sxp2 <= '1'; else sxp2 <= '0'; end if;
            syn2 <= dy1(3);
            if dy1(3) = '0' and dy1(2 downto 0) /= "000" then syp2 <= '1'; else syp2 <= '0'; end if;
            if ax > ay then dist2 <= ax; else dist2 <= ay; end if;
        end if;
    end process;

    -- ---- S3: geometri (kombinasional) ----
    t       <= ps2(2 downto 0);
    c       <= ps2(3);
    d_empty <= '1' when pd2(2 downto 0) = "000" else '0';
    d_enemy <= '1' when pd2(2 downto 0) /= "000" and pd2(3) /= c else '0';
    d_own   <= '1' when pd2(2 downto 0) /= "000" and pd2(3) = c else '0';
    dx0     <= '1' when dx2 = "0000" else '0';
    dy0     <= '1' when dy2 = "0000" else '0';
    dy_f1   <= '1' when (c = '1' and dy2 = "1111") or (c = '0' and dy2 = "0001") else '0';
    dy_f2   <= '1' when (c = '1' and dy2 = "1110") or (c = '0' and dy2 = "0010") else '0';
    p_start <= '1' when (c = '1' and sr2 = 6) or (c = '0' and sr2 = 1) else '0';
    -- en passant: serong 1 ke kotak kosong yang persis kotak ep (kotak ini tidak pernah
    -- berisi raja, jadi tidak pernah dihitung sebagai serangan ke raja)
    ep_ok   <= '1' when adx2 = 1 and dy_f1 = '1' and d_empty = '1' and ep_valid = '1' and dst2 = ep_sq else '0';
    pawn_ok <= '1' when (dx0 = '1' and dy_f1 = '1' and d_empty = '1') or
                        (dx0 = '1' and dy_f2 = '1' and p_start = '1' and d_empty = '1') or
                        (adx2 = 1 and dy_f1 = '1' and d_enemy = '1') or ep_ok = '1' else '0';
    knight_ok <= '1' when ((adx2 = 1 and ady2 = 2) or (adx2 = 2 and ady2 = 1)) and d_own = '0' else '0';
    diag      <= '1' when adx2 = ady2 and dx0 = '0' else '0';
    orth      <= dx0 xor dy0;
    bishop_ok <= diag and not d_own;
    rook_ok   <= orth and not d_own;
    queen_ok  <= (diag or orth) and not d_own;
    king_ok   <= '1' when adx2 <= 1 and ady2 <= 1 and not (dx0 = '1' and dy0 = '1') and d_own = '0' else '0';

    process (t, pawn_ok, knight_ok, bishop_ok, rook_ok, queen_ok, king_ok)
    begin
        case t is
            when "001"  => geo3 <= pawn_ok;
            when "010"  => geo3 <= knight_ok;
            when "011"  => geo3 <= bishop_ok;
            when "100"  => geo3 <= rook_ok;
            when "101"  => geo3 <= queen_ok;
            when "110"  => geo3 <= king_ok;
            when others => geo3 <= '0';
        end case;
    end process;

    process (clk)
    begin
        if rising_edge(clk) then
            v4    <= v3;
            geo3r <= geo3;
            ps3   <= ps2;
            for i in 1 to 6 loop
                idx3(i) <= stepc(sr2, syp2, syn2, i) & stepc(sf2, sxp2, sxn2, i);
                if i < to_integer(dist2) and t /= "010" then act3(i) <= '1'; else act3(i) <= '0'; end if;  -- kuda melompat
            end loop;
        end if;
    end process;

    -- ---- S4: apakah kotak perantara terisi ----
    process (clk)
    begin
        if rising_edge(clk) then
            v5   <= v4;
            geo4 <= geo3r;
            ps4  <= ps3;
            for j in 1 to 6 loop
                blk4(j) <= act3(j) and occ_map(to_integer(unsigned(idx3(j))));
            end loop;
        end if;
    end process;

    -- ---- S5: hasil ----
    process (clk)
    begin
        if rising_edge(clk) then
            done_r <= v5;
            if geo4 = '1' and blk4 = "000000" then ok_r <= '1'; else ok_r <= '0'; end if;
            sp_r   <= ps4;
        end if;
    end process;
end rtl;
