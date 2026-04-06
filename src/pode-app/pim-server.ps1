#requires -Version 7.0

<#
.SYNOPSIS
    PIM Activation Web Server - Pode-based REST API and Web UI
.DESCRIPTION
    Starts a Pode HTTP server that serves the PIMActivation web interface
    and REST API for role activation, deactivation, and management.
#>

param(
    [string]
    $Port = (${env:PODE_PORT} ?? '8080'),

    [ValidateSet('development', 'production')]
    [string]
    $Mode = (${env:PODE_MODE} ?? 'production'),

    [ValidateSet('Verbose', 'Debug', 'Information', 'Warning', 'Error')]
    [string]
    $LogLevel = (${env:LOG_LEVEL} ?? 'Information')
)

# Set error action preference
$ErrorActionPreference = 'Stop'

# Import required modules
try {
    Import-Module Pode -ErrorAction Stop
}
catch {
    Write-Error "Failed to import Pode module. Install it first with: Install-Module -Name Pode -Force"
    exit 1
}

# Import custom modules (available in main script scope)
$ModulePath = Join-Path $PSScriptRoot 'modules'
$MiddlewarePath = Join-Path $PSScriptRoot 'middleware'
$RoutesPath = Join-Path $PSScriptRoot 'routes'

. (Join-Path $ModulePath 'Logger.ps1')
. (Join-Path $ModulePath 'Configuration.ps1')
. (Join-Path $ModulePath 'PIMApiLayer.ps1')
. (Join-Path $MiddlewarePath 'AuthMiddleware.ps1')
. (Join-Path $RoutesPath 'Roles.ps1')
. (Join-Path $RoutesPath 'Config.ps1')

# Initialize logging
Initialize-Logger -Level $LogLevel -Path '/var/log/pim/pode.log'

Write-Log -Message "Starting PIM Activation Web Service" -Level 'Information'
Write-Log -Message "Mode: $Mode, Port: $Port, LogLevel: $LogLevel" -Level 'Information'

# Start Pode server
Start-PodeServer -Name 'PIM-Activation' -Threads 5 {

    # Configure endpoint (HTTPS if certificate is present, otherwise HTTP)
    $serverPort = [int]($env:PODE_PORT ?? '8080')
    $certPath = $env:PODE_CERT_PATH ?? '/etc/pim-certs/cert.pem'
    $keyPath = $env:PODE_CERT_KEY_PATH ?? '/etc/pim-certs/key.pem'

    if ((Test-Path $certPath) -and (Test-Path $keyPath)) {
        Add-PodeEndpoint -Address * -Port $serverPort -Protocol Https -Certificate $certPath -CertificateKey $keyPath
        Write-Log -Message "HTTPS endpoint configured on port $serverPort" -Level 'Information'
    }
    else {
        Add-PodeEndpoint -Address * -Port $serverPort -Protocol Http
        Write-Log -Message "HTTP endpoint configured on port $serverPort (no certificate found)" -Level 'Information'
    }

    # Import scripts into Pode route runspaces so handler functions are available
    Use-PodeScript -Path (Join-Path $PSScriptRoot 'modules' 'Logger.ps1')
    Use-PodeScript -Path (Join-Path $PSScriptRoot 'modules' 'Configuration.ps1')
    Use-PodeScript -Path (Join-Path $PSScriptRoot 'modules' 'PIMApiLayer.ps1')
    Use-PodeScript -Path (Join-Path $PSScriptRoot 'middleware' 'AuthMiddleware.ps1')
    Use-PodeScript -Path (Join-Path $PSScriptRoot 'routes' 'Roles.ps1')
    Use-PodeScript -Path (Join-Path $PSScriptRoot 'routes' 'Config.ps1')

    # Security response headers on all routes
    Add-PodeMiddleware -Name 'SecurityHeaders' -ScriptBlock {
        Add-PodeHeader -Name 'X-Content-Type-Options' -Value 'nosniff'
        Add-PodeHeader -Name 'X-Frame-Options' -Value 'DENY'
        Add-PodeHeader -Name 'Referrer-Policy' -Value 'strict-origin-when-cross-origin'
        Add-PodeHeader -Name 'Permissions-Policy' -Value 'camera=(), microphone=(), geolocation=()'
        if ($WebEvent.Request.Url.Scheme -eq 'https') {
            Add-PodeHeader -Name 'Strict-Transport-Security' -Value 'max-age=31536000; includeSubDomains'
        }
        return $true
    }

    # Initialize shared session state
    Set-PodeState -Name 'AuthSessions' -Value @{} | Out-Null

    # Session cleanup timer - runs every 5 minutes
    Add-PodeTimer -Name 'SessionCleanup' -Interval 300 -ScriptBlock {
        Clear-ExpiredAuthSessions
    }

    # Set the folder for static files
    $publicPath = Join-Path $PSScriptRoot 'public'

    # Health check endpoint
    Add-PodeRoute -Method Get -Path '/api/health' -ScriptBlock {
        Write-PodeJsonResponse -Value @{
            status    = 'healthy'
            timestamp = (Get-Date -AsUTC).ToString('o')
            version   = '2.0.0'
        }
    }

    # Authentication routes
    Add-PodeRoute -Method Get -Path '/api/auth/login' -ScriptBlock {
        Invoke-AuthLogin -Request $WebEvent.Request
    }

    Add-PodeRoute -Method Get -Path '/api/auth/callback' -ScriptBlock {
        Invoke-AuthCallback -Request $WebEvent.Request
    }

    Add-PodeRoute -Method Post -Path '/api/auth/logout' -ScriptBlock {
        Invoke-AuthLogout -Request $WebEvent.Request
    }

    Add-PodeRoute -Method Get -Path '/api/auth/me' -ScriptBlock {
        Invoke-AuthMe -Request $WebEvent.Request
    }

    # Role Management routes
    Add-PodeRoute -Method Get -Path '/api/roles/eligible' -ScriptBlock {
        Invoke-GetEligibleRoles -Request $WebEvent.Request
    }

    Add-PodeRoute -Method Get -Path '/api/roles/active' -ScriptBlock {
        Invoke-GetActiveRoles -Request $WebEvent.Request
    }

    Add-PodeRoute -Method Post -Path '/api/roles/activate' -ScriptBlock {
        Invoke-ActivateRole -Request $WebEvent.Request -Body $WebEvent.Body
    }

    Add-PodeRoute -Method Post -Path '/api/roles/deactivate' -ScriptBlock {
        Invoke-DeactivateRole -Request $WebEvent.Request -Body $WebEvent.Body
    }

    Add-PodeRoute -Method Get -Path '/api/roles/policies/:roleId' -ScriptBlock {
        Invoke-GetRolePolicies -Request $WebEvent.Request -RoleId $WebEvent.Parameters.roleId
    }

    # Configuration routes
    Add-PodeRoute -Method Get -Path '/api/config/features' -ScriptBlock {
        Invoke-GetFeatureConfig -Request $WebEvent.Request
    }

    Add-PodeRoute -Method Get -Path '/api/config/theme' -ScriptBlock {
        Invoke-GetThemeConfig -Request $WebEvent.Request
    }

    # User preference routes
    Add-PodeRoute -Method Get -Path '/api/user/preferences' -ScriptBlock {
        Invoke-GetUserPreferences -Request $WebEvent.Request
    }

    Add-PodeRoute -Method Post -Path '/api/user/preferences' -ScriptBlock {
        Invoke-UpdateUserPreferences -Request $WebEvent.Request -Body $WebEvent.Body
    }

    # Serve static files (css, js, images) from public folder at root
    if (Test-Path $publicPath) {
        Add-PodeStaticRoute -Path '/' -Source $publicPath -Defaults @('index.html')
    }

    Write-Log -Message "PIM Activation Web Service started on port $serverPort" -Level 'Information'
}
