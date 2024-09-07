# Ensure script stops on first error
$ErrorActionPreference = "Stop"

# Create the dist directory if it doesn't exist
if (-not (Test-Path -Path ".\dist")) {
    New-Item -ItemType Directory -Path ".\dist"
}

# Compile the PowerShell script into an executable
Invoke-ps2exe .\WarframeMarketTool.ps1 .\dist\WarframeMarketTool.exe
Invoke-ps2exe .\SetsStatistics.ps1 .\dist\SetsStatistics.exe

# Copy the Views folder to the dist directory
Copy-Item -Path ".\Views" -Destination ".\dist\Views" -Recurse -Force

# Copy the config.json file to the dist directory
Copy-Item -Path ".\config_base.json" -Destination ".\dist\config.json" -Force

Write-Host "###################################################################################"
Write-Host "Build process completed."
Write-Host "###################################################################################"
