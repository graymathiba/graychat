$exe = "c:\Users\PC\GRYCHAT\grychat\build\windows\x64\runner\Release\grychat.exe"

if (-not (Test-Path $exe)) {
    Write-Host "ERROR: grychat.exe not found at $exe" -ForegroundColor Red
    exit
}

Write-Host "Launching Grychat Peer 1..." -ForegroundColor Green
$env:APP_PROFILE = "peer1"
Start-Process -FilePath $exe

Start-Sleep -Seconds 2

Write-Host "Launching Grychat Peer 2..." -ForegroundColor Green
$env:APP_PROFILE = "peer2"
Start-Process -FilePath $exe

Write-Host "Both instances launched successfully!" -ForegroundColor Cyan
