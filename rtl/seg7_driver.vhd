-- seg7_driver.vhd : 4 digit 7-segmen Basys 3 (anoda dan segmen aktif rendah).
-- Kode karakter 5 bit:
--   0..9 = angka, 10..17 = A b C d E F G H, 18 = '-',
--   19 = 'L', 20 = 'o', 21 = 'S', 22 = 'U', 23 = 'n', 24 = 'r', 25 = 'P', 26 = 'I', lainnya = kosong.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity seg7_driver is
    port (
        clk  : in  std_logic;
        c3, c2, c1, c0 : in std_logic_vector(4 downto 0);   -- c3 = digit paling kiri
        dpon : in  std_logic_vector(3 downto 0);            -- 1 = titik desimal digit itu menyala
        dp   : out std_logic;
        seg  : out std_logic_vector(6 downto 0);            -- {g,f,e,d,c,b,a}, aktif rendah
        an   : out std_logic_vector(3 downto 0)
    );
end seg7_driver;

architecture rtl of seg7_driver is
    signal refresh : unsigned(16 downto 0) := (others => '0');
    signal ch      : std_logic_vector(4 downto 0);
begin
    process (clk)
    begin
        if rising_edge(clk) then
            refresh <= refresh + 1;
        end if;
    end process;

    process (refresh, c0, c1, c2, c3, dpon)
    begin
        case refresh(16 downto 15) is
            when "00" => an <= "1110"; ch <= c0; dp <= not dpon(0);
            when "01" => an <= "1101"; ch <= c1; dp <= not dpon(1);
            when "10" => an <= "1011"; ch <= c2; dp <= not dpon(2);
            when others => an <= "0111"; ch <= c3; dp <= not dpon(3);
        end case;
    end process;

    with to_integer(unsigned(ch)) select
        seg <= not "0111111" when 0,
               not "0000110" when 1,
               not "1011011" when 2,
               not "1001111" when 3,
               not "1100110" when 4,
               not "1101101" when 5,
               not "1111101" when 6,
               not "0000111" when 7,
               not "1111111" when 8,
               not "1101111" when 9,
               not "1110111" when 10,   -- A
               not "1111100" when 11,   -- b
               not "0111001" when 12,   -- C
               not "1011110" when 13,   -- d
               not "1111001" when 14,   -- E
               not "1110001" when 15,   -- F
               not "0111101" when 16,   -- G
               not "1110110" when 17,   -- H
               not "1000000" when 18,   -- -
               not "0111000" when 19,   -- L
               not "1011100" when 20,   -- o
               not "1101101" when 21,   -- S
               not "0111110" when 22,   -- U
               not "1010100" when 23,   -- n
               not "1010000" when 24,   -- r
               not "1110011" when 25,   -- P
               not "0000110" when 26,   -- I
               "1111111"     when others;
end rtl;
