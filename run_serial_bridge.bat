@echo off
echo ========================================================
echo  AgroEYE - USB Serial to Backend Telemetry Bridge
echo  (100% Offline ^& Jammer-Proof Hardware Mode)
echo ========================================================
echo.
cd /d "%~dp0backend"
call .\myenv\Scripts\activate.bat
python serial_bridge.py
pause
