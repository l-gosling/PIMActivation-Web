#requires -Version 7.0

<#
.SYNOPSIS
    Role management API routes
.DESCRIPTION
    Handles role activation, deactivation, and role queries
#>

<#
.SYNOPSIS
    Determine whether Azure Resource roles should be shown
.DESCRIPTION
    Returns $true only if Azure roles are enabled in the server config AND
    the current user has not disabled them in their preferences.
.PARAMETER ConfigEnabled
    Whether INCLUDE_AZURE_RESOURCES is true in the server configuration
#>
function Get-AzureRoleVisibility {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [bool]$ConfigEnabled
    )

    if (-not $ConfigEnabled) { return $false }

    $ctx = Get-CurrentSessionContext
    if ($ctx.Session) {
        $prefs = Read-UserPreferences -UserId $ctx.UserId
        if ($prefs.ContainsKey('showAzureRoles') -and -not $prefs.showAzureRoles) {
            return $false
        }
    }
    return $true
}

<#
.SYNOPSIS
    Get eligible roles for the current user
#>
function Invoke-GetEligibleRoles {
    [CmdletBinding()]
    param(
        [object]$Request
    )

    try {
        if (-not (Assert-AuthenticatedSession)) { return }

        $config = Get-AllConfig
        $showAzure = Get-AzureRoleVisibility -ConfigEnabled $config.IncludeAzureResources
        Write-Log -Message "Eligible roles request: Azure=$showAzure" -Level 'Debug'

        $result = Get-PIMEligibleRolesForWeb -UserContext $WebEvent.Auth -IncludeEntraRoles:$config.IncludeEntraRoles -IncludeGroups:$config.IncludeGroups -IncludeAzureResources:$showAzure

        Write-PodeJsonResponse -Value $result -StatusCode 200
    }
    catch {
        Write-Log -Message "Route error (eligible): $($_.Exception.Message)" -Level 'Error'
        Write-PodeJsonResponse -Value @{
            success = $false
            error   = 'An internal error occurred'
        } -StatusCode 500
    }
}

<#
.SYNOPSIS
    Get active roles for the current user
#>
function Invoke-GetActiveRoles {
    [CmdletBinding()]
    param(
        [object]$Request
    )

    try {
        if (-not (Assert-AuthenticatedSession)) { return }

        $config = Get-AllConfig
        $showAzure = Get-AzureRoleVisibility -ConfigEnabled $config.IncludeAzureResources

        $result = Get-PIMActiveRolesForWeb -UserContext $WebEvent.Auth -IncludeEntraRoles:$config.IncludeEntraRoles -IncludeGroups:$config.IncludeGroups -IncludeAzureResources:$showAzure

        Write-PodeJsonResponse -Value $result -StatusCode 200
    }
    catch {
        Write-Log -Message "Route error (active): $($_.Exception.Message)" -Level 'Error'
        Write-PodeJsonResponse -Value @{
            success = $false
            error   = 'An internal error occurred'
        } -StatusCode 500
    }
}

<#
.SYNOPSIS
    Activate a role
#>
function Invoke-ActivateRole {
    [CmdletBinding()]
    param(
        [object]$Request,
        [object]$Body
    )

    try {
        if (-not (Assert-AuthenticatedSession)) { return }

        $data = $WebEvent.Data
        $roleId = $data.roleId
        $roleType = $data.roleType ?? 'User'
        $directoryScopeId = $data.directoryScopeId ?? '/'
        $justification = $data.justification
        $ticketNumber = $data.ticketNumber
        $durationMinutes = $data.durationMinutes ?? 60

        if ([string]::IsNullOrWhiteSpace($roleId) -or -not ($roleId -as [guid])) {
            Write-PodeJsonResponse -Value @{
                success = $false
                error   = 'Invalid roleId'
            } -StatusCode 400
            return
        }

        if ($durationMinutes -lt 1 -or $durationMinutes -gt 1440) {
            Write-PodeJsonResponse -Value @{
                success = $false
                error   = 'Duration must be between 1 and 1440 minutes'
            } -StatusCode 400
            return
        }

        $duration = [timespan]::FromMinutes($durationMinutes)

        $result = Invoke-PIMRoleActivationForWeb -RoleId $roleId -UserContext $WebEvent.Auth -RoleType $roleType -DirectoryScopeId $directoryScopeId -Justification $justification -TicketNumber $ticketNumber -Duration $duration

        if ($result.success) {
            Write-PodeJsonResponse -Value $result -StatusCode 200
        }
        else {
            Write-PodeJsonResponse -Value $result -StatusCode 400
        }
    }
    catch {
        Write-Log -Message "Activate error: $($_.Exception.Message)" -Level 'Error'
        Write-PodeJsonResponse -Value @{
            success = $false
            error   = $_.Exception.Message
        } -StatusCode 500
    }
}

<#
.SYNOPSIS
    Deactivate a role
#>
function Invoke-DeactivateRole {
    [CmdletBinding()]
    param(
        [object]$Request,
        [object]$Body
    )

    try {
        if (-not (Assert-AuthenticatedSession)) { return }

        $data = $WebEvent.Data
        $roleId = $data.roleId
        $roleType = $data.roleType ?? 'User'
        $directoryScopeId = $data.directoryScopeId ?? '/'

        if ([string]::IsNullOrWhiteSpace($roleId) -or -not ($roleId -as [guid])) {
            Write-PodeJsonResponse -Value @{
                success = $false
                error   = 'Invalid roleId'
            } -StatusCode 400
            return
        }

        $result = Invoke-PIMRoleDeactivationForWeb -RoleId $roleId -UserContext $WebEvent.Auth -RoleType $roleType -DirectoryScopeId $directoryScopeId

        if ($result.success) {
            Write-PodeJsonResponse -Value $result -StatusCode 200
        }
        else {
            Write-PodeJsonResponse -Value $result -StatusCode 400
        }
    }
    catch {
        Write-Log -Message "Deactivate error: $($_.Exception.Message)" -Level 'Error'
        Write-PodeJsonResponse -Value @{
            success = $false
            error   = $_.Exception.Message
        } -StatusCode 500
    }
}

<#
.SYNOPSIS
    Get role policies
#>
function Invoke-GetRolePolicies {
    [CmdletBinding()]
    param(
        [object]$Request,

        [string]$RoleId
    )

    try {
        if (-not (Assert-AuthenticatedSession)) { return }

        if ([string]::IsNullOrWhiteSpace($RoleId) -or -not ($RoleId -as [guid])) {
            Write-PodeJsonResponse -Value @{
                success = $false
                error   = 'Invalid roleId'
            } -StatusCode 400
            return
        }

        $result = Get-PIMRolePolicyForWeb -RoleId $RoleId

        Write-PodeJsonResponse -Value $result -StatusCode 200
    }
    catch {
        Write-Log -Message "Route error (policies): $($_.Exception.Message)" -Level 'Error'
        Write-PodeJsonResponse -Value @{
            success = $false
            error   = 'An internal error occurred'
        } -StatusCode 500
    }
}
