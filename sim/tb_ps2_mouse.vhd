-- tb_ps2_mouse.vhd : uji unit ps2_mouse pada layar 800x600 (papan 512x512, petak 64x64).
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_ps2_mouse is
end tb_ps2_mouse;

architecture sim of tb_ps2_mouse is
    signal clk, rst : std_logic := '0';
    signal ps2_clk, ps2_data : std_logic := 'H';
    signal mouse_x, mouse_y : unsigned(10 downto 0);
    signal mouse_sq : std_logic_vector(5 downto 0);
    signal mouse_inb, moved, click_l, click_r, click_m, btn_l, btn_r : std_logic;
    signal scroll_up, scroll_dn, has_wheel, ready : std_logic;
    signal fin : boolean := false;

    function odd_par(b : std_logic_vector(7 downto 0)) return std_logic is
    begin
        return not (b(0) xor b(1) xor b(2) xor b(3) xor b(4) xor b(5) xor b(6) xor b(7));
    end function;
begin
    clk <= not clk after 5 ns when not fin;

    dut : entity work.ps2_mouse
        generic map (INIT_WAIT_CLKS => 100, INHIBIT_CLKS => 20, FILTER_BITS => 4)
        port map (
            clk => clk, rst => rst, ps2_clk => ps2_clk, ps2_data => ps2_data,
            mouse_x => mouse_x, mouse_y => mouse_y, mouse_sq => mouse_sq, mouse_inb => mouse_inb,
            moved => moved, click_l => click_l, click_r => click_r, click_m => click_m,
            btn_l => btn_l, btn_r => btn_r, scroll_up => scroll_up, scroll_dn => scroll_dn,
            has_wheel => has_wheel, ready => ready
        );

    main : process
        variable cmd : std_logic_vector(7 downto 0);
        variable got_moved, got_cl, got_cr, got_su, got_sd : boolean;

        procedure check(c : boolean; msg : string) is
        begin
            if not c then
                report "GAGAL tb_ps2_mouse: " & msg severity failure;
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
                ps2_clk <= '0';
                wait for 200 ns;
                ps2_clk <= 'H';
                if i < 10 then wait for 100 ns; else wait for 20 ns; end if;
            end loop;
            ps2_data <= 'H';
        end procedure;

        procedure ps2_dev_recv(variable rx : out std_logic_vector(7 downto 0)) is
            variable bits : std_logic_vector(8 downto 0);
            variable par  : std_logic;
        begin
            if to_X01(ps2_clk) /= '0' then wait until to_X01(ps2_clk) = '0'; end if;
            if to_X01(ps2_clk) /= '1' then wait until to_X01(ps2_clk) = '1'; end if;
            check(to_X01(ps2_data) = '0', "Start bit host tidak 0");
            wait for 100 ns;
            for i in 0 to 8 loop
                ps2_clk <= '0'; wait for 200 ns; ps2_clk <= 'H'; wait for 100 ns;
                bits(i) := to_X01(ps2_data);
                wait for 100 ns;
            end loop;
            ps2_clk <= '0'; wait for 200 ns; ps2_clk <= 'H'; wait for 100 ns;
            check(to_X01(ps2_data) = '1', "Stop bit host bukan 1");
            ps2_data <= '0'; wait for 100 ns;
            ps2_clk <= '0'; wait for 200 ns; ps2_clk <= 'H'; wait for 100 ns;
            ps2_data <= 'H'; wait for 100 ns;

            rx := bits(7 downto 0);
            par := bits(0) xor bits(1) xor bits(2) xor bits(3) xor
                   bits(4) xor bits(5) xor bits(6) xor bits(7) xor bits(8);
            check(par = '1', "Paritas ganjil host salah");
        end procedure;

        procedure run_init(dev_id : std_logic_vector(7 downto 0)) is
            type cmd_arr_t is array (0 to 8) of std_logic_vector(7 downto 0);
            constant EXP_CMDS : cmd_arr_t := (x"FF", x"F3", x"C8", x"F3", x"64", x"F3", x"50", x"F2", x"F4");
        begin
            for i in 0 to 8 loop
                ps2_dev_recv(cmd);
                check(cmd = EXP_CMDS(i), "Perintah PS/2 langkah " & integer'image(i) & " salah");
                ps2_dev_send(x"FA");
                if i = 0 then
                    ps2_dev_send(x"AA"); ps2_dev_send(x"00");
                elsif i = 7 then
                    ps2_dev_send(dev_id);
                end if;
            end loop;
        end procedure;

        procedure send_pkt4(bl, br, bm : std_logic; dx, dy, dz : integer) is
            variable b0, b1, b2, b3 : std_logic_vector(7 downto 0);
            variable dx_s, dy_s : signed(8 downto 0);
            variable dz_s : signed(3 downto 0);
        begin
            dx_s := to_signed(dx, 9);
            dy_s := to_signed(dy, 9);
            dz_s := to_signed(dz, 4);
            b0 := '0' & '0' & dy_s(8) & dx_s(8) & '1' & bm & br & bl;
            b1 := std_logic_vector(dx_s(7 downto 0));
            b2 := std_logic_vector(dy_s(7 downto 0));
            b3 := std_logic_vector(resize(dz_s, 8));

            got_moved := false; got_cl := false; got_cr := false; got_su := false; got_sd := false;
            ps2_dev_send(b0); ps2_dev_send(b1); ps2_dev_send(b2); ps2_dev_send(b3);
            for k in 0 to 30 loop
                wait until rising_edge(clk);
                if moved = '1' then got_moved := true; end if;
                if click_l = '1' then got_cl := true; end if;
                if click_r = '1' then got_cr := true; end if;
                if scroll_up = '1' then got_su := true; end if;
                if scroll_dn = '1' then got_sd := true; end if;
            end loop;
        end procedure;

        procedure send_pkt3(bl, br, bm : std_logic; dx, dy : integer) is
            variable b0, b1, b2 : std_logic_vector(7 downto 0);
            variable dx_s, dy_s : signed(8 downto 0);
        begin
            dx_s := to_signed(dx, 9);
            dy_s := to_signed(dy, 9);
            b0 := '0' & '0' & dy_s(8) & dx_s(8) & '1' & bm & br & bl;
            b1 := std_logic_vector(dx_s(7 downto 0));
            b2 := std_logic_vector(dy_s(7 downto 0));

            got_moved := false; got_cl := false; got_cr := false; got_su := false; got_sd := false;
            ps2_dev_send(b0); ps2_dev_send(b1); ps2_dev_send(b2);
            for k in 0 to 30 loop
                wait until rising_edge(clk);
                if moved = '1' then got_moved := true; end if;
                if click_l = '1' then got_cl := true; end if;
                if click_r = '1' then got_cr := true; end if;
                if scroll_up = '1' then got_su := true; end if;
                if scroll_dn = '1' then got_sd := true; end if;
            end loop;
        end procedure;
    begin
        ps2_clk <= 'H'; ps2_data <= 'H';

        -- Fase 1: Mode IntelliMouse 800x600 (ID = 0x03)
        run_init(x"03");
        wait for 300 ns;
        check(ready = '1' and has_wheel = '1', "Init IntelliMouse gagal");
        check(mouse_x = 288 and mouse_y = 304, "Posisi awal harus (288, 304)");
        check(mouse_inb = '1' and mouse_sq = "011100", "Posisi awal harus di e4 (28)");

        -- Gerak ke petak f2: (352, 432) -> bx=320 (col 5), by=384 (row 6 -> rank 1 = 13)
        send_pkt4('0', '0', '0', 64, -128, 0);
        check(got_moved and mouse_x = 352 and mouse_y = 432, "Koordinat harus (352, 432)");
        check(mouse_inb = '1' and mouse_sq = "001101", "mouse_sq harus f2 (13)");

        -- Clamp tepi layar 800x600 kanan-atas (799, 0)
        send_pkt4('0', '0', '0', 250, 250, 0);
        send_pkt4('0', '0', '0', 250, 250, 0);
        check(mouse_x = 799 and mouse_y = 0 and mouse_inb = '0', "Clamp kanan-atas 800x600 salah");

        -- Klik kiri & kanan
        send_pkt4('1', '0', '0', 0, 0, 0);
        check(got_cl and btn_l = '1', "click_l gagal");
        send_pkt4('1', '0', '0', 0, 0, 0);
        check(not got_cl, "click_l tidak boleh berulang saat ditahan");
        send_pkt4('0', '1', '0', 0, 0, 0);
        check(got_cr and btn_l = '0' and btn_r = '1', "click_r gagal");
        send_pkt4('0', '0', '0', 0, 0, 0);

        -- Scroll atas & bawah
        send_pkt4('0', '0', '0', 0, 0, 1);
        check(got_sd and not got_su, "scroll_dn gagal");
        send_pkt4('0', '0', '0', 0, 0, -1);
        check(got_su and not got_sd, "scroll_up gagal");

        -- Fase 2: Reset & fallback 3-byte (ID = 0x00)
        rst <= '1'; wait for 100 ns; rst <= '0';
        run_init(x"00");
        wait for 300 ns;
        check(ready = '1' and has_wheel = '0', "Fallback 3-byte gagal");
        send_pkt3('1', '0', '0', -32, 32);
        check(mouse_x = 256 and mouse_y = 272 and got_cl and not got_su and not got_sd, "Paket 3-byte gagal");

        report "PASS tb_ps2_mouse";
        fin <= true;
        wait;
    end process;
end sim;
