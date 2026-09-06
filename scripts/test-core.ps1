# Runs the ProportionCore test suite on Windows.
#
# Swift on Windows links against MSVC's C runtime, so the toolchain must run
# inside a Visual Studio developer environment. This script sets that up
# (vcvars64 + the swift.org toolchain on PATH) and then runs `swift test`.
#
# Prerequisites (both installable via winget):
#   winget install Swift.Toolchain
#   winget install Microsoft.VisualStudio.2022.BuildTools --override "--quiet --wait --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.22621"
#
# Usage:  powershell -File scripts\test-core.ps1 [extra swift test args]

param([Parameter(ValueFromRemainingArguments = $true)] [string[]] $SwiftArgs)

$ErrorActionPreference = "Stop"

$toolchains = Join-Path $env:LOCALAPPDATA "Programs\Swift\Toolchains"
$toolchain = Get-ChildItem $toolchains -Directory | Sort-Object Name -Descending | Select-Object -First 1
if (-not $toolchain) { throw "No Swift toolchain found under $toolchains" }
$swiftBin = Join-Path $toolchain.FullName "usr\bin"

$sdkroot = [Environment]::GetEnvironmentVariable("SDKROOT", "User")
if (-not $sdkroot) { throw "SDKROOT is not set; re-run the Swift installer" }

$installer = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer"
$vcvars = Get-ChildItem "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\*\VC\Auxiliary\Build\vcvars64.bat" | Select-Object -First 1
if (-not $vcvars) { throw "vcvars64.bat not found; install Visual Studio Build Tools with the C++ toolset" }

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$package = Join-Path $PSScriptRoot "..\ProportionCore"
$extra = ($SwiftArgs -join " ")

# Quoted `set "VAR=value"` matters: cmd otherwise keeps the space before `&&`.
$cmd = "set `"PATH=$installer;$swiftBin;$userPath;%PATH%`"&& call `"$($vcvars.FullName)`" >nul && set `"SDKROOT=$sdkroot`"&& cd /d `"$package`" && swift test $extra 2>&1"
cmd /c $cmd
exit $LASTEXITCODE
