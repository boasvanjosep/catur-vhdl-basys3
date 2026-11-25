-- DIHASILKAN OTOMATIS oleh tools/gen_piece_rom_vhdl.py dari tabel sprite yang sama dengan versi Verilog
-- (tools/gen_pieces.py) -- jangan diedit tangan.
-- ROM sprite bidak 20x20, 2 bit/piksel (0 transparan, 1 garis tepi, 2 isi).
-- Masukan: tipe bidak (1..6) dan baris (0..19); keluaran: 20 piksel, kiri = bit teratas.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity piece_rom is
    port (
        ptype : in  std_logic_vector(2 downto 0);
        row   : in  std_logic_vector(4 downto 0);
        bits  : out std_logic_vector(39 downto 0)
    );
end piece_rom;

architecture rtl of piece_rom is
begin
    process (ptype, row)
    begin
        case to_integer(unsigned(ptype & row)) is
            when 32 => bits <= x"0000000000";  -- PION
            when 33 => bits <= x"0000000000";  -- PION
            when 34 => bits <= x"0000000000";  -- PION
            when 35 => bits <= x"0000550000";  -- PION
            when 36 => bits <= x"0001aa4000";  -- PION
            when 37 => bits <= x"0006aa9000";  -- PION
            when 38 => bits <= x"0006aa9000";  -- PION
            when 39 => bits <= x"0006aa9000";  -- PION
            when 40 => bits <= x"0001aa4000";  -- PION
            when 41 => bits <= x"0000690000";  -- PION
            when 42 => bits <= x"0001aa4000";  -- PION
            when 43 => bits <= x"0006aa9000";  -- PION
            when 44 => bits <= x"0006aa9000";  -- PION
            when 45 => bits <= x"001aaaa400";  -- PION
            when 46 => bits <= x"006aaaa900";  -- PION
            when 47 => bits <= x"006aaaa900";  -- PION
            when 48 => bits <= x"0055555500";  -- PION
            when 49 => bits <= x"0000000000";  -- PION
            when 50 => bits <= x"0000000000";  -- PION
            when 51 => bits <= x"0000000000";  -- PION
            when 64 => bits <= x"0000000000";  -- KUDA
            when 65 => bits <= x"0000000000";  -- KUDA
            when 66 => bits <= x"0010400000";  -- KUDA
            when 67 => bits <= x"0019640000";  -- KUDA
            when 68 => bits <= x"006aa90000";  -- KUDA
            when 69 => bits <= x"01a6aa9000";  -- KUDA
            when 70 => bits <= x"06aaaaa900";  -- KUDA
            when 71 => bits <= x"1aaaaaaa40";  -- KUDA
            when 72 => bits <= x"1aaaaaaa90";  -- KUDA
            when 73 => bits <= x"16a6aaaa90";  -- KUDA
            when 74 => bits <= x"0569aaaa90";  -- KUDA
            when 75 => bits <= x"0006aaaa40";  -- KUDA
            when 76 => bits <= x"001aaaa900";  -- KUDA
            when 77 => bits <= x"006aaaa900";  -- KUDA
            when 78 => bits <= x"01aaaaa900";  -- KUDA
            when 79 => bits <= x"06aaaaa900";  -- KUDA
            when 80 => bits <= x"0555555500";  -- KUDA
            when 81 => bits <= x"0000000000";  -- KUDA
            when 82 => bits <= x"0000000000";  -- KUDA
            when 83 => bits <= x"0000000000";  -- KUDA
            when 96 => bits <= x"0000000000";  -- GAJAH
            when 97 => bits <= x"0000140000";  -- GAJAH
            when 98 => bits <= x"0000690000";  -- GAJAH
            when 99 => bits <= x"0001aa4000";  -- GAJAH
            when 100 => bits <= x"0006969000";  -- GAJAH
            when 101 => bits <= x"0006aa9000";  -- GAJAH
            when 102 => bits <= x"0006aa9000";  -- GAJAH
            when 103 => bits <= x"0001aa4000";  -- GAJAH
            when 104 => bits <= x"0055555500";  -- GAJAH
            when 105 => bits <= x"001aaaa400";  -- GAJAH
            when 106 => bits <= x"0006aa9000";  -- GAJAH
            when 107 => bits <= x"0006aa9000";  -- GAJAH
            when 108 => bits <= x"001aaaa400";  -- GAJAH
            when 109 => bits <= x"006aaaa900";  -- GAJAH
            when 110 => bits <= x"01aaaaaa40";  -- GAJAH
            when 111 => bits <= x"0155555540";  -- GAJAH
            when 112 => bits <= x"0000000000";  -- GAJAH
            when 113 => bits <= x"0000000000";  -- GAJAH
            when 114 => bits <= x"0000000000";  -- GAJAH
            when 115 => bits <= x"0000000000";  -- GAJAH
            when 128 => bits <= x"0000000000";  -- BENTENG
            when 129 => bits <= x"0000000000";  -- BENTENG
            when 130 => bits <= x"0054551500";  -- BENTENG
            when 131 => bits <= x"0064691900";  -- BENTENG
            when 132 => bits <= x"0065695900";  -- BENTENG
            when 133 => bits <= x"006aaaa900";  -- BENTENG
            when 134 => bits <= x"0016aa9400";  -- BENTENG
            when 135 => bits <= x"0006aa9000";  -- BENTENG
            when 136 => bits <= x"0006aa9000";  -- BENTENG
            when 137 => bits <= x"0006aa9000";  -- BENTENG
            when 138 => bits <= x"0006aa9000";  -- BENTENG
            when 139 => bits <= x"0006aa9000";  -- BENTENG
            when 140 => bits <= x"0016aa9400";  -- BENTENG
            when 141 => bits <= x"006aaaa900";  -- BENTENG
            when 142 => bits <= x"006aaaa900";  -- BENTENG
            when 143 => bits <= x"01aaaaaa40";  -- BENTENG
            when 144 => bits <= x"0155555540";  -- BENTENG
            when 145 => bits <= x"0000000000";  -- BENTENG
            when 146 => bits <= x"0000000000";  -- BENTENG
            when 147 => bits <= x"0000000000";  -- BENTENG
            when 160 => bits <= x"0000000000";  -- RATU
            when 161 => bits <= x"0404141010";  -- RATU
            when 162 => bits <= x"1919146464";  -- RATU
            when 163 => bits <= x"1919146464";  -- RATU
            when 164 => bits <= x"0659146590";  -- RATU
            when 165 => bits <= x"06a9aa6a90";  -- RATU
            when 166 => bits <= x"06aaaaaa90";  -- RATU
            when 167 => bits <= x"01aaaaaa40";  -- RATU
            when 168 => bits <= x"006aaaa900";  -- RATU
            when 169 => bits <= x"001aaaa400";  -- RATU
            when 170 => bits <= x"0006aa9000";  -- RATU
            when 171 => bits <= x"0006aa9000";  -- RATU
            when 172 => bits <= x"001aaaa400";  -- RATU
            when 173 => bits <= x"006aaaa900";  -- RATU
            when 174 => bits <= x"01aaaaaa40";  -- RATU
            when 175 => bits <= x"0155555540";  -- RATU
            when 176 => bits <= x"0000000000";  -- RATU
            when 177 => bits <= x"0000000000";  -- RATU
            when 178 => bits <= x"0000000000";  -- RATU
            when 179 => bits <= x"0000000000";  -- RATU
            when 192 => bits <= x"0000000000";  -- RAJA
            when 193 => bits <= x"0000140000";  -- RAJA
            when 194 => bits <= x"0001554000";  -- RAJA
            when 195 => bits <= x"0001554000";  -- RAJA
            when 196 => bits <= x"0000140000";  -- RAJA
            when 197 => bits <= x"0000140000";  -- RAJA
            when 198 => bits <= x"0005555000";  -- RAJA
            when 199 => bits <= x"001a69a400";  -- RAJA
            when 200 => bits <= x"006a69a900";  -- RAJA
            when 201 => bits <= x"006aaaa900";  -- RAJA
            when 202 => bits <= x"001aaaa400";  -- RAJA
            when 203 => bits <= x"0006aa9000";  -- RAJA
            when 204 => bits <= x"0006aa9000";  -- RAJA
            when 205 => bits <= x"001aaaa400";  -- RAJA
            when 206 => bits <= x"006aaaa900";  -- RAJA
            when 207 => bits <= x"01aaaaaa40";  -- RAJA
            when 208 => bits <= x"0155555540";  -- RAJA
            when 209 => bits <= x"0000000000";  -- RAJA
            when 210 => bits <= x"0000000000";  -- RAJA
            when 211 => bits <= x"0000000000";  -- RAJA
            when others => bits <= (others => '0');
        end case;
    end process;
end rtl;
