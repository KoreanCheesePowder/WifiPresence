$ErrorActionPreference = "Stop"
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
Set-Location $PSScriptRoot

function Run-ST {
  param([string[]]$Arguments)
  & smartthings @Arguments | Out-Host
  if ($LASTEXITCODE -ne 0) {
    throw "SmartThings CLI command failed: smartthings $($Arguments -join ' ')"
  }
}

Write-Host "===============================================" -ForegroundColor Cyan
Write-Host " Synology Wi-Fi Presence Edge Driver v1.0.3" -ForegroundColor Cyan
Write-Host " RT2600ac / SRM 1.2.x" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Get-Command smartthings -ErrorAction SilentlyContinue)) {
  throw "SmartThings CLI was not found in PATH. Install or configure SmartThings CLI first."
}

Write-Host "[1/2] Packaging and installing driver to hub..." -ForegroundColor Cyan
Run-ST @("edge:drivers:package", ".", "--install")

Write-Host "[2/2] Installation command completed." -ForegroundColor Cyan
Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Next steps:" -ForegroundColor Green
Write-Host "1. Open SmartThings app." -ForegroundColor Green
Write-Host "2. Add device and scan nearby devices." -ForegroundColor Green
Write-Host "3. Open C.P Synology Wi-Fi Presence device settings." -ForegroundColor Green
Write-Host "4. Enter router LAN IP, SRM account, password, and phone Wi-Fi MAC addresses." -ForegroundColor Green
Write-Host "5. Default polling is 15 seconds and away confirmation delay is 120 seconds." -ForegroundColor Green
Write-Host ""
Write-Host "Important: Use the Wi-Fi MAC address shown by SRM for each phone." -ForegroundColor Yellow
Write-Host "For iPhone/Android private MAC, enter the private MAC used for this home Wi-Fi." -ForegroundColor Yellow
