$ErrorActionPreference = "Stop"
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
Set-Location $PSScriptRoot

function Invoke-STCapture {
  param([string[]]$Arguments)
  $oldPref = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  $output = & smartthings @Arguments 2>&1 | Out-String
  $exit = $LASTEXITCODE
  $ErrorActionPreference = $oldPref
  return [PSCustomObject]@{ ExitCode = $exit; Output = $output }
}

function Run-ST {
  param([string[]]$Arguments)
  & smartthings @Arguments | Out-Host
  if ($LASTEXITCODE -ne 0) {
    throw "SmartThings CLI command failed: smartthings $($Arguments -join ' ')"
  }
}

Write-Host "===============================================" -ForegroundColor Cyan
Write-Host " Synology Wi-Fi Presence Edge Driver v1.1.6" -ForegroundColor Cyan
Write-Host " RT2600ac / SRM 1.2.x" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Get-Command smartthings -ErrorAction SilentlyContinue)) {
  throw "SmartThings CLI was not found in PATH. Install or configure SmartThings CLI first."
}

$StatusCapabilityId = "buildbook37604.synologydriverstatusv111"
Write-Host "[1/3] Preparing Driver Status capability..." -ForegroundColor Cyan

# Use a new capability ID for this build. If a previous interrupted run already
# created it, treat the SmartThings ConflictError as success and continue.
$create = Invoke-STCapture @("capabilities:create", "-i", "capability-driver-status.json")
if ($create.ExitCode -ne 0) {
  if ($create.Output -match "already exists" -or $create.Output -match "ConflictError") {
    Write-Host "Driver Status capability already exists. Continuing." -ForegroundColor DarkGray
  } else {
    Write-Host $create.Output
    throw "Unable to prepare Driver Status capability: $StatusCapabilityId"
  }
} else {
  Write-Host $create.Output
}

# Presentation: update first if it already exists; otherwise create it.
$update = Invoke-STCapture @("capabilities:presentation:update", $StatusCapabilityId, "-i", "presentation-driver-status.json")
if ($update.ExitCode -ne 0) {
  $createPres = Invoke-STCapture @("capabilities:presentation:create", $StatusCapabilityId, "-i", "presentation-driver-status.json")
  if ($createPres.ExitCode -ne 0) {
    Write-Host $createPres.Output
    throw "Unable to prepare Driver Status presentation: $StatusCapabilityId"
  } else {
    Write-Host $createPres.Output
  }
} else {
  Write-Host $update.Output
}

Write-Host "[2/3] Packaging and installing driver to hub..." -ForegroundColor Cyan
Run-ST @("edge:drivers:package", ".", "--install")

Write-Host "[3/3] Installation command completed." -ForegroundColor Cyan
Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "UI order:" -ForegroundColor Green
Write-Host "1. 전체 WIFI 재실 상태"
Write-Host "2. 핸드폰 1 재실 상태"
Write-Host "3. 핸드폰 2 재실 상태"
Write-Host "4. 핸드폰 3 재실 상태"
Write-Host "5. 핸드폰 4 재실 상태"
Write-Host "6. 드라이버 상태"
Write-Host "7. 제작자 정보"
