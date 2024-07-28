@echo off
REM Compile the PowerShell script into an executable
powershell -Command "Invoke-ps2exe .\WarframeMarketTool.ps1 .\dist\WarframeMarketTool.exe"

REM Create the bin directory if it doesn't exist
if not exist ".\dist\" (
    mkdir ".\dist"
)

REM Copy the Views folder to the bin directory
xcopy ".\Views" ".\dist\Views" /E /I /Y

REM Copy the config.json file to the bin directory
copy ".\config.json" ".\dist\config.json" /Y
echo ###################################################################################
echo Build process completed.
echo ###################################################################################
