-- bin2bcd.vhd : biner 9 bit (0..511) -> 3 digit BCD dengan algoritma double-dabble serial,
-- diperbarui terus-menerus (sekitar 11 clock per konversi).
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity bin2bcd is
    port (
        clk : in  std_logic;
        bin : in  std_logic_vector(8 downto 0);
        bcd : out std_logic_vector(11 downto 0)
    );
end bin2bcd;

architecture rtl of bin2bcd is
    signal n   : unsigned(3 downto 0)         := (others => '0');
    signal sh  : std_logic_vector(8 downto 0)  := (others => '0');
    signal acc : std_logic_vector(11 downto 0) := (others => '0');
    signal bcd_r : std_logic_vector(11 downto 0) := (others => '0');

    -- tambah 3 pada tiap digit yang >= 5
    function add3(a : std_logic_vector(11 downto 0)) return std_logic_vector is
        variable r : std_logic_vector(11 downto 0);
    begin
        for i in 0 to 2 loop
            if unsigned(a(4*i+3 downto 4*i)) >= 5 then
                r(4*i+3 downto 4*i) := std_logic_vector(unsigned(a(4*i+3 downto 4*i)) + 3);
            else
                r(4*i+3 downto 4*i) := a(4*i+3 downto 4*i);
            end if;
        end loop;
        return r;
    end function;

    signal a3 : std_logic_vector(11 downto 0);
begin
    bcd <= bcd_r;
    a3  <= add3(acc);

    process (clk)
    begin
        if rising_edge(clk) then
            if n = 0 then
                sh  <= bin;
                acc <= (others => '0');
                n   <= to_unsigned(9, 4);
            else
                acc <= a3(10 downto 0) & sh(8);
                sh  <= sh(7 downto 0) & '0';
                n   <= n - 1;
                if n = 1 then
                    bcd_r <= a3(10 downto 0) & sh(8);
                end if;
            end if;
        end if;
    end process;
end rtl;
