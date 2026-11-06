@echo off
echo ========================================================
echo  AgroEYE - USB Serial to Backend Telemetry Bridge
echo  (100% Offline ^& Jammer-Proof Hardware Mode)
echo ========================================================
echo.
cd /d "%~dp0backend"
rem Create backend\myenv, install requirements.txt, and install pyserial for USB telemetry.
call .\myenv\Scripts\activate.bat
python serial_bridge.py
pause
