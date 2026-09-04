@echo off
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0DLSS5-Lab\Start-PAL-Windowed.ps1" -ClientWidth 640 -ClientHeight 400
exit /b %ERRORLEVEL%
