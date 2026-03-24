param(
    [string]$FolderName = "FortiWeb Labs"
)

$ErrorActionPreference = "Stop"

$Script:LogFile = Join-Path (Get-Location).Path ("edge-managedfavorites-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")

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

function Ensure-RegistryPath {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
        Write-Log "Created registry path: $Path"
    }
    else {
        Write-Log "Registry path already exists: $Path"
    }
}

function Ensure-EdgeClosed {
    Write-Step "Checking Microsoft Edge process"

    $edgeProcesses = Get-Process msedge -ErrorAction SilentlyContinue

    if ($edgeProcesses) {
        Write-Log "Microsoft Edge is running. Attempting to stop it..." "WARN"

        try {
            $edgeProcesses | Stop-Process -Force -ErrorAction Stop
            Start-Sleep -Seconds 2
            Write-Log "Microsoft Edge processes terminated successfully."
        }
        catch {
            throw "Failed to stop Microsoft Edge processes: $($_.Exception.Message)"
        }
    }
    else {
        Write-Log "Microsoft Edge is not running."
    }
}

try {
    New-Item -ItemType File -Path $Script:LogFile -Force | Out-Null
    Write-Log "Script started."

    $bookmarksToAdd = @(
        @{ name = "XPERTS Hands-on-Labs"; url = "https://canada.amerintlxperts.com/hands-on-labs.html" }
        @{ name = "FortiWeb Admin";       url = "https://fwb-xperts.labsec.ca:8443" }
        @{ name = "Demo Tool";            url = "http://demotool-xperts.labsec.ca:8080" }
        @{ name = "DVWA";                 url = "http://dvwa-xperts.labsec.ca" }
        @{ name = "Banking Application";  url = "http://bank-xperts.labsec.ca" }
        @{ name = "MCP Server";           url = "http://mcp-xperts.labsec.ca" }
        @{ name = "Juiceshop";            url = "http://juiceshop-xperts.labsec.ca" }
        @{ name = "Petstore";             url = "http://petstore3-xperts.labsec.ca" }
        @{ name = "Speedtest";            url = "http://speedtest-xperts.labsec.ca" }
        @{ name = "CSP Server";           url = "http://csp-xperts.labsec.ca" }
    )

    Ensure-EdgeClosed

    Write-Step "Preparing Edge policy registry path"
    $edgePolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    Ensure-RegistryPath -Path $edgePolicyPath

    Write-Step "Building ManagedFavorites JSON"

    $managedFavorites = @(
        @{
            toplevel_name = $FolderName
        }
    )

    foreach ($bm in $bookmarksToAdd) {
        $managedFavorites += @{
            name = $bm.name
            url  = $bm.url
        }
    }

    $managedFavoritesJson = $managedFavorites | ConvertTo-Json -Depth 20 -Compress
    Write-Log "ManagedFavorites JSON built successfully."

    Write-Step "Backing up existing registry values if present"

    $backup = [ordered]@{
        Timestamp          = (Get-Date).ToString("s")
        RegistryPath       = $edgePolicyPath
        ManagedFavorites   = $null
        FavoritesBarEnabled = $null
    }

    try {
        $existingManagedFavorites = (Get-ItemProperty -Path $edgePolicyPath -Name "ManagedFavorites" -ErrorAction Stop).ManagedFavorites
        $backup.ManagedFavorites = $existingManagedFavorites
        Write-Log "Existing ManagedFavorites value found and backed up."
    }
    catch {
        Write-Log "No existing ManagedFavorites value found."
    }

    try {
        $existingFavoritesBarEnabled = (Get-ItemProperty -Path $edgePolicyPath -Name "FavoritesBarEnabled" -ErrorAction Stop).FavoritesBarEnabled
        $backup.FavoritesBarEnabled = $existingFavoritesBarEnabled
        Write-Log "Existing FavoritesBarEnabled value found and backed up."
    }
    catch {
        Write-Log "No existing FavoritesBarEnabled value found."
    }

    $backupFile = Join-Path (Get-Location).Path ("edge-managedfavorites-backup-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".json")
    $backup | ConvertTo-Json -Depth 10 | Set-Content -Path $backupFile -Encoding UTF8
    Write-Log "Registry backup saved to: $backupFile"

    Write-Step "Writing Edge policies to registry"

    New-ItemProperty -Path $edgePolicyPath `
        -Name "ManagedFavorites" `
        -Value $managedFavoritesJson `
        -PropertyType String `
        -Force | Out-Null
    Write-Log "ManagedFavorites written successfully."

    New-ItemProperty -Path $edgePolicyPath `
        -Name "FavoritesBarEnabled" `
        -Value 1 `
        -PropertyType DWord `
        -Force | Out-Null
    Write-Log "FavoritesBarEnabled set to 1."

    Write-Step "Validation"
    $writtenManagedFavorites = (Get-ItemProperty -Path $edgePolicyPath -Name "ManagedFavorites").ManagedFavorites
    $writtenFavoritesBarEnabled = (Get-ItemProperty -Path $edgePolicyPath -Name "FavoritesBarEnabled").FavoritesBarEnabled

    if ($writtenManagedFavorites -ne $managedFavoritesJson) {
        throw "Validation failed: ManagedFavorites registry value does not match expected JSON."
    }

    if ($writtenFavoritesBarEnabled -ne 1) {
        throw "Validation failed: FavoritesBarEnabled registry value is not 1."
    }

    Write-Log "Registry values validated successfully."

    Write-Step "Summary"
    Write-Host "Folder name           : $FolderName" -ForegroundColor Green
    Write-Host "Bookmarks configured  : $($bookmarksToAdd.Count)" -ForegroundColor Green
    Write-Host "Registry path         : $edgePolicyPath" -ForegroundColor Green
    Write-Host "Backup file           : $backupFile" -ForegroundColor Green
    Write-Host "Log file              : $Script:LogFile" -ForegroundColor Green
    Write-Host ""
    Write-Host "Edge must be restarted for the policy to appear." -ForegroundColor Yellow
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    Write-Host ""
    Write-Host "Operation failed." -ForegroundColor Red
    Write-Host "See log file: $Script:LogFile" -ForegroundColor Red
    exit 1
}
