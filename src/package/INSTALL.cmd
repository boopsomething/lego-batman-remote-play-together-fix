@echo off
title SOTAVPN LEGO Batman COOP Fix - Install
set "SCRIPT=%~dp0_SOTAVPN\Install-CoopFix.ps1"
if not exist "%SCRIPT%" (
  echo Package is incomplete: _SOTAVPN\Install-CoopFix.ps1 is missing.
  echo Extract the full archive and try again.
  echo.
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
set "RESULT=%ERRORLEVEL%"
echo.
if not "%RESULT%"=="0" echo Installation failed. Read the error message above.
pause
exit /b %RESULT%
