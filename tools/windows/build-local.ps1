# SPDX-FileCopyrightText: Copyright 2026 Eden Emulator Project
# SPDX-License-Identifier: GPL-3.0-or-later

# Local Windows build with MSVC, the same configuration as the fork's release job.
#
# Needs: Visual Studio 2022 Build Tools (C++ workload), Qt 6.8.3 msvc2022_64 with qtcharts,
# the Vulkan SDK and, optionally, sccache. See docs/Build.md.
#
#   .\tools\windows\build-local.ps1               # incremental Release build
#   .\tools\windows\build-local.ps1 -Reconfigure  # rerun CMake first
#   .\tools\windows\build-local.ps1 -Clean        # delete the build folder and start over
#
# Output: build\local\bin\lichii.exe

param(
    [switch]$Reconfigure,
    [switch]$Clean,
    [string]$BuildType = "Release",
    [string]$QtDir = "C:\Qt\6.8.3\msvc2022_64",
    [string]$VulkanSdk = "C:\VulkanSDK\1.4.341.1"
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path "$PSScriptRoot\..\..").Path
$BuildDir = Join-Path $Root "build\local"

foreach ($required in @($QtDir, $VulkanSdk)) {
    if (-not (Test-Path $required)) { throw "Not found: $required" }
}

# Enter the MSVC x64 developer environment (cl, link, the Windows SDK, and VS's CMake and Ninja).
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs = & $vswhere -products * -version "[17,18)" -latest `
    -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw "Visual Studio 2022 with the C++ tools is not installed" }
Import-Module "$vs\Common7\Tools\Microsoft.VisualStudio.DevShell.dll"
Enter-VsDevShell -VsInstallPath $vs -SkipAutomaticLocation -DevCmdArguments "-arch=x64 -host_arch=x64" | Out-Null

# English compiler messages: Ninja reads the "Note: including file:" lines of a localized cl
# (Spanish "Nota: inclusión del archivo:") in the wrong code page, records no header dependencies
# and floods the log with them.
$env:VSLANG = "1033"
$env:VULKAN_SDK = $VulkanSdk
$env:PATH = "$QtDir\bin;$VulkanSdk\Bin;$env:PATH"
# Keep the dependency downloads (CPM) inside the repo so -Clean does not throw them away.
$env:CPM_SOURCE_CACHE = Join-Path $Root ".cache\cpm"

if ($Clean -and (Test-Path $BuildDir)) {
    Remove-Item -Recurse -Force $BuildDir
}

# Windows PowerShell turns any stderr line of a native program (CMake's warnings) into a
# terminating error under "Stop", so the CMake steps are checked by their exit codes instead.
$ErrorActionPreference = "Continue"

$launcher = @()
if (Get-Command sccache -ErrorAction SilentlyContinue) {
    $launcher = @("-DCMAKE_C_COMPILER_LAUNCHER=sccache", "-DCMAKE_CXX_COMPILER_LAUNCHER=sccache")
}

if ($Reconfigure -or -not (Test-Path (Join-Path $BuildDir "CMakeCache.txt"))) {
    cmake -S $Root -B $BuildDir -G Ninja `
        "-DCMAKE_BUILD_TYPE=$BuildType" `
        -DCMAKE_C_COMPILER=cl -DCMAKE_CXX_COMPILER=cl `
        "-DCMAKE_PREFIX_PATH=$QtDir" `
        -DBUILD_TESTING=OFF -DYUZU_TESTS=OFF `
        -DENABLE_QT=ON -DYUZU_CMD=ON `
        -DYUZU_ROOM=OFF -DYUZU_ROOM_STANDALONE=OFF `
        -DYUZU_USE_BUNDLED_QT=OFF -DYUZU_USE_BUNDLED_SDL3=ON `
        -DVulkanHeaders_FORCE_BUNDLED=ON -DVulkanUtilityLibraries_FORCE_BUNDLED=ON `
        -DENABLE_UPDATE_CHECKER=OFF `
        -DUSE_DISCORD_PRESENCE=OFF `
        @launcher
    if ($LASTEXITCODE -ne 0) { throw "CMake configure failed" }
}

cmake --build $BuildDir --parallel
if ($LASTEXITCODE -ne 0) { throw "Build failed" }

Write-Host ""
Write-Host "Built: $(Join-Path $BuildDir 'bin\lichii.exe')"
