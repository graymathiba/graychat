@echo off
title GryChat Launcher
setlocal enabledelayedexpansion

echo ========================================
echo         GryChat - Starting All
echo ========================================

:: Check for .env file
if not exist "%~dp0.env" (
    echo [WARN] No .env found at %~dp0.env
    echo [WARN] Copy .env.example to .env and fill in your values.
    echo.
)

:: Build Flutter app with dart-define from .env (if present)
echo [1/4] Building Flutter app...
set CMAKE_POLICY_VERSION_MINIMUM=3.5
set DART_DEFINES=
if exist "%~dp0.env" (
    for /f "usebackq tokens=1,2 delims==" %%a in ("%~dp0.env") do (
        if not "%%a"=="" if not "%%a:~0,1"=="#" (
            set "key=%%a"
            set "val=%%b"
            if not "!val!"=="" (
                set "DART_DEFINES=!DART_DEFINES! --dart-define=%%a=%%b"
            )
        )
    )
)
cd /d "%~dp0grychat"
if exist "build\windows\x64\runner\Debug\grychat.exe" (
    echo [SKIP] Binary already exists, delete to force rebuild.
) else (
    flutter build windows --debug%DART_DEFINES%
)
cd /d "%~dp0"

:: Start backend server (tsx, per package.json scripts)
echo [2/4] Starting backend server...
start "GryChat Server" /D "%~dp0backend" cmd /k "npm start"
timeout /t 5 /nobreak >nul

:: Start first instance
echo [3/4] Starting instance 1 (peer1)...
start "GryChat Peer1" cmd /c "set APP_PROFILE=peer1 && "%~dp0grychat\build\windows\x64\runner\Debug\grychat.exe""

:: Start second instance
echo [4/4] Starting instance 2 (peer2)...
start "GryChat Peer2" cmd /c "set APP_PROFILE=peer2 && "%~dp0grychat\build\windows\x64\runner\Debug\grychat.exe""

echo.
echo All started. Close this window or press Ctrl+C to stop.
pause
