@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0stage-rust-engines.ps1" -Latest
echo.
echo Sources downloaded to upstream\staged, NOT activated in Android application.
pause
