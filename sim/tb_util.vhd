-- tb_util.vhd : fungsi bantu untuk testbench (baca file hex vektor uji, konversi teks).
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use std.textio.all;

package tb_util is
    function hex2slv(s : string; w : integer) return std_logic_vector;
    function slv2hex(v : std_logic_vector) return string;
    impure function count_lines(fname : string) return integer;
end package tb_util;

package body tb_util is
    function hex2slv(s : string; w : integer) return std_logic_vector is
        variable r : std_logic_vector(w - 1 downto 0) := (others => '0');
        variable n : integer := 0;
        variable d : integer;
        variable pos : integer := 0;    -- posisi nibble dari kanan
        variable c : character;
    begin
        for i in s'right downto s'left loop
            c := s(i);
            if    c >= '0' and c <= '9' then d := character'pos(c) - character'pos('0');
            elsif c >= 'a' and c <= 'f' then d := character'pos(c) - character'pos('a') + 10;
            elsif c >= 'A' and c <= 'F' then d := character'pos(c) - character'pos('A') + 10;
            else d := -1; end if;
            if d >= 0 then
                for b in 0 to 3 loop
                    if pos * 4 + b < w then
                        if ((d / (2 ** b)) mod 2) = 1 then r(pos * 4 + b) := '1'; else r(pos * 4 + b) := '0'; end if;
                    end if;
                end loop;
                pos := pos + 1;
            end if;
        end loop;
        return r;
    end function;

    function slv2hex(v : std_logic_vector) return string is
        constant nn  : integer := (v'length + 3) / 4;
        variable vv  : std_logic_vector(nn * 4 - 1 downto 0) := (others => '0');
        variable res : string(1 to nn);
        variable d   : integer;
        constant hx  : string(1 to 16) := "0123456789abcdef";
    begin
        vv(v'length - 1 downto 0) := v;
        for i in 0 to nn - 1 loop
            d := to_integer(unsigned(vv(4 * (nn - 1 - i) + 3 downto 4 * (nn - 1 - i))));
            res(i + 1) := hx(d + 1);
        end loop;
        return res;
    end function;

    impure function count_lines(fname : string) return integer is
        file f : text open read_mode is fname;
        variable l : line;
        variable n : integer := 0;
    begin
        while not endfile(f) loop readline(f, l); n := n + 1; end loop;
        return n;
    end function;
end package body tb_util;
