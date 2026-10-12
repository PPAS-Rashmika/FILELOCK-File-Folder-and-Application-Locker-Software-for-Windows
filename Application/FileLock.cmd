@echo off
setlocal
if exist "%ProgramFiles%\FileLock\App\FileLock.exe" (
    start "" "%ProgramFiles%\FileLock\App\FileLock.exe"
    exit /b 0
)
if exist "%~dp0FileLock\FileLock.exe" (
    start "" "%~dp0FileLock\FileLock.exe"
    exit /b 0
)
if exist "%~dp0dist\FileLock\FileLock.exe" (
    start "" "%~dp0dist\FileLock\FileLock.exe"
    exit /b 0
)
echo Extract the complete FileLock package and run install.cmd first.
pause
exit /b 1
