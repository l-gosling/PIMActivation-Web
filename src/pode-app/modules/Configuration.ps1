#requires -Version 7.0

<#
.SYNOPSIS
    Configuration module for PIM Activation Web Service
.DESCRIPTION
    Manages configuration from environment variables and config files
#>

<#
.SYNOPSIS
    Get configuration value
#>
function Get-ConfigValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Key,

        [string]$DefaultValue = $null
    )

    $envKey = $Key -replace '\s+', '_'
    $value = [Environment]::GetEnvironmentVariable($envKey)
    
    return $value ?? $DefaultValue
}

<#
.SYNOPSIS
    Get all configuration as hashtable
#>
function Get-AllConfig {
    [CmdletBinding()]
    param()
    return @{
        EntraTenantId       = Get-ConfigValue 'ENTRA_TENANT_ID'
        EntraClientId       = Get-ConfigValue 'ENTRA_CLIENT_ID'
        EntraClientSecret   = Get-ConfigValue 'ENTRA_CLIENT_SECRET'
        PodePort            = Get-ConfigValue 'PODE_PORT' '8080'
        PodeMode            = Get-ConfigValue 'PODE_MODE' 'production'
        LogLevel            = Get-ConfigValue 'LOG_LEVEL' 'Information'
        SessionTimeout      = [int](Get-ConfigValue 'SESSION_TIMEOUT' '3600')
        IncludeEntraRoles   = [bool]::Parse((Get-ConfigValue 'INCLUDE_ENTRA_ROLES' 'true'))
        IncludeGroups       = [bool]::Parse((Get-ConfigValue 'INCLUDE_GROUPS' 'true'))
        IncludeAzureResources = [bool]::Parse((Get-ConfigValue 'INCLUDE_AZURE_RESOURCES' 'false'))
        IncludeAuditLogs    = [bool]::Parse((Get-ConfigValue 'INCLUDE_AUDIT_LOGS' 'true'))
        GraphApiTimeout     = [int](Get-ConfigValue 'GRAPH_API_TIMEOUT' '30000')
        GraphBatchSize      = [int](Get-ConfigValue 'GRAPH_BATCH_SIZE' '20')
    }
}

<#
.SYNOPSIS
    Validate required configuration
#>
function Test-RequiredConfig {
    [CmdletBinding()]
    param()
    $placeholders = @('your-tenant-id', 'your-client-id', 'your-client-secret', 'your-app-client-id', 'your-app-client-secret')
    $required = @(
        @{ Env = 'ENTRA_TENANT_ID';     Value = $env:ENTRA_TENANT_ID }
        @{ Env = 'ENTRA_CLIENT_ID';     Value = $env:ENTRA_CLIENT_ID }
        @{ Env = 'ENTRA_CLIENT_SECRET'; Value = $env:ENTRA_CLIENT_SECRET }
    )

    foreach ($item in $required) {
        if ([string]::IsNullOrWhiteSpace($item.Value)) {
            throw "Missing required configuration: $($item.Env). Create a .env file from .env.example and set your Entra ID credentials."
        }
        if ($item.Value -in $placeholders) {
            throw "Configuration $($item.Env) still has the placeholder value '$($item.Value)'. Update your .env file with real Entra ID credentials."
        }
    }
}
