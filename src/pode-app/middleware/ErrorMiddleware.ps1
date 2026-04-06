#requires -Version 7.0

<#
.SYNOPSIS
    Error handling middleware
.DESCRIPTION
    Catches and formats errors consistently
#>

function Get-PodeErrorMiddleware {
    return {
        try {
            # Continue to next middleware
            return $true
        }
        catch {
            $errorDetails = @{
                error       = 'Internal Server Error'
                message     = $_.Exception.Message
                timestamp   = (Get-Date -AsUTC).ToString('o')
                errorId     = [guid]::NewGuid().ToString()
            }

            if ($PodeContext.Server.Mode -eq 'development') {
                $errorDetails['stackTrace'] = $_.ScriptStackTrace
            }

            Write-PodeJsonResponse -Value $errorDetails -StatusCode 500
            return $false
        }
    }
}

