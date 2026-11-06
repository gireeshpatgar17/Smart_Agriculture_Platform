@echo off
echo ========================================================
echo  AgroEYE - Setting up ADB USB Reverse Tunnel and Mobile App
echo ========================================================

echo Setting up ADB reverse tunnel on ports 8000 and 8888...
"C:\Users\darsh\AppData\Local\Android\Sdk\platform-tools\adb.exe" reverse tcp:8000 tcp:8000
"C:\Users\darsh\AppData\Local\Android\Sdk\platform-tools\adb.exe" reverse tcp:8888 tcp:8000

echo.
echo Launching Flutter App on connected mobile device...
cd /d "%~dp0frontend"
flutter run -d 7L4T89U4LZSCG6AI
pause
