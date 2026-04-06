#requires -Version 7.0

<#
.SYNOPSIS
    Logging module for PIM Activation Web Service
.DESCRIPTION
    Provides structured logging functionality with JSON support.
    Uses Pode state for config so it works across runspaces.
#>

<#
.SYNOPSIS
    Initialize logging configuration (call inside Start-PodeServer block)
#>
function Initialize-Logger {
    param(
        [ValidateSet('Verbose', 'Debug', 'Information', 'Warning', 'Error')]
        [string]$Level = 'Information',
        [string]$Path = $null
    )

    # Store in Pode state if available, otherwise use env vars as fallback
    try {
        Set-PodeState -Name 'LogConfig' -Value @{
            Level = $Level
            Path  = $Path
        } | Out-Null
    }
    catch {
        # Pode not initialized yet (called outside server block) — use env vars
        $env:PIM_LOG_LEVEL = $Level
        $env:PIM_LOG_PATH = $Path
    }

    if ($Path) {
        $dir = Split-Path $Path -Parent
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
}

<#
.SYNOPSIS
    Write a log entry
#>
function Write-Log {
    param(
        [string]$Message,

        [ValidateSet('Verbose', 'Debug', 'Information', 'Warning', 'Error')]
        [string]$Level = 'Information',

        [hashtable]$Data = @{}
    )

    $logLevels = @{
        'Verbose'     = 0
        'Debug'       = 1
        'Information' = 2
        'Warning'     = 3
        'Error'       = 4
    }

    # Get config from Pode state or env vars
    $configLevel = 'Information'
    $configPath = $null
    try {
        $config = Get-PodeState -Name 'LogConfig'
        if ($config) {
            $configLevel = $config.Level
            $configPath = $config.Path
        }
    }
    catch {
        $configLevel = $env:PIM_LOG_LEVEL ?? 'Information'
        $configPath = $env:PIM_LOG_PATH
    }

    if ($logLevels[$Level] -lt $logLevels[$configLevel]) {
        return
    }

    $timestamp = Get-Date -Format 'o'
    $logEntry = @{
        timestamp = $timestamp
        level     = $Level
        message   = $Message
    } + $Data

    $jsonLog = $logEntry | ConvertTo-Json -Compress

    Write-Host $jsonLog

    if ($configPath) {
        Add-Content -Path $configPath -Value $jsonLog -ErrorAction SilentlyContinue
    }
}
