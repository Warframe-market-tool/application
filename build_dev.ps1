# Ensure script stops on first error
$ErrorActionPreference = "Stop"

# Create the dist directory if it doesn't exist
if (-not (Test-Path -Path ".\build_dev")) {
    New-Item -ItemType Directory -Path ".\build_dev"
}

# Compile the PowerShell script into an executable
Invoke-ps2exe .\WarframeMarketTool.ps1 .\build_dev\WarframeMarketTool.exe


# Copy the Views folder to the dist directory
Copy-Item -Path ".\Views" -Destination ".\build_dev\Views" -Recurse -Force

# Copy the config.json file to the dist directory
Copy-Item -Path ".\config_base.json" -Destination ".\build_dev\config.json" -Force

Write-Host "###################################################################################"
Write-Host "Build DEV process completed."
Write-Host "###################################################################################"
