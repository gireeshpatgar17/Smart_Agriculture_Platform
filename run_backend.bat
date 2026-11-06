@echo off
echo Starting FastAPI Backend for Smart Agriculture...
cd /d "%~dp0backend"
rem Create backend\myenv and install requirements.txt before running this launcher.
call .\myenv\Scripts\activate.bat
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
pause
