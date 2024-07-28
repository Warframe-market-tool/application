@echo off
REM Compile the PowerShell script into an executable
powershell -Command "Invoke-ps2exe .\WarframeMarketTool.ps1 .\bin\WarframeMarketTool.exe"

REM Create the bin directory if it doesn't exist
if not exist ".\bin\" (
    mkdir ".\bin"
)

REM Copy the Views folder to the bin directory
xcopy ".\Views" ".\bin\Views" /E /I /Y

REM Copy the config.json file to the bin directory
copy ".\config.json" ".\bin\config.json" /Y
echo ###################################################################################
echo Build process completed.
echo ###################################################################################
