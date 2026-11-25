-- game_ctrl.vhd : kursor + pilih bidak + perintah ke chess_engine + popup promosi & konfirmasi.
--   Mendukung kontrol hybrid tombol Basys 3 DAN mouse PS/2 (papan 800x600 + klik kotak popup).
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.chess_pkg.all;

entity game_ctrl is
    port (
        clk, rst : in std_logic;
        b_up, b_dn, b_lf, b_rt, b_ct : in std_logic;     -- pulsa 1 clock tombol
        m_move_sq   : in std_logic;                      -- pulsa saat mouse bergerak di papan
        m_sq        : in std_logic_vector(5 downto 0);   -- kotak di bawah pointer mouse
        m_x, m_y    : in unsigned(10 downto 0);          -- koordinat pointer untuk hitbox popup
        m_inb       : in std_logic;                      -- '1' jika pointer di dalam papan
        m_click_l   : in std_logic;                      -- pulsa 1 clock klik kiri
        m_click_r   : in std_logic;                      -- pulsa 1 clock klik kanan
        m_sc_up     : in std_logic;                      -- pulsa 1 clock scroll atas
        m_sc_dn     : in std_logic;                      -- pulsa 1 clock scroll bawah
        -- dari mesin
        busy        : in std_logic;
        board       : in board_t;
        turn        : in std_logic;
        status      : in std_logic_vector(1 downto 0);
        timeout     : in std_logic_vector(1 downto 0);   -- 0 normal, 1/2 = waktu putih/hitam habis
        undo_edge   : in std_logic;                      -- pulsa perintah undo
        resign_edge : in std_logic;                      -- pulsa perintah menyerah
        offer_edge  : in std_logic;                      -- pulsa perintah tawaran remis
        dest_mask   : in std_logic_vector(63 downto 0);
        cpu_en      : in std_logic;                      -- mode lawan komputer: undo membatalkan 2 langkah
        undo_cnt    : in std_logic_vector(1 downto 0);   -- jumlah langkah yang bisa dibatalkan di mesin
        -- ke mesin
        cmd_gen     : out std_logic := '0';
        cmd_move    : out std_logic := '0';
        cmd_undo    : out std_logic := '0';
        cmd_from    : out std_logic_vector(5 downto 0) := (others => '0');
        cmd_to      : out std_logic_vector(5 downto 0) := (others => '0');
        cmd_promo   : out std_logic_vector(1 downto 0) := "00";   -- 0 ratu, 1 benteng, 2 gajah, 3 kuda
        -- tampilan
        cursor      : out std_logic_vector(5 downto 0) := "001100";
        sel_valid   : out std_logic := '0';
        sel_sq      : out std_logic_vector(5 downto 0) := (others => '0');
        promo_active: out std_logic;
        ctl_idle    : out std_logic;                     -- tidak sedang mengurus perintah / menu
        promo_choice: out std_logic_vector(1 downto 0) := "00";
        result      : out std_logic_vector(1 downto 0) := "00";   -- 0 jalan, 1 putih menyerah, 2 hitam menyerah, 3 remis sepakat
        prompt      : out std_logic_vector(1 downto 0) := "00"    -- 0 tidak ada, 1 tawaran remis, 2 konfirmasi menyerah
    );
end game_ctrl;

architecture rtl of game_ctrl is
    type state_t is (S_IDLE, S_ISSUE, S_WAIT, S_PROMO);
    signal st : state_t := S_IDLE;
    signal promo_to : std_logic_vector(5 downto 0) := (others => '0');
    signal pc, sel_pc : std_logic_vector(3 downto 0);
    signal own, over, sel_pawn, last_rank, frozen : std_logic;
    signal undo_pend, resign_pend, offer_pend, undo2 : std_logic := '0';
    signal m_click_l_d : std_logic := '0';
    signal ct_eff, lf_eff, rt_eff : std_logic;
    signal in_prm0, in_prm1, in_prm2, in_prm3, in_cfm_yes, in_cfm_no : std_logic;
begin
    pc <= get_sq(board, cursor);
    own <= '1' when pc(2 downto 0) /= "000" and pc(3) = turn else '0';
    over <= '1' when status = "10" or status = "11" or timeout /= "00" or result /= "00" else '0';
    sel_pc <= get_sq(board, sel_sq);
    sel_pawn <= '1' when sel_pc(2 downto 0) = "001" else '0';
    last_rank <= '1' when (turn = '1' and cursor(5 downto 3) = "000") or (turn = '0' and cursor(5 downto 3) = "111") else '0';
    frozen <= '1' when st = S_PROMO or prompt /= "00" else '0';

    -- Hitbox popup promosi (4 kotak) & konfirmasi ([ YA ] / [ TIDAK ])
    in_prm0 <= '1' when m_y >= PRM_Y0 and m_y <= PRM_Y1 and m_x >= PRM_B0_X0 and m_x <= PRM_B0_X1 else '0';
    in_prm1 <= '1' when m_y >= PRM_Y0 and m_y <= PRM_Y1 and m_x >= PRM_B1_X0 and m_x <= PRM_B1_X1 else '0';
    in_prm2 <= '1' when m_y >= PRM_Y0 and m_y <= PRM_Y1 and m_x >= PRM_B2_X0 and m_x <= PRM_B2_X1 else '0';
    in_prm3 <= '1' when m_y >= PRM_Y0 and m_y <= PRM_Y1 and m_x >= PRM_B3_X0 and m_x <= PRM_B3_X1 else '0';
    in_cfm_yes <= '1' when m_y >= CFM_Y0 and m_y <= CFM_Y1 and m_x >= CFM_YES_X0 and m_x <= CFM_YES_X1 else '0';
    in_cfm_no  <= '1' when m_y >= CFM_Y0 and m_y <= CFM_Y1 and m_x >= CFM_NO_X0  and m_x <= CFM_NO_X1  else '0';

    -- Tunda klik papan 1 clock agar cursor sudah mengarah ke m_sq sebelum pc/own/dest_mask dibaca
    ct_eff <= b_ct or m_click_l_d;
    lf_eff <= b_lf or m_sc_up;
    rt_eff <= b_rt or m_sc_dn;

    promo_active <= '1' when st = S_PROMO else '0';
    ctl_idle     <= '1' when st = S_IDLE and undo_pend = '0' and resign_pend = '0' and offer_pend = '0' and
                             prompt = "00" and m_click_l = '0' and m_click_l_d = '0' else '0';

    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                cursor <= "001100";  sel_valid <= '0';  sel_sq <= (others => '0');
                cmd_gen <= '0';  cmd_move <= '0';  cmd_undo <= '0';
                cmd_from <= (others => '0');  cmd_to <= (others => '0');
                cmd_promo <= "00";  promo_choice <= "00";  promo_to <= (others => '0');
                result <= "00";  prompt <= "00";
                undo_pend <= '0';  resign_pend <= '0';  offer_pend <= '0';  undo2 <= '0';
                m_click_l_d <= '0';
                st <= S_IDLE;
            else
                cmd_gen <= '0';  cmd_move <= '0';  cmd_undo <= '0';
                if frozen = '0' and over = '0' and m_click_l = '1' and m_inb = '1' then
                    m_click_l_d <= '1';
                else
                    m_click_l_d <= '0';
                end if;

                if undo_edge   = '1' then undo_pend   <= '1'; end if;
                if resign_edge = '1' then resign_pend <= '1'; end if;
                if offer_edge  = '1' then offer_pend  <= '1'; end if;

                if frozen = '0' then
                    if m_move_sq = '1' or (m_click_l = '1' and m_inb = '1') then
                        cursor <= m_sq;
                    else
                        if b_up = '1' then cursor(5 downto 3) <= std_logic_vector(unsigned(cursor(5 downto 3)) + 1); end if;
                        if b_dn = '1' then cursor(5 downto 3) <= std_logic_vector(unsigned(cursor(5 downto 3)) - 1); end if;
                        if b_rt = '1' then cursor(2 downto 0) <= std_logic_vector(unsigned(cursor(2 downto 0)) + 1); end if;
                        if b_lf = '1' then cursor(2 downto 0) <= std_logic_vector(unsigned(cursor(2 downto 0)) - 1); end if;
                    end if;
                end if;
                if over = '1' then prompt <= "00"; end if;

                case st is
                when S_IDLE =>
                    if busy = '0' then
                        if undo_pend = '1' then
                            undo_pend <= '0';
                            if timeout = "00" and result = "00" and prompt = "00" then
                                cmd_undo <= '1';  sel_valid <= '0';  st <= S_ISSUE;
                                if cpu_en = '1' and turn = '0' and undo_cnt = "10" then undo2 <= '1'; else undo2 <= '0'; end if;
                            end if;
                        elsif resign_pend = '1' or offer_pend = '1' then
                            resign_pend <= '0';  offer_pend <= '0';
                            if over = '0' and prompt = "00" then
                                if resign_pend = '1' then prompt <= "10"; else prompt <= "01"; end if;
                            end if;
                        elsif prompt /= "00" then
                            if b_ct = '1' or (m_click_l = '1' and in_cfm_yes = '1') then
                                if prompt = "01" then result <= "11";
                                elsif turn = '1' then result <= "10";
                                else result <= "01";
                                end if;
                                prompt <= "00";  sel_valid <= '0';
                            elsif b_dn = '1' or m_click_r = '1' or (m_click_l = '1' and in_cfm_no = '1') then
                                prompt <= "00";
                            end if;
                        elsif m_click_r = '1' and over = '0' then
                            sel_valid <= '0';
                        elsif ct_eff = '1' and over = '0' then
                            if sel_valid = '0' then
                                if own = '1' then
                                    sel_sq <= cursor;  sel_valid <= '1';
                                    cmd_gen <= '1';  cmd_from <= cursor;  st <= S_ISSUE;
                                end if;
                            elsif cursor = sel_sq then
                                sel_valid <= '0';
                            elsif dest_mask(to_integer(unsigned(cursor))) = '1' then
                                if sel_pawn = '1' and last_rank = '1' then
                                    promo_to <= cursor;  promo_choice <= "00";  st <= S_PROMO;
                                else
                                    cmd_move <= '1';  cmd_from <= sel_sq;  cmd_to <= cursor;  cmd_promo <= "00";
                                    sel_valid <= '0';  st <= S_ISSUE;
                                end if;
                            elsif own = '1' then
                                sel_sq <= cursor;
                                cmd_gen <= '1';  cmd_from <= cursor;  st <= S_ISSUE;
                            end if;
                        end if;
                    end if;
                when S_ISSUE =>
                    st <= S_WAIT;
                when S_WAIT =>
                    if busy = '0' then
                        if undo2 = '1' then cmd_undo <= '1';  undo2 <= '0';  st <= S_ISSUE;
                        else st <= S_IDLE;
                        end if;
                    end if;
                when S_PROMO =>
                    resign_pend <= '0';  offer_pend <= '0';
                    if over = '1' then
                        st <= S_IDLE;
                    elsif rt_eff = '1' then
                        promo_choice <= std_logic_vector(unsigned(promo_choice) + 1);
                    elsif lf_eff = '1' then
                        promo_choice <= std_logic_vector(unsigned(promo_choice) - 1);
                    elsif b_ct = '1' then
                        cmd_move <= '1';  cmd_from <= sel_sq;  cmd_to <= promo_to;  cmd_promo <= promo_choice;
                        sel_valid <= '0';  st <= S_ISSUE;
                    elsif m_click_l = '1' and in_prm0 = '1' then
                        cmd_move <= '1';  cmd_from <= sel_sq;  cmd_to <= promo_to;  cmd_promo <= "00";
                        sel_valid <= '0';  st <= S_ISSUE;
                    elsif m_click_l = '1' and in_prm1 = '1' then
                        cmd_move <= '1';  cmd_from <= sel_sq;  cmd_to <= promo_to;  cmd_promo <= "01";
                        sel_valid <= '0';  st <= S_ISSUE;
                    elsif m_click_l = '1' and in_prm2 = '1' then
                        cmd_move <= '1';  cmd_from <= sel_sq;  cmd_to <= promo_to;  cmd_promo <= "10";
                        sel_valid <= '0';  st <= S_ISSUE;
                    elsif m_click_l = '1' and in_prm3 = '1' then
                        cmd_move <= '1';  cmd_from <= sel_sq;  cmd_to <= promo_to;  cmd_promo <= "11";
                        sel_valid <= '0';  st <= S_ISSUE;
                    elsif b_dn = '1' or m_click_r = '1' then
                        st <= S_IDLE;
                    end if;
                end case;
            end if;
        end if;
    end process;
end rtl;
