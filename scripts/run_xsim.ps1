# run_xsim.ps1 : Menjalankan kompilasi VHDL-2008 dan seluruh 4 testbench Vivado XSim.
# Pemakaian:
#   powershell -ExecutionPolicy Bypass -File .\scripts\run_xsim.ps1

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$RtlDir   = Join-Path $RepoRoot "rtl"
$SimDir   = Join-Path $RepoRoot "sim"

function Find-VivadoBin {
    if (Get-Command xvhdl -ErrorAction SilentlyContinue) {
        return Split-Path -Parent (Get-Command xvhdl).Source
    }
    $candidates = @()
    foreach ($base in @("C:\AMDDesignTools", "C:\Xilinx\Vivado")) {
        if (Test-Path $base) {
            $candidates += Get-ChildItem -Path $base -Recurse -Filter "xvhdl.bat" -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty DirectoryName
        }
    }
    if ($candidates.Count -gt 0) {
        return ($candidates | Sort-Object -Descending | Select-Object -First 1)
    }
    throw "Vivado XSim (xvhdl) tidak ditemukan di PATH maupun C:\AMDDesignTools / C:\Xilinx\Vivado."
}

$VivadoBin = Find-VivadoBin
$Xvhdl = Join-Path $VivadoBin "xvhdl.bat"
$Xelab = Join-Path $VivadoBin "xelab.bat"
$Xsim  = Join-Path $VivadoBin "xsim.bat"

$WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) "catur_vhdl_basys3_xsim"
if (Test-Path $WorkDir) {
    Remove-Item -Path $WorkDir -Recurse -Force
}
New-Item -ItemType Directory -Path $WorkDir | Out-Null

$RtlOrder = @(
    "chess_pkg.vhd",
    "debounce.vhd",
    "clk_vga_mmcm.vhd",
    "vga_timing.vhd",
    "hist.vhd",
    "chess_clock.vhd",
    "bin2bcd.vhd",
    "seg7_driver.vhd",
    "pseudo_legal.vhd",
    "chess_engine.vhd",
    "cpu_player.vhd",
    "replay.vhd",
    "anim.vhd",
    "captured_calc.vhd",
    "ps2_mouse.vhd",
    "menu_ctrl.vhd",
    "game_ctrl.vhd",
    "piece_rom.vhd",
    "vga_render.vhd",
    "top_core.vhd",
    "top.vhd"
)

$SimOrder = @(
    "tb_util.vhd",
    "tb_captured_calc.vhd",
    "tb_ps2_mouse.vhd",
    "tb_menu_ctrl.vhd",
    "tb_mouse_sys.vhd"
)

$AllFiles = @()
foreach ($f in $RtlOrder) { $AllFiles += (Join-Path $RtlDir $f) }
foreach ($f in $SimOrder) { $AllFiles += (Join-Path $SimDir $f) }

Push-Location $WorkDir
try {
    Write-Host "=== Kompilasi VHDL-2008 (21 RTL + 5 SIM) ===" -ForegroundColor Cyan
    & $Xvhdl --2008 @AllFiles
    if ($LASTEXITCODE -ne 0) { throw "Kompilasi xvhdl gagal ($LASTEXITCODE)" }

    $Testbenches = @("tb_captured_calc", "tb_ps2_mouse", "tb_menu_ctrl", "tb_mouse_sys")
    foreach ($tb in $Testbenches) {
        Write-Host "`n=== Menjalankan $tb ===" -ForegroundColor Cyan
        & $Xelab "work.$tb" -L unisim -s "${tb}_sim"
        if ($LASTEXITCODE -ne 0) { throw "Elaborasi $tb gagal ($LASTEXITCODE)" }

        $out = & $Xsim "${tb}_sim" -runall 2>&1
        $out | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) { throw "Simulasi $tb gagal ($LASTEXITCODE)" }
        if (-not ($out -match "PASS $tb")) {
            throw "Penanda PASS $tb tidak ditemukan pada keluaran XSim!"
        }
    }

    Write-Host "`nSeluruh 4 testbench Vivado XSim LULUS (PASS)." -ForegroundColor Green
}
finally {
    Pop-Location
    if (Test-Path $WorkDir) {
        Remove-Item -Path $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
