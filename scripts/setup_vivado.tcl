# setup_vivado.tcl : Mengimpor seluruh berkas RTL, simulasi, dan XDC ke proyek Vivado aktif
# serta mengaktifkan VHDL-2008 dengan urutan kompilasi chess_pkg.vhd di posisi teratas.
#
# Pemakaian di Tcl Console Vivado (setelah membuat/membuka proyek xc7a35tcpg236-1):
#   source scripts/setup_vivado.tcl

set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize [file join $script_dir ".."]]

set rtl_order [list \
    "chess_pkg.vhd" \
    "debounce.vhd" \
    "clk_vga_mmcm.vhd" \
    "vga_timing.vhd" \
    "hist.vhd" \
    "chess_clock.vhd" \
    "bin2bcd.vhd" \
    "seg7_driver.vhd" \
    "pseudo_legal.vhd" \
    "chess_engine.vhd" \
    "cpu_player.vhd" \
    "replay.vhd" \
    "anim.vhd" \
    "captured_calc.vhd" \
    "ps2_mouse.vhd" \
    "menu_ctrl.vhd" \
    "game_ctrl.vhd" \
    "piece_rom.vhd" \
    "vga_render.vhd" \
    "top_core.vhd" \
    "top.vhd" \
]

set rtl_files {}
foreach f $rtl_order {
    lappend rtl_files [file join $repo_root "rtl" $f]
}

set sim_files [list \
    [file join $repo_root "sim" "tb_util.vhd"] \
    [file join $repo_root "sim" "tb_captured_calc.vhd"] \
    [file join $repo_root "sim" "tb_ps2_mouse.vhd"] \
    [file join $repo_root "sim" "tb_menu_ctrl.vhd"] \
    [file join $repo_root "sim" "tb_mouse_sys.vhd"] \
]

set xdc_file [file join $repo_root "constraints" "basys3_chess_mouse.xdc"]

set_property target_language VHDL [current_project]
set_property part xc7a35tcpg236-1 [current_project]

add_files -norecurse -fileset sources_1 $rtl_files
add_files -norecurse -fileset constrs_1 $xdc_file
add_files -norecurse -fileset sim_1 $sim_files

set_property file_type {VHDL 2008} [get_files *.vhd]
set_property top top [get_filesets sources_1]
set_property top tb_mouse_sys [get_filesets sim_1]

# Pastikan chess_pkg.vhd berada di urutan paling awal pada fileset sources_1 dan sim_1
reorder_files -fileset sources_1 -front [get_files [file join $repo_root "rtl" "chess_pkg.vhd"]]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "INFO: Proyek Vivado siap untuk xc7a35tcpg236-1 (VHDL-2008, 21 RTL, 5 SIM, 1 XDC)."
