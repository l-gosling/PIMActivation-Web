#requires -Version 7.0

<#
.SYNOPSIS
    Logging module for PIM Activation Web Service
.DESCRIPTION
    Provides structured logging functionality with JSON support
#>

# Global logger state
$script:LogConfig = @{
    Level         = 'Information'
    Path          = $null
    Format        = 'Json'
    MaxFileSize   = 10MB
    MaxBackupFiles = 5
}

<#
.SYNOPSIS
    Initialize logging configuration
#>
function Initialize-Logger {
    param(
        [ValidateSet('Verbose', 'Debug', 'Information', 'Warning', 'Error')]
        [string]
        $Level = 'Information',

        [string]
        $Path = $null
    )

    $script:LogConfig.Level = $Level
    $script:LogConfig.Path = $Path

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
        [string]
        $Message,

        [ValidateSet('Verbose', 'Debug', 'Information', 'Warning', 'Error')]
        [string]
        $Level = 'Information',

        [hashtable]
        $Data = @{}
    )

    # Convert level string to numeric value for filtering
    $logLevels = @{
        'Verbose'     = 0
        'Debug'       = 1
        'Information' = 2
        'Warning'     = 3
        'Error'       = 4
    }

    if ($logLevels[$Level] -lt $logLevels[$script:LogConfig.Level]) {
        return
    }

    $timestamp = Get-Date -Format 'o'
    $logEntry = @{
        timestamp = $timestamp
        level     = $Level
        message   = $Message
    } + $Data

    $jsonLog = $logEntry | ConvertTo-Json -Compress

    # Write to console
    Write-Host $jsonLog

    # Write to file if configured
    if ($script:LogConfig.Path) {
        Add-Content -Path $script:LogConfig.Path -Value $jsonLog -ErrorAction SilentlyContinue
    }
}
