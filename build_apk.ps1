# Growize — Android release APK (arm64-v8a)
#
# Targets 64-bit ARM only — covers every Android phone released since ~2015
# and produces the smallest possible single-file APK (~30-40% smaller than
# the fat universal build).
#
# Run from the project root in PowerShell:
#   .\build_apk.ps1
#
# Output: build\app\outputs\flutter-apk\app-release.apk

Write-Host "Building Growize APK (arm64)..." -ForegroundColor Cyan

& C:\flutter\bin\flutter.bat build apk `
    --release `
    --target-platform android-arm64 `
    --dart-define-from-file=.env.production `
    --shrink `
    --obfuscate `
    --split-debug-info=build\debug-info

if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed." -ForegroundColor Red
    exit 1
}

$apk = "build\app\outputs\flutter-apk\app-release.apk"
$sizeMB = [math]::Round((Get-Item $apk).Length / 1MB, 1)

Write-Host ""
Write-Host "APK ready -> $apk ($sizeMB MB)" -ForegroundColor Green
Write-Host ""
Write-Host "Share this file directly with investors to sideload," -ForegroundColor Yellow
Write-Host "or upload to the Play Store as an AAB (run build_aab.ps1 for that)." -ForegroundColor Yellow
