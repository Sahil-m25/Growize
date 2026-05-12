# Regenerate Android project structure (v2 embedding, keeps Dart code intact)
$userPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
$machinePath = [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
$env:PATH = "$userPath;$machinePath"

Set-Location "C:\Users\Sahil\Downloads\ARL\arl_app"

Write-Host "Regenerating Android project structure..." -ForegroundColor Cyan
& flutter create --platforms android .

Write-Host ""
Write-Host "Running flutter pub get..." -ForegroundColor Cyan
& flutter pub get

Write-Host ""
Write-Host "Done! Now run: flutter run" -ForegroundColor Green
Write-Host "Press any key to close."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
