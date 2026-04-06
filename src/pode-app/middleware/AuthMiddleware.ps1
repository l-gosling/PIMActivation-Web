#requires -Version 7.0

<#
.SYNOPSIS
    Authentication middleware for Pode
.DESCRIPTION
    Implements OAuth 2.0 Authorization Code flow with Entra ID.
    Uses Pode state (Set-PodeState/Get-PodeState) for session storage
    so sessions are shared across all runspaces.
#>

<#
.SYNOPSIS
    Generate a cryptographically secure random string
#>
function New-SecureToken {
    param([int]$ByteLength = 48)
    $bytes = [byte[]]::new($ByteLength)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    return ([Convert]::ToBase64String($bytes) -replace '[+/=]', '')
}

<#
.SYNOPSIS
    Helper to get/set the sessions hashtable from Pode shared state
#>
function Get-AuthSession {
    param([string]$SessionId)
    $sessions = Get-PodeState -Name 'AuthSessions'
    if ($sessions -and $sessions.ContainsKey($SessionId)) {
        return $sessions[$SessionId]
    }
    return $null
}

function Set-AuthSession {
    param([string]$SessionId, [hashtable]$Data)
    Lock-PodeObject -Object (Get-PodeState -Name 'AuthSessions') -ScriptBlock {
        $sessions = Get-PodeState -Name 'AuthSessions'
        $sessions[$SessionId] = $Data
        Set-PodeState -Name 'AuthSessions' -Value $sessions | Out-Null
    }
}

function Remove-AuthSession {
    param([string]$SessionId)
    Lock-PodeObject -Object (Get-PodeState -Name 'AuthSessions') -ScriptBlock {
        $sessions = Get-PodeState -Name 'AuthSessions'
        $sessions.Remove($SessionId) | Out-Null
        Set-PodeState -Name 'AuthSessions' -Value $sessions | Out-Null
    }
}

<#
.SYNOPSIS
    Clean up expired sessions (called by timer)
#>
function Clear-ExpiredAuthSessions {
    $now = Get-Date
    Lock-PodeObject -Object (Get-PodeState -Name 'AuthSessions') -ScriptBlock {
        $sessions = Get-PodeState -Name 'AuthSessions'
        $expired = @($sessions.Keys | Where-Object { $sessions[$_].ExpiresAt -lt $now })
        foreach ($id in $expired) {
            $sessions.Remove($id)
        }
        if ($expired.Count -gt 0) {
            Set-PodeState -Name 'AuthSessions' -Value $sessions | Out-Null
            Write-Host "Cleaned up $($expired.Count) expired session(s)"
        }
    }
}

<#
.SYNOPSIS
    Get Entra ID OAuth configuration from environment
#>
function Get-OAuthConfig {
    $tenantId = $env:ENTRA_TENANT_ID
    $clientId = $env:ENTRA_CLIENT_ID
    $clientSecret = $env:ENTRA_CLIENT_SECRET
    $redirectUri = $env:ENTRA_REDIRECT_URI ?? "http://localhost:$($env:PODE_PORT ?? '8080')/api/auth/callback"

    return @{
        TenantId      = $tenantId
        ClientId      = $clientId
        ClientSecret  = $clientSecret
        RedirectUri   = $redirectUri
        AuthorizeUrl  = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/authorize"
        TokenUrl      = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
        Scopes        = 'openid profile email User.Read'
    }
}

<#
.SYNOPSIS
    Helper to extract cookie value (Pode returns hashtable or string depending on version)
#>
function Get-CookieValue {
    param([string]$Name)
    $cookie = Get-PodeCookie -Name $Name
    if ($cookie -is [hashtable]) { return $cookie.Value }
    return "$cookie"
}

<#
.SYNOPSIS
    Login route - redirects browser to Entra ID
#>
function Invoke-AuthLogin {
    param([object]$Request)

    try {
        $oauth = Get-OAuthConfig
        $state = New-SecureToken

        Set-PodeCookie -Name 'oauth_state' -Value $state -ExpiryDate ([datetime]::UtcNow.AddMinutes(10))

        $query = [System.Web.HttpUtility]::ParseQueryString('')
        $query['client_id']     = $oauth.ClientId
        $query['response_type'] = 'code'
        $query['redirect_uri']  = $oauth.RedirectUri
        $query['response_mode'] = 'query'
        $query['scope']         = $oauth.Scopes
        $query['state']         = $state
        $query['prompt']        = 'select_account'

        Move-PodeResponseUrl -Url "$($oauth.AuthorizeUrl)?$($query.ToString())"
    }
    catch {
        Write-PodeJsonResponse -Value @{ success = $false; error = $_.Exception.Message } -StatusCode 500
    }
}

<#
.SYNOPSIS
    OAuth callback - exchanges authorization code for tokens
#>
function Invoke-AuthCallback {
    param([object]$Request)

    try {
        $code      = $WebEvent.Query['code']
        $state     = $WebEvent.Query['state']
        $error_msg = $WebEvent.Query['error']

        if ($error_msg) {
            $errorDesc = $WebEvent.Query['error_description'] ?? $error_msg
            Move-PodeResponseUrl -Url "/?error=$([System.Web.HttpUtility]::UrlEncode($errorDesc))"
            return
        }

        if ([string]::IsNullOrWhiteSpace($code)) {
            Move-PodeResponseUrl -Url '/?error=Missing+authorization+code'
            return
        }

        # Verify state
        $savedState = Get-CookieValue -Name 'oauth_state'
        if ($savedState -ne $state) {
            Move-PodeResponseUrl -Url "/?error=$([System.Web.HttpUtility]::UrlEncode("State mismatch"))"
            return
        }

        # Exchange code for tokens via curl (IPv6 workaround on Alpine)
        $oauth = Get-OAuthConfig
        $curlArgs = @(
            '-s', '-4', '-X', 'POST', $oauth.TokenUrl,
            '-d', "client_id=$($oauth.ClientId)",
            '-d', "client_secret=$([System.Web.HttpUtility]::UrlEncode($oauth.ClientSecret))",
            '-d', "code=$([System.Web.HttpUtility]::UrlEncode($code))",
            '-d', "redirect_uri=$([System.Web.HttpUtility]::UrlEncode($oauth.RedirectUri))",
            '-d', 'grant_type=authorization_code',
            '-d', "scope=$([System.Web.HttpUtility]::UrlEncode($oauth.Scopes))"
        )
        $tokenJson = & curl @curlArgs 2>&1
        $tokenResponse = $tokenJson | ConvertFrom-Json

        if ($tokenResponse.error) {
            throw "Token exchange failed: $($tokenResponse.error_description ?? $tokenResponse.error)"
        }

        # Decode JWT to get user claims
        $jwt = $tokenResponse.id_token ?? $tokenResponse.access_token
        if (-not $jwt) { throw "No token in response" }

        $jwtParts = $jwt -split '\.'
        $payloadBase64 = $jwtParts[1] -replace '-', '+' -replace '_', '/'
        switch ($payloadBase64.Length % 4) {
            2 { $payloadBase64 += '==' }
            3 { $payloadBase64 += '=' }
        }
        $payloadJson = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payloadBase64))
        $claims = $payloadJson | ConvertFrom-Json

        # Create session with cryptographic ID
        $sessionId = New-SecureToken
        Set-AuthSession -SessionId $sessionId -Data @{
            UserId       = $claims.oid ?? $claims.sub
            Email        = $claims.preferred_username ?? $claims.email ?? $claims.upn
            Name         = $claims.name ?? $claims.preferred_username ?? $claims.upn
            AccessToken  = $tokenResponse.access_token
            RefreshToken = $tokenResponse.refresh_token
            ExpiresAt    = (Get-Date).AddSeconds([int]($tokenResponse.expires_in ?? 3600))
            CreatedAt    = Get-Date
        }

        Write-Host "Session created for: $($claims.name)"

        Set-PodeCookie -Name 'pim_session' -Value $sessionId -ExpiryDate ([datetime]::UtcNow.AddHours(1)) -HttpOnly
        Remove-PodeCookie -Name 'oauth_state'

        Move-PodeResponseUrl -Url '/'
    }
    catch {
        Write-Host "OAuth callback error: $($_.Exception.Message)"
        Move-PodeResponseUrl -Url "/?error=$([System.Web.HttpUtility]::UrlEncode($_.Exception.Message))"
    }
}

<#
.SYNOPSIS
    Validate CSRF token on state-changing requests
#>
function Test-CsrfToken {
    $sessionId = Get-CookieValue -Name 'pim_session'
    if (-not $sessionId) { return $false }

    $session = Get-AuthSession -SessionId $sessionId
    if (-not $session) { return $false }

    $headerToken = $WebEvent.Request.Headers['X-CSRF-Token']
    if ([string]::IsNullOrWhiteSpace($headerToken)) { return $false }

    return $headerToken -eq $session.CsrfToken
}

<#
.SYNOPSIS
    Logout route handler
#>
function Invoke-AuthLogout {
    param([object]$Request)

    try {
        $sessionId = Get-CookieValue -Name 'pim_session'

        if ($sessionId) {
            Remove-AuthSession -SessionId $sessionId
        }

        Remove-PodeCookie -Name 'pim_session'

        Write-PodeJsonResponse -Value @{ success = $true; message = 'Logged out successfully' }
    }
    catch {
        Write-PodeJsonResponse -Value @{ success = $false; error = $_.Exception.Message } -StatusCode 400
    }
}

<#
.SYNOPSIS
    Get current user info from session
#>
function Invoke-AuthMe {
    param([object]$Request)

    try {
        $sessionId = Get-CookieValue -Name 'pim_session'

        if (-not $sessionId) {
            Write-PodeJsonResponse -Value @{ success = $false; error = 'Not authenticated' } -StatusCode 401
            return
        }

        $session = Get-AuthSession -SessionId $sessionId

        if (-not $session) {
            Remove-PodeCookie -Name 'pim_session'
            Write-PodeJsonResponse -Value @{ success = $false; error = 'Session not found' } -StatusCode 401
            return
        }

        if ($session.ExpiresAt -lt (Get-Date)) {
            Remove-AuthSession -SessionId $sessionId
            Remove-PodeCookie -Name 'pim_session'
                Write-PodeJsonResponse -Value @{ success = $false; error = 'Session expired' } -StatusCode 401
            return
        }

        Write-PodeJsonResponse -Value @{
            success = $true
            user    = @{
                id    = $session.UserId
                name  = $session.Name
                email = $session.Email
            }
        }
    }
    catch {
        Write-PodeJsonResponse -Value @{ success = $false; error = $_.Exception.Message } -StatusCode 400
    }
}

<#
.SYNOPSIS
    Get the access token for the current session (used by PIM API calls)
#>
function Get-SessionAccessToken {
    $sessionId = Get-CookieValue -Name 'pim_session'
    if (-not $sessionId) { return $null }

    $session = Get-AuthSession -SessionId $sessionId
    if (-not $session -or $session.ExpiresAt -lt (Get-Date)) { return $null }

    return $session.AccessToken
}
