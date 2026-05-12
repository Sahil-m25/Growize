@echo off
cd /d "C:\Users\Sahil\Downloads\ARL\arl_app"

:: Try to find flutter in common winget install locations
set FLUTTER_BIN=

if exist "C:\flutter\bin\flutter.bat" set FLUTTER_BIN=C:\flutter\bin
if exist "C:\src\flutter\bin\flutter.bat" set FLUTTER_BIN=C:\src\flutter\bin
if exist "%USERPROFILE%\flutter\bin\flutter.bat" set FLUTTER_BIN=%USERPROFILE%\flutter\bin
if exist "%USERPROFILE%\AppData\Local\flutter\bin\flutter.bat" set FLUTTER_BIN=%USERPROFILE%\AppData\Local\flutter\bin
if exist "%LOCALAPPDATA%\Programs\flutter\bin\flutter.bat" set FLUTTER_BIN=%LOCALAPPDATA%\Programs\flutter\bin
if exist "C:\tools\flutter\bin\flutter.bat" set FLUTTER_BIN=C:\tools\flutter\bin

if "%FLUTTER_BIN%"=="" (
    echo Flutter not found in common locations. Searching...
    for /f "delims=" %%F in ('where flutter 2^>nul') do set FLUTTER_BIN=%%~dpF
)

if "%FLUTTER_BIN%"=="" (
    echo ERROR: Could not find Flutter SDK.
    echo Please check where winget installed it by running:
    echo   where flutter
    echo Then tell Claude the path.
    pause
    exit /b 1
)

echo Found Flutter at: %FLUTTER_BIN%
set PATH=%FLUTTER_BIN%;%PATH%

echo Running flutter pub get...
flutter pub get

echo.
echo Done! Press any key to close.
pause
