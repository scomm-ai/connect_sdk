#Requires -Version 5.1
param(
  [Parameter(Mandatory = $true)][string]$Triple,
  [Parameter(Mandatory = $true)][string]$Library,
  [string]$OutDir = ""
)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
if (-not $OutDir) { $OutDir = Join-Path $Root "native\prebuilt-dist" }
if (-not (Test-Path $Library)) { throw "Library not found: $Library" }

$Stage = Join-Path $Root "native\prebuilt\$Triple"
New-Item -ItemType Directory -Force -Path $Stage, $OutDir | Out-Null
Copy-Item -Force $Library $Stage
Write-Host "Staged $Library -> $Stage"

$Zip = Join-Path $OutDir "datachannel-$Triple.zip"
if (Test-Path $Zip) { Remove-Item -Force $Zip }
Compress-Archive -Path $Stage -DestinationPath $Zip
Write-Host "Wrote $Zip"
