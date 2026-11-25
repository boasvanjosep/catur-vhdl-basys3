-- top.vhd : pembungkus tingkat papan Basys 3 (VGA 800x600 @ 60 Hz + Mouse PS/2 + kontrol board).
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity top is
    generic (
        DEBOUNCE      : integer := 1_000_000;
        TICK_CLKS     : integer := 100_000_000;
        PS2_INIT_WAIT : integer := 1_000_000;
        PS2_INHIBIT   : integer := 12_000;
        SIM_BYPASS    : boolean := false
    );
    port (
        clk       : in    std_logic;
        sw_menu   : in    std_logic;
        sw_undo   : in    std_logic;
        sw_remis  : in    std_logic;
        sw_resign : in    std_logic;
        sw_rst    : in    std_logic;
        btnU, btnD, btnL, btnR, btnC : in std_logic;
        PS2Clk    : inout std_logic;
        PS2Data   : inout std_logic;
        led       : out   std_logic_vector(15 downto 0);
        seg       : out   std_logic_vector(6 downto 0);
        dp        : out   std_logic;
        an        : out   std_logic_vector(3 downto 0);
        vgaRed, vgaGreen, vgaBlue : out std_logic_vector(3 downto 0);
        Hsync, Vsync : out std_logic
    );
end top;

architecture rtl of top is
begin
    core : entity work.top_core
        generic map (
            DEBOUNCE      => DEBOUNCE,
            TICK_CLKS     => TICK_CLKS,
            PS2_INIT_WAIT => PS2_INIT_WAIT,
            PS2_INHIBIT   => PS2_INHIBIT,
            SIM_BYPASS    => SIM_BYPASS
        )
        port map (
            clk       => clk,
            sw_menu   => sw_menu,
            sw_undo   => sw_undo,
            sw_remis  => sw_remis,
            sw_resign => sw_resign,
            sw_rst    => sw_rst,
            btnU      => btnU,
            btnD      => btnD,
            btnL      => btnL,
            btnR      => btnR,
            btnC      => btnC,
            PS2Clk    => PS2Clk,
            PS2Data   => PS2Data,
            led       => led,
            seg       => seg,
            dp        => dp,
            an        => an,
            vgaRed    => vgaRed,
            vgaGreen  => vgaGreen,
            vgaBlue   => vgaBlue,
            Hsync     => Hsync,
            Vsync     => Vsync,
            dbg       => open
        );
end rtl;
