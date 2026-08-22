@echo off
setlocal enabledelayedexpansion

:: Build and run peer 2 with environment variables from .env
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
set APP_PROFILE=peer2
flutter run --debug%DART_DEFINES%
