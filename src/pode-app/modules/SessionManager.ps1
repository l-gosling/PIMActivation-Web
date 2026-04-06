#requires -Version 7.0

<#
.SYNOPSIS
    Session management module
.DESCRIPTION
    Manages user sessions and authentication tokens
#>

$script:Sessions = @{}
$script:SessionLock = [System.Threading.ReaderWriterLockSlim]::new()

<#
.SYNOPSIS
    Create a new session
#>
function New-Session {
    param(
        [string]
        $UserId,

        [hashtable]
        $Claims = @{}
    )

    $sessionId = [guid]::NewGuid().ToString()
    $session = @{
        Id            = $sessionId
        UserId        = $UserId
        Claims        = $Claims
        CreatedAt     = Get-Date
        LastActivity  = Get-Date
        AccessToken   = $null
        RefreshToken  = $null
        ExpiresAt     = (Get-Date).AddHours(1)
    }

    $script:SessionLock.EnterWriteLock()
    try {
        $script:Sessions[$sessionId] = $session
    }
    finally {
        $script:SessionLock.ExitWriteLock()
    }

    return $sessionId
}

<#
.SYNOPSIS
    Get session by ID
#>
function Get-Session {
    param(
        [string]
        $SessionId
    )

    $script:SessionLock.EnterReadLock()
    try {
        $session = $script:Sessions[$SessionId]
        if ($session -and $session.ExpiresAt -gt (Get-Date)) {
            $session.LastActivity = Get-Date
            return $session
        }
        return $null
    }
    finally {
        $script:SessionLock.ExitReadLock()
    }
}

<#
.SYNOPSIS
    Remove session
#>
function Remove-Session {
    param(
        [string]
        $SessionId
    )

    $script:SessionLock.EnterWriteLock()
    try {
        $script:Sessions.Remove($SessionId) | Out-Null
    }
    finally {
        $script:SessionLock.ExitWriteLock()
    }
}

<#
.SYNOPSIS
    Clean up expired sessions
#>
function Clear-ExpiredSessions {
    $now = Get-Date

    $script:SessionLock.EnterWriteLock()
    try {
        $expiredIds = @($script:Sessions.Keys | Where-Object {
            $script:Sessions[$_].ExpiresAt -lt $now
        })

        foreach ($id in $expiredIds) {
            $script:Sessions.Remove($id)
        }

        return $expiredIds.Count
    }
    finally {
        $script:SessionLock.ExitWriteLock()
    }
}
