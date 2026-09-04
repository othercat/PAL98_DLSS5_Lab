@echo off
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0DLSS5-Lab\Start-DLSS5Lab.ps1"
set "LAB_EXIT=%ERRORLEVEL%"
echo.
if not "%LAB_EXIT%"=="0" echo Test failed. Please send the newest DLSS5-Lab\evidence folder to the package author.
pause
exit /b %LAB_EXIT%
