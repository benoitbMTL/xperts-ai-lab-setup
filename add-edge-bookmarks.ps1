param(
    [string]$FolderName = "FortiWeb Labs"
)

$ErrorActionPreference = "Stop"

$Script:LogFile = Join-Path (Get-Location).Path ("edge-bookmarks-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")

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

function New-EdgeId {
    param([ref]$Counter)
    $Counter.Value++
    return [string]$Counter.Value
}

function New-EdgeDateAdded {
    $epoch = [datetime]::SpecifyKind([datetime]"1601-01-01T00:00:00Z", [System.DateTimeKind]::Utc)
    $now = [datetime]::UtcNow
    $microseconds = [int64](($now - $epoch).TotalMilliseconds * 1000)
    return [string]$microseconds
}

function New-EmptyBookmarksFile {
    param([string]$Path)

    Write-Log "Creating new Edge Bookmarks file at: $Path" "WARN"

    $parent = Split-Path -Path $Path -Parent
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $now = New-EdgeDateAdded

    $emptyStructure = [ordered]@{
        checksum = ""
        roots = [ordered]@{
            bookmark_bar = [ordered]@{
                children      = @()
                date_added    = $now
                date_last_used = "0"
                date_modified = $now
                guid          = [guid]::NewGuid().ToString()
                id            = "1"
                name          = "Favorites bar"
                type          = "folder"
            }
            other = [ordered]@{
                children      = @()
                date_added    = $now
                date_last_used = "0"
                date_modified = $now
                guid          = [guid]::NewGuid().ToString()
                id            = "2"
                name          = "Other favorites"
                type          = "folder"
            }
            synced = [ordered]@{
                children      = @()
                date_added    = $now
                date_last_used = "0"
                date_modified = $now
                guid          = [guid]::NewGuid().ToString()
                id            = "3"
                name          = "Mobile bookmarks"
                type          = "folder"
            }
        }
        version = 1
    }

    $emptyStructure | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8

    Write-Log "Empty bookmarks file created."
}

function Get-EdgeBookmarksFile {
    $userDataRoot = Join-Path $env:LOCALAPPDATA "Microsoft\Edge\User Data"
    Write-Log "Looking for Edge profiles in: $userDataRoot"

    if (-not (Test-Path -LiteralPath $userDataRoot)) {
        throw "Edge user data directory not found: $userDataRoot"
    }

    $candidateFiles = @()
    $defaultBookmarks = Join-Path $userDataRoot "Default\Bookmarks"

    if (Test-Path -LiteralPath $defaultBookmarks) {
        $candidateFiles += $defaultBookmarks
    }

    $profileDirs = Get-ChildItem -LiteralPath $userDataRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'Profile *' }

    foreach ($dir in $profileDirs) {
        $candidate = Join-Path $dir.FullName "Bookmarks"
        if (Test-Path -LiteralPath $candidate) {
            $candidateFiles += $candidate
        }
    }

    $candidateFiles = $candidateFiles | Select-Object -Unique

    if (-not $candidateFiles -or $candidateFiles.Count -eq 0) {
        Write-Log "No Edge Bookmarks file found. Creating one in Default profile." "WARN"
        New-EmptyBookmarksFile -Path $defaultBookmarks
        return $defaultBookmarks
    }

    Write-Log "Detected bookmark files:"
    foreach ($file in $candidateFiles) {
        Write-Log " - $file"
    }

    if ($candidateFiles -contains $defaultBookmarks) {
        Write-Log "Using Default profile bookmarks file."
        return $defaultBookmarks
    }

    Write-Log "Using first detected profile bookmarks file."
    return ($candidateFiles | Select-Object -First 1)
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

function Update-MaxId {
    param($Node)

    if ($null -ne $Node.id -and $Node.id -match '^\d+$') {
        $idNum = [int64]$Node.id
        if ($idNum -gt $script:MaxId) {
            $script:MaxId = $idNum
        }
    }

    if ($Node.children) {
        foreach ($child in $Node.children) {
            Update-MaxId -Node $child
        }
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
        @{ name = "MCP Server";           url = "http://mcp-xperts.labsec.ca/mcp" }
        @{ name = "Juiceshop";            url = "http://juiceshop-xperts.labsec.ca" }
        @{ name = "Petstore";             url = "http://petstore3-xperts.labsec.ca" }
        @{ name = "Speedtest";            url = "http://speedtest-xperts.labsec.ca" }
        @{ name = "CSP Server";           url = "http://csp-xperts.labsec.ca" }
    )

    Ensure-EdgeClosed

    Write-Step "Locating Edge bookmarks file"
    $bookmarkFile = Get-EdgeBookmarksFile
    Write-Log "Selected bookmarks file: $bookmarkFile"

    if (-not (Test-Path -LiteralPath $bookmarkFile)) {
        throw "Selected Edge bookmarks file does not exist: $bookmarkFile"
    }

    Write-Step "Creating backup"
    $backupFile = "$bookmarkFile.bak_" + (Get-Date -Format "yyyyMMdd_HHmmss")
    Copy-Item -LiteralPath $bookmarkFile -Destination $backupFile -Force
    Write-Log "Backup created: $backupFile"

    Write-Step "Loading bookmarks JSON"
    $json = Get-Content -LiteralPath $bookmarkFile -Raw -Encoding UTF8 | ConvertFrom-Json

    if (-not $json.roots -or -not $json.roots.bookmark_bar) {
        throw "Unexpected Edge bookmarks structure."
    }

    $bookmarkBar = $json.roots.bookmark_bar

    if (-not $bookmarkBar.children) {
        $bookmarkBar | Add-Member -NotePropertyName children -NotePropertyValue @() -Force
    }

    Write-Step "Scanning existing bookmark IDs"
    $script:MaxId = 0
    Update-MaxId -Node $json.roots.bookmark_bar
    if ($json.roots.other)  { Update-MaxId -Node $json.roots.other }
    if ($json.roots.synced) { Update-MaxId -Node $json.roots.synced }

    Write-Log "Current maximum bookmark ID: $script:MaxId"
    $counter = $script:MaxId

    Write-Step "Locating or creating folder"
    $targetFolder = $null

    foreach ($child in $bookmarkBar.children) {
        if ($child.type -eq "folder" -and $child.name -eq $FolderName) {
            $targetFolder = $child
            break
        }
    }

    if ($null -eq $targetFolder) {
        $targetFolder = [pscustomobject]@{
            children       = @()
            date_added     = New-EdgeDateAdded
            date_last_used = "0"
            date_modified  = New-EdgeDateAdded
            guid           = [guid]::NewGuid().ToString()
            id             = New-EdgeId ([ref]$counter)
            name           = $FolderName
            type           = "folder"
        }

        $bookmarkBar.children += $targetFolder
        Write-Log "Created folder '$FolderName' on the favorites bar."
    }
    else {
        if (-not $targetFolder.children) {
            $targetFolder | Add-Member -NotePropertyName children -NotePropertyValue @() -Force
        }
        Write-Log "Folder '$FolderName' already exists on the favorites bar."
    }

    Write-Step "Adding bookmarks"
    $existingUrls = @{}
    foreach ($child in $targetFolder.children) {
        if ($child.type -eq "url" -and $child.url) {
            $existingUrls[$child.url] = $true
        }
    }

    $addedCount = 0
    $skippedCount = 0

    foreach ($bm in $bookmarksToAdd) {
        if ($existingUrls.ContainsKey($bm.url)) {
            Write-Log "Skipping existing bookmark: $($bm.name) -> $($bm.url)"
            $skippedCount++
            continue
        }

        $newBookmark = [pscustomobject]@{
            date_added     = New-EdgeDateAdded
            date_last_used = "0"
            guid           = [guid]::NewGuid().ToString()
            id             = New-EdgeId ([ref]$counter)
            name           = $bm.name
            type           = "url"
            url            = $bm.url
        }

        $targetFolder.children += $newBookmark
        Write-Log "Added bookmark: $($bm.name) -> $($bm.url)"
        $addedCount++
    }

    $targetFolder.date_modified = New-EdgeDateAdded
    $bookmarkBar.date_modified = New-EdgeDateAdded

    Write-Step "Saving updated bookmarks file"
    $json | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $bookmarkFile -Encoding UTF8
    Write-Log "Bookmarks file updated successfully."

    Write-Step "Summary"
    Write-Host "Folder name : $FolderName" -ForegroundColor Green
    Write-Host "Added       : $addedCount" -ForegroundColor Green
    Write-Host "Skipped     : $skippedCount" -ForegroundColor Green
    Write-Host "Bookmark DB : $bookmarkFile" -ForegroundColor Green
    Write-Host "Backup file : $backupFile" -ForegroundColor Green
    Write-Host "Log file    : $Script:LogFile" -ForegroundColor Green
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    Write-Host ""
    Write-Host "Operation failed." -ForegroundColor Red
    Write-Host "See log file: $Script:LogFile" -ForegroundColor Red
    exit 1
}
