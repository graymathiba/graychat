@echo off
setlocal enabledelayedexpansion
echo Launching Grychat Peer 1 and Peer 2 (Debug Mode)...

:: Build with dart-define from .env
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

if not exist "build\windows\x64\runner\Debug\grychat.exe" (
    echo Building grychat.exe...
    flutter build windows --debug%DART_DEFINES%
    if errorlevel 1 (
        echo ERROR: Build failed.
        pause
        exit /b 1
    )
)

set EXE_DIR=%CD%\build\windows\x64\runner\Debug
set EXE=grychat.exe

if not exist "%EXE_DIR%\%EXE%" (
    echo ERROR: grychat.exe not found at %EXE_DIR%\%EXE%
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
pause
