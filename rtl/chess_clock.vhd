-- chess_clock.vhd : jam catur dua pemain (hitung mundur, resolusi 1 detik).
--   preset (dibaca selama rst = '1'): 0 tanpa batas, 1 = 1 mnt, 2 = 3, 3 = 5, 4 = 10, 5 = 15, 6 = 30, 7 = 60 mnt
--   Jam putih mulai berjalan setelah langkah pertama putih (langkah pertama gratis);
--   sesudah itu hanya jam pemain yang sedang jalan yang berkurang.
--   Jam berhenti saat jeda, saat skakmat/pat, atau setelah ada yang waktunya habis.
--   Waktu habis -> timeout = "01" (putih kalah) atau "10" (hitam kalah).
-- Waktu disimpan BCD {menit puluhan, menit satuan, detik puluhan, detik satuan}.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity chess_clock is
    generic (TICK_CLKS : integer := 100_000_000);
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        preset    : in  std_logic_vector(2 downto 0);
        turn      : in  std_logic;            -- '0' putih jalan
        started   : in  std_logic;            -- langkah pertama sudah dimainkan
        paused    : in  std_logic;
        game_over : in  std_logic;            -- skakmat / pat / menyerah / remis
        w_time    : out std_logic_vector(15 downto 0);
        b_time    : out std_logic_vector(15 downto 0);
        unlimited : out std_logic;
        timeout   : out std_logic_vector(1 downto 0)
    );
end chess_clock;

architecture rtl of chess_clock is
    function preset_bcd(p : std_logic_vector(2 downto 0)) return std_logic_vector is
    begin
        case p is
            when "001" => return x"0100";
            when "010" => return x"0300";
            when "011" => return x"0500";
            when "100" => return x"1000";
            when "101" => return x"1500";
            when "110" => return x"3000";
            when "111" => return x"6000";
            when others => return x"0000";
        end case;
    end function;

    -- kurangi 1 detik (jangan dipanggil bila waktu = 0)
    function bcd_dec(t : std_logic_vector(15 downto 0)) return std_logic_vector is
        variable m1, m0, s1, s0 : unsigned(3 downto 0);
    begin
        m1 := unsigned(t(15 downto 12)); m0 := unsigned(t(11 downto 8));
        s1 := unsigned(t(7 downto 4));   s0 := unsigned(t(3 downto 0));
        if s0 /= 0 then
            s0 := s0 - 1;
        else
            s0 := to_unsigned(9, 4);
            if s1 /= 0 then
                s1 := s1 - 1;
            else
                s1 := to_unsigned(5, 4);
                if m0 /= 0 then
                    m0 := m0 - 1;
                else
                    m0 := to_unsigned(9, 4);
                    if m1 /= 0 then
                        m1 := m1 - 1;
                    else
                        m1 := (others => '0'); m0 := (others => '0');
                        s1 := (others => '0'); s0 := (others => '0');
                    end if;
                end if;
            end if;
        end if;
        return std_logic_vector(m1) & std_logic_vector(m0) & std_logic_vector(s1) & std_logic_vector(s0);
    end function;

    signal w_r, b_r : std_logic_vector(15 downto 0) := (others => '0');
    signal unl_r    : std_logic := '0';
    signal to_r     : std_logic_vector(1 downto 0) := "00";
    signal tick     : integer range 0 to TICK_CLKS := 0;
    signal running  : std_logic;
begin
    w_time <= w_r;  b_time <= b_r;  unlimited <= unl_r;  timeout <= to_r;

    running <= '1' when unl_r = '0' and started = '1' and paused = '0' and game_over = '0' and to_r = "00"
               else '0';

    process (clk)
        variable nxt : std_logic_vector(15 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                w_r   <= preset_bcd(preset);
                b_r   <= preset_bcd(preset);
                if preset = "000" then unl_r <= '1'; else unl_r <= '0'; end if;
                to_r  <= "00";
                tick  <= 0;
            elsif running = '1' then
                if tick = TICK_CLKS - 1 then
                    tick <= 0;
                    if turn = '0' then
                        nxt := bcd_dec(w_r);
                        w_r <= nxt;
                        if nxt = x"0000" then to_r <= "01"; end if;
                    else
                        nxt := bcd_dec(b_r);
                        b_r <= nxt;
                        if nxt = x"0000" then to_r <= "10"; end if;
                    end if;
                else
                    tick <= tick + 1;
                end if;
            end if;
        end if;
    end process;
end rtl;
