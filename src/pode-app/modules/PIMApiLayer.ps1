#requires -Version 7.0

<#
.SYNOPSIS
    PIM API Layer - Microsoft Graph REST API calls for PIM role management
.DESCRIPTION
    Provides functions to query, activate, and deactivate PIM roles
    using the Microsoft Graph API. Uses curl for HTTP calls (IPv6 workaround on Alpine).
#>

function Get-GraphBaseUrl { return 'https://graph.microsoft.com/v1.0' }

<#
.SYNOPSIS
    Make a Graph API request using curl (IPv6 workaround)
#>
function Invoke-GraphApi {
    param(
        [string]$AccessToken,
        [string]$Method = 'GET',
        [string]$Endpoint,
        [string]$Body = $null
    )

    $url = "$(Get-GraphBaseUrl)$Endpoint"
    $curlArgs = @(
        '-s', '-4',
        '-X', $Method,
        '-H', "Authorization: Bearer $AccessToken",
        '-H', 'Content-Type: application/json'
    )

    if ($Body) {
        $bodyFile = "/tmp/graph_body_$([guid]::NewGuid().ToString('N').Substring(0,8)).json"
        $Body | Set-Content -Path $bodyFile -Encoding UTF8 -NoNewline
        $curlArgs += @('-d', "@$bodyFile")
    }

    try {
        $curlArgs += $url
        $rawOutput = & /usr/bin/curl @curlArgs 2>&1
        $responseText = if ($null -eq $rawOutput) { '' } elseif ($rawOutput -is [array]) { $rawOutput -join "`n" } else { "$rawOutput" }
        $responseText = $responseText.Trim()
    }
    finally {
        if ($bodyFile -and (Test-Path $bodyFile)) { Remove-Item $bodyFile -Force -ErrorAction SilentlyContinue }
    }

    if (-not $responseText -or $responseText.Length -eq 0) {
        throw "Empty response from Graph API: $Method $Endpoint"
    }

    # Use -AsHashtable to ensure nested objects have accessible properties
    $result = $responseText | ConvertFrom-Json -AsHashtable

    if ($result.ContainsKey('error') -and $result.error) {
        throw "Graph API error: $($result.error.message) ($($result.error.code))"
    }

    return $result
}

<#
.SYNOPSIS
    Get the current user's ID from the access token
#>
function Get-CurrentUserId {
    param([string]$AccessToken)

    $me = Invoke-GraphApi -AccessToken $AccessToken -Endpoint '/me?$select=id'
    return $me.id
}

<#
.SYNOPSIS
    Get eligible roles for current user (Entra ID + Groups)
#>
function Get-PIMEligibleRolesForWeb {
    param(
        [hashtable]$UserContext,
        [switch]$IncludeEntraRoles,
        [switch]$IncludeGroups,
        [switch]$IncludeAzureResources
    )

    try {
        $sessionId = Get-CookieValue -Name 'pim_session'
        $session = if ($sessionId) { Get-AuthSession -SessionId $sessionId } else { $null }
        $accessToken = if ($session) { $session.AccessToken } else { $null }
        if (-not $accessToken) {
            return @{ roles = @(); success = $false; error = "No access token"; timestamp = (Get-Date -AsUTC).ToString('o') }
        }

        $userId = Get-CurrentUserId -AccessToken $accessToken
        $allRoles = [System.Collections.ArrayList]::new()

        # Entra ID eligible roles
        if ($IncludeEntraRoles) {
            try {
                $filter = [System.Web.HttpUtility]::UrlEncode("principalId eq '$userId'")
                $entraRoles = Invoke-GraphApi -AccessToken $accessToken -Endpoint "/roleManagement/directory/roleEligibilityScheduleInstances?`$filter=$filter&`$expand=roleDefinition"
                $entraValues = @($entraRoles.value)
                Write-Host "Entra eligible: found $($entraValues.Count) role(s)"

                foreach ($r in $entraValues) {
                    $roleName = if ($r.roleDefinition) { $r.roleDefinition.displayName } else { "Role $($r.roleDefinitionId)" }
                    $scope = $r.directoryScopeId ?? '/'
                    $scopeDisplay = 'Directory'
                    if ($scope -ne '/' -and $scope -match '/administrativeUnits/(.+)') {
                        try {
                            $au = Invoke-GraphApi -AccessToken $accessToken -Endpoint "/directory/administrativeUnits/$($Matches[1])?`$select=displayName"
                            $scopeDisplay = "AU: $($au.displayName)"
                        }
                        catch {
                            Write-Host "AU lookup failed for $($Matches[1]): $($_.Exception.Message)"
                            $scopeDisplay = "AU: $($Matches[1])"
                        }
                    }

                    $null = $allRoles.Add(@{
                        id               = $r.roleDefinitionId
                        uid              = "$($r.roleDefinitionId)|$scope"
                        name             = $roleName
                        type             = 'Entra'
                        status           = 'Eligible'
                        source           = 'EntraID'
                        resourceName     = 'Entra ID Directory'
                        scope            = $scopeDisplay
                        startDateTime    = $r.startDateTime
                        endDateTime      = $r.endDateTime
                        memberType       = ($r.memberType ?? 'Direct')
                        directoryScopeId = $scope
                        principalId      = $r.principalId
                    })
                }
            }
            catch {
                Write-Host "Error fetching Entra eligible roles: $($_.Exception.Message)"
            }
        }

        # PIM-enabled Groups eligible
        if ($IncludeGroups) {
            try {
                $filter = [System.Web.HttpUtility]::UrlEncode("principalId eq '$userId'")
                $groupRoles = Invoke-GraphApi -AccessToken $accessToken -Endpoint "/identityGovernance/privilegedAccess/group/eligibilityScheduleInstances?`$filter=$filter&`$expand=group"
                $groupValues = @($groupRoles.value)
                Write-Host "Group eligible: found $($groupValues.Count) role(s)"

                foreach ($r in $groupValues) {
                    $groupName = $(if ($r.group) { $r.group.displayName } else { "Group $($r.groupId)" })
                    $null = $allRoles.Add(@{
                        id               = $r.groupId
                        uid              = "group|$($r.groupId)"
                        name             = $groupName
                        type             = 'Group'
                        status           = 'Eligible'
                        source           = 'PIMGroup'
                        resourceName     = $groupName
                        scope            = 'Directory'
                        startDateTime    = $r.startDateTime
                        endDateTime      = $r.endDateTime
                        memberType       = ($r.accessId ?? 'member')
                        directoryScopeId = $null
                        principalId      = $r.principalId
                    })
                }
            }
            catch {
                Write-Host "Error fetching Group eligible roles: $($_.Exception.Message)"
            }
        }

        # Fetch policies for each eligible role and merge into role data
        Write-Host "Fetching policies for $($allRoles.Count) eligible roles"
        foreach ($role in $allRoles) {
            try {
                $policy = Get-PIMRolePolicyForWeb -RoleId $role.id -AccessToken $accessToken -RoleType $role.type
                if ($policy.success) {
                    $role.requiresMfa = $policy.requiresMfa
                    $role.requiresJustification = $policy.requiresJustification
                    $role.requiresTicket = $policy.requiresTicket
                    $role.requiresApproval = $policy.requiresApproval
                    $role.maxDurationHours = $policy.maxDurationHours
                }
            }
            catch {
                Write-Host "Policy fetch failed for $($role.name): $($_.Exception.Message)"
            }
        }

        Write-Host "Returning $($allRoles.Count) eligible roles"
        return @{
            roles     = @($allRoles)
            success   = $true
            timestamp = (Get-Date -AsUTC).ToString('o')
        }
    }
    catch {
        Write-Host "EligibleRoles ERROR: $($_.Exception.Message)"
        return @{
            roles     = @()
            success   = $false
            error     = $_.Exception.Message
            timestamp = (Get-Date -AsUTC).ToString('o')
        }
    }
}

<#
.SYNOPSIS
    Get active roles for current user (Entra ID + Groups)
#>
function Get-PIMActiveRolesForWeb {
    param(
        [hashtable]$UserContext,
        [switch]$IncludeEntraRoles,
        [switch]$IncludeGroups
    )

    try {
        $sessionId = Get-CookieValue -Name 'pim_session'
        $session = if ($sessionId) { Get-AuthSession -SessionId $sessionId } else { $null }
        $accessToken = if ($session) { $session.AccessToken } else { $null }
        if (-not $accessToken) {
            return @{ roles = @(); success = $false; error = 'No access token'; timestamp = (Get-Date -AsUTC).ToString('o') }
        }

        $userId = Get-CurrentUserId -AccessToken $accessToken
        $allRoles = [System.Collections.ArrayList]::new()

        # Entra ID active roles
        if ($IncludeEntraRoles) {
            try {
                $filter = [System.Web.HttpUtility]::UrlEncode("principalId eq '$userId'")
                $entraRoles = Invoke-GraphApi -AccessToken $accessToken -Endpoint "/roleManagement/directory/roleAssignmentScheduleInstances?`$filter=$filter"

                # Need role definitions for display names
                $roleDefCache = @{}
                foreach ($r in @($entraRoles.value)) {
                    $roleDefId = $r.roleDefinitionId
                    if (-not $roleDefId) { continue }

                    if (-not $roleDefCache.ContainsKey($roleDefId)) {
                        try {
                            $roleDef = Invoke-GraphApi -AccessToken $accessToken -Endpoint "/roleManagement/directory/roleDefinitions/$roleDefId`?`$select=displayName"
                            $roleDefCache[$roleDefId] = $roleDef.displayName
                        }
                        catch {
                            $roleDefCache[$roleDefId] = "Role $roleDefId"
                        }
                    }
                    $roleName = $roleDefCache[$roleDefId]

                    # Only include time-bound (activated) assignments, not permanent
                    if ($r.assignmentType -eq 'Activated') {
                        $scope = $r.directoryScopeId ?? '/'
                        $scopeDisplay = 'Directory'
                        if ($scope -ne '/' -and $scope -match '/administrativeUnits/(.+)') {
                            try {
                                $au = Invoke-GraphApi -AccessToken $accessToken -Endpoint "/directory/administrativeUnits/$($Matches[1])?`$select=displayName"
                                $scopeDisplay = "AU: $($au.displayName)"
                            }
                            catch {
                            Write-Host "AU lookup failed for $($Matches[1]): $($_.Exception.Message)"
                            $scopeDisplay = "AU: $($Matches[1])"
                        }
                        }

                        $null = $allRoles.Add(@{
                            id               = $r.roleDefinitionId
                            uid              = "$($r.roleDefinitionId)|$scope"
                            name             = $roleName
                            type             = 'Entra'
                            status           = 'Active'
                            source           = 'EntraID'
                            resourceName     = 'Entra ID Directory'
                            scope            = $scopeDisplay
                            startDateTime    = $r.startDateTime
                            endDateTime      = $r.endDateTime
                            memberType       = ($r.memberType ?? 'Direct')
                            directoryScopeId = $scope
                            principalId      = $r.principalId
                        })
                    }
                }
            }
            catch {
                Write-Host "Error fetching Entra active roles: $($_.Exception.Message)"
            }
        }

        # PIM-enabled Groups active
        if ($IncludeGroups) {
            try {
                $filter = [System.Web.HttpUtility]::UrlEncode("principalId eq '$userId'")
                $groupRoles = Invoke-GraphApi -AccessToken $accessToken -Endpoint "/identityGovernance/privilegedAccess/group/assignmentScheduleInstances?`$filter=$filter&`$expand=group"

                foreach ($r in @($groupRoles.value)) {
                    # Only include activated assignments
                    if ($r.assignmentType -eq 'Activated') {
                        $groupName = $(if ($r.group) { $r.group.displayName } else { "Group $($r.groupId)" })
                        $null = $allRoles.Add(@{
                            id               = $r.groupId
                            uid              = "group|$($r.groupId)"
                            name             = $groupName
                            type             = 'Group'
                            status           = 'Active'
                            source           = 'PIMGroup'
                            resourceName     = $groupName
                            scope            = 'Directory'
                            startDateTime    = $r.startDateTime
                            endDateTime      = $r.endDateTime
                            memberType       = ($r.accessId ?? 'member')
                            directoryScopeId = $null
                            principalId      = $r.principalId
                        })
                    }
                }
            }
            catch {
                Write-Host "Error fetching Group active roles: $($_.Exception.Message)"
            }
        }

        return @{
            roles     = @($allRoles)
            success   = $true
            timestamp = (Get-Date -AsUTC).ToString('o')
        }
    }
    catch {
        return @{
            roles     = @()
            success   = $false
            error     = $_.Exception.Message
            timestamp = (Get-Date -AsUTC).ToString('o')
        }
    }
}

<#
.SYNOPSIS
    Activate a PIM role
#>
function Invoke-PIMRoleActivationForWeb {
    param(
        [string]$RoleId,
        [hashtable]$UserContext,
        [ValidateSet('User', 'Group', 'AzureResource')]
        [string]$RoleType = 'User',
        [string]$Justification = $null,
        [string]$TicketNumber = $null,
        [timespan]$Duration = [timespan]::FromHours(1)
    )

    try {
        $sid = Get-CookieValue -Name 'pim_session'
        $sess = if ($sid) { Get-AuthSession -SessionId $sid } else { $null }
        $accessToken = if ($sess) { $sess.AccessToken } else { $null }
        if (-not $accessToken) {
            return @{ roleId = $RoleId; status = 'failed'; success = $false; error = 'No access token' }
        }

        $userId = Get-CurrentUserId -AccessToken $accessToken

        # Convert duration to ISO 8601 format
        $isoDuration = "PT$([int]$Duration.TotalHours)H"
        if ($Duration.TotalHours -lt 1) {
            $isoDuration = "PT$([int]$Duration.TotalMinutes)M"
        }

        $body = @{
            action        = 'selfActivate'
            principalId   = $userId
            justification = ($Justification ?? 'Activated via PIM Web')
            scheduleInfo  = @{
                startDateTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'")
                expiration    = @{
                    type     = 'AfterDuration'
                    duration = $isoDuration
                }
            }
        }

        if ($TicketNumber) {
            $body.ticketInfo = @{
                ticketNumber = $TicketNumber
                ticketSystem = 'General'
            }
        }

        $endpoint = $null
        switch ($RoleType) {
            'User' {
                $body.roleDefinitionId = $RoleId
                $body.directoryScopeId = '/'
                $endpoint = '/roleManagement/directory/roleAssignmentScheduleRequests'
            }
            'Group' {
                $body.groupId  = $RoleId
                $body.accessId = 'member'
                $endpoint = '/identityGovernance/privilegedAccess/group/assignmentScheduleRequests'
            }
            default {
                return @{ roleId = $RoleId; status = 'failed'; success = $false; error = "Unsupported role type: $RoleType" }
            }
        }

        $bodyJson = $body | ConvertTo-Json -Depth 5 -Compress
        $response = Invoke-GraphApi -AccessToken $accessToken -Method 'POST' -Endpoint $endpoint -Body $bodyJson

        return @{
            roleId      = $RoleId
            status      = 'activated'
            requestId   = $response.id
            activatedAt = (Get-Date -AsUTC).ToString('o')
            expiresAt   = (Get-Date -AsUTC).Add($Duration).ToString('o')
            success     = $true
            timestamp   = (Get-Date -AsUTC).ToString('o')
        }
    }
    catch {
        return @{
            roleId    = $RoleId
            status    = 'failed'
            success   = $false
            error     = $_.Exception.Message
            timestamp = (Get-Date -AsUTC).ToString('o')
        }
    }
}

<#
.SYNOPSIS
    Deactivate a PIM role
#>
function Invoke-PIMRoleDeactivationForWeb {
    param(
        [string]$RoleId,
        [hashtable]$UserContext,
        [ValidateSet('User', 'Group', 'AzureResource')]
        [string]$RoleType = 'User'
    )

    try {
        $sid = Get-CookieValue -Name 'pim_session'
        $sess = if ($sid) { Get-AuthSession -SessionId $sid } else { $null }
        $accessToken = if ($sess) { $sess.AccessToken } else { $null }
        if (-not $accessToken) {
            return @{ roleId = $RoleId; status = 'failed'; success = $false; error = 'No access token' }
        }

        $userId = Get-CurrentUserId -AccessToken $accessToken

        $body = @{
            action        = 'selfDeactivate'
            principalId   = $userId
            justification = 'Deactivated via PIM Web'
        }

        $endpoint = $null
        switch ($RoleType) {
            'User' {
                $body.roleDefinitionId = $RoleId
                $body.directoryScopeId = '/'
                $endpoint = '/roleManagement/directory/roleAssignmentScheduleRequests'
            }
            'Group' {
                $body.groupId  = $RoleId
                $body.accessId = 'member'
                $endpoint = '/identityGovernance/privilegedAccess/group/assignmentScheduleRequests'
            }
            default {
                return @{ roleId = $RoleId; status = 'failed'; success = $false; error = "Unsupported role type: $RoleType" }
            }
        }

        $bodyJson = $body | ConvertTo-Json -Depth 5 -Compress
        $response = Invoke-GraphApi -AccessToken $accessToken -Method 'POST' -Endpoint $endpoint -Body $bodyJson

        return @{
            roleId        = $RoleId
            status        = 'deactivated'
            requestId     = $response.id
            deactivatedAt = (Get-Date -AsUTC).ToString('o')
            success       = $true
            timestamp     = (Get-Date -AsUTC).ToString('o')
        }
    }
    catch {
        return @{
            roleId    = $RoleId
            status    = 'failed'
            success   = $false
            error     = $_.Exception.Message
            timestamp = (Get-Date -AsUTC).ToString('o')
        }
    }
}

<#
.SYNOPSIS
    Get policy requirements for a role
#>
function Get-PIMRolePolicyForWeb {
    param(
        [string]$RoleId,
        [string]$AccessToken = $null,
        [string]$RoleType = 'Entra'
    )

    try {
        if (-not $AccessToken) {
            $sid = Get-CookieValue -Name 'pim_session'
            $sess = if ($sid) { Get-AuthSession -SessionId $sid } else { $null }
            $AccessToken = if ($sess) { $sess.AccessToken } else { $null }
        }
        if (-not $AccessToken) {
            return @{ roleId = $RoleId; success = $false; error = 'No access token' }
        }

        $policyInfo = @{
            roleId                = $RoleId
            requiresJustification = $false
            requiresMfa           = $false
            requiresTicket        = $false
            requiresApproval      = $false
            maxDurationHours      = 8
            success               = $true
            timestamp             = (Get-Date -AsUTC).ToString('o')
        }

        # Helper to parse policy rules into policyInfo
        $parseRules = {
            param($rules)
            foreach ($rule in @($rules)) {
                $ruleType = $rule.'@odata.type'
                $ruleId = $rule.id

                # Expiration rule
                if (($ruleType -eq '#microsoft.graph.unifiedRoleManagementPolicyExpirationRule') -or
                    ($ruleId -and $ruleId -like '*Expiration_EndUser_Assignment')) {
                    if ($rule.maximumDuration) {
                        try {
                            $dur = [System.Xml.XmlConvert]::ToTimeSpan($rule.maximumDuration)
                            $policyInfo.maxDurationHours = [int]$dur.TotalHours
                        } catch { }
                    }
                }
                # Enablement rule
                elseif (($ruleType -eq '#microsoft.graph.unifiedRoleManagementPolicyEnablementRule') -or
                        ($ruleId -and $ruleId -like '*Enablement_EndUser_Assignment')) {
                    if ($rule.enabledRules) {
                        $enabled = @($rule.enabledRules)
                        $policyInfo.requiresJustification = 'Justification' -in $enabled
                        $policyInfo.requiresTicket = 'Ticketing' -in $enabled
                        $policyInfo.requiresMfa = 'MultiFactorAuthentication' -in $enabled
                    }
                }
                # Approval rule
                elseif (($ruleType -eq '#microsoft.graph.unifiedRoleManagementPolicyApprovalRule') -or
                        ($ruleId -and $ruleId -like '*Approval_EndUser_Assignment')) {
                    if ($rule.setting -and $rule.setting.isApprovalRequired) {
                        $policyInfo.requiresApproval = $true
                    }
                }
            }
        }

        if ($RoleType -eq 'Entra') {
            try {
                $filter = [System.Web.HttpUtility]::UrlEncode("scopeId eq '/' and scopeType eq 'DirectoryRole' and roleDefinitionId eq '$RoleId'")
                $assignments = Invoke-GraphApi -AccessToken $AccessToken -Endpoint "/policies/roleManagementPolicyAssignments?`$filter=$filter"

                if ($assignments.value -and @($assignments.value).Count -gt 0) {
                    $policyId = $assignments.value[0].policyId
                    $policy = Invoke-GraphApi -AccessToken $AccessToken -Endpoint "/policies/roleManagementPolicies/$policyId`?`$expand=rules"
                    & $parseRules $policy.rules
                }
            }
            catch {
                Write-Host "Entra policy lookup failed for $RoleId`: $($_.Exception.Message)"
            }
        }
        elseif ($RoleType -eq 'Group') {
            try {
                $filter = [System.Web.HttpUtility]::UrlEncode("scopeId eq '$RoleId' and scopeType eq 'Group'")
                $assignments = Invoke-GraphApi -AccessToken $AccessToken -Endpoint "/policies/roleManagementPolicyAssignments?`$filter=$filter"

                if ($assignments.value -and @($assignments.value).Count -gt 0) {
                    $assignment = $assignments.value | Where-Object { $_.roleDefinitionId -eq 'member' } | Select-Object -First 1
                    if (-not $assignment) { $assignment = $assignments.value[0] }

                    $policy = Invoke-GraphApi -AccessToken $AccessToken -Endpoint "/policies/roleManagementPolicies/$($assignment.policyId)`?`$expand=rules"
                    & $parseRules $policy.rules
                }
            }
            catch {
                Write-Host "Group policy lookup failed for $RoleId`: $($_.Exception.Message)"
            }
        }

        return $policyInfo
    }
    catch {
        return @{
            roleId    = $RoleId
            success   = $false
            error     = $_.Exception.Message
            timestamp = (Get-Date -AsUTC).ToString('o')
        }
    }
}
