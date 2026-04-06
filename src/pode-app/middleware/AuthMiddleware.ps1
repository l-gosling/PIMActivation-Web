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
.PARAMETER ByteLength
    Number of random bytes to generate. The output string will be longer
    due to Base64 encoding. Default is 48 bytes (~64 characters).
#>
function New-SecureToken {
    [CmdletBinding()]
    param(
        [int]$ByteLength = 48
    )

    $bytes = [byte[]]::new($ByteLength)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)

    # Strip +, /, = from Base64 to produce a URL-safe token that works in cookies without encoding
    return ([Convert]::ToBase64String($bytes) -replace '[+/=]', '')
}

<#
.SYNOPSIS
    Retrieve a session from Pode shared state by its ID
.PARAMETER SessionId
    The cryptographic session token stored in the client cookie
#>
function Get-AuthSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SessionId
    )

    $sessions = Get-PodeState -Name 'AuthSessions'
    if ($sessions -and $sessions.ContainsKey($SessionId)) {
        return $sessions[$SessionId]
    }
    return $null
}

<#
.SYNOPSIS
    Store or update a session in Pode shared state (thread-safe via Lock-PodeObject)
.PARAMETER SessionId
    The cryptographic session token
.PARAMETER Data
    Hashtable containing session data (UserId, Email, Name, AccessToken, etc.)
#>
function Set-AuthSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SessionId,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Data
    )

    Lock-PodeObject -Object (Get-PodeState -Name 'AuthSessions') -ScriptBlock {
        $sessions = Get-PodeState -Name 'AuthSessions'
        $sessions[$SessionId] = $Data
        Set-PodeState -Name 'AuthSessions' -Value $sessions | Out-Null
    }
}

<#
.SYNOPSIS
    Remove a session from Pode shared state (thread-safe via Lock-PodeObject)
.PARAMETER SessionId
    The cryptographic session token to remove
#>
function Remove-AuthSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SessionId
    )

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
    [CmdletBinding()]
    param()

    $now = Get-Date
    Lock-PodeObject -Object (Get-PodeState -Name 'AuthSessions') -ScriptBlock {
        $sessions = Get-PodeState -Name 'AuthSessions'
        $expired = @($sessions.Keys | Where-Object { $sessions[$_].ExpiresAt -lt $now })
        foreach ($id in $expired) {
            $sessions.Remove($id)
        }
        if ($expired.Count -gt 0) {
            Set-PodeState -Name 'AuthSessions' -Value $sessions | Out-Null
            Write-Log -Message "Cleaned up $($expired.Count) expired session(s)" -Level 'Information'
        }
    }
}

<#
.SYNOPSIS
    Get Entra ID OAuth configuration from environment
#>
function Get-OAuthConfig {
    [CmdletBinding()]
    param()

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
        Scopes        = 'openid profile email offline_access User.Read RoleManagement.ReadWrite.Directory PrivilegedAccess.ReadWrite.AzureADGroup Policy.Read.All AdministrativeUnit.Read.All'
    }
}

<#
.SYNOPSIS
    Set a cookie with SameSite attribute (Pode 2.x lacks native SameSite support)
.DESCRIPTION
    Constructs the Set-Cookie header manually to include the SameSite attribute,
    and registers the cookie in Pode's PendingCookies for Remove-PodeCookie compatibility.
.PARAMETER Name
    Cookie name
.PARAMETER Value
    Cookie value
.PARAMETER ExpiryDate
    Absolute expiry date (UTC)
.PARAMETER HttpOnly
    Prevent JavaScript access
.PARAMETER Secure
    Only send over HTTPS
.PARAMETER SameSite
    SameSite attribute: 'Strict', 'Lax', or 'None'
#>
function Set-SecureCookie {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Value = '',
        [datetime]$ExpiryDate,
        [switch]$HttpOnly,
        [switch]$Secure,
        [ValidateSet('Strict', 'Lax', 'None')]
        [string]$SameSite = 'Lax'
    )

    $parts = @("$Name=$Value", 'Path=/')
    if ($ExpiryDate -ne [datetime]::MinValue) {
        $parts += "Expires=$($ExpiryDate.ToUniversalTime().ToString('R'))"
    }
    if ($HttpOnly) { $parts += 'HttpOnly' }
    if ($Secure)   { $parts += 'Secure' }
    $parts += "SameSite=$SameSite"

    Add-PodeHeader -Name 'Set-Cookie' -Value ($parts -join '; ')

    # Register in Pode's internal tracking so Remove-PodeCookie still works
    $cookie = [System.Net.Cookie]::new($Name, $Value)
    $cookie.HttpOnly = [bool]$HttpOnly
    $cookie.Secure = [bool]$Secure
    $cookie.Path = '/'
    if ($ExpiryDate -ne [datetime]::MinValue) {
        $cookie.Expires = $ExpiryDate.ToUniversalTime()
    }
    $WebEvent.PendingCookies[$cookie.Name] = $cookie
}

<#
.SYNOPSIS
    Helper to extract cookie value (Pode returns hashtable or string depending on version)
.PARAMETER Name
    The name of the cookie to retrieve
#>
function Get-CookieValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    $cookie = Get-PodeCookie -Name $Name
    if ($cookie -is [hashtable]) { return $cookie.Value }
    return "$cookie"
}

<#
.SYNOPSIS
    Get the current request's session context (session, tokens, and user ID)
.DESCRIPTION
    Consolidates the cookie lookup, session retrieval, and token extraction
    into a single call. Returns a hashtable with all session-related values,
    using $null for any missing piece.
#>
function Get-CurrentSessionContext {
    [CmdletBinding()]
    param()

    $sessionId = Get-CookieValue -Name 'pim_session'
    $session = if ($sessionId) { Get-AuthSession -SessionId $sessionId } else { $null }

    return @{
        SessionId        = $sessionId
        Session          = $session
        AccessToken      = if ($session) { $session.AccessToken } else { $null }
        AzureAccessToken = if ($session) { $session.AzureAccessToken } else { $null }
        UserId           = if ($session) { $session.UserId } else { $null }
    }
}

<#
.SYNOPSIS
    Verify the current request is authenticated, returning a 401 JSON response if not
.DESCRIPTION
    Checks the pim_session cookie and validates the session exists.
    Returns $true if the session is valid. Returns $false after writing a
    401 response, so the caller should 'return' immediately when $false.
#>
function Assert-AuthenticatedSession {
    [CmdletBinding()]
    param()

    $ctx = Get-CurrentSessionContext
    if (-not $ctx.SessionId -or -not $ctx.Session) {
        Write-PodeJsonResponse -Value @{ success = $false; error = 'Not authenticated' } -StatusCode 401
        return $false
    }
    if ($ctx.Session.ExpiresAt -lt (Get-Date)) {
        Remove-AuthSession -SessionId $ctx.SessionId
        Remove-PodeCookie -Name 'pim_session'
        Write-PodeJsonResponse -Value @{ success = $false; error = 'Session expired' } -StatusCode 401
        return $false
    }
    return $true
}

<#
.SYNOPSIS
    Login route - redirects browser to Entra ID
#>
function Invoke-AuthLogin {
    [CmdletBinding()]
    param(
        [object]$Request
    )

    try {
        $oauth = Get-OAuthConfig
        $state = New-SecureToken

        Set-SecureCookie -Name 'oauth_state' -Value $state -ExpiryDate ([datetime]::UtcNow.AddMinutes(10)) -SameSite 'Lax'

        $query = [System.Web.HttpUtility]::ParseQueryString('')
        $query['client_id']     = $oauth.ClientId
        $query['response_type'] = 'code'
        $query['redirect_uri']  = $oauth.RedirectUri
        $query['response_mode'] = 'query'
        $query['scope']         = $oauth.Scopes
        $query['state']         = $state
        # Omit prompt= so Entra reuses an existing SSO session; falls back to interactive login automatically

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
    [CmdletBinding()]
    param(
        [object]$Request
    )

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

        # Exchange authorization code for tokens
        $oauth = Get-OAuthConfig
        $tokenBody = @{
            client_id     = $oauth.ClientId
            client_secret = $oauth.ClientSecret
            code          = $code
            redirect_uri  = $oauth.RedirectUri
            grant_type    = 'authorization_code'
            scope         = $oauth.Scopes
        }
        $tokenResult = Invoke-WebRequest -Uri $oauth.TokenUrl -Method Post -Body $tokenBody -ContentType 'application/x-www-form-urlencoded' -SkipHttpErrorCheck
        $tokenResponse = $tokenResult.Content | ConvertFrom-Json

        if ($tokenResponse.error) {
            throw "Token exchange failed: $($tokenResponse.error_description ?? $tokenResponse.error)"
        }

        # Decode JWT to get user claims
        $jwt = $tokenResponse.id_token ?? $tokenResponse.access_token
        if (-not $jwt) { throw "No token in response" }

        # JWT uses Base64url encoding (RFC 7515): '-' instead of '+', '_' instead of '/',
        # and padding '=' characters are omitted. Restore standard Base64 before decoding.
        $jwtParts = $jwt -split '\.'
        $payloadBase64 = $jwtParts[1] -replace '-', '+' -replace '_', '/'
        switch ($payloadBase64.Length % 4) {
            2 { $payloadBase64 += '==' }
            3 { $payloadBase64 += '=' }
        }
        $payloadJson = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payloadBase64))
        $claims = $payloadJson | ConvertFrom-Json

        # Exchange refresh token for Azure Management token
        $azureToken = $null
        $refreshToken = $tokenResponse.refresh_token
        if ($refreshToken) {
            try {
                $azTokenBody = @{
                    client_id     = $oauth.ClientId
                    client_secret = $oauth.ClientSecret
                    refresh_token = $refreshToken
                    grant_type    = 'refresh_token'
                    scope         = 'https://management.azure.com/.default'
                }
                $azTokenResult = Invoke-WebRequest -Uri $oauth.TokenUrl -Method Post -Body $azTokenBody -ContentType 'application/x-www-form-urlencoded' -SkipHttpErrorCheck
                $azTokenResponse = $azTokenResult.Content | ConvertFrom-Json
                if (-not $azTokenResponse.error) {
                    $azureToken = $azTokenResponse.access_token
                    Write-Log -Message "Azure Management token acquired" -Level 'Debug'
                }
                else {
                    Write-Log -Message "Azure token exchange failed (non-fatal)" -Level 'Warning'
                }
            }
            catch {
                Write-Log -Message "Azure token exchange failed (non-fatal): $($_.Exception.Message)" -Level 'Warning'
            }
        }

        # Create session with cryptographic ID
        $sessionId = New-SecureToken
        Set-AuthSession -SessionId $sessionId -Data @{
            UserId            = $claims.oid ?? $claims.sub
            Email             = $claims.preferred_username ?? $claims.email ?? $claims.upn
            Name              = $claims.name ?? $claims.preferred_username ?? $claims.upn
            AccessToken       = $tokenResponse.access_token
            AzureAccessToken  = $azureToken
            RefreshToken      = $tokenResponse.refresh_token
            ExpiresAt         = (Get-Date).AddSeconds([int]($env:SESSION_TIMEOUT ?? '3600'))
            CreatedAt         = Get-Date
        }

        Write-Log -Message "Session created for: $($claims.name)" -Level 'Information'

        $sessionTimeout = [int]($env:SESSION_TIMEOUT ?? '3600')
        $isHttps = (Test-Path ($env:PODE_CERT_PATH ?? '/etc/pim-certs/cert.pem'))
        Set-SecureCookie -Name 'pim_session' -Value $sessionId -ExpiryDate ([datetime]::UtcNow.AddSeconds($sessionTimeout)) -HttpOnly -Secure:$isHttps -SameSite 'Lax'
        Remove-PodeCookie -Name 'oauth_state'

        Move-PodeResponseUrl -Url '/'
    }
    catch {
        Write-Log -Message "OAuth callback error: $($_.Exception.Message)" -Level 'Error'
        Move-PodeResponseUrl -Url "/?error=$([System.Web.HttpUtility]::UrlEncode($_.Exception.Message))"
    }
}

<#
.SYNOPSIS
    Logout route handler
#>
function Invoke-AuthLogout {
    [CmdletBinding()]
    param(
        [object]$Request
    )

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
    [CmdletBinding()]
    param(
        [object]$Request
    )

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
    [CmdletBinding()]
    param()

    $ctx = Get-CurrentSessionContext
    if (-not $ctx.Session -or $ctx.Session.ExpiresAt -lt (Get-Date)) { return $null }
    return $ctx.AccessToken
}
