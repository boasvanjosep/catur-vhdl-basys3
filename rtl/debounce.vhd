-- debounce.vhd : sinkronisasi 2 flip-flop + debounce + pulsa 1 clock saat ditekan.
-- STABLE_CLKS = berapa clock sinyal harus stabil (100 MHz: 1_000_000 = 10 ms).
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity debounce is
    generic (STABLE_CLKS : integer := 1_000_000);
    port (
        clk   : in  std_logic;
        din   : in  std_logic;
        level : out std_logic;
        pulse : out std_logic
    );
end debounce;

architecture rtl of debounce is
    signal s0, s1    : std_logic := '0';
    signal lvl, puls : std_logic := '0';
    signal cnt       : integer range 0 to STABLE_CLKS := 0;
begin
    level <= lvl;
    pulse <= puls;
    process (clk)
    begin
        if rising_edge(clk) then
            s0   <= din;
            s1   <= s0;
            puls <= '0';
            if s1 = lvl then
                cnt <= 0;
            elsif cnt >= STABLE_CLKS - 1 then
                cnt <= 0;
                lvl <= s1;
                if s1 = '1' then
                    puls <= '1';
                end if;
            else
                cnt <= cnt + 1;
            end if;
        end if;
    end process;
end rtl;
