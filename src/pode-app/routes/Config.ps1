#requires -Version 7.0

<#
.SYNOPSIS
    Configuration API routes
.DESCRIPTION
    Provides feature and theme configuration to the frontend,
    and manages per-user preference storage.
#>

<#
.SYNOPSIS
    Get feature configuration
#>
function Invoke-GetFeatureConfig {
    [CmdletBinding()]
    param(
        [object]$Request
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
    [CmdletBinding()]
    param(
        [object]$Request
    )

    try {
        $theme = @{
            primaryColor        = $env:THEME_PRIMARY_COLOR ?? '#0078D4'
            secondaryColor      = $env:THEME_SECONDARY_COLOR ?? '#107C10'
            dangerColor         = $env:THEME_DANGER_COLOR ?? '#DA3B01'
            warningColor        = $env:THEME_WARNING_COLOR ?? '#FFB900'
            successColor        = $env:THEME_SUCCESS_COLOR ?? '#107C10'
            sectionHeaderColor  = $env:THEME_SECTION_HEADER_COLOR ?? ($env:THEME_PRIMARY_COLOR ?? '#0078D4')
            entraColor          = $env:THEME_ENTRA_COLOR ?? '#0078D4'
            groupColor          = $env:THEME_GROUP_COLOR ?? '#107C10'
            azureColor          = $env:THEME_AZURE_COLOR ?? '#003067'
            neutralLight        = '#F3F2F1'
            neutralQuaternary   = '#D0D0D0'
            fontFamily          = $env:THEME_FONT_FAMILY ?? 'Segoe UI, -apple-system, sans-serif'
            borderRadius        = '4px'
            shadowDepth         = '0 1.6px 3.6px rgba(0, 0, 0, 0.132), 0 0.3px 0.9px rgba(0, 0, 0, 0.108)'
            copyright           = $env:APP_COPYRIGHT ?? ''
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

function Get-PreferencesPath {
    [CmdletBinding()]
    param()
    return '/var/pim-data/preferences'
}

function Get-DefaultPreferences {
    [CmdletBinding()]
    param()
    return @{
        theme            = 'auto'
        sortOrder        = 'name'
        groupBy          = 'type'
        defaultDuration  = 60
        rememberAccount  = $true
        autoRefresh      = $false
        refreshInterval  = 300
        showAzureRoles   = $true
        profiles         = @()
        history          = @()
    }
}

function Get-AllowedPreferences {
    [CmdletBinding()]
    param()
    return @{
        theme            = 'string'
        sortOrder        = 'string'
        groupBy          = 'string'
        defaultDuration  = 'int'
        rememberAccount  = 'bool'
        autoRefresh      = 'bool'
        refreshInterval  = 'int'
        showAzureRoles   = 'bool'
        profiles         = 'json'
        history          = 'json'
    }
}

<#
.SYNOPSIS
    Get a sanitized filename for a user ID
.DESCRIPTION
    Hashes the user ID with SHA256 to produce a safe, deterministic filename.
    User IDs (GUIDs or UPNs) may contain characters invalid for filenames on some
    platforms, so hashing avoids filesystem issues.
.PARAMETER UserId
    The Entra ID user object ID or UPN
#>
function Get-UserPrefsFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$UserId
    )

    $hash = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($UserId)
    $hashStr = [BitConverter]::ToString($hash.ComputeHash($bytes)) -replace '-', ''
    return Join-Path (Get-PreferencesPath) "$hashStr.json"
}

<#
.SYNOPSIS
    Load preferences for a user from disk, merged with defaults
.DESCRIPTION
    Reads the user's saved preferences JSON file and merges it with the
    default preferences so newly added preference keys are always present.
    Only keys listed in Get-AllowedPreferences are kept.
.PARAMETER UserId
    The Entra ID user object ID
#>
function Read-UserPreferences {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$UserId
    )

    $file = Get-UserPrefsFile -UserId $UserId
    if (Test-Path $file) {
        try {
            $saved = Get-Content $file -Raw | ConvertFrom-Json -AsHashtable
            $merged = Get-DefaultPreferences
            $allowedPrefs = Get-AllowedPreferences
            foreach ($key in $saved.Keys) {
                if ($allowedPrefs.ContainsKey($key)) {
                    $merged[$key] = $saved[$key]
                }
            }
            return $merged
        }
        catch {
            Write-Log -Message "Failed to read preferences for user: $($_.Exception.Message)" -Level 'Warning'
        }
    }
    return (Get-DefaultPreferences)
}

<#
.SYNOPSIS
    Save preferences for a user to disk
.DESCRIPTION
    Validates and type-casts incoming preference values against the allowed
    preference schema, then merges with existing preferences to preserve
    keys not included in the current update.
.PARAMETER UserId
    The Entra ID user object ID
.PARAMETER Preferences
    Hashtable of preference key/value pairs to save
#>
function Write-UserPreferences {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$UserId,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Preferences
    )

    $file = Get-UserPrefsFile -UserId $UserId
    $allowedPrefs = Get-AllowedPreferences

    # Validate and filter to allowed keys only
    $clean = @{}
    foreach ($key in $Preferences.Keys) {
        if (-not $allowedPrefs.ContainsKey($key)) { continue }

        $val = $Preferences[$key]
        switch ($allowedPrefs[$key]) {
            'int'    { $clean[$key] = [int]$val }
            'bool'   { $clean[$key] = [bool]$val }
            'string' { $clean[$key] = [string]$val }
            'json'   { $clean[$key] = $val }
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
    [CmdletBinding()]
    param(
        [object]$Request
    )

    try {
        $ctx = Get-CurrentSessionContext

        if (-not $ctx.Session) {
            # Return defaults for unauthenticated users
            Write-PodeJsonResponse -Value @{
                success     = $true
                preferences = (Get-DefaultPreferences)
            }
            return
        }

        $preferences = Read-UserPreferences -UserId $ctx.UserId

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
    [CmdletBinding()]
    param(
        [object]$Request,
        [object]$Body
    )

    try {
        $ctx = Get-CurrentSessionContext

        if (-not $ctx.Session) {
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

        Write-UserPreferences -UserId $ctx.UserId -Preferences $prefs

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
