-- captured_calc.vhd : Menghitung daftar bidak yang sudah dimakan beserta selisih materi
--   langsung dari keadaan papan (otomatis sinkron dengan undo, promosi, replay, dan reset).
--   cap_by_w : 15 slot x 3 bit (bit [3i+2:3i]) berisi bidak hitam yang dimakan Putih.
--   cap_by_b : 15 slot x 3 bit (bit [3i+2:3i]) berisi bidak putih yang dimakan Hitam.
--   Urutan prioritas ikon: Q(5), R(4), B(3), N(2), P(1), slot sisa = 0.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.chess_pkg.all;

entity captured_calc is
    port (
        clk      : in  std_logic;
        board    : in  board_t;
        cap_by_w : out std_logic_vector(44 downto 0) := (others => '0');
        cap_by_b : out std_logic_vector(44 downto 0) := (others => '0');
        w_adv    : out unsigned(5 downto 0) := (others => '0');
        b_adv    : out unsigned(5 downto 0) := (others => '0')
    );
end captured_calc;

architecture rtl of captured_calc is
    function max0(v : integer) return integer is
    begin
        if v > 0 then return v; else return 0; end if;
    end function;

    function pack_captured(p, n, b, r, q : integer) return std_logic_vector is
        variable extra : integer;
        variable cq, cr, cb, cn, cp : integer;
        variable idx   : integer;
        variable res   : std_logic_vector(44 downto 0) := (others => '0');

        procedure push_type(cnt : integer; code : std_logic_vector(2 downto 0)) is
        begin
            for k in 1 to 15 loop
                if k <= cnt and idx < 15 then
                    res(idx * 3 + 2 downto idx * 3) := code;
                    idx := idx + 1;
                end if;
            end loop;
        end procedure;
    begin
        extra := max0(q - 1) + max0(r - 2) + max0(b - 2) + max0(n - 2);
        cq    := max0(1 - q);
        cr    := max0(2 - r);
        cb    := max0(2 - b);
        cn    := max0(2 - n);
        cp    := max0(8 - p - extra);
        idx   := 0;

        push_type(cq, "101"); -- Ratu
        push_type(cr, "100"); -- Benteng
        push_type(cb, "011"); -- Gajah
        push_type(cn, "010"); -- Kuda
        push_type(cp, "001"); -- Pion
        return res;
    end function;
begin
    process (clk)
        variable sq_p : piece_t;
        variable wp, wn, wb, wr, wq : integer range 0 to 64;
        variable bp, bn, bb, br, bq : integer range 0 to 64;
        variable w_mat, b_mat, diff : integer;
    begin
        if rising_edge(clk) then
            wp := 0; wn := 0; wb := 0; wr := 0; wq := 0;
            bp := 0; bn := 0; bb := 0; br := 0; bq := 0;

            for i in 0 to 63 loop
                sq_p := board(i * 4 + 3 downto i * 4);
                if sq_p(3) = '0' then
                    case sq_p(2 downto 0) is
                        when "001" => wp := wp + 1;
                        when "010" => wn := wn + 1;
                        when "011" => wb := wb + 1;
                        when "100" => wr := wr + 1;
                        when "101" => wq := wq + 1;
                        when others => null;
                    end case;
                else
                    case sq_p(2 downto 0) is
                        when "001" => bp := bp + 1;
                        when "010" => bn := bn + 1;
                        when "011" => bb := bb + 1;
                        when "100" => br := br + 1;
                        when "101" => bq := bq + 1;
                        when others => null;
                    end case;
                end if;
            end loop;

            w_mat := wp + 3 * wn + 3 * wb + 5 * wr + 9 * wq;
            b_mat := bp + 3 * bn + 3 * bb + 5 * br + 9 * bq;

            if w_mat > b_mat then
                diff := w_mat - b_mat;
                if diff > 39 then diff := 39; end if;
                w_adv <= to_unsigned(diff, 6);
                b_adv <= (others => '0');
            elsif b_mat > w_mat then
                diff := b_mat - w_mat;
                if diff > 39 then diff := 39; end if;
                b_adv <= to_unsigned(diff, 6);
                w_adv <= (others => '0');
            else
                w_adv <= (others => '0');
                b_adv <= (others => '0');
            end if;

            -- Bidak hitam yang hilang = dimakan Putih; bidak putih yang hilang = dimakan Hitam
            cap_by_w <= pack_captured(bp, bn, bb, br, bq);
            cap_by_b <= pack_captured(wp, wn, wb, wr, wq);
        end if;
    end process;
end rtl;
