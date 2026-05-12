# Flutter Auto-Installer
# Downloads Flutter SDK, installs to C:\flutter, adds to PATH, runs pub get

$ErrorActionPreference = "Stop"
$installDir = "C:\flutter"
$pubspecDir = "C:\Users\Sahil\Downloads\ARL\arl_app"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Flutter Auto-Installer" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if flutter already exists somewhere
if (Test-Path "$installDir\bin\flutter.bat") {
    Write-Host "Flutter already found at $installDir" -ForegroundColor Green
} else {
    Write-Host "Fetching latest Flutter stable release info..." -ForegroundColor Yellow
    try {
        $releasesUrl = "https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json"
        $releases = Invoke-RestMethod -Uri $releasesUrl
        $latestHash = $releases.current_release.stable
        $latestRelease = $releases.releases | Where-Object { $_.hash -eq $latestHash }
        $downloadUrl = "https://storage.googleapis.com/flutter_infra_release/releases/" + $latestRelease.archive
        $version = $latestRelease.version
        Write-Host "Latest stable: $version" -ForegroundColor Green
        Write-Host "Download URL: $downloadUrl" -ForegroundColor Gray
    } catch {
        # Fallback to a known good version
        $version = "3.29.3"
        $downloadUrl = "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.29.3-stable.zip"
        Write-Host "Using fallback version: $version" -ForegroundColor Yellow
    }

    $zipPath = "$env:TEMP\flutter_windows.zip"
    Write-Host ""
    Write-Host "Downloading Flutter $version (~700 MB)... this will take a few minutes." -ForegroundColor Yellow

    $ProgressPreference = 'SilentlyContinue'  # much faster download without progress bar
    Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing
    Write-Host "Download complete!" -ForegroundColor Green

    Write-Host "Extracting to $installDir ..." -ForegroundColor Yellow
    if (Test-Path $installDir) { Remove-Item $installDir -Recurse -Force }
    Expand-Archive -Path $zipPath -DestinationPath "C:\" -Force
    Remove-Item $zipPath -Force
    Write-Host "Extraction complete!" -ForegroundColor Green
}

# Add to user PATH
Write-Host ""
Write-Host "Adding C:\flutter\bin to your PATH..." -ForegroundColor Yellow
$flutterBin = "C:\flutter\bin"
$currentPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
if ($currentPath -notlike "*$flutterBin*") {
    [System.Environment]::SetEnvironmentVariable("PATH", "$flutterBin;$currentPath", "User")
    Write-Host "PATH updated." -ForegroundColor Green
} else {
    Write-Host "Already in PATH." -ForegroundColor Green
}
$env:PATH = "$flutterBin;$env:PATH"

# Run flutter pub get
Write-Host ""
Write-Host "Running flutter pub get in arl_app..." -ForegroundColor Cyan
Set-Location $pubspecDir
& "$flutterBin\flutter.bat" pub get

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " All done! Flutter is installed." -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Press any key to close."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
