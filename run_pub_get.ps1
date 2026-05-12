# Read the fresh PATH from registry (picks up winget installs without needing a reboot)
$userPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
$machinePath = [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
$env:PATH = "$userPath;$machinePath"

Set-Location "C:\Users\Sahil\Downloads\ARL\arl_app"

# Find flutter
$flutterPath = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutterPath) {
    Write-Host "Flutter not found in PATH. Trying common locations..." -ForegroundColor Yellow
    $candidates = @(
        "C:\flutter\bin\flutter.bat",
        "$env:USERPROFILE\flutter\bin\flutter.bat",
        "$env:LOCALAPPDATA\flutter\bin\flutter.bat",
        "$env:LOCALAPPDATA\Programs\flutter\bin\flutter.bat"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) {
            $flutterPath = $c
            Write-Host "Found Flutter at: $c" -ForegroundColor Green
            break
        }
    }
}

if (-not $flutterPath) {
    Write-Host "ERROR: Flutter not found. Please tell Claude where it was installed." -ForegroundColor Red
    pause
    exit 1
}

Write-Host "Running flutter pub get..." -ForegroundColor Cyan
& flutter pub get

Write-Host ""
Write-Host "Done! Press any key to close."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
