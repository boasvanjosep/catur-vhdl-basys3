-- ps2_mouse.vhd : Pengendali PS/2 dua arah dengan dukungan IntelliMouse (scroll wheel)
--   untuk layar 800x600 (papan 512x512 pada offset BOARD_X0=32, BOARD_Y0=48, petak 64x64).
--   Otomatis retry jika mouse belum terpasang atau baru dicolok belakangan.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.chess_pkg.all;

entity ps2_mouse is
    generic (
        INIT_WAIT_CLKS : integer := 1_000_000; -- 10 ms pada 100 MHz
        INHIBIT_CLKS   : integer := 12_000;    -- 120 us pada 100 MHz
        FILTER_BITS    : integer := 4
    );
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        ps2_clk   : inout std_logic;
        ps2_data  : inout std_logic;
        mouse_x   : out unsigned(10 downto 0) := to_unsigned(288, 11);
        mouse_y   : out unsigned(10 downto 0) := to_unsigned(304, 11);
        mouse_sq  : out std_logic_vector(5 downto 0);
        mouse_inb : out std_logic;
        moved     : out std_logic := '0';
        click_l   : out std_logic := '0';
        click_r   : out std_logic := '0';
        click_m   : out std_logic := '0';
        btn_l     : out std_logic := '0';
        btn_r     : out std_logic := '0';
        scroll_up : out std_logic := '0';
        scroll_dn : out std_logic := '0';
        has_wheel : out std_logic := '0';
        ready     : out std_logic := '0'
    );
end ps2_mouse;

architecture rtl of ps2_mouse is
    function max_i(a, b : integer) return integer is
    begin
        if a > b then return a; else return b; end if;
    end function;

    function odd_parity(b : std_logic_vector(7 downto 0)) return std_logic is
    begin
        return not (b(0) xor b(1) xor b(2) xor b(3) xor b(4) xor b(5) xor b(6) xor b(7));
    end function;

    constant START_HOLD_CLKS : integer := max_i(4, INHIBIT_CLKS / 12);
    constant RX_WD_CLKS      : integer := max_i(200, INHIBIT_CLKS * 40);
    constant TX_WD_CLKS      : integer := max_i(400, INHIBIT_CLKS * 200);
    constant BAT_WAIT_CLKS   : integer := max_i(400, INIT_WAIT_CLKS * 40);
    constant ACK_WAIT_CLKS   : integer := max_i(400, INHIBIT_CLKS * 200);

    -- Kontrol open-drain
    signal clk_oe, data_oe : std_logic := '0';

    -- Sinkronisasi & glitch filter
    signal clk_s0, clk_s1   : std_logic := '1';
    signal data_s0, data_s1 : std_logic := '1';
    signal clk_flt, data_flt : std_logic_vector(FILTER_BITS - 1 downto 0) := (others => '1');
    signal clk_f, clk_fp, data_f : std_logic := '1';
    signal clk_fall : std_logic := '0';

    -- Transceiver PS/2 tingkat rendah
    type phy_st_t is (PHY_RX, PHY_TX_INH, PHY_TX_START, PHY_TX_REL_CLK, PHY_TX_BITS, PHY_TX_ACK, PHY_TX_IDLE);
    signal phy_st     : phy_st_t := PHY_RX;
    signal tx_start   : std_logic := '0';
    signal tx_byte    : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_shift   : std_logic_vector(8 downto 0) := (others => '0');
    signal tx_bit_cnt : integer range 0 to 11 := 0;
    signal phy_timer  : integer range 0 to TX_WD_CLKS := 0;
    signal tx_done, tx_err : std_logic := '0';

    signal rx_active  : std_logic := '0';
    signal rx_cnt     : integer range 0 to 11 := 0;
    signal rx_data    : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_par     : std_logic := '0';
    signal rx_stop    : std_logic := '0';
    signal rx_wd      : integer range 0 to RX_WD_CLKS := 0;
    signal rx_done    : std_logic := '0';
    signal rx_byte    : std_logic_vector(7 downto 0) := (others => '0');

    -- FSM inisialisasi IntelliMouse & penerimaan paket stream
    type init_st_t is (
        ST_WAIT_INIT,
        ST_TX_CMD,
        ST_WAIT_TX,
        ST_WAIT_ACK,
        ST_WAIT_BAT_AA,
        ST_WAIT_BAT_00,
        ST_WAIT_DEVID,
        ST_STREAM
    );
    signal ist        : init_st_t := ST_WAIT_INIT;
    signal step_idx   : integer range 0 to 9 := 0;
    signal wait_timer : integer range 0 to BAT_WAIT_CLKS := 0;

    signal pkt_idx   : integer range 0 to 3 := 0;
    signal pkt_b0    : std_logic_vector(7 downto 0) := (others => '0');
    signal pkt_b1    : std_logic_vector(7 downto 0) := (others => '0');
    signal pkt_b2    : std_logic_vector(7 downto 0) := (others => '0');
    signal pkt_wd    : integer range 0 to RX_WD_CLKS := 0;

    signal mouse_x_r   : unsigned(10 downto 0) := to_unsigned(288, 11);
    signal mouse_y_r   : unsigned(10 downto 0) := to_unsigned(304, 11);
    signal btn_l_r     : std_logic := '0';
    signal btn_r_r     : std_logic := '0';
    signal btn_m_r     : std_logic := '0';
    signal has_wheel_r : std_logic := '0';
    signal ready_r     : std_logic := '0';
    signal inb_i       : std_logic;
    signal bx_rel, by_rel : unsigned(10 downto 0);

    function cmd_for_step(idx : integer) return std_logic_vector is
    begin
        case idx is
            when 0 => return x"FF";
            when 1 => return x"F3";
            when 2 => return x"C8";
            when 3 => return x"F3";
            when 4 => return x"64";
            when 5 => return x"F3";
            when 6 => return x"50";
            when 7 => return x"F2";
            when 8 => return x"F4";
            when others => return x"F4";
        end case;
    end function;
begin
    ps2_clk  <= '0' when clk_oe  = '1' else 'Z';
    ps2_data <= '0' when data_oe = '1' else 'Z';

    mouse_x   <= mouse_x_r;
    mouse_y   <= mouse_y_r;
    btn_l     <= btn_l_r;
    btn_r     <= btn_r_r;
    has_wheel <= has_wheel_r;
    ready     <= ready_r;

    inb_i <= '1' when mouse_x_r >= BOARD_X0 and mouse_x_r < BOARD_X0 + BOARD_SZ and
                      mouse_y_r >= BOARD_Y0 and mouse_y_r < BOARD_Y0 + BOARD_SZ else '0';
    mouse_inb <= inb_i;
    bx_rel    <= mouse_x_r - BOARD_X0;
    by_rel    <= mouse_y_r - BOARD_Y0;
    mouse_sq  <= std_logic_vector((7 - by_rel(8 downto 6)) & bx_rel(8 downto 6)) when inb_i = '1'
                 else (others => '0');

    -- ---------------- Sinkronisasi & Filter Glitch ----------------
    process (clk)
        constant ALL_ONE  : std_logic_vector(FILTER_BITS - 1 downto 0) := (others => '1');
        constant ALL_ZERO : std_logic_vector(FILTER_BITS - 1 downto 0) := (others => '0');
    begin
        if rising_edge(clk) then
            if rst = '1' then
                clk_s0   <= '1';  clk_s1   <= '1';
                data_s0  <= '1';  data_s1  <= '1';
                clk_flt  <= ALL_ONE;
                data_flt <= ALL_ONE;
                clk_f    <= '1';  clk_fp   <= '1';
                data_f   <= '1';
            else
                clk_s0  <= to_X01(ps2_clk);
                clk_s1  <= clk_s0;
                data_s0 <= to_X01(ps2_data);
                data_s1 <= data_s0;

                clk_flt  <= clk_flt(FILTER_BITS - 2 downto 0) & clk_s1;
                data_flt <= data_flt(FILTER_BITS - 2 downto 0) & data_s1;

                clk_fp <= clk_f;
                if clk_flt = ALL_ONE then
                    clk_f <= '1';
                elsif clk_flt = ALL_ZERO then
                    clk_f <= '0';
                end if;

                if data_flt = ALL_ONE then
                    data_f <= '1';
                elsif data_flt = ALL_ZERO then
                    data_f <= '0';
                end if;
            end if;
        end if;
    end process;

    clk_fall <= '1' when clk_fp = '1' and clk_f = '0' else '0';

    -- ---------------- Transceiver PS/2 (TX & RX) ----------------
    process (clk)
        variable par_ok : std_logic;
    begin
        if rising_edge(clk) then
            tx_done <= '0';
            tx_err  <= '0';
            rx_done <= '0';

            if rst = '1' then
                phy_st     <= PHY_RX;
                clk_oe     <= '0';
                data_oe    <= '0';
                tx_bit_cnt <= 0;
                phy_timer  <= 0;
                rx_active  <= '0';
                rx_cnt     <= 0;
                rx_wd      <= 0;
            else
                case phy_st is
                when PHY_RX =>
                    clk_oe  <= '0';
                    data_oe <= '0';
                    if tx_start = '1' then
                        rx_active  <= '0';
                        rx_cnt     <= 0;
                        rx_wd      <= 0;
                        tx_shift   <= odd_parity(tx_byte) & tx_byte;
                        tx_bit_cnt <= 0;
                        phy_timer  <= 0;
                        clk_oe     <= '1';
                        data_oe    <= '0';
                        phy_st     <= PHY_TX_INH;
                    else
                        if rx_active = '1' then
                            if rx_wd = RX_WD_CLKS then
                                rx_active <= '0';
                                rx_cnt    <= 0;
                                rx_wd     <= 0;
                            else
                                rx_wd <= rx_wd + 1;
                            end if;
                        end if;

                        if clk_fall = '1' then
                            rx_wd <= 0;
                            if rx_active = '0' then
                                if data_f = '0' then
                                    rx_active <= '1';
                                    rx_cnt    <= 1;
                                end if;
                            else
                                if rx_cnt <= 8 then
                                    rx_data(rx_cnt - 1) <= data_f;
                                    rx_cnt <= rx_cnt + 1;
                                elsif rx_cnt = 9 then
                                    rx_par <= data_f;
                                    rx_cnt <= 10;
                                elsif rx_cnt = 10 then
                                    rx_stop <= data_f;
                                    rx_cnt  <= 11;
                                end if;
                            end if;
                        elsif rx_active = '1' and rx_cnt = 11 and clk_f = '1' then
                            par_ok := rx_data(0) xor rx_data(1) xor rx_data(2) xor rx_data(3) xor
                                      rx_data(4) xor rx_data(5) xor rx_data(6) xor rx_data(7) xor rx_par;
                            if rx_stop = '1' and par_ok = '1' then
                                rx_byte <= rx_data;
                                rx_done <= '1';
                            end if;
                            rx_active <= '0';
                            rx_cnt    <= 0;
                            rx_wd     <= 0;
                        end if;
                    end if;

                when PHY_TX_INH =>
                    clk_oe  <= '1';
                    data_oe <= '0';
                    if phy_timer >= INHIBIT_CLKS - 1 then
                        phy_timer <= 0;
                        data_oe   <= '1';
                        phy_st    <= PHY_TX_START;
                    else
                        phy_timer <= phy_timer + 1;
                    end if;

                when PHY_TX_START =>
                    clk_oe  <= '1';
                    data_oe <= '1';
                    if phy_timer >= START_HOLD_CLKS - 1 then
                        phy_timer <= 0;
                        clk_oe    <= '0';
                        phy_st    <= PHY_TX_REL_CLK;
                    else
                        phy_timer <= phy_timer + 1;
                    end if;

                when PHY_TX_REL_CLK =>
                    clk_oe  <= '0';
                    data_oe <= '1';
                    if clk_f = '1' then
                        phy_timer <= 0;
                        phy_st    <= PHY_TX_BITS;
                    elsif phy_timer >= TX_WD_CLKS then
                        clk_oe  <= '0';
                        data_oe <= '0';
                        tx_err  <= '1';
                        phy_st  <= PHY_RX;
                    else
                        phy_timer <= phy_timer + 1;
                    end if;

                when PHY_TX_BITS =>
                    clk_oe <= '0';
                    if clk_fall = '1' then
                        phy_timer <= 0;
                        if tx_bit_cnt < 9 then
                            data_oe    <= not tx_shift(tx_bit_cnt);
                            tx_bit_cnt <= tx_bit_cnt + 1;
                        else
                            data_oe <= '0';
                            phy_st  <= PHY_TX_ACK;
                        end if;
                    elsif phy_timer >= TX_WD_CLKS then
                        clk_oe  <= '0';
                        data_oe <= '0';
                        tx_err  <= '1';
                        phy_st  <= PHY_RX;
                    else
                        phy_timer <= phy_timer + 1;
                    end if;

                when PHY_TX_ACK =>
                    clk_oe  <= '0';
                    data_oe <= '0';
                    if clk_fall = '1' then
                        phy_timer <= 0;
                        phy_st    <= PHY_TX_IDLE;
                    elsif phy_timer >= TX_WD_CLKS then
                        tx_err <= '1';
                        phy_st <= PHY_RX;
                    else
                        phy_timer <= phy_timer + 1;
                    end if;

                when PHY_TX_IDLE =>
                    clk_oe  <= '0';
                    data_oe <= '0';
                    if clk_f = '1' and data_f = '1' then
                        tx_done <= '1';
                        phy_st  <= PHY_RX;
                    elsif phy_timer >= TX_WD_CLKS then
                        tx_err <= '1';
                        phy_st <= PHY_RX;
                    else
                        phy_timer <= phy_timer + 1;
                    end if;
                end case;
            end if;
        end if;
    end process;

    -- ---------------- FSM Inisialisasi & Pemroses Paket ----------------
    process (clk)
        variable dx_s, dy_s : signed(11 downto 0);
        variable nx_s, ny_s : signed(11 downto 0);
        variable nx_u, ny_u : unsigned(10 downto 0);
        variable dz_s       : signed(3 downto 0);
        variable bl_n, br_n, bm_n : std_logic;

        procedure commit_packet(b0, b1, b2, b3 : std_logic_vector(7 downto 0); wheel : std_logic) is
        begin
            dx_s := resize(signed(b0(4) & b1), 12);
            dy_s := resize(signed(b0(5) & b2), 12);
            nx_s := signed('0' & mouse_x_r) + dx_s;
            ny_s := signed('0' & mouse_y_r) - dy_s;

            if nx_s < 0 then nx_u := to_unsigned(0, 11);
            elsif nx_s > SCR_W - 1 then nx_u := to_unsigned(SCR_W - 1, 11);
            else nx_u := unsigned(nx_s(10 downto 0));
            end if;

            if ny_s < 0 then ny_u := to_unsigned(0, 11);
            elsif ny_s > SCR_H - 1 then ny_u := to_unsigned(SCR_H - 1, 11);
            else ny_u := unsigned(ny_s(10 downto 0));
            end if;

            if nx_u /= mouse_x_r or ny_u /= mouse_y_r then
                moved <= '1';
            end if;
            mouse_x_r <= nx_u;
            mouse_y_r <= ny_u;

            bl_n := b0(0);
            br_n := b0(1);
            bm_n := b0(2);
            if bl_n = '1' and btn_l_r = '0' then click_l <= '1'; end if;
            if br_n = '1' and btn_r_r = '0' then click_r <= '1'; end if;
            if bm_n = '1' and btn_m_r = '0' then click_m <= '1'; end if;
            btn_l_r <= bl_n;
            btn_r_r <= br_n;
            btn_m_r <= bm_n;

            if wheel = '1' then
                dz_s := signed(b3(3 downto 0));
                if dz_s > 0 then
                    scroll_dn <= '1';
                elsif dz_s < 0 then
                    scroll_up <= '1';
                end if;
            end if;
        end procedure;
    begin
        if rising_edge(clk) then
            tx_start  <= '0';
            moved     <= '0';
            click_l   <= '0';
            click_r   <= '0';
            click_m   <= '0';
            scroll_up <= '0';
            scroll_dn <= '0';

            if rst = '1' then
                ist         <= ST_WAIT_INIT;
                step_idx    <= 0;
                wait_timer  <= 0;
                pkt_idx     <= 0;
                pkt_wd      <= 0;
                mouse_x_r   <= to_unsigned(288, 11);
                mouse_y_r   <= to_unsigned(304, 11);
                btn_l_r     <= '0';
                btn_r_r     <= '0';
                btn_m_r     <= '0';
                has_wheel_r <= '0';
                ready_r     <= '0';
            else
                case ist is
                when ST_WAIT_INIT =>
                    ready_r     <= '0';
                    has_wheel_r <= '0';
                    step_idx    <= 0;
                    if wait_timer >= INIT_WAIT_CLKS - 1 then
                        wait_timer <= 0;
                        ist        <= ST_TX_CMD;
                    else
                        wait_timer <= wait_timer + 1;
                    end if;

                when ST_TX_CMD =>
                    tx_byte  <= cmd_for_step(step_idx);
                    tx_start <= '1';
                    ist      <= ST_WAIT_TX;

                when ST_WAIT_TX =>
                    if tx_done = '1' then
                        wait_timer <= 0;
                        ist        <= ST_WAIT_ACK;
                    elsif tx_err = '1' then
                        wait_timer <= 0;
                        ist        <= ST_WAIT_INIT;
                    end if;

                when ST_WAIT_ACK =>
                    if rx_done = '1' then
                        if rx_byte = x"FA" then
                            wait_timer <= 0;
                            if step_idx = 0 then
                                ist <= ST_WAIT_BAT_AA;
                            elsif step_idx = 7 then
                                ist <= ST_WAIT_DEVID;
                            elsif step_idx = 8 then
                                ready_r <= '1';
                                pkt_idx <= 0;
                                pkt_wd  <= 0;
                                ist     <= ST_STREAM;
                            else
                                step_idx <= step_idx + 1;
                                ist      <= ST_TX_CMD;
                            end if;
                        elsif rx_byte = x"FE" then
                            ist <= ST_TX_CMD;
                        else
                            wait_timer <= 0;
                            ist        <= ST_WAIT_INIT;
                        end if;
                    elsif wait_timer >= ACK_WAIT_CLKS then
                        wait_timer <= 0;
                        ist        <= ST_WAIT_INIT;
                    else
                        wait_timer <= wait_timer + 1;
                    end if;

                when ST_WAIT_BAT_AA =>
                    if rx_done = '1' then
                        if rx_byte = x"AA" then
                            wait_timer <= 0;
                            ist        <= ST_WAIT_BAT_00;
                        end if;
                    elsif wait_timer >= BAT_WAIT_CLKS then
                        wait_timer <= 0;
                        step_idx   <= 1;
                        ist        <= ST_TX_CMD;
                    else
                        wait_timer <= wait_timer + 1;
                    end if;

                when ST_WAIT_BAT_00 =>
                    if rx_done = '1' then
                        wait_timer <= 0;
                        step_idx   <= 1;
                        ist        <= ST_TX_CMD;
                    elsif wait_timer >= ACK_WAIT_CLKS then
                        wait_timer <= 0;
                        step_idx   <= 1;
                        ist        <= ST_TX_CMD;
                    else
                        wait_timer <= wait_timer + 1;
                    end if;

                when ST_WAIT_DEVID =>
                    if rx_done = '1' then
                        if rx_byte = x"03" or rx_byte = x"04" then
                            has_wheel_r <= '1';
                        else
                            has_wheel_r <= '0';
                        end if;
                        wait_timer <= 0;
                        step_idx   <= 8;
                        ist        <= ST_TX_CMD;
                    elsif wait_timer >= ACK_WAIT_CLKS then
                        has_wheel_r <= '0';
                        wait_timer  <= 0;
                        step_idx    <= 8;
                        ist         <= ST_TX_CMD;
                    else
                        wait_timer <= wait_timer + 1;
                    end if;

                when ST_STREAM =>
                    if pkt_idx /= 0 then
                        if pkt_wd >= RX_WD_CLKS then
                            pkt_idx <= 0;
                            pkt_wd  <= 0;
                        else
                            pkt_wd <= pkt_wd + 1;
                        end if;
                    end if;

                    if rx_done = '1' then
                        pkt_wd <= 0;
                        case pkt_idx is
                            when 0 =>
                                if rx_byte(3) = '1' then
                                    pkt_b0  <= rx_byte;
                                    pkt_idx <= 1;
                                end if;
                            when 1 =>
                                pkt_b1  <= rx_byte;
                                pkt_idx <= 2;
                            when 2 =>
                                if has_wheel_r = '1' then
                                    pkt_b2  <= rx_byte;
                                    pkt_idx <= 3;
                                else
                                    commit_packet(pkt_b0, pkt_b1, rx_byte, x"00", '0');
                                    pkt_idx <= 0;
                                end if;
                            when 3 =>
                                commit_packet(pkt_b0, pkt_b1, pkt_b2, rx_byte, '1');
                                pkt_idx <= 0;
                        end case;
                    end if;
                end case;
            end if;
        end if;
    end process;
end rtl;
