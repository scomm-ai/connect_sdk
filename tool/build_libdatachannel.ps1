#Requires -Version 5.1
<#
.SYNOPSIS
  Builds libdatachannel shared library for scommconnector FFI (Mbed TLS backend).

.EXAMPLE
  .\tool\build_libdatachannel.ps1
  .\tool\build_libdatachannel.ps1 -CopyToRunner "C:\dev\secMail10\build\windows\x64\runner\Debug"
#>
param(
  [string]$BuildType = "Release",
  [string]$CopyToRunner = "",
  [string]$Generator = "Visual Studio 18 2026"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Native = Join-Path $Root "native"
$BuildDir = Join-Path $Native "build"
$LibSrc = Join-Path $Root "third_party\libdatachannel"
$MbedSrc = Join-Path $Root "third_party\mbedtls"

$cmake = "C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
if (-not (Test-Path $cmake)) {
  $cmake = "cmake"
}

if (-not (Test-Path (Join-Path $LibSrc "CMakeLists.txt"))) {
  Push-Location $Root
  git submodule update --init --recursive --depth 1
  Pop-Location
}

if (-not (Test-Path (Join-Path $MbedSrc "CMakeLists.txt"))) {
  git clone --depth 1 --branch v3.6.2 https://github.com/Mbed-TLS/mbedtls.git $MbedSrc
  Push-Location $MbedSrc
  git submodule update --init --recursive --depth 1
  Pop-Location
}

$configureArgs = @(
  "-S", $Native,
  "-B", $BuildDir,
  "-G", $Generator,
  "-A", "x64",
  "-DNO_MEDIA=ON",
  "-DNO_WEBSOCKET=ON",
  "-DNO_EXAMPLES=ON",
  "-DNO_TESTS=ON",
  "-DUSE_MBEDTLS=ON"
)

Write-Host "Configuring with $cmake ..."
& $cmake @configureArgs
if ($LASTEXITCODE -ne 0) { throw "cmake configure failed" }

Write-Host "Building ($BuildType)..."
& $cmake --build $BuildDir --config $BuildType --parallel
if ($LASTEXITCODE -ne 0) { throw "cmake build failed" }

$dllCandidates = @(
  (Join-Path $BuildDir "libdatachannel\$BuildType\datachannel.dll"),
  (Join-Path $BuildDir "$BuildType\datachannel.dll"),
  (Join-Path $BuildDir "datachannel.dll")
)
$dll = $dllCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $dll) {
  $dll = Get-ChildItem $BuildDir -Recurse -Filter "datachannel.dll" -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty FullName
}

if (-not $dll) {
  throw "Build finished but datachannel.dll was not found under $BuildDir"
}

Write-Host "Built: $dll"

$destinations = @()
if ($CopyToRunner -and (Test-Path $CopyToRunner)) {
  $destinations += $CopyToRunner
}

# Auto-detect secMail10 runner dirs when present.
foreach ($cfg in @("Debug", "Release", "Profile")) {
  $runner = "C:\dev\secMail10\build\windows\x64\runner\$cfg"
  if (Test-Path $runner) { $destinations += $runner }
}

$destinations = $destinations | Select-Object -Unique
foreach ($dest in $destinations) {
  Copy-Item -Force $dll $dest
  $pdb = [IO.Path]::ChangeExtension($dll, ".pdb")
  if (Test-Path $pdb) { Copy-Item -Force $pdb $dest }
  Write-Host "Copied datachannel.dll -> $dest"
}

Write-Host "Done. Restart the Flutter app to pick up the DLL."
