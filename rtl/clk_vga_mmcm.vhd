-- clk_vga_mmcm.vhd : Pembangkit pixel clock 40 MHz untuk VGA 800x600 @ 60 Hz dari input 100 MHz
--   menggunakan primitif Artix-7 MMCME2_BASE + BUFG (tanpa file IP .xci).
--   Saat SIM_BYPASS = true, memakai clk_in langsung dengan pix_ce 50 MHz agar simulasi cepat.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library UNISIM;
use UNISIM.VComponents.all;

entity clk_vga_mmcm is
    generic (
        SIM_BYPASS : boolean := false
    );
    port (
        clk_in  : in  std_logic;
        pix_clk : out std_logic;
        pix_ce  : out std_logic;
        locked  : out std_logic
    );
end clk_vga_mmcm;

architecture rtl of clk_vga_mmcm is
begin
    g_hw : if not SIM_BYPASS generate
        signal clkfb, clkfb_buf, pix_raw : std_logic;
    begin
        u_mmcm : MMCME2_BASE
            generic map (
                BANDWIDTH          => "OPTIMIZED",
                CLKFBOUT_MULT_F    => 8.0,   -- 100 MHz * 8 = 800 MHz VCO
                CLKIN1_PERIOD      => 10.0,
                CLKOUT0_DIVIDE_F   => 20.0,  -- 800 MHz / 20 = 40.0 MHz
                CLKOUT0_DUTY_CYCLE => 0.5,
                CLKOUT0_PHASE      => 0.0,
                DIVCLK_DIVIDE      => 1,
                STARTUP_WAIT       => FALSE
            )
            port map (
                CLKOUT0   => pix_raw,
                CLKOUT0B  => open,
                CLKOUT1   => open,
                CLKOUT1B  => open,
                CLKOUT2   => open,
                CLKOUT2B  => open,
                CLKOUT3   => open,
                CLKOUT3B  => open,
                CLKOUT4   => open,
                CLKOUT5   => open,
                CLKOUT6   => open,
                CLKFBOUT  => clkfb,
                CLKFBOUTB => open,
                LOCKED    => locked,
                CLKIN1    => clk_in,
                PWRDWN    => '0',
                RST       => '0',
                CLKFBIN   => clkfb_buf
            );

        u_bufg_fb : BUFG port map (I => clkfb,   O => clkfb_buf);
        u_bufg_px : BUFG port map (I => pix_raw, O => pix_clk);
        pix_ce <= '1';
    end generate;

    g_sim : if SIM_BYPASS generate
        signal tog : std_logic := '0';
    begin
        process (clk_in)
        begin
            if rising_edge(clk_in) then
                tog <= not tog;
            end if;
        end process;
        pix_clk <= clk_in;
        pix_ce  <= tog;
        locked  <= '1';
    end generate;
end rtl;
