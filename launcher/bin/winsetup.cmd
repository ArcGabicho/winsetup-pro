@echo off
setlocal
set "_wsp_shim=%~dp0winsetup.ps1"
where pwsh >nul 2>&1
if %errorlevel%==0 (
  pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%_wsp_shim%" %*
) else (
  powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%_wsp_shim%" %*
)
exit /b %errorlevel%
