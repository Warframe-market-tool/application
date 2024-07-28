# Ensure script stops on first error
$ErrorActionPreference = "Stop"
# Import the ps2exe module
Import-Module ps2exe
# Compile the PowerShell script into an executable
ps2exe WarframeMarketTool.ps1 dist\WarframeMarketTool.exe

# Create the dist directory if it doesn't exist
if (-not (Test-Path -Path ".\dist")) {
    New-Item -ItemType Directory -Path ".\dist"
}

# Copy the Views folder to the dist directory
Copy-Item -Path ".\Views" -Destination ".\dist\Views" -Recurse -Force

# Copy the config.json file to the dist directory
Copy-Item -Path "config.json" -Destination ".\dist\config.json" -Force

Write-Host "###################################################################################"
Write-Host "Build process completed."
Write-Host "###################################################################################"
