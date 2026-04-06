#requires -Version 7.0

<#
.SYNOPSIS
    Configuration API routes
.DESCRIPTION
    Provides feature and theme configuration to the frontend
#>

<#
.SYNOPSIS
    Get feature configuration
#>
function Invoke-GetFeatureConfig {
    param(
        [object]
        $Request
    )

    try {
        $config = Get-AllConfig

        $features = @{
            includeEntraRoles      = $config.IncludeEntraRoles
            includeGroups          = $config.IncludeGroups
            includeAzureResources  = $config.IncludeAzureResources
            sessionTimeout         = $config.SessionTimeout
            graphBatchSize         = $config.GraphBatchSize
        }

        Write-PodeJsonResponse -Value @{
            success  = $true
            features = $features
        } -StatusCode 200
    }
    catch {
        Write-PodeJsonResponse -Value @{
            success = $false
            error   = $_.Exception.Message
        } -StatusCode 500
    }
}

<#
.SYNOPSIS
    Get theme configuration
#>
function Invoke-GetThemeConfig {
    param(
        [object]
        $Request
    )

    try {
        $theme = @{
            primaryColor        = '#0078D4'  # Entra ID Blue
            secondaryColor      = '#107C10' # Graph Green
            dangerColor         = '#DA3B01'  # Error Red
            warningColor        = '#FFB900'  # Warning Yellow
            successColor        = '#107C10'  # Success Green
            neutralLight        = '#F3F2F1'
            neutralQuaternary   = '#D0D0D0'
            fontFamily          = 'Segoe UI, -apple-system, sans-serif'
            borderRadius        = '4px'
            shadowDepth         = '0 1.6px 3.6px rgba(0, 0, 0, 0.132), 0 0.3px 0.9px rgba(0, 0, 0, 0.108)'
        }

        Write-PodeJsonResponse -Value @{
            success = $true
            theme   = $theme
        } -StatusCode 200
    }
    catch {
        Write-PodeJsonResponse -Value @{
            success = $false
            error   = $_.Exception.Message
        } -StatusCode 500
    }
}

function Get-PreferencesPath { return '/var/pim-data/preferences' }

function Get-DefaultPreferences {
    return @{
        theme            = 'auto'
        sortOrder        = 'name'
        groupBy          = 'type'
        defaultDuration  = 60
        rememberAccount  = $true
        autoRefresh      = $false
        refreshInterval  = 300
    }
}

function Get-AllowedPreferences {
    return @{
        theme            = 'string'
        sortOrder        = 'string'
        groupBy          = 'string'
        defaultDuration  = 'int'
        rememberAccount  = 'bool'
        autoRefresh      = 'bool'
        refreshInterval  = 'int'
    }
}

<#
.SYNOPSIS
    Get a sanitized filename for a user ID
#>
function Get-UserPrefsFile {
    param([string]$UserId)
    # Hash the user ID to avoid filesystem issues with special chars
    $hash = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($UserId)
    $hashStr = [BitConverter]::ToString($hash.ComputeHash($bytes)) -replace '-', ''
    return Join-Path (Get-PreferencesPath) "$hashStr.json"
}

<#
.SYNOPSIS
    Load preferences for a user from disk
#>
function Read-UserPreferences {
    param([string]$UserId)

    $file = Get-UserPrefsFile -UserId $UserId
    if (Test-Path $file) {
        try {
            $saved = Get-Content $file -Raw | ConvertFrom-Json -AsHashtable
            # Merge with defaults so new preference keys are always present
            $merged = (Get-DefaultPreferences)
            foreach ($key in $saved.Keys) {
                if ((Get-AllowedPreferences).ContainsKey($key)) {
                    $merged[$key] = $saved[$key]
                }
            }
            return $merged
        }
        catch {
            Write-Host "Failed to read preferences for user: $($_.Exception.Message)"
        }
    }
    return (Get-DefaultPreferences)
}

<#
.SYNOPSIS
    Save preferences for a user to disk
#>
function Write-UserPreferences {
    param([string]$UserId, [hashtable]$Preferences)

    $file = Get-UserPrefsFile -UserId $UserId

    # Validate and filter to allowed keys only
    $clean = @{}
    foreach ($key in $Preferences.Keys) {
        if (-not (Get-AllowedPreferences).ContainsKey($key)) { continue }

        $val = $Preferences[$key]
        switch ((Get-AllowedPreferences)[$key]) {
            'int'    { $clean[$key] = [int]$val }
            'bool'   { $clean[$key] = [bool]$val }
            'string' { $clean[$key] = [string]$val }
        }
    }

    # Merge with existing to preserve keys not in this update
    $existing = Read-UserPreferences -UserId $UserId
    foreach ($key in $clean.Keys) {
        $existing[$key] = $clean[$key]
    }

    $existing | ConvertTo-Json -Depth 5 | Set-Content $file -Encoding UTF8
}

<#
.SYNOPSIS
    Get user preferences
#>
function Invoke-GetUserPreferences {
    param([object]$Request)

    try {
        $sessionId = Get-CookieValue -Name 'pim_session'
        $session = if ($sessionId) { Get-AuthSession -SessionId $sessionId } else { $null }

        if (-not $session) {
            # Return defaults for unauthenticated users
            Write-PodeJsonResponse -Value @{
                success     = $true
                preferences = (Get-DefaultPreferences)
            }
            return
        }

        $preferences = Read-UserPreferences -UserId $session.UserId

        Write-PodeJsonResponse -Value @{
            success     = $true
            preferences = $preferences
        }
    }
    catch {
        Write-PodeJsonResponse -Value @{
            success = $false
            error   = $_.Exception.Message
        } -StatusCode 500
    }
}

<#
.SYNOPSIS
    Update user preferences
#>
function Invoke-UpdateUserPreferences {
    param([object]$Request, [object]$Body)

    try {
        $sessionId = Get-CookieValue -Name 'pim_session'
        $session = if ($sessionId) { Get-AuthSession -SessionId $sessionId } else { $null }

        if (-not $session) {
            Write-PodeJsonResponse -Value @{
                success = $false
                error   = 'Not authenticated'
            } -StatusCode 401
            return
        }

        $body = $WebEvent.Data
        if (-not $body) {
            Write-PodeJsonResponse -Value @{
                success = $false
                error   = 'No preferences provided'
            } -StatusCode 400
            return
        }

        # Convert PSObject to hashtable if needed
        $prefs = @{}
        if ($body -is [hashtable]) {
            $prefs = $body
        }
        else {
            foreach ($prop in $body.PSObject.Properties) {
                $prefs[$prop.Name] = $prop.Value
            }
        }

        Write-UserPreferences -UserId $session.UserId -Preferences $prefs

        Write-PodeJsonResponse -Value @{
            success = $true
            message = 'Preferences updated successfully'
        }
    }
    catch {
        Write-PodeJsonResponse -Value @{
            success = $false
            error   = $_.Exception.Message
        } -StatusCode 500
    }
}

