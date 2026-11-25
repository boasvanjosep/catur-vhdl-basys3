-- vga_timing.vhd : VESA 800x600 @ 60 Hz (pixel clock 40 MHz, polaritas sync positif).
--   Horizontal : 800 aktif, front porch 40, sync 128 (840..967), back porch 88 -> total 1056.
--   Vertikal   : 600 aktif, front porch 1,  sync 4   (601..604), back porch 23 -> total 628.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity vga_timing is
    port (
        pix_clk : in  std_logic;
        pix_ce  : in  std_logic;
        x       : out unsigned(10 downto 0);   -- 0..1055
        y       : out unsigned(10 downto 0);   -- 0..627
        hs      : out std_logic;               -- aktif tinggi
        vs      : out std_logic                -- aktif tinggi
    );
end vga_timing;

architecture rtl of vga_timing is
    signal xr   : unsigned(10 downto 0) := (others => '0');
    signal yr   : unsigned(10 downto 0) := (others => '0');
    signal hs_r : std_logic := '0';
    signal vs_r : std_logic := '0';
begin
    x <= xr;  y <= yr;  hs <= hs_r;  vs <= vs_r;

    process (pix_clk)
    begin
        if rising_edge(pix_clk) then
            if pix_ce = '1' then
                if xr = 1055 then
                    xr <= (others => '0');
                    if yr = 627 then yr <= (others => '0'); else yr <= yr + 1; end if;
                else
                    xr <= xr + 1;
                end if;
                if (xr >= 840) and (xr < 968) then hs_r <= '1'; else hs_r <= '0'; end if;
                if (yr >= 601) and (yr < 605) then vs_r <= '1'; else vs_r <= '0'; end if;
            end if;
        end if;
    end process;
end rtl;
