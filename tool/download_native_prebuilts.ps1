#Requires -Version 5.1
<#
.SYNOPSIS
  Download published datachannel prebuilts into native/prebuilt/.
#>
param(
  [string]$Tag = "",
  [string]$Repo = $(if ($env:SCOMM_NATIVE_PREBUILT_REPO) { $env:SCOMM_NATIVE_PREBUILT_REPO } else { "scomm-ai/connect_sdk" })
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
if (-not $Tag) {
  if ($env:SCOMM_NATIVE_PREBUILT_TAG) { $Tag = $env:SCOMM_NATIVE_PREBUILT_TAG }
  elseif (Test-Path (Join-Path $Root "native\PREBUILT_TAG")) {
    $Tag = (Get-Content (Join-Path $Root "native\PREBUILT_TAG") -Raw).Trim()
  }
}
if (-not $Tag) {
  throw "No prebuilt tag (native/PREBUILT_TAG or -Tag / SCOMM_NATIVE_PREBUILT_TAG)"
}

$Out = Join-Path $Root "native\prebuilt"
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$Base = "https://github.com/$Repo/releases/download/$Tag"

$assets = @(
  "datachannel-windows-x86_64.zip",
  "datachannel-linux-x86_64.zip",
  "datachannel-linux-aarch64.zip",
  "datachannel-android-arm64-v8a.zip",
  "datachannel-android-x86_64.zip",
  "datachannel-macos-arm64.zip",
  "datachannel-macos-x86_64.zip",
  "datachannel-ios-arm64.zip"
)

$ok = 0
foreach ($asset in $assets) {
  $url = "$Base/$asset"
  $tmp = Join-Path $env:TEMP $asset
  Write-Host "Downloading $url"
  try {
    Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
  } catch {
    Write-Host "[WARN] missing asset: $asset"
    continue
  }
  Expand-Archive -Path $tmp -DestinationPath $Out -Force
  Remove-Item -Force $tmp
  $ok++
}

$arm64 = Join-Path $Out "android-arm64-v8a\libdatachannel.so"
$x64 = Join-Path $Out "android-x86_64\libdatachannel.so"
if (Test-Path $arm64) {
  $dest = Join-Path $Out "android-jni\arm64-v8a"
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Copy-Item -Force $arm64 $dest
}
if (Test-Path $x64) {
  $dest = Join-Path $Out "android-jni\x86_64"
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Copy-Item -Force $x64 $dest
}

if ($ok -eq 0) {
  throw "No prebuilt assets downloaded for tag $Tag"
}
Write-Host "[OK] Downloaded $ok prebuilt asset(s) for $Tag into $Out"
