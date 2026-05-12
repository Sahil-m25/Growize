$env:PATH = "C:\flutter\bin;$env:PATH"
Set-Location "C:\Users\Sahil\Downloads\ARL\arl_app"

Write-Host "Running flutter analyze first..." -ForegroundColor Cyan
flutter analyze 2>&1 | Tee-Object -FilePath "analyze_output.txt"

Write-Host ""
Write-Host "Launching in Chrome..." -ForegroundColor Cyan
flutter run -d chrome 2>&1 | Tee-Object -FilePath "flutter_output.txt"
