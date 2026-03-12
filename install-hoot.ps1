param(
    [ValidateSet("install", "uninstall")]
    [string]$Action = "install"
)

$ErrorActionPreference = "Stop"

$Script:LogDir = (Get-Location).Path
$Script:LogFile = Join-Path $Script:LogDir ("hoot-" + $Action + "-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")

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

function Refresh-Path {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
    Write-Log "PATH refreshed for current session."
}

function Get-CommandPath {
    param(
        [string[]]$Candidates
    )

    foreach ($candidate in $Candidates) {
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($cmd) {
            return $cmd.Source
        }
    }

    return $null
}

function Ensure-CommandPath {
    param(
        [string[]]$Candidates,
        [string]$DisplayName
    )

    $path = Get-CommandPath -Candidates $Candidates
    if (-not $path) {
        throw "Required command not found: $DisplayName"
    }

    return $path
}

function Invoke-LoggedCommand {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [switch]$IgnoreExitCode
    )

    $commandText = $FilePath
    if ($Arguments -and $Arguments.Count -gt 0) {
        $commandText += " " + ($Arguments -join " ")
    }

    Write-Log "Running: $commandText"

    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()

    try {
        $process = Start-Process -FilePath $FilePath `
                                 -ArgumentList $Arguments `
                                 -NoNewWindow `
                                 -Wait `
                                 -PassThru `
                                 -RedirectStandardOutput $stdoutFile `
                                 -RedirectStandardError $stderrFile

        $stdoutLines = @()
        $stderrLines = @()

        if (Test-Path $stdoutFile) {
            $stdoutLines = Get-Content -Path $stdoutFile -ErrorAction SilentlyContinue
        }

        if (Test-Path $stderrFile) {
            $stderrLines = Get-Content -Path $stderrFile -ErrorAction SilentlyContinue
        }

        foreach ($line in $stdoutLines) {
            Add-Content -Path $Script:LogFile -Value $line
        }

        foreach ($line in $stderrLines) {
            Add-Content -Path $Script:LogFile -Value $line

            if ($line -match '^\s*npm\s+warn\b' -or $line -match '^\s*npm\s+WARN\b') {
                Write-Log $line "WARN"
            }
        }

        $allLines = @($stdoutLines) + @($stderrLines)

        if (-not $IgnoreExitCode -and $process.ExitCode -ne 0) {
            throw "Command failed with exit code $($process.ExitCode): $commandText"
        }

        return [PSCustomObject]@{
            Output   = $allLines
            ExitCode = $process.ExitCode
        }
    }
    finally {
        Remove-Item $stdoutFile -Force -ErrorAction SilentlyContinue
        Remove-Item $stderrFile -Force -ErrorAction SilentlyContinue
    }
}

function Test-WingetResultIsAcceptable {
    param(
        [int]$ExitCode,
        [object[]]$Output
    )

    if ($ExitCode -eq 0) {
        return $true
    }

    $text = ($Output | Out-String)

    if ($text -match "No available upgrade found") { return $true }
    if ($text -match "No newer package versions are available") { return $true }
    if ($text -match "Found an existing package already installed") { return $true }
    if ($text -match "Trying to upgrade the installed package") { return $true }
    if ($text -match "No installed package found matching input criteria") { return $true }

    return $false
}

function Get-WingetPath {
    return Ensure-CommandPath -Candidates @("winget.exe", "winget") -DisplayName "winget"
}

function Get-NodeExePath {
    return Ensure-CommandPath -Candidates @("node.exe", "node") -DisplayName "node"
}

function Get-NpmCmdPath {
    $path = Get-CommandPath -Candidates @("npm.cmd")
    if ($path) {
        return $path
    }

    $nodePath = Get-CommandPath -Candidates @("node.exe", "node")
    if ($nodePath) {
        $nodeDir = Split-Path $nodePath -Parent
        $candidate = Join-Path $nodeDir "npm.cmd"
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    throw "Required command not found: npm.cmd"
}

function Install-Or-Upgrade-Node20 {
    Write-Step "Checking winget"
    $wingetPath = Get-WingetPath
    Write-Log "winget is available at: $wingetPath"

    Write-Step "Installing or upgrading Node.js 20 LTS"

    $installResult = Invoke-LoggedCommand -FilePath $wingetPath -Arguments @(
        "install",
        "--id", "OpenJS.NodeJS",
        "--version", "20.20.1",
        "--exact",
        "--accept-source-agreements",
        "--accept-package-agreements",
        "--silent"
    ) -IgnoreExitCode

    if (Test-WingetResultIsAcceptable -ExitCode $installResult.ExitCode -Output $installResult.Output) {
        Write-Log "winget install returned an acceptable result."
        return
    }

    Write-Log "winget install did not return an acceptable result. Trying winget upgrade." "WARN"

    $upgradeResult = Invoke-LoggedCommand -FilePath $wingetPath -Arguments @(
        "upgrade",
        "--id", "OpenJS.NodeJS",
        "--version", "20.20.1",
        "--exact",
        "--accept-source-agreements",
        "--accept-package-agreements",
        "--silent"
    ) -IgnoreExitCode

    if (Test-WingetResultIsAcceptable -ExitCode $upgradeResult.ExitCode -Output $upgradeResult.Output) {
        Write-Log "winget upgrade returned an acceptable result."
        return
    }

    throw "Node.js 20 installation or upgrade failed."
}

function Get-NodeVersion {
    $nodeExe = Get-NodeExePath
    return ((Invoke-LoggedCommand -FilePath $nodeExe -Arguments @("-v")).Output | Select-Object -Last 1).ToString().Trim()
}

function Get-NpmVersion {
    $npmCmd = Get-NpmCmdPath
    return ((Invoke-LoggedCommand -FilePath $npmCmd -Arguments @("-v")).Output | Select-Object -Last 1).ToString().Trim()
}

function Get-NpmRootGlobal {
    $npmCmd = Get-NpmCmdPath
    return ((Invoke-LoggedCommand -FilePath $npmCmd -Arguments @("root", "-g")).Output | Select-Object -Last 1).ToString().Trim()
}

function Install-Hoot {
    Write-Step "Validating Node.js and npm"

    $nodeExe = Get-NodeExePath
    $npmCmd  = Get-NpmCmdPath

    $nodeVersion = Get-NodeVersion
    $npmVersion  = Get-NpmVersion

    Write-Log "Detected node executable: $nodeExe"
    Write-Log "Detected npm command: $npmCmd"
    Write-Log "Detected Node.js version: $nodeVersion"
    Write-Log "Detected npm version: $npmVersion"

    Write-Step "Installing or upgrading Hoot"
    $npmInstallResult = Invoke-LoggedCommand -FilePath $npmCmd -Arguments @("install", "-g", "@portkey-ai/hoot")

    if ($npmInstallResult.ExitCode -eq 0) {
        Write-Log "Hoot installation completed successfully."
    }

    Write-Step "Locating hoot.js"
    $npmRoot = Get-NpmRootGlobal
    $hootJs = Join-Path $npmRoot "@portkey-ai\hoot\bin\hoot.js"

    if (-not (Test-Path $hootJs)) {
        throw "Could not find hoot.js at: $hootJs"
    }

    Write-Log "npm global root: $npmRoot"
    Write-Log "hoot.js path: $hootJs"

    Write-Step "Backing up hoot.js"
    $backupPath = "${hootJs}.bak"
    Copy-Item -Path $hootJs -Destination $backupPath -Force
    Write-Log "Backup created: $backupPath"

    Write-Step "Applying Windows patch (shell: true)"
    $content = Get-Content -Path $hootJs -Raw -Encoding UTF8

    if ($content -match 'spawn\(viteCommand,\s*viteArgs,\s*\{\s*shell:\s*true,') {
        Write-Log "Patch already present. No changes needed."
    }
    else {
        $pattern = 'spawn\(viteCommand,\s*viteArgs,\s*\{'
        $replacement = "spawn(viteCommand, viteArgs, {`r`n  shell: true,"
        $patched = [regex]::Replace($content, $pattern, $replacement, 1)

        if ($patched -eq $content) {
            throw "Patch could not be applied automatically. The expected spawn(...) block was not found."
        }

        Set-Content -Path $hootJs -Value $patched -Encoding UTF8
        Write-Log "Patch applied successfully."
    }
}

function Validate-Install {
    Write-Step "Final validation"

    $nodeExe = Get-NodeExePath
    $npmCmd  = Get-NpmCmdPath
    $hootCmd = Get-Command "hoot" -ErrorAction SilentlyContinue

    if (-not $hootCmd) {
        throw "hoot command not found in PATH."
    }

    $nodeVersion = Get-NodeVersion
    $npmVersion  = Get-NpmVersion
    $npmRoot     = Get-NpmRootGlobal

    $hootPackageJson = Join-Path $npmRoot "@portkey-ai\hoot\package.json"
    if (-not (Test-Path $hootPackageJson)) {
        throw "Could not find Hoot package.json at: $hootPackageJson"
    }

    $hootPackage = Get-Content -Path $hootPackageJson -Raw -Encoding UTF8 | ConvertFrom-Json
    $hootVersion = $hootPackage.version

    if (-not $hootVersion) {
        throw "Could not determine Hoot version from package.json."
    }

    Write-Log "Detected node executable: $nodeExe"
    Write-Log "Detected npm command: $npmCmd"
    Write-Log "Detected Node.js version: $nodeVersion"
    Write-Log "Detected npm version: $npmVersion"
    Write-Log "Detected Hoot version: $hootVersion"
    Write-Log "Hoot command path: $($hootCmd.Source)"

    Write-Step "Summary"
    Write-Host "Node.js version : $nodeVersion" -ForegroundColor Green
    Write-Host "npm version     : $npmVersion" -ForegroundColor Green
    Write-Host "Hoot version    : $hootVersion" -ForegroundColor Green
    Write-Host "hoot command    : $($hootCmd.Source)" -ForegroundColor Green
    Write-Host "Log file        : $Script:LogFile" -ForegroundColor Green
}

function Uninstall-HootAndNode {
    Write-Step "Checking winget"
    $wingetPath = Get-WingetPath
    Write-Log "winget is available at: $wingetPath"

    Write-Step "Uninstalling Hoot"
    try {
        $npmCmd = Get-NpmCmdPath
        $npmUninstall = Invoke-LoggedCommand -FilePath $npmCmd -Arguments @("uninstall", "-g", "@portkey-ai/hoot") -IgnoreExitCode
        Write-Log "npm uninstall exit code: $($npmUninstall.ExitCode)"
    }
    catch {
        Write-Log "npm.cmd not found. Skipping npm uninstall." "WARN"
    }

    $appDataNpm = Join-Path $env:APPDATA "npm"
    if (Test-Path $appDataNpm) {
        Get-ChildItem -Path $appDataNpm -Filter "hoot*" -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                Remove-Item $_.FullName -Force -ErrorAction Stop
                Write-Log "Removed file: $($_.FullName)"
            }
            catch {
                Write-Log "Could not remove file: $($_.FullName)" "WARN"
            }
        }
    }

    $hootDataDir = Join-Path $env:USERPROFILE ".hoot"
    if (Test-Path $hootDataDir) {
        Remove-Item $hootDataDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Removed Hoot data directory: $hootDataDir"
    }

    Write-Step "Uninstalling Node.js 20"
    $wingetUninstall = Invoke-LoggedCommand -FilePath $wingetPath -Arguments @(
        "uninstall",
        "--id", "OpenJS.NodeJS",
        "--exact",
        "--accept-source-agreements"
    ) -IgnoreExitCode

    if (Test-WingetResultIsAcceptable -ExitCode $wingetUninstall.ExitCode -Output $wingetUninstall.Output) {
        Write-Log "winget uninstall for Node.js returned an acceptable result."
    }
    else {
        Write-Log "winget uninstall for Node.js returned a non-zero exit code." "WARN"
    }

    Write-Step "Uninstall summary"
    Write-Host "Hoot uninstall attempted." -ForegroundColor Green
    Write-Host "Node.js uninstall attempted." -ForegroundColor Green
    Write-Host "Log file: $Script:LogFile" -ForegroundColor Green
}

try {
    Initialize-Log
    Write-Log "Script started with action: $Action"

    if ($Action -eq "install") {
        Install-Or-Upgrade-Node20
        Refresh-Path
        Install-Hoot
        Refresh-Path
        Validate-Install

        Write-Step "Completed"
        Write-Host "Installation and patching completed successfully." -ForegroundColor Green
        Write-Host "You can now run: hoot" -ForegroundColor Green
    }
    elseif ($Action -eq "uninstall") {
        Uninstall-HootAndNode

        Write-Step "Completed"
        Write-Host "Uninstall completed." -ForegroundColor Green
    }
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    Write-Host ""
    Write-Host "Operation failed." -ForegroundColor Red
    Write-Host "See log file: $Script:LogFile" -ForegroundColor Red
    exit 1
}