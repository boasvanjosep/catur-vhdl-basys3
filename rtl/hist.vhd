-- hist.vhd : riwayat langkah (maks 511 langkah) untuk replay. Satu entri 14 bit:
--   {promosi[1:0], tujuan[5:0], asal[5:0]}. push = langkah nyata, pop = undo.
-- Bila riwayat penuh, langkah berikutnya tidak disimpan (dihitung di skipped supaya undo tetap seimbang).
-- Memori 512 x 14 dengan baca sinkron (read-first) -> disintesis sebagai Block RAM.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity hist is
    port (
        clk   : in  std_logic;
        rst   : in  std_logic;
        push  : in  std_logic;
        pdata : in  std_logic_vector(13 downto 0);
        pop   : in  std_logic;
        count : out std_logic_vector(9 downto 0);
        raddr : in  std_logic_vector(8 downto 0);
        rdata : out std_logic_vector(13 downto 0)
    );
end hist;

architecture rtl of hist is
    type mem_t is array (0 to 511) of std_logic_vector(13 downto 0);
    signal mem     : mem_t := (others => (others => '0'));
    signal cnt     : unsigned(9 downto 0) := (others => '0');
    signal skipped : unsigned(9 downto 0) := (others => '0');
    signal rdata_r : std_logic_vector(13 downto 0) := (others => '0');
    signal we      : std_logic;
begin
    count <= std_logic_vector(cnt);
    rdata <= rdata_r;
    we    <= '1' when push = '1' and cnt < 511 else '0';

    process (clk)
    begin
        if rising_edge(clk) then
            if we = '1' then
                mem(to_integer(cnt(8 downto 0))) <= pdata;
            end if;
            rdata_r <= mem(to_integer(unsigned(raddr)));
        end if;
    end process;

    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                cnt <= (others => '0');
                skipped <= (others => '0');
            elsif push = '1' then
                if cnt < 511 then cnt <= cnt + 1; else skipped <= skipped + 1; end if;
            elsif pop = '1' then
                if skipped /= 0 then skipped <= skipped - 1;
                elsif cnt /= 0 then cnt <= cnt - 1;
                end if;
            end if;
        end if;
    end process;
end rtl;
