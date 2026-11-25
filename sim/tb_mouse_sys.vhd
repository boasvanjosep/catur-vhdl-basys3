-- tb_mouse_sys.vhd : uji integrasi penuh top_core 800x600:
--   1. Mouse PS/2 IntelliMouse (menu klik baris + < / >, makan bidak + captured tray,
--      shortcut BTNL Undo & BTND Menyerah, modal Konfirmasi, modal Game Over + [CEK PAPAN] + [MAIN LAGI]).
--   2. Fault tolerance saat mouse tidak tersambung (mouse_ready = '0', kontrol penuh via tombol & SW12..15).
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.chess_pkg.all;

entity tb_mouse_sys is
end tb_mouse_sys;

architecture sim of tb_mouse_sys is
    signal clk : std_logic := '0';
    signal sw_menu, sw_undo, sw_remis, sw_resign, sw_rst : std_logic := '0';
    signal bU, bD, bL, bR, bC : std_logic := '0';
    signal ps2_clk, ps2_data : std_logic := 'H';
    signal led : std_logic_vector(15 downto 0);
    signal seg : std_logic_vector(6 downto 0);
    signal dp  : std_logic;
    signal an  : std_logic_vector(3 downto 0);
    signal vr, vg, vb : std_logic_vector(3 downto 0);
    signal hsync, vsync : std_logic;
    signal dbg : dbg_t;

    -- Instance kedua tanpa mouse untuk uji fault tolerance
    signal sw_menu_fb, sw_undo_fb : std_logic := '0';
    signal bU_fb, bC_fb : std_logic := '0';
    signal ps2_clk_fb, ps2_data_fb : std_logic := 'H';
    signal dbg_fb : dbg_t;

    signal fin : boolean := false;

    function odd_par(b : std_logic_vector(7 downto 0)) return std_logic is
    begin
        return not (b(0) xor b(1) xor b(2) xor b(3) xor b(4) xor b(5) xor b(6) xor b(7));
    end function;
begin
    clk <= not clk after 5 ns when not fin;

    dut : entity work.top_core
        generic map (DEBOUNCE => 4, TICK_CLKS => 2000, PS2_INIT_WAIT => 200, PS2_INHIBIT => 20, SIM_BYPASS => true)
        port map (
            clk => clk, sw_menu => sw_menu, sw_undo => sw_undo, sw_remis => sw_remis,
            sw_resign => sw_resign, sw_rst => sw_rst,
            btnU => bU, btnD => bD, btnL => bL, btnR => bR, btnC => bC,
            PS2Clk => ps2_clk, PS2Data => ps2_data,
            led => led, seg => seg, dp => dp, an => an,
            vgaRed => vr, vgaGreen => vg, vgaBlue => vb, Hsync => hsync, Vsync => vsync,
            dbg => dbg
        );

    dut_fb : entity work.top_core
        generic map (DEBOUNCE => 4, TICK_CLKS => 2000, PS2_INIT_WAIT => 200, PS2_INHIBIT => 20, SIM_BYPASS => true)
        port map (
            clk => clk, sw_menu => sw_menu_fb, sw_undo => sw_undo_fb, sw_remis => '0',
            sw_resign => '0', sw_rst => '0',
            btnU => bU_fb, btnD => '0', btnL => '0', btnR => '0', btnC => bC_fb,
            PS2Clk => ps2_clk_fb, PS2Data => ps2_data_fb,
            led => open, seg => open, dp => open, an => open,
            vgaRed => open, vgaGreen => open, vgaBlue => open, Hsync => open, Vsync => open,
            dbg => dbg_fb
        );

    main : process
        variable cmd : std_logic_vector(7 downto 0);

        procedure check(c : boolean; msg : string) is
        begin
            if not c then
                report "GAGAL tb_mouse_sys: " & msg severity failure;
            end if;
        end procedure;

        procedure ps2_dev_send(b : std_logic_vector(7 downto 0)) is
            variable frame : std_logic_vector(10 downto 0);
        begin
            frame := '1' & odd_par(b) & b & '0';
            if to_X01(ps2_clk) /= '1' then wait until to_X01(ps2_clk) = '1'; end if;
            wait for 100 ns;
            for i in 0 to 10 loop
                if frame(i) = '0' then ps2_data <= '0'; else ps2_data <= 'H'; end if;
                wait for 100 ns;
                ps2_clk <= '0'; wait for 200 ns; ps2_clk <= 'H';
                if i < 10 then wait for 100 ns; else wait for 20 ns; end if;
            end loop;
            ps2_data <= 'H';
        end procedure;

        procedure ps2_dev_recv(variable rx : out std_logic_vector(7 downto 0)) is
            variable bits : std_logic_vector(8 downto 0);
        begin
            if to_X01(ps2_clk) /= '0' then wait until to_X01(ps2_clk) = '0'; end if;
            if to_X01(ps2_clk) /= '1' then wait until to_X01(ps2_clk) = '1'; end if;
            check(to_X01(ps2_data) = '0', "Start bit host bukan 0");
            wait for 100 ns;
            for i in 0 to 8 loop
                ps2_clk <= '0'; wait for 200 ns; ps2_clk <= 'H'; wait for 100 ns;
                bits(i) := to_X01(ps2_data);
                wait for 100 ns;
            end loop;
            ps2_clk <= '0'; wait for 200 ns; ps2_clk <= 'H'; wait for 100 ns;
            ps2_data <= '0'; wait for 100 ns;
            ps2_clk <= '0'; wait for 200 ns; ps2_clk <= 'H'; wait for 100 ns;
            ps2_data <= 'H'; wait for 100 ns;
            rx := bits(7 downto 0);
        end procedure;

        procedure run_intellimouse_init is
            type cmd_arr_t is array (0 to 8) of std_logic_vector(7 downto 0);
            constant EXP_CMDS : cmd_arr_t := (x"FF", x"F3", x"C8", x"F3", x"64", x"F3", x"50", x"F2", x"F4");
        begin
            for i in 0 to 8 loop
                ps2_dev_recv(cmd);
                check(cmd = EXP_CMDS(i), "Perintah init salah pada langkah " & integer'image(i));
                ps2_dev_send(x"FA");
                if i = 0 then
                    ps2_dev_send(x"AA"); ps2_dev_send(x"00");
                elsif i = 7 then
                    ps2_dev_send(x"03");
                end if;
            end loop;
        end procedure;

        procedure send_pkt4(bl, br : std_logic; dx, dy, dz : integer) is
            variable b0, b1, b2, b3 : std_logic_vector(7 downto 0);
            variable dx_s, dy_s : signed(8 downto 0);
            variable dz_s : signed(3 downto 0);
        begin
            dx_s := to_signed(dx, 9);
            dy_s := to_signed(dy, 9);
            dz_s := to_signed(dz, 4);
            b0 := '0' & '0' & dy_s(8) & dx_s(8) & '1' & '0' & br & bl;
            b1 := std_logic_vector(dx_s(7 downto 0));
            b2 := std_logic_vector(dy_s(7 downto 0));
            b3 := std_logic_vector(resize(dz_s, 8));
            ps2_dev_send(b0); ps2_dev_send(b1); ps2_dev_send(b2); ps2_dev_send(b3);
            for k in 0 to 10 loop wait until rising_edge(clk); end loop;
        end procedure;

        procedure move_to_px(tx, ty : integer) is
            variable dx, dy : integer;
        begin
            while to_integer(dbg.mouse_x) /= tx or to_integer(dbg.mouse_y) /= ty loop
                dx := tx - to_integer(dbg.mouse_x);
                if dx > 200 then dx := 200; elsif dx < -200 then dx := -200; end if;
                dy := to_integer(dbg.mouse_y) - ty;
                if dy > 200 then dy := 200; elsif dy < -200 then dy := -200; end if;
                send_pkt4('0', '0', dx, dy, 0);
            end loop;
        end procedure;

        procedure click_left is
        begin
            send_pkt4('1', '0', 0, 0, 0);
            send_pkt4('0', '0', 0, 0, 0);
        end procedure;

        procedure press_btn(signal btn : out std_logic) is
        begin
            btn <= '1';
            for k in 0 to 6 loop wait until rising_edge(clk); end loop;
            btn <= '0';
            for k in 0 to 6 loop wait until rising_edge(clk); end loop;
        end procedure;

        procedure wait_engine_idle is
        begin
            for k in 0 to 10 loop wait until rising_edge(clk); end loop;
            while dbg.busy = '1' loop wait until rising_edge(clk); end loop;
            for k in 0 to 5 loop wait until rising_edge(clk); end loop;
        end procedure;

        procedure wait_fb_idle is
        begin
            for k in 0 to 10 loop wait until rising_edge(clk); end loop;
            while dbg_fb.busy = '1' loop wait until rising_edge(clk); end loop;
            for k in 0 to 5 loop wait until rising_edge(clk); end loop;
        end procedure;

        procedure check_vga_clean(tag : string) is
        begin
            for k in 0 to 250 loop
                wait until rising_edge(clk);
                check(not is_X(vr) and not is_X(vg) and not is_X(vb) and not is_X(hsync) and not is_X(vsync),
                      "Sinyal VGA mengandung X/U pada " & tag);
            end loop;
        end procedure;
    begin
        ps2_clk <= 'H'; ps2_data <= 'H';
        ps2_clk_fb <= 'H'; ps2_data_fb <= 'H';
        sw_menu <= '0'; sw_undo <= '0'; sw_remis <= '0'; sw_resign <= '0'; sw_rst <= '0';

        -- 1. Inisialisasi mouse
        run_intellimouse_init;
        for k in 0 to 20 loop wait until rising_edge(clk); end loop;
        check(dbg.mouse_ready = '1' and dbg.has_wheel = '1', "Mouse harus siap dengan wheel");

        -- 2. Buka menu (SW0), klik baris 3 (TEMA, y=264), lalu klik '>' (460) -> '<' (304) -> '>' (460)
        sw_menu <= '1';
        for k in 0 to 5 loop wait until rising_edge(clk); end loop;
        move_to_px(200, 264);
        click_left;
        check(dbg.menu_idx = 3 and dbg.theme = "00", "Klik pertama baris 3 hanya sorot dan tampilkan < >");
        move_to_px(460, 264);
        click_left;
        check(dbg.theme = "01", "Klik > ubah tema ke 01");
        move_to_px(304, 264);
        click_left;
        check(dbg.theme = "00", "Klik < kembalikan tema ke 00");
        move_to_px(460, 264);
        click_left;
        check(dbg.theme = "01", "Klik > ubah tema ke 01");
        check_vga_clean("menu terbuka");
        sw_menu <= '0';
        for k in 0 to 5 loop wait until rising_edge(clk); end loop;
        check(dbg.theme = "01" and dbg.menu_open = '0', "Tema harus tersimpan setelah menu ditutup");

        -- 3. Mainkan e2->e4, d7->d5, e4xd5 untuk menguji bidak dimakan (800x600: x=32+col*64+32, y=48+(7-rank)*64+32)
        -- e2: (320, 464), e4: (320, 336)
        move_to_px(320, 464); click_left; wait_engine_idle;
        move_to_px(320, 336); click_left; wait_engine_idle;
        -- d7: (256, 144), d5: (256, 272)
        move_to_px(256, 144); click_left; wait_engine_idle;
        move_to_px(256, 272); click_left; wait_engine_idle;
        -- e4xd5
        move_to_px(320, 336); click_left; wait_engine_idle;
        move_to_px(256, 272); click_left; wait_engine_idle;
        for k in 0 to 4 loop wait until rising_edge(clk); end loop;
        check(dbg.cap_by_w(2 downto 0) = "001" and dbg.w_adv = 1, "Pion hitam dimakan harus tercatat di cap_by_w dan w_adv=+1");
        check_vga_clean("bidak dimakan");

        -- 4. Tekan BTNL (shortcut Undo langsung di board saat mouse tersambung)
        press_btn(bL);
        wait_engine_idle;
        for k in 0 to 4 loop wait until rising_edge(clk); end loop;
        check(dbg.cap_by_w = (44 downto 0 => '0') and dbg.w_adv = 0, "BTNL shortcut harus membatalkan makan pion");
        check(get_sq(dbg.board, "011100") = "0001" and get_sq(dbg.board, "100011") = "1001", "Pion harus kembali ke e4 dan d5");

        -- 5. Tekan BTND (shortcut Menyerah) -> klik [ YA ] (200, 280) -> cek modal Game Over
        press_btn(bD);
        check(dbg.prompt = "10", "BTND shortcut harus memunculkan popup konfirmasi menyerah");
        move_to_px(200, 280);
        click_left;
        for k in 0 to 5 loop wait until rising_edge(clk); end loop;
        check(dbg.result = "01" and dbg.over_top = '1' and dbg.popup_hide = '0', "Popup Game Over harus tampil setelah menyerah");
        check_vga_clean("popup game over");

        -- 6. Klik [CEK PAPAN] (380, 328) -> popup sembunyi -> BTND tampilkan lagi -> klik [MAIN LAGI] (200, 328)
        move_to_px(380, 328);
        click_left;
        check(dbg.popup_hide = '1', "Klik [CEK PAPAN] harus menyembunyikan popup");
        press_btn(bD);
        check(dbg.popup_hide = '0', "BTND harus menampilkan popup kembali");
        move_to_px(200, 328);
        click_left;
        wait_engine_idle;
        check(dbg.board = INIT_BOARD and dbg.over_top = '0' and dbg.theme = "01",
              "[MAIN LAGI] harus reset papan dan mempertahankan tema");

        -- 7. Uji Fault Tolerance tanpa mouse pada dut_fb (mouse_ready = '0')
        check(dbg_fb.mouse_ready = '0', "dut_fb harus berstatus tanpa mouse");
        press_btn(bC_fb); -- pilih e2
        wait_fb_idle;
        check(dbg_fb.sel_valid = '1' and dbg_fb.sel_sq = "001100", "BTNC tanpa mouse harus memilih e2");
        press_btn(bU_fb);
        press_btn(bU_fb);
        press_btn(bC_fb); -- pindah ke e4
        wait_fb_idle;
        check(get_sq(dbg_fb.board, "011100") = "0001", "Navigasi tombol tanpa mouse harus jalan ke e4");
        sw_undo_fb <= '1';
        wait_fb_idle;
        check(get_sq(dbg_fb.board, "001100") = "0001" and dbg_fb.turn = '0', "SW12 Undo harus bekerja di mode tanpa mouse");

        report "PASS tb_mouse_sys";
        fin <= true;
        wait;
    end process;
end sim;
