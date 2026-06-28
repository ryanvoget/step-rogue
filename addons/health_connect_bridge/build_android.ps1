# Build the Health Connect Android plugin.
# Requirements: Java 17+ installed (https://adoptium.net)
# Run from PowerShell: .\build_android.ps1
# Downloads Gradle automatically on first run.

#Requires -Version 5.1
param([switch]$Clean)

$ErrorActionPreference = "Stop"
$GradleVersion  = "8.5"
$ScriptDir      = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot    = (Resolve-Path "$ScriptDir\..\..")
$GradleDir      = "$env:LOCALAPPDATA\parsec-tools\gradle-$GradleVersion"
$GradleExe      = "$GradleDir\bin\gradle.bat"
$OutputDir      = Join-Path $ProjectRoot "android\plugins"

# 1 — Java check
try {
    $javaOut = & java -version 2>&1
    Write-Host "Java: $($javaOut[0])"
} catch {
    Write-Error "Java 17+ is required. Download from https://adoptium.net"
    exit 1
}

# 2 — Download Gradle if not cached
if (-not (Test-Path $GradleExe)) {
    Write-Host "Downloading Gradle $GradleVersion (one-time setup)..."
    $zipUrl  = "https://services.gradle.org/distributions/gradle-$GradleVersion-bin.zip"
    $zipPath = "$env:TEMP\gradle-$GradleVersion.zip"
    Invoke-WebRequest $zipUrl -OutFile $zipPath
    New-Item -ItemType Directory -Force (Split-Path $GradleDir) | Out-Null
    Expand-Archive $zipPath -DestinationPath (Split-Path $GradleDir) -Force
    Write-Host "Gradle ready."
}

# 3 — Build
Push-Location $ScriptDir
try {
    if ($Clean) {
        Write-Host "Cleaning..."
        & $GradleExe clean
    }
    Write-Host "Building HealthConnectBridge..."
    & $GradleExe assembleRelease
    if ($LASTEXITCODE -ne 0) { throw "Gradle build failed (exit $LASTEXITCODE)" }
} finally {
    Pop-Location
}

# 4 — Copy AAR to android/plugins/
New-Item -ItemType Directory -Force $OutputDir | Out-Null
$src = Join-Path $ScriptDir "build\outputs\aar\health_connect_bridge-release.aar"
$dst = Join-Path $OutputDir "HealthConnectBridge.aar"
Copy-Item $src $dst -Force

Write-Host ""
Write-Host "Done: android/plugins/HealthConnectBridge.aar"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  git add android/ .gitignore"
Write-Host "  git commit -m 'Add Health Connect plugin binary'"
Write-Host "  git push"
