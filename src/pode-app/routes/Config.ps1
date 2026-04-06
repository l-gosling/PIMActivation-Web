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

<#
.SYNOPSIS
    Get user preferences
#>
function Invoke-GetUserPreferences {
    param(
        [object]
        $Request
    )

    try {
        # TODO: Load from persistent storage
        $preferences = @{
            theme            = 'light'
            sortOrder        = 'name'
            groupBy          = 'type'
            defaultDuration  = 60
            rememberAccount  = $true
            autoRefresh      = $false
            refreshInterval  = 300
        }

        Write-PodeJsonResponse -Value @{
            success       = $true
            preferences   = $preferences
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
    Update user preferences
#>
function Invoke-UpdateUserPreferences {
    param(
        [object]
        $Request,

        [object]
        $Body
    )

    try {
        # TODO: Save to persistent storage
        Write-PodeJsonResponse -Value @{
            success = $true
            message = 'Preferences updated successfully'
        } -StatusCode 200
    }
    catch {
        Write-PodeJsonResponse -Value @{
            success = $false
            error   = $_.Exception.Message
        } -StatusCode 500
    }
}

