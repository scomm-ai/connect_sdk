#Requires -Version 5.1
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Mbed = Join-Path $Root "third_party\mbedtls"
if (Test-Path (Join-Path $Mbed "CMakeLists.txt")) {
  Write-Host "mbedtls already present at $Mbed"
  exit 0
}
if (Test-Path $Mbed) { Remove-Item -Recurse -Force $Mbed }
git clone --depth 1 --branch v3.6.2 https://github.com/Mbed-TLS/mbedtls.git $Mbed
Push-Location $Mbed
git submodule update --init --recursive --depth 1
Pop-Location
Write-Host "Cloned mbedtls v3.6.2"
