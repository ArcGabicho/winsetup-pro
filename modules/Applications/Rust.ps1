# modules/Applications/Rust.ps1 - Rust via rustup (installs rustc + cargo).
# Needs the MSVC build tools / linker for most crates; Visual Studio or the
# "Desktop C++" build tools cover that.

New-WinSetupComponent -Id 'rust' -Name 'Rust' -Category 'Development' `
    -Description 'Rust toolchain (rustup, rustc, cargo)' -Tags @('rust', 'runtime') `
    -Test {
        param($Context)
        $v = Get-WinSetupExeVersion -Command 'rustc'
        if (-not $v) { return New-WinSetupDetectionResult -Installed $false }
        New-WinSetupDetectionResult -Installed $true -Version $v -Summary "rustc $v"
    } `
    -Install {
        param($Context)
        Install-WinSetupWingetPackage -Id 'Rustlang.Rustup' -VerifyCommand 'rustup'
        if (Get-Command rustup -ErrorAction SilentlyContinue) {
            & rustup default stable 2>&1 | ForEach-Object { Write-WinSetupLog -Level DEBUG -Module 'rust' -Message ([string]$_) }
        }
    }
