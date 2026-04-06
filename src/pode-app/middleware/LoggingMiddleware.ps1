#requires -Version 7.0

<#
.SYNOPSIS
    Logging middleware
.DESCRIPTION
    Logs HTTP requests and responses
#>

function Get-PodeLoggingMiddleware {
    return {
        $logEntry = @{
            timestamp = (Get-Date -AsUTC).ToString('o')
            method    = $WebEvent.Method
            path      = $WebEvent.Path
            ip        = $WebEvent.RemoteEndpoint.Address.IPAddressToString
            userAgent = $WebEvent.Request.UserAgent
        }

        Write-Log -Message "HTTP $($WebEvent.Method) $($WebEvent.Path)" -Level 'Information' -Data $logEntry

        return $true
    }
}

