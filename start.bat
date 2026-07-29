@echo off
title GryChat Launcher
echo ========================================
echo         GryChat - Starting All
echo ========================================

:: Start backend server
echo [1/3] Starting backend server...
start "GryChat Server" /D "%~dp0backend" npx ts-node index.ts
timeout /t 3 /nobreak >nul

:: Start first instance
echo [2/3] Starting instance 1 (peer1)...
start "GryChat Peer1" cmd /c "set APP_PROFILE=peer1 && "%~dp0grychat\build\windows\x64\runner\Debug\grychat.exe""

:: Start second instance
echo [3/3] Starting instance 2 (peer2)...
start "GryChat Peer2" cmd /c "set APP_PROFILE=peer2 && "%~dp0grychat\build\windows\x64\runner\Debug\grychat.exe""

echo.
echo All started. Close this window or press Ctrl+C to stop.
pause
