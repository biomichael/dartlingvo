@echo off
REM Build the lsd_decoder.dll for Windows
REM Requires Visual Studio Developer Command Prompt (cl.exe on PATH)

setlocal

set SRC=lsd_c_wrapper.c
set OUT=lsd_decoder.dll

REM Try to find cl.exe via vcvars
where cl.exe >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo cl.exe not found. Open a "Developer Command Prompt for Visual Studio" and re-run.
    echo.
    echo Or use:
    echo   "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
    echo   %0
    exit /b 1
)

echo Compiling %SRC% -^> %OUT% ...
cl /LD /O2 /W3 %SRC% /Fe%OUT%

if %ERRORLEVEL% equ 0 (
    echo.
    echo Success: %OUT% created.
    echo Copy it next to the Flutter app executable or into the project root.
) else (
    echo.
    echo Build failed.
    exit /b 1
)

endlocal
