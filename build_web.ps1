# Growize — Flutter web release build
# Run from the project root in PowerShell:
#   .\build_web.ps1
#
# Uses --web-renderer auto:
#   mobile browsers  -> html renderer  (no 2 MB WASM download, fast first paint)
#   desktop browsers -> canvaskit      (pixel-perfect fidelity)
#
# After this completes, deploy by dragging build\web into https://app.netlify.com/drop

Write-Host "Building Growize for web..." -ForegroundColor Cyan

& C:\flutter\bin\flutter.bat build web `
    --release `
    --dart-define-from-file=.env.production `
    --web-renderer auto `
    --pwa-strategy offline-first `
    --no-source-maps

if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed." -ForegroundColor Red
    exit 1
}

$sizeMB = [math]::Round((Get-ChildItem "build\web" -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB, 1)
Write-Host ""
Write-Host "Build complete -> build\web ($sizeMB MB total)" -ForegroundColor Green
Write-Host ""
Write-Host "To deploy:" -ForegroundColor Yellow
Write-Host "  1. Go to https://app.netlify.com/drop"
Write-Host "  2. Drag the 'build\web' folder onto the page"
Write-Host "  3. Your app is live at a *.netlify.app URL within seconds"
