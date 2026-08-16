$ErrorActionPreference = "Stop"
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

param(
  [string]$HostName = "192.168.1.1",
  [int]$Port = 8000,
  [switch]$Https,
  [string]$User = "",
  [string]$Password = ""
)

$scheme = if ($Https) { "https" } else { "http" }
$base = "${scheme}://${HostName}:${Port}/webapi"

function Invoke-SrmGet {
  param([string]$Path, [hashtable]$Query)
  $pairs = @()
  foreach ($key in $Query.Keys) {
    $pairs += ([uri]::EscapeDataString([string]$key) + "=" + [uri]::EscapeDataString([string]$Query[$key]))
  }
  $uri = "$base/$Path?" + ($pairs -join "&")
  Write-Host "GET $uri" -ForegroundColor DarkGray
  if ($Https) {
    try {
      return Invoke-RestMethod -Uri $uri -Method Get -UseBasicParsing
    } catch {
      if ($_.Exception.Message -match "trust relationship|certificate") {
        Write-Host "TLS certificate validation failed. Try local HTTP port 8000 for probing." -ForegroundColor Yellow
      }
      throw
    }
  }
  return Invoke-RestMethod -Uri $uri -Method Get -UseBasicParsing
}

Write-Host "Synology SRM API probe v1.0.0" -ForegroundColor Cyan
Write-Host "Target: $base" -ForegroundColor Cyan
Write-Host ""

$info = Invoke-SrmGet "query.cgi" @{
  api = "SYNO.API.Info"
  version = "1"
  method = "query"
  query = "SYNO.API.Auth,SYNO.Core.Network.NSM.Device"
}

Write-Host "API.Info result:" -ForegroundColor Green
$info | ConvertTo-Json -Depth 10

if ([string]::IsNullOrWhiteSpace($User) -or [string]::IsNullOrWhiteSpace($Password)) {
  Write-Host ""
  Write-Host "No credentials were supplied. API.Info probe is complete." -ForegroundColor Yellow
  Write-Host "Example:" -ForegroundColor Yellow
  Write-Host '.\SRM-API-PROBE.ps1 -HostName 192.168.1.1 -Port 8000 -User "account" -Password "password"' -ForegroundColor Yellow
  exit 0
}

$authPath = "auth.cgi"
$authVersion = 3
if ($info.data.'SYNO.API.Auth') {
  if ($info.data.'SYNO.API.Auth'.path) { $authPath = [string]$info.data.'SYNO.API.Auth'.path }
  if ($info.data.'SYNO.API.Auth'.maxVersion) { $authVersion = [Math]::Min([int]$info.data.'SYNO.API.Auth'.maxVersion, 3) }
}

$login = Invoke-SrmGet $authPath @{
  api = "SYNO.API.Auth"
  version = [string]$authVersion
  method = "login"
  account = $User
  passwd = $Password
  session = "WiFiPresence"
  format = "sid"
}

Write-Host "Login result:" -ForegroundColor Green
$login | ConvertTo-Json -Depth 10

if (-not $login.success -or -not $login.data.sid) {
  throw "SRM login failed."
}

$sid = [string]$login.data.sid
$deviceMeta = $info.data.'SYNO.Core.Network.NSM.Device'
$devicePath = if ($deviceMeta.path) { [string]$deviceMeta.path } else { "entry.cgi" }
$maxVersion = if ($deviceMeta.maxVersion) { [int]$deviceMeta.maxVersion } else { 1 }
$methods = @("get", "list", "load", "get_list", "list_devices", "query")

Write-Host ""
Write-Host "Trying SYNO.Core.Network.NSM.Device methods..." -ForegroundColor Cyan
foreach ($method in $methods) {
  for ($version = $maxVersion; $version -ge 1; $version--) {
    try {
      $result = Invoke-SrmGet $devicePath @{
        api = "SYNO.Core.Network.NSM.Device"
        version = [string]$version
        method = $method
        _sid = $sid
      }
      Write-Host "METHOD=$method VERSION=$version" -ForegroundColor Magenta
      $result | ConvertTo-Json -Depth 20
      if ($result.success) {
        Write-Host "SUCCESS: Copy this output and send it for driver tuning." -ForegroundColor Green
        break
      }
    } catch {
      Write-Host "METHOD=$method VERSION=$version ERROR=$($_.Exception.Message)" -ForegroundColor DarkYellow
    }
  }
}

try {
  Invoke-SrmGet $authPath @{
    api = "SYNO.API.Auth"
    version = "2"
    method = "logout"
    session = "WiFiPresence"
    _sid = $sid
  } | Out-Null
} catch {}
