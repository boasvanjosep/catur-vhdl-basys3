-- anim.vhd : animasi bidak meluncur untuk papan 800x600 (petak 64x64 px dengan offset BOARD_X0/Y0).
--   Mensinkronkan vs (aktif tinggi dari domain pix_clk) dan memicu langkah animasi 16 frame.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.chess_pkg.all;

entity anim is
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;
        vs       : in  std_logic;                       -- vsync aktif tinggi dari vga_timing
        en       : in  std_logic;                       -- opsi animasi aktif
        ev       : in  std_logic;                       -- pulsa: langkah baru
        ev_from  : in  std_logic_vector(5 downto 0);
        ev_to    : in  std_logic_vector(5 downto 0);
        ev_piece : in  std_logic_vector(3 downto 0);
        anim_on  : out std_logic;
        x, y     : out unsigned(10 downto 0);           -- pojok kiri atas kotak melayang
        xe, ye   : out unsigned(10 downto 0);           -- x + 64, y + 64
        piece    : out std_logic_vector(3 downto 0);
        dst      : out std_logic_vector(5 downto 0)
    );
end anim;

architecture rtl of anim is
    signal p          : unsigned(4 downto 0) := (others => '0');
    signal fx, fy, tx, ty : unsigned(10 downto 0) := (others => '0');
    signal vs_s0, vs_s1, vs_s2 : std_logic := '0';
    signal on_r       : std_logic := '0';
    signal frame_tick : std_logic;
    signal dx, dy     : signed(11 downto 0);
    signal mx, my     : signed(16 downto 0);
    signal sx, sy     : signed(11 downto 0);
    signal x_r, y_r, xe_r, ye_r : unsigned(10 downto 0) := (others => '0');
    signal piece_r    : std_logic_vector(3 downto 0) := (others => '0');
    signal dst_r      : std_logic_vector(5 downto 0) := (others => '0');

    function sq_x(col : std_logic_vector(2 downto 0)) return unsigned is
    begin
        return to_unsigned(BOARD_X0, 11) + shift_left(resize(unsigned(col), 11), 6);
    end function;

    function sq_y(row : std_logic_vector(2 downto 0)) return unsigned is
    begin
        return to_unsigned(BOARD_Y0, 11) + shift_left(resize(7 - unsigned(row), 11), 6);
    end function;
begin
    anim_on <= on_r;  x <= x_r;  y <= y_r;  xe <= xe_r;  ye <= ye_r;
    piece <= piece_r; dst <= dst_r;

    frame_tick <= vs_s1 and (not vs_s2);

    dx <= signed('0' & tx) - signed('0' & fx);
    dy <= signed('0' & ty) - signed('0' & fy);
    mx <= resize(dx * signed("0" & std_logic_vector(p)), 17);
    my <= resize(dy * signed("0" & std_logic_vector(p)), 17);
    sx <= signed('0' & fx) + resize(shift_right(mx, 4), 12);
    sy <= signed('0' & fy) + resize(shift_right(my, 4), 12);

    process (clk)
    begin
        if rising_edge(clk) then
            vs_s0 <= vs;
            vs_s1 <= vs_s0;
            vs_s2 <= vs_s1;
            x_r   <= unsigned(sx(10 downto 0));
            y_r   <= unsigned(sy(10 downto 0));
            xe_r  <= unsigned(sx(10 downto 0)) + SQ_SZ;
            ye_r  <= unsigned(sy(10 downto 0)) + SQ_SZ;
            if rst = '1' or en = '0' then
                on_r <= '0';  p <= (others => '0');
            elsif ev = '1' then
                fx <= sq_x(ev_from(2 downto 0));
                fy <= sq_y(ev_from(5 downto 3));
                tx <= sq_x(ev_to(2 downto 0));
                ty <= sq_y(ev_to(5 downto 3));
                piece_r <= ev_piece;  dst_r <= ev_to;
                p <= (others => '0');  on_r <= '1';
            elsif on_r = '1' and frame_tick = '1' then
                if p = 16 then on_r <= '0'; else p <= p + 1; end if;
            end if;
        end if;
    end process;
end rtl;
