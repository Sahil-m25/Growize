# Download JDK 17, extract to user folder, configure Flutter, run the app
$userPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
$machinePath = [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
$env:PATH = "$userPath;$machinePath"

$jdkDir = "$env:USERPROFILE\jdk17"
$jdkBin = "$jdkDir\bin"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " JDK 17 Setup for Flutter" -ForegroundColor Cyan
Write-Host "========================================`n"

if (Test-Path "$jdkBin\java.exe") {
    Write-Host "JDK 17 already found at $jdkDir" -ForegroundColor Green
} else {
    $url = "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.11%2B9/OpenJDK17U-jdk_x64_windows_hotspot_17.0.11_9.zip"
    $zip = "$env:TEMP\jdk17.zip"

    Write-Host "Downloading JDK 17 (~190 MB)..." -ForegroundColor Yellow
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    Write-Host "Download complete. Extracting..." -ForegroundColor Yellow

    Expand-Archive -Path $zip -DestinationPath "$env:TEMP\jdk17_extract" -Force
    Remove-Item $zip -Force

    # The zip extracts to a subfolder like jdk-17.0.11+9 — move it
    $extracted = Get-ChildItem "$env:TEMP\jdk17_extract" -Directory | Select-Object -First 1
    if (Test-Path $jdkDir) { Remove-Item $jdkDir -Recurse -Force }
    Move-Item $extracted.FullName $jdkDir
    Remove-Item "$env:TEMP\jdk17_extract" -Recurse -Force
    Write-Host "Extracted to $jdkDir" -ForegroundColor Green
}

# Fix JAVA_HOME at user level (overrides the broken machine-level one for new sessions)
[System.Environment]::SetEnvironmentVariable("JAVA_HOME", $jdkDir, "User")
$env:JAVA_HOME = $jdkDir
$env:PATH = "$jdkBin;$env:PATH"

Write-Host "`nJAVA_HOME set to: $jdkDir" -ForegroundColor Green
Write-Host "Java version: $(& "$jdkBin\java.exe" -version 2>&1 | Select-Object -First 1)"

# Tell Flutter to use this JDK
Write-Host "`nConfiguring Flutter JDK..." -ForegroundColor Cyan
& flutter config --jdk-dir "$jdkDir"

# Run the app
Write-Host "`nLaunching flutter run..." -ForegroundColor Cyan
Set-Location "C:\Users\Sahil\Downloads\ARL\arl_app"
& flutter run
