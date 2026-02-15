#
# Post-Push Notification Script — PowerShell
#
# Gathers git metadata and POSTs change notification to GAS web app.
#
# Prerequisites:
#   - git (for commit metadata) - optional, falls back gracefully
#   - PowerShell 3.0+ (for Invoke-RestMethod and ConvertTo-Json)
#
# Usage:
#   $env:GAS_WEBAPP_URL = "https://script.google.com/macros/s/YOUR_SCRIPT_ID/exec"
#   .\scripts\post-push-notify.ps1
#

# Configuration
$GAS_WEBAPP_URL = if ($env:GAS_WEBAPP_URL) { $env:GAS_WEBAPP_URL } else { "https://YOUR_GAS_SCRIPT_URL_HERE/exec" }
$APPS_SCRIPT_DIR = "apps-script/src"

Write-Host "┌────────────────────────────────────────────────────────────────┐" -ForegroundColor Blue
Write-Host "│ GAS Change Tracker — Post-Push Notification                   │" -ForegroundColor Blue
Write-Host "└────────────────────────────────────────────────────────────────┘" -ForegroundColor Blue
Write-Host ""

# Check if git is available
$gitAvailable = Get-Command git -ErrorAction SilentlyContinue

if (-not $gitAvailable) {
    Write-Host "Warning: git not found. Using fallback values." -ForegroundColor Yellow
    $commitMessage = "Manual push (git not available)"
    $commitHash = "unknown"
    $author = "unknown"
    $changedFiles = @()
} else {
    try {
        # Gather git metadata
        $commitMessage = & git log -1 --pretty=format:"%s" 2>$null
        if (-not $commitMessage) { $commitMessage = "Manual push" }

        $commitHash = & git log -1 --pretty=format:"%h" 2>$null
        if (-not $commitHash) { $commitHash = "unknown" }

        $author = & git log -1 --pretty=format:"%an" 2>$null
        if (-not $author) { $author = "unknown" }

        # Get changed files in apps-script/src/ from the last commit
        $allChangedFiles = & git diff-tree --no-commit-id --name-only -r HEAD 2>$null
        $changedFiles = $allChangedFiles | Where-Object { $_ -like "$APPS_SCRIPT_DIR/*" } | ForEach-Object {
            $_ -replace "^$APPS_SCRIPT_DIR/", ""
        }

        # Fallback if no files found
        if (-not $changedFiles) {
            $changedFiles = @("(no apps-script changes in last commit)")
        }
    } catch {
        Write-Host "Warning: Error reading git metadata. Using fallback values." -ForegroundColor Yellow
        $commitMessage = "Manual push (git error)"
        $commitHash = "unknown"
        $author = "unknown"
        $changedFiles = @("(git error)")
    }
}

# Build JSON payload
$payload = @{
    action = "reportChange"
    author = $author
    changelog = $commitMessage
    commitHash = $commitHash
    files = $changedFiles
}

# Display what we're sending
Write-Host "Metadata gathered:" -ForegroundColor Green
Write-Host "  Author:      $author"
Write-Host "  Commit:      $commitHash"
Write-Host "  Message:     $commitMessage"
Write-Host "  Files:       $($changedFiles -join ', ')"
Write-Host ""

# Check if URL is configured
if ($GAS_WEBAPP_URL -like "*YOUR_GAS_SCRIPT_URL_HERE*") {
    Write-Host "Warning: GAS_WEBAPP_URL not configured. Using placeholder." -ForegroundColor Yellow
    Write-Host '  Set it with: $env:GAS_WEBAPP_URL = "https://script.google.com/..."'
    Write-Host ""
}

Write-Host "Sending notification to: $GAS_WEBAPP_URL" -ForegroundColor Blue
Write-Host ""

# POST to GAS web app
try {
    $jsonPayload = $payload | ConvertTo-Json -Compress
    $response = Invoke-RestMethod -Uri $GAS_WEBAPP_URL `
                                  -Method Post `
                                  -Body $jsonPayload `
                                  -ContentType "application/json" `
                                  -ErrorAction Stop

    Write-Host "Response:" -ForegroundColor Green
    $response | ConvertTo-Json | Write-Host
    Write-Host ""

    # Check for success
    if ($response.success -eq $true) {
        Write-Host "✓ Change notification sent successfully" -ForegroundColor Green
        exit 0
    } else {
        Write-Host "⚠ Warning: Response may indicate an error" -ForegroundColor Yellow
        exit 1
    }
} catch {
    Write-Host "Error: Failed to send notification" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
