-- tb_captured_calc.vhd : uji unit penghitung bidak dimakan dan selisih materi.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.chess_pkg.all;

entity tb_captured_calc is
end tb_captured_calc;

architecture sim of tb_captured_calc is
    signal clk      : std_logic := '0';
    signal board    : board_t := INIT_BOARD;
    signal cap_by_w, cap_by_b : std_logic_vector(44 downto 0);
    signal w_adv, b_adv       : unsigned(5 downto 0);
    signal fin      : boolean := false;
begin
    clk <= not clk after 5 ns when not fin;

    dut : entity work.captured_calc
        port map (
            clk => clk, board => board,
            cap_by_w => cap_by_w, cap_by_b => cap_by_b,
            w_adv => w_adv, b_adv => b_adv
        );

    main : process
        variable b : board_t;
        procedure check(c : boolean; msg : string) is
        begin
            if not c then
                report "GAGAL tb_captured_calc: " & msg severity failure;
            end if;
        end procedure;
    begin
        -- 1. Papan awal: belum ada bidak dimakan
        board <= INIT_BOARD;
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait for 1 ns;
        check(cap_by_w = (44 downto 0 => '0'), "Papan awal cap_by_w harus kosong");
        check(cap_by_b = (44 downto 0 => '0'), "Papan awal cap_by_b harus kosong");
        check(w_adv = 0 and b_adv = 0, "Papan awal selisih materi harus 0");

        -- 2. Putih memakan 1 Ratu hitam (d8=59), 1 Benteng hitam (a8=56), 1 Pion hitam (e7=52)
        b := INIT_BOARD;
        b := put_sq(b, std_logic_vector(to_unsigned(59, 6)), "0000");
        b := put_sq(b, std_logic_vector(to_unsigned(56, 6)), "0000");
        b := put_sq(b, std_logic_vector(to_unsigned(52, 6)), "0000");
        board <= b;
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait for 1 ns;
        check(cap_by_w(2 downto 0) = "101", "Slot 0 harus Ratu (5)");
        check(cap_by_w(5 downto 3) = "100", "Slot 1 harus Benteng (4)");
        check(cap_by_w(8 downto 6) = "001", "Slot 2 harus Pion (1)");
        check(cap_by_w(11 downto 9) = "000", "Slot 3 harus kosong");
        check(w_adv = 15 and b_adv = 0, "Selisih materi Putih harus +15");

        -- 3. Kompensasi promosi: Putih kehilangan 1 pion (a2=8) karena promosi jadi Ratu ke-2 (c6=42)
        b := INIT_BOARD;
        b := put_sq(b, std_logic_vector(to_unsigned(8, 6)), "0000");
        b := put_sq(b, std_logic_vector(to_unsigned(42, 6)), "0101"); -- Ratu Putih tambahan
        board <= b;
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait for 1 ns;
        check(cap_by_b = (44 downto 0 => '0'), "Pion yang promosi tidak boleh dianggap dimakan");
        check(w_adv = 8 and b_adv = 0, "Keunggulan materi setelah promosi harus +8");

        -- 4. Undo / Reset kembali ke INIT_BOARD
        board <= INIT_BOARD;
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait for 1 ns;
        check(cap_by_w = (44 downto 0 => '0') and w_adv = 0, "Setelah undo/reset harus kembali 0");

        report "PASS tb_captured_calc";
        fin <= true;
        wait;
    end process;
end sim;
