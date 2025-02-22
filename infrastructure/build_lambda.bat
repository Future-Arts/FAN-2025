@echo off
setlocal enabledelayedexpansion

rem Get script directory
set "SCRIPT_DIR=%~dp0"
rem Remove trailing backslash
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

rem Set source and infrastructure directories
set "SRC_DIR=%SCRIPT_DIR%\..\src"
set "INFRA_DIR=%SCRIPT_DIR%"
set "PACKAGE_DIR=%INFRA_DIR%\lambda_package"

echo Creating Lambda deployment package...

rem Create virtual environment if it doesn't exist
if not exist "%SRC_DIR%\.venv" (
    echo Creating virtual environment...
    python -m venv "%SRC_DIR%\.venv"
)

rem Activate virtual environment
call "%SRC_DIR%\.venv\Scripts\activate.bat"

rem Create package directory if it doesn't exist
if not exist "%PACKAGE_DIR%" mkdir "%PACKAGE_DIR%"

rem Install dependencies
echo Installing dependencies...
pip install -r "%SRC_DIR%\requirements.txt" -t "%PACKAGE_DIR%"

rem Copy source file
echo Copying source files...
copy "%SRC_DIR%\pagescraper.py" "%PACKAGE_DIR%"

rem Create zip file (using PowerShell since it's more reliable than Windows zip)
echo Creating zip file...
powershell -command "Compress-Archive -Path '%PACKAGE_DIR%\*' -DestinationPath '%INFRA_DIR%\lambda_function.zip' -Force"

rem Cleanup
echo Cleaning up...
rmdir /s /q "%PACKAGE_DIR%"

echo Lambda package created successfully at %INFRA_DIR%\lambda_function.zip

rem Deactivate virtual environment
deactivate

endlocal
