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
. (Join-Path $ModulePath 'SessionManager.ps1')
. (Join-Path $ModulePath 'PIMApiLayer.ps1')
. (Join-Path $MiddlewarePath 'AuthMiddleware.ps1')
. (Join-Path $MiddlewarePath 'ErrorMiddleware.ps1')
. (Join-Path $MiddlewarePath 'LoggingMiddleware.ps1')
. (Join-Path $RoutesPath 'Health.ps1')
. (Join-Path $RoutesPath 'Auth.ps1')
. (Join-Path $RoutesPath 'Roles.ps1')
. (Join-Path $RoutesPath 'Config.ps1')

# Initialize logging
Initialize-Logger -Level $LogLevel -Path '/var/log/pim/pode.log'

Write-Log -Message "Starting PIM Activation Web Service" -Level 'Information'
Write-Log -Message "Mode: $Mode, Port: $Port, LogLevel: $LogLevel" -Level 'Information'

# Start Pode server
Start-PodeServer -Name 'PIM-Activation' -Threads 5 {

    # Configure endpoint
    $serverPort = [int]($env:PODE_PORT ?? '8080')
    Add-PodeEndpoint -Address * -Port $serverPort -Protocol Http

    # Import scripts into Pode route runspaces so handler functions are available
    Use-PodeScript -Path (Join-Path $PSScriptRoot 'modules' 'Logger.ps1')
    Use-PodeScript -Path (Join-Path $PSScriptRoot 'modules' 'Configuration.ps1')
    Use-PodeScript -Path (Join-Path $PSScriptRoot 'modules' 'SessionManager.ps1')
    Use-PodeScript -Path (Join-Path $PSScriptRoot 'modules' 'PIMApiLayer.ps1')
    Use-PodeScript -Path (Join-Path $PSScriptRoot 'middleware' 'AuthMiddleware.ps1')
    Use-PodeScript -Path (Join-Path $PSScriptRoot 'middleware' 'ErrorMiddleware.ps1')
    Use-PodeScript -Path (Join-Path $PSScriptRoot 'middleware' 'LoggingMiddleware.ps1')
    Use-PodeScript -Path (Join-Path $PSScriptRoot 'routes' 'Health.ps1')
    Use-PodeScript -Path (Join-Path $PSScriptRoot 'routes' 'Auth.ps1')
    Use-PodeScript -Path (Join-Path $PSScriptRoot 'routes' 'Roles.ps1')
    Use-PodeScript -Path (Join-Path $PSScriptRoot 'routes' 'Config.ps1')

    # Initialize shared session state
    Set-PodeState -Name 'AuthSessions' -Value @{} | Out-Null

    # Session cleanup timer - runs every 5 minutes
    Add-PodeTimer -Name 'SessionCleanup' -Interval 300 -ScriptBlock {
        Clear-ExpiredAuthSessions
    }

    # Endware: append SameSite=Lax to our cookies
    Add-PodeEndware -ScriptBlock {
        $cookies = $WebEvent.Response.Headers['Set-Cookie']
        if ($cookies) {
            foreach ($c in @($cookies)) {
                if ($c -match '^(pim_|oauth_)' -and $c -notmatch 'SameSite') {
                    $WebEvent.Response.Headers.Remove('Set-Cookie')
                    $WebEvent.Response.Headers.Add('Set-Cookie', "$c; SameSite=Lax")
                }
            }
        }
    }

    # Set the folder for static files
    $publicPath = Join-Path $PSScriptRoot 'public'

    # CORS middleware - restrict to same origin
    Add-PodeMiddleware -Name 'CorsMiddleware' -ScriptBlock {
        $origin = $WebEvent.Request.Headers['Origin']
        $host = $WebEvent.Request.Headers['Host']

        # Only allow same-origin requests
        if ($origin -and $origin -notmatch "^https?://$([regex]::Escape($host))$") {
            Set-PodeResponseStatus -Code 403
            return $false
        }

        if ($origin) {
            Set-PodeHeader -Name 'Access-Control-Allow-Origin' -Value $origin
            Set-PodeHeader -Name 'Access-Control-Allow-Methods' -Value 'GET, POST, DELETE, OPTIONS'
            Set-PodeHeader -Name 'Access-Control-Allow-Headers' -Value 'Content-Type, X-CSRF-Token'
            Set-PodeHeader -Name 'Access-Control-Allow-Credentials' -Value 'true'
        }

        if ($WebEvent.Method -eq 'OPTIONS') {
            Set-PodeResponseStatus -Code 204
            return $false
        }

        return $true
    }

    # CSRF middleware - validate token on POST/PUT/DELETE requests
    Add-PodeMiddleware -Name 'CsrfMiddleware' -ScriptBlock {
        # Skip CSRF check for safe methods and non-API routes
        if ($WebEvent.Method -in @('GET', 'HEAD', 'OPTIONS')) { return $true }
        if ($WebEvent.Path -notlike '/api/*') { return $true }
        # Skip for logout (session is being destroyed anyway)
        if ($WebEvent.Path -eq '/api/auth/logout') { return $true }

        if (-not (Test-CsrfToken)) {
            Write-PodeJsonResponse -Value @{ success = $false; error = 'Invalid CSRF token' } -StatusCode 403
            return $false
        }

        return $true
    }

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

    Write-Host "PIM Activation Web Service started on port $serverPort"
}
