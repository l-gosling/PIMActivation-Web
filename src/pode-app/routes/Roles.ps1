#requires -Version 7.0

<#
.SYNOPSIS
    Role management API routes
.DESCRIPTION
    Handles role activation, deactivation, and role queries
#>

<#
.SYNOPSIS
    Get eligible roles for the current user
#>
function Invoke-GetEligibleRoles {
    param(
        [object]
        $Request
    )

    try {
        $config = Get-AllConfig

        $result = Get-PIMEligibleRolesForWeb -UserContext $WebEvent.Auth -IncludeEntraRoles:$config.IncludeEntraRoles -IncludeGroups:$config.IncludeGroups

        Write-PodeJsonResponse -Value $result -StatusCode 200
    }
    catch {
        Write-PodeJsonResponse -Value @{
            success = $false
            error   = $_.Exception.Message
        } -StatusCode 500
    }
}

<#
.SYNOPSIS
    Get active roles for the current user
#>
function Invoke-GetActiveRoles {
    param(
        [object]
        $Request
    )

    try {
        $config = Get-AllConfig

        $result = Get-PIMActiveRolesForWeb -UserContext $WebEvent.Auth -IncludeEntraRoles:$config.IncludeEntraRoles -IncludeGroups:$config.IncludeGroups

        Write-PodeJsonResponse -Value $result -StatusCode 200
    }
    catch {
        Write-PodeJsonResponse -Value @{
            success = $false
            error   = $_.Exception.Message
        } -StatusCode 500
    }
}

<#
.SYNOPSIS
    Activate a role
#>
function Invoke-ActivateRole {
    param(
        [object]$Request,
        [object]$Body
    )

    try {
        $data = $WebEvent.Data
        $roleId = $data.roleId
        $roleType = $data.roleType ?? 'User'
        $justification = $data.justification
        $ticketNumber = $data.ticketNumber
        $durationMinutes = $data.durationMinutes ?? 60

        if ([string]::IsNullOrWhiteSpace($roleId)) {
            Write-PodeJsonResponse -Value @{
                success = $false
                error   = 'roleId is required'
            } -StatusCode 400
            return
        }

        $duration = [timespan]::FromMinutes($durationMinutes)

        $result = Invoke-PIMRoleActivationForWeb -RoleId $roleId -UserContext $WebEvent.Auth -RoleType $roleType -Justification $justification -TicketNumber $ticketNumber -Duration $duration

        if ($result.success) {
            Write-PodeJsonResponse -Value $result -StatusCode 200
        }
        else {
            Write-PodeJsonResponse -Value $result -StatusCode 400
        }
    }
    catch {
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
    param(
        [object]$Request,
        [object]$Body
    )

    try {
        $data = $WebEvent.Data
        $roleId = $data.roleId
        $roleType = $data.roleType ?? 'User'

        if ([string]::IsNullOrWhiteSpace($roleId)) {
            Write-PodeJsonResponse -Value @{
                success = $false
                error   = 'roleId is required'
            } -StatusCode 400
            return
        }

        $result = Invoke-PIMRoleDeactivationForWeb -RoleId $roleId -UserContext $WebEvent.Auth -RoleType $roleType

        if ($result.success) {
            Write-PodeJsonResponse -Value $result -StatusCode 200
        }
        else {
            Write-PodeJsonResponse -Value $result -StatusCode 400
        }
    }
    catch {
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
    param(
        [object]
        $Request,

        [string]
        $RoleId
    )

    try {
        if ([string]::IsNullOrWhiteSpace($RoleId)) {
            Write-PodeJsonResponse -Value @{
                success = $false
                error   = 'roleId is required'
            } -StatusCode 400
            return
        }

        $result = Get-PIMRolePolicyForWeb -RoleId $RoleId

        Write-PodeJsonResponse -Value $result -StatusCode 200
    }
    catch {
        Write-PodeJsonResponse -Value @{
            success = $false
            error   = $_.Exception.Message
        } -StatusCode 500
    }
}

