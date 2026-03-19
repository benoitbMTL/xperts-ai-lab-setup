param(
    [ValidateSet("install", "uninstall")]
    [string]$Action = "install"
)

$ErrorActionPreference = "Stop"

$Script:WorkingDir = (Get-Location).Path
$Script:LogFile = Join-Path $Script:WorkingDir ("cherry-studio-" + $Action + "-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")

# Default target: Windows x64 Setup installer from the latest GitHub release
$Script:GitHubRepoApi = "https://api.github.com/repos/CherryHQ/cherry-studio/releases/latest"
$Script:AssetPattern = '^Cherry-Studio-.*-x64-setup\.exe$'

function Initialize-Log {
    New-Item -ItemType File -Path $Script:LogFile -Force | Out-Null
}

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"

    Add-Content -Path $Script:LogFile -Value $line

    switch ($Level) {
        "ERROR" { Write-Host $line -ForegroundColor Red }
        "WARN"  { Write-Host $line -ForegroundColor Yellow }
        default { Write-Host $line }
    }
}

function Write-Step {
    param([string]$Message)

    Write-Host ""
    Write-Host "=== $Message ===" -ForegroundColor Cyan
    Add-Content -Path $Script:LogFile -Value ""
    Add-Content -Path $Script:LogFile -Value "=== $Message ==="
}

function Ensure-Admin {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)

    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This script must be run as Administrator."
    }
}

function Get-LatestReleaseInfo {
    Write-Step "Fetching latest Cherry Studio release metadata"
    Write-Log "Querying GitHub API: $Script:GitHubRepoApi"

    $headers = @{
        "Accept" = "application/vnd.github+json"
        "User-Agent" = "Cherry-Studio-Installer-Script"
    }

    $release = Invoke-RestMethod -Uri $Script:GitHubRepoApi -Headers $headers -Method Get

    if (-not $release) {
        throw "Could not retrieve release metadata from GitHub."
    }

    if (-not $release.tag_name) {
        throw "Release metadata does not contain a tag_name."
    }

    $asset = $release.assets | Where-Object { $_.name -match $Script:AssetPattern } | Select-Object -First 1

    if (-not $asset) {
        throw "Could not find a Windows x64 setup asset matching pattern: $Script:AssetPattern"
    }

    Write-Log "Latest release tag: $($release.tag_name)"
    Write-Log "Selected asset: $($asset.name)"
    Write-Log "Asset download URL: $($asset.browser_download_url)"

    return [PSCustomObject]@{
        TagName     = $release.tag_name
        AssetName   = $asset.name
        DownloadUrl = $asset.browser_download_url
        PublishedAt = $release.published_at
    }
}

function Download-Installer {
    param(
        [string]$Url,
        [string]$FileName
    )

    Write-Step "Downloading installer"

    $downloadPath = Join-Path $Script:WorkingDir $FileName
    Write-Log "Downloading to: $downloadPath"

    Invoke-WebRequest -Uri $Url -OutFile $downloadPath -UseBasicParsing
    Unblock-File -LiteralPath $downloadPath -ErrorAction SilentlyContinue

    if (-not (Test-Path -LiteralPath $downloadPath)) {
        throw "Download failed. File not found after download: $downloadPath"
    }

    $fileInfo = Get-Item -LiteralPath $downloadPath
    Write-Log "Downloaded file size: $($fileInfo.Length) bytes"

    return $downloadPath
}

function Install-CherryStudio {
    param(
        [string]$InstallerPath
    )

    Write-Step "Running Cherry Studio installer"

    Write-Log "Installer path: $InstallerPath"
    Write-Log "Starting silent installation using direct execution: /S"

    if (-not (Test-Path -LiteralPath $InstallerPath)) {
        throw "Installer not found: $InstallerPath"
    }

    try {
        Unblock-File -LiteralPath $InstallerPath -ErrorAction SilentlyContinue
    }
    catch {
        Write-Log "Could not unblock installer, continuing anyway." "WARN"
    }

    Push-Location (Split-Path -Path $InstallerPath -Parent)
    try {
        & $InstallerPath /S
        $exitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    if ($null -eq $exitCode) {
        $exitCode = 0
    }

    Write-Log "Installer exit code: $exitCode"

    if ($exitCode -ne 0) {
        throw "Cherry Studio installer failed with exit code $exitCode."
    }
}

function Get-CherryInstallCandidates {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Cherry Studio\Cherry Studio.exe"),
        (Join-Path ${env:ProgramFiles} "Cherry Studio\Cherry Studio.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Cherry Studio\Cherry Studio.exe")
    )

    return $candidates
}

function Get-CherryExecutable {
    $candidates = Get-CherryInstallCandidates

    foreach ($path in $candidates) {
        if ($path -and (Test-Path -LiteralPath $path)) {
            return $path
        }
    }

    return $null
}

function Validate-Install {
    Write-Step "Validating installation"

    $maxAttempts = 15
    $sleepSeconds = 2
    $exePath = $null

    for ($i = 1; $i -le $maxAttempts; $i++) {
        $exePath = Get-CherryExecutable
        if ($exePath) {
            break
        }

        Write-Log "Cherry Studio executable not found yet. Retry $i/$maxAttempts..." "WARN"
        Start-Sleep -Seconds $sleepSeconds
    }

    if (-not $exePath) {
        throw "Cherry Studio executable was not found in standard install locations."
    }

    $versionInfo = (Get-Item -LiteralPath $exePath).VersionInfo
    $productVersion = $versionInfo.ProductVersion
    $fileVersion = $versionInfo.FileVersion

    Write-Log "Cherry Studio executable found at: $exePath"
    Write-Log "Product version: $productVersion"
    Write-Log "File version: $fileVersion"

    Write-Step "Summary"
    Write-Host "Cherry Studio executable : $exePath" -ForegroundColor Green
    Write-Host "Product version          : $productVersion" -ForegroundColor Green
    Write-Host "File version             : $fileVersion" -ForegroundColor Green
    Write-Host "Log file                 : $Script:LogFile" -ForegroundColor Green
}

function Uninstall-CherryStudio {
    Write-Step "Attempting Cherry Studio uninstall"

    $exePath = Get-CherryExecutable
    if (-not $exePath) {
        Write-Log "Cherry Studio executable not found. Nothing to uninstall." "WARN"
        return
    }

    $installDir = Split-Path $exePath -Parent
    $uninstallExe = Join-Path $installDir "Uninstall Cherry Studio.exe"

    if (-not (Test-Path -LiteralPath $uninstallExe)) {
        $uninstallExe = Join-Path $installDir "Uninstall.exe"
    }

    if (-not (Test-Path -LiteralPath $uninstallExe)) {
        throw "Uninstaller not found in: $installDir"
    }

    Write-Log "Using uninstaller: $uninstallExe"

    $process = Start-Process -FilePath $uninstallExe `
                             -ArgumentList @("/S") `
                             -Wait `
                             -PassThru

    Write-Log "Uninstaller exit code: $($process.ExitCode)"

    if ($process.ExitCode -ne 0) {
        throw "Cherry Studio uninstaller failed with exit code $($process.ExitCode)."
    }

    Write-Step "Uninstall summary"
    Write-Host "Cherry Studio uninstall completed." -ForegroundColor Green
    Write-Host "Log file: $Script:LogFile" -ForegroundColor Green
}

try {
    Initialize-Log
    Write-Log "Script started with action: $Action"

    Ensure-Admin

    if ($Action -eq "install") {
        $releaseInfo = Get-LatestReleaseInfo
        $installerPath = Download-Installer -Url $releaseInfo.DownloadUrl -FileName $releaseInfo.AssetName
        Install-CherryStudio -InstallerPath $installerPath
        Validate-Install

        Write-Step "Completed"
        Write-Host "Cherry Studio installation completed successfully." -ForegroundColor Green
    }
    elseif ($Action -eq "uninstall") {
        Uninstall-CherryStudio

        Write-Step "Completed"
        Write-Host "Cherry Studio uninstall completed successfully." -ForegroundColor Green
    }
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    Write-Host ""
    Write-Host "Operation failed." -ForegroundColor Red
    Write-Host "See log file: $Script:LogFile" -ForegroundColor Red
    exit 1
}
