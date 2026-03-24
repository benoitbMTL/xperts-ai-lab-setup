$ErrorActionPreference = "Stop"

# -------------------------------------------------------------------
# Config
# -------------------------------------------------------------------
$FolderName   = "FortiWeb Labs"
$LogRoot      = "C:\xperts-ai-setup"
$LogFile      = Join-Path $LogRoot "edge-managed-bookmarks.log"
$RegistryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"

$Bookmarks = @(
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

# -------------------------------------------------------------------
# Logging
# -------------------------------------------------------------------
if (-not (Test-Path $LogRoot)) {
    New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null
}
if (-not (Test-Path $LogFile)) {
    New-Item -Path $LogFile -ItemType File -Force | Out-Null
}

function Log($msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
    Add-Content -Path $LogFile -Value $line
    Write-Host $line
}

# -------------------------------------------------------------------
# Main
# -------------------------------------------------------------------
try {
    Log "Starting Edge Managed Favorites setup"

    # Ensure registry path
    if (-not (Test-Path $RegistryPath)) {
        New-Item -Path $RegistryPath -Force | Out-Null
        Log "Created registry path"
    }

    # Build JSON (THIS IS THE FIX 👇)
    $ManagedFavorites = @(
        @{
            toplevel_name = $FolderName
            children      = $Bookmarks
        }
    )

    $Json = $ManagedFavorites | ConvertTo-Json -Depth 10 -Compress
    Log "Built JSON for $($Bookmarks.Count) bookmarks"

    # Write registry
    New-ItemProperty -Path $RegistryPath `
        -Name "ManagedFavorites" `
        -Value $Json `
        -PropertyType String `
        -Force | Out-Null

    New-ItemProperty -Path $RegistryPath `
        -Name "FavoritesBarEnabled" `
        -Value 1 `
        -PropertyType DWord `
        -Force | Out-Null

    Log "Registry updated successfully"

    Log "Completed successfully"
    Write-Host "`nAll bookmarks are under folder: $FolderName" -ForegroundColor Green
}
catch {
    Log "ERROR: $($_.Exception.Message)"
    exit 1
}
