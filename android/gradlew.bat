@echo off
setlocal
set GRADLE_VERSION=8.9
set CACHE_DIR=%USERPROFILE%\.gradle\oat-wrapper
set DIST_DIR=%CACHE_DIR%\gradle-%GRADLE_VERSION%
set ZIP=%CACHE_DIR%\gradle-%GRADLE_VERSION%-bin.zip

if exist "%DIST_DIR%\bin\gradle.bat" goto run

if not exist "%CACHE_DIR%" mkdir "%CACHE_DIR%"
if not exist "%ZIP%" (
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing 'https://services.gradle.org/distributions/gradle-%GRADLE_VERSION%-bin.zip' -OutFile '%ZIP%'"
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -Force '%ZIP%' '%CACHE_DIR%'"

:run
call "%DIST_DIR%\bin\gradle.bat" %*
