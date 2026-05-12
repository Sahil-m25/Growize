# Find a valid JDK and fix JAVA_HOME, then run flutter run

$userPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
$machinePath = [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
$env:PATH = "$userPath;$machinePath"

Write-Host "Searching for valid Java installation..." -ForegroundColor Cyan

$javaExe = $null
$jdkRoot = $null

# 1. Android Studio bundled JDK (best for Flutter)
$androidStudioPaths = @(
    "C:\Program Files\Android\Android Studio\jbr",
    "C:\Program Files\Android\Android Studio\jre"
)
foreach ($p in $androidStudioPaths) {
    if (Test-Path "$p\bin\java.exe") { $jdkRoot = $p; break }
}

# 2. Eclipse Adoptium - scan for any valid version
if (-not $jdkRoot) {
    $adoptium = Get-ChildItem "C:\Program Files\Eclipse Adoptium\" -Directory -ErrorAction SilentlyContinue
    foreach ($d in $adoptium) {
        if (Test-Path "$($d.FullName)\bin\java.exe") { $jdkRoot = $d.FullName; break }
    }
}

# 3. General scan of Program Files for any JDK
if (-not $jdkRoot) {
    $candidates = Get-ChildItem "C:\Program Files" -Recurse -Filter "java.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($candidates) { $jdkRoot = $candidates.Directory.Parent.FullName }
}

# 4. Check JAVA_HOME if it's set and valid
if (-not $jdkRoot) {
    $currentJH = [System.Environment]::GetEnvironmentVariable("JAVA_HOME", "Machine")
    if ($currentJH -and (Test-Path "$currentJH\bin\java.exe")) { $jdkRoot = $currentJH }
}

if (-not $jdkRoot) {
    Write-Host "ERROR: No valid Java installation found." -ForegroundColor Red
    Write-Host "Please install Java 17 from: https://adoptium.net/temurin/releases/?version=17" -ForegroundColor Yellow
    Write-Host "Press any key to exit."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

Write-Host "Found JDK at: $jdkRoot" -ForegroundColor Green

# Fix JAVA_HOME
[System.Environment]::SetEnvironmentVariable("JAVA_HOME", $jdkRoot, "User")
$env:JAVA_HOME = $jdkRoot
$env:PATH = "$jdkRoot\bin;$env:PATH"

# Also tell Flutter about the JDK
Write-Host "Configuring Flutter to use this JDK..." -ForegroundColor Cyan
& flutter config --jdk-dir "$jdkRoot"

# Now run flutter run
Write-Host ""
Write-Host "Running flutter run..." -ForegroundColor Cyan
Set-Location "C:\Users\Sahil\Downloads\ARL\arl_app"
& flutter run
