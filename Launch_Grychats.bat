@echo off
echo Launching Grychat Peer 1 and Peer 2 (Debug Mode)...

set EXE_DIR=c:\Users\PC\GRYCHAT\grychat\build\windows\x64\runner\Debug
set EXE=grychat.exe

if not exist "%EXE_DIR%\%EXE%" (
    echo ERROR: grychat.exe not found at %EXE_DIR%\%EXE%
    echo Please run "flutter build windows --debug" in the grychat folder first.
    pause
    exit /b 1
)

cd /d "%EXE_DIR%"

set APP_PROFILE=peer1
start "Grychat Peer 1" "%EXE%"

ping -n 3 127.0.0.1 >nul

set APP_PROFILE=peer2
start "Grychat Peer 2" "%EXE%"

echo Both instances launched successfully!
