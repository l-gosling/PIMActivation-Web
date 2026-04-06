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
    $config = Get-AllConfig
    $required = @('EntraTenantId', 'EntraClientId', 'EntraClientSecret')
    
    foreach ($key in $required) {
        if ([string]::IsNullOrWhiteSpace($config[$key])) {
            throw "Missing required configuration: $key (env: $(($key -replace '([a-z])([A-Z])', '$1_$2').ToUpper()))"
        }
    }
}
