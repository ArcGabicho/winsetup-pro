# WinSetup Pro profile fragment: prompt
#
# A lightweight prompt (cwd + git branch + elevation marker). It backs off
# entirely when posh-git or oh-my-posh are managing the prompt, or when the
# user has already redefined `prompt` themselves.

if (-not (Get-Module -Name 'posh-git') -and -not $env:POSH_THEME) {

    $script:WSPDefaultPrompt = $true

    function global:prompt {
        $lastOk = $?
        $esc = [char]27
        $cwd = $ExecutionContext.SessionState.Path.CurrentLocation.Path.Replace($HOME, '~')

        $branch = ''
        if (Get-Command git -ErrorAction SilentlyContinue) {
            $b = (git rev-parse --abbrev-ref HEAD 2>$null)
            if ($LASTEXITCODE -eq 0 -and $b) { $branch = " $esc[33m($b)$esc[0m" }
        }

        $admin = ''
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        if ((New-Object System.Security.Principal.WindowsPrincipal($id)).IsInRole(
                [System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
            $admin = "$esc[31m#$esc[0m "
        }

        $mark = if ($lastOk) { "$esc[32m" } else { "$esc[31m" }
        "${admin}$esc[36m$cwd$esc[0m$branch`n$mark`u{276f}$esc[0m "
    }
}
