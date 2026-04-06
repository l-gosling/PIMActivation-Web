#requires -Version 7.0

<#
.SYNOPSIS
    PIM API Layer - Microsoft Graph REST API calls for PIM role management
.DESCRIPTION
    Provides functions to query, activate, and deactivate PIM roles
    using the Microsoft Graph API. Uses curl for HTTP calls (IPv6 workaround on Alpine).
#>

function Get-GraphBaseUrl { return 'https://graph.microsoft.com/v1.0' }
function Get-AzureBaseUrl { return 'https://management.azure.com' }

<#
.SYNOPSIS
    Make an Azure Management REST API request
#>
function Invoke-AzureApi {
    param(
        [string]$AccessToken,
        [string]$Method = 'GET',
        [string]$Endpoint,
        [string]$Body = $null,
        [string]$ApiVersion = '2020-10-01'
    )

    $separator = if ($Endpoint -match '\?') { '&' } else { '?' }
    $url = "$(Get-AzureBaseUrl)$Endpoint${separator}api-version=$ApiVersion"
    $curlArgs = @(
        '-s', '-4',
        '-X', $Method,
        '-H', "Authorization: Bearer $AccessToken",
        '-H', 'Content-Type: application/json'
    )

    if ($Body) {
        $bodyFile = "/tmp/az_body_$([guid]::NewGuid().ToString('N').Substring(0,8)).json"
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
        throw "Empty response from Azure API: $Method $Endpoint"
    }

    $result = $responseText | ConvertFrom-Json -AsHashtable

    if ($result.ContainsKey('error') -and $result.error) {
        throw "Azure API error: $($result.error.message) ($($result.error.code))"
    }

    return $result
}

<#
.SYNOPSIS
    Get Azure session token from the current request
#>
function Get-AzureSessionToken {
    $sessionId = Get-CookieValue -Name 'pim_session'
    $session = if ($sessionId) { Get-AuthSession -SessionId $sessionId } else { $null }
    if ($session) { return $session.AzureAccessToken }
    return $null
}

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
        $auCache = @{}  # Cache AU id -> display name

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
                        $auId = $Matches[1]
                        if ($auCache.ContainsKey($auId)) {
                            $scopeDisplay = $auCache[$auId]
                        }
                        else {
                            try {
                                $au = Invoke-GraphApi -AccessToken $accessToken -Endpoint "/directory/administrativeUnits/$auId`?`$select=displayName"
                                $scopeDisplay = "AU: $($au.displayName)"
                            }
                            catch {
                                Write-Host "AU lookup failed for $auId`: $($_.Exception.Message)"
                                $scopeDisplay = "AU: $auId"
                            }
                            $auCache[$auId] = $scopeDisplay
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

        # Azure resource eligible roles
        if ($IncludeAzureResources) {
            $azToken = Get-AzureSessionToken
            if ($azToken) {
                try {
                    # Get subscriptions
                    $subs = Invoke-AzureApi -AccessToken $azToken -Endpoint '/subscriptions' -ApiVersion '2022-01-01'
                    foreach ($sub in @($subs.value)) {
                        try {
                            $subScope = "/subscriptions/$($sub.subscriptionId)"
                            $eligible = Invoke-AzureApi -AccessToken $azToken -Endpoint "$subScope/providers/Microsoft.Authorization/roleEligibilityScheduleInstances" -ApiVersion '2020-10-01'
                            foreach ($r in @($eligible.value)) {
                                # Only include roles for the current user
                                if ($r.properties.principalId -ne $userId) { continue }
                                $roleName = $r.properties.expandedProperties.roleDefinition.displayName ?? 'Azure Role'
                                $scopeDisplay = $sub.displayName
                                if ($r.properties.scope -ne $subScope) {
                                    $scopeDisplay = "$($sub.displayName) / $($r.properties.scope -replace "^$subScope/", '')"
                                }
                                $roleDefId = $r.properties.roleDefinitionId -replace '.*/roleDefinitions/', ''

                                $null = $allRoles.Add(@{
                                    id               = $roleDefId
                                    uid              = "azure|$roleDefId|$($r.properties.scope)"
                                    name             = $roleName
                                    type             = 'AzureResource'
                                    status           = 'Eligible'
                                    source           = 'Azure'
                                    resourceName     = $sub.displayName
                                    scope            = $scopeDisplay
                                    startDateTime    = $r.properties.startDateTime
                                    endDateTime      = $r.properties.endDateTime
                                    memberType       = 'Direct'
                                    directoryScopeId = $r.properties.scope
                                    principalId      = $r.properties.principalId
                                    roleDefinitionId = $r.properties.roleDefinitionId
                                })
                            }
                        }
                        catch {
                            Write-Host "Azure eligible roles failed for sub $($sub.displayName): $($_.Exception.Message)"
                        }
                    }
                    Write-Host "Azure eligible: found roles across $(@($subs.value).Count) subscription(s)"
                }
                catch {
                    Write-Host "Error fetching Azure subscriptions: $($_.Exception.Message)"
                }
            }
        }

        # Batch fetch all Entra policies in one call, then match to roles
        Write-Host "Fetching policies for $($allRoles.Count) eligible roles"
        $policyCache = @{}
        try {
            # Get all DirectoryRole policy assignments at once
            $entraRoleIds = @($allRoles | Where-Object { $_.type -eq 'Entra' } | ForEach-Object { $_.id } | Select-Object -Unique)
            if ($entraRoleIds.Count -gt 0) {
                $filter = [System.Web.HttpUtility]::UrlEncode("scopeId eq '/' and scopeType eq 'DirectoryRole'")
                $allAssignments = Invoke-GraphApi -AccessToken $accessToken -Endpoint "/policies/roleManagementPolicyAssignments?`$filter=$filter"
                foreach ($a in @($allAssignments.value)) {
                    if ($a.roleDefinitionId -and $a.roleDefinitionId -in $entraRoleIds -and -not $policyCache.ContainsKey($a.roleDefinitionId)) {
                        try {
                            $policy = Invoke-GraphApi -AccessToken $accessToken -Endpoint "/policies/roleManagementPolicies/$($a.policyId)?`$expand=rules"
                            $info = @{ maxDurationHours = 8; requiresMfa = $false; requiresJustification = $false; requiresTicket = $false; requiresApproval = $false }
                            foreach ($rule in @($policy.rules)) {
                                $rt = $rule.'@odata.type'
                                if ($rt -eq '#microsoft.graph.unifiedRoleManagementPolicyExpirationRule' -and $rule.maximumDuration) {
                                    try { $info.maxDurationHours = [int][System.Xml.XmlConvert]::ToTimeSpan($rule.maximumDuration).TotalHours } catch {}
                                }
                                elseif ($rt -eq '#microsoft.graph.unifiedRoleManagementPolicyEnablementRule' -and $rule.enabledRules) {
                                    $enabled = @($rule.enabledRules)
                                    $info.requiresJustification = 'Justification' -in $enabled
                                    $info.requiresTicket = 'Ticketing' -in $enabled
                                    $info.requiresMfa = 'MultiFactorAuthentication' -in $enabled
                                }
                                elseif ($rt -eq '#microsoft.graph.unifiedRoleManagementPolicyApprovalRule' -and $rule.setting -and $rule.setting.isApprovalRequired) {
                                    $info.requiresApproval = $true
                                }
                            }
                            $policyCache[$a.roleDefinitionId] = $info
                        }
                        catch { Write-Host "Policy fetch failed for $($a.roleDefinitionId): $($_.Exception.Message)" }
                    }
                }
            }

            # Fetch group policies individually (usually few)
            $groupRoleIds = @($allRoles | Where-Object { $_.type -eq 'Group' } | ForEach-Object { $_.id } | Select-Object -Unique)
            foreach ($gid in $groupRoleIds) {
                try {
                    $p = Get-PIMRolePolicyForWeb -RoleId $gid -AccessToken $accessToken -RoleType 'Group'
                    if ($p.success) { $policyCache["group_$gid"] = $p }
                }
                catch { }
            }
        }
        catch {
            Write-Host "Batch policy fetch error: $($_.Exception.Message)"
        }

        # Apply policies to roles
        foreach ($role in $allRoles) {
            $key = if ($role.type -eq 'Group') { "group_$($role.id)" } else { $role.id }
            if ($policyCache.ContainsKey($key)) {
                $p = $policyCache[$key]
                $role.requiresMfa = $p.requiresMfa
                $role.requiresJustification = $p.requiresJustification
                $role.requiresTicket = $p.requiresTicket
                $role.requiresApproval = $p.requiresApproval
                $role.maxDurationHours = $p.maxDurationHours
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
        [switch]$IncludeGroups,
        [switch]$IncludeAzureResources
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
        $auCache = @{}

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

                    $scope = $r.directoryScopeId ?? '/'
                    $scopeDisplay = 'Directory'
                    if ($scope -ne '/' -and $scope -match '/administrativeUnits/(.+)') {
                        $auId = $Matches[1]
                        if ($auCache.ContainsKey($auId)) {
                            $scopeDisplay = $auCache[$auId]
                        }
                        else {
                            try {
                                $au = Invoke-GraphApi -AccessToken $accessToken -Endpoint "/directory/administrativeUnits/$auId`?`$select=displayName"
                                $scopeDisplay = "AU: $($au.displayName)"
                            }
                            catch {
                                Write-Host "AU lookup failed for $auId`: $($_.Exception.Message)"
                                $scopeDisplay = "AU: $auId"
                            }
                            $auCache[$auId] = $scopeDisplay
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
            catch {
                Write-Host "Error fetching Group active roles: $($_.Exception.Message)"
            }
        }

        # Azure resource active roles
        if ($IncludeAzureResources) {
            $azToken = Get-AzureSessionToken
            if ($azToken) {
                try {
                    $subs = Invoke-AzureApi -AccessToken $azToken -Endpoint '/subscriptions' -ApiVersion '2022-01-01'
                    foreach ($sub in @($subs.value)) {
                        try {
                            $subScope = "/subscriptions/$($sub.subscriptionId)"
                            $active = Invoke-AzureApi -AccessToken $azToken -Endpoint "$subScope/providers/Microsoft.Authorization/roleAssignmentScheduleInstances" -ApiVersion '2020-10-01'
                            foreach ($r in @($active.value)) {
                                if ($r.properties.principalId -ne $userId) { continue }
                                $roleName = $r.properties.expandedProperties.roleDefinition.displayName ?? 'Azure Role'
                                $scopeDisplay = $sub.displayName
                                if ($r.properties.scope -ne $subScope) {
                                    $scopeDisplay = "$($sub.displayName) / $($r.properties.scope -replace "^$subScope/", '')"
                                }
                                $roleDefId = $r.properties.roleDefinitionId -replace '.*/roleDefinitions/', ''

                                $null = $allRoles.Add(@{
                                    id               = $roleDefId
                                    uid              = "azure|$roleDefId|$($r.properties.scope)"
                                    name             = $roleName
                                    type             = 'AzureResource'
                                    status           = 'Active'
                                    source           = 'Azure'
                                    resourceName     = $sub.displayName
                                    scope            = $scopeDisplay
                                    startDateTime    = $r.properties.startDateTime
                                    endDateTime      = $r.properties.endDateTime
                                    memberType       = ($r.properties.assignmentType ?? 'Direct')
                                    directoryScopeId = $r.properties.scope
                                    principalId      = $r.properties.principalId
                                    roleDefinitionId = $r.properties.roleDefinitionId
                                })
                            }
                        }
                        catch {
                            Write-Host "Azure active roles failed for sub $($sub.displayName): $($_.Exception.Message)"
                        }
                    }
                }
                catch {
                    Write-Host "Error fetching Azure active subscriptions: $($_.Exception.Message)"
                }
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
        [string]$DirectoryScopeId = '/',
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
                $body.directoryScopeId = if ($DirectoryScopeId) { $DirectoryScopeId } else { '/' }
                $endpoint = '/roleManagement/directory/roleAssignmentScheduleRequests'
            }
            'Group' {
                $body.groupId  = $RoleId
                $body.accessId = 'member'
                $endpoint = '/identityGovernance/privilegedAccess/group/assignmentScheduleRequests'
            }
            'AzureResource' {
                # Azure uses a different API entirely
                $azToken = Get-AzureSessionToken
                if (-not $azToken) {
                    return @{ roleId = $RoleId; status = 'failed'; success = $false; error = 'No Azure access token' }
                }
                $reqName = [guid]::NewGuid().ToString()
                $azBody = @{
                    properties = @{
                        principalId      = $userId
                        roleDefinitionId = $DirectoryScopeId + "/providers/Microsoft.Authorization/roleDefinitions/$RoleId"
                        requestType      = 'SelfActivate'
                        justification    = ($Justification ?? 'Activated via PIM Web')
                        scheduleInfo     = @{
                            startDateTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'")
                            expiration    = @{
                                type     = 'AfterDuration'
                                duration = $isoDuration
                            }
                        }
                    }
                }
                if ($TicketNumber) {
                    $azBody.properties.ticketInfo = @{ ticketNumber = $TicketNumber; ticketSystem = 'General' }
                }
                $azBodyJson = $azBody | ConvertTo-Json -Depth 5 -Compress
                $response = Invoke-AzureApi -AccessToken $azToken -Method 'PUT' -Endpoint "$DirectoryScopeId/providers/Microsoft.Authorization/roleAssignmentScheduleRequests/$reqName" -Body $azBodyJson
                return @{
                    roleId = $RoleId; status = 'activated'; success = $true
                    activatedAt = (Get-Date -AsUTC).ToString('o')
                    expiresAt = (Get-Date -AsUTC).Add($Duration).ToString('o')
                    timestamp = (Get-Date -AsUTC).ToString('o')
                }
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
        [string]$RoleType = 'User',
        [string]$DirectoryScopeId = '/'
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
                $body.directoryScopeId = if ($DirectoryScopeId) { $DirectoryScopeId } else { '/' }
                $endpoint = '/roleManagement/directory/roleAssignmentScheduleRequests'
            }
            'Group' {
                $body.groupId  = $RoleId
                $body.accessId = 'member'
                $endpoint = '/identityGovernance/privilegedAccess/group/assignmentScheduleRequests'
            }
            'AzureResource' {
                $azToken = Get-AzureSessionToken
                if (-not $azToken) {
                    return @{ roleId = $RoleId; status = 'failed'; success = $false; error = 'No Azure access token' }
                }
                $reqName = [guid]::NewGuid().ToString()
                $fullRoleDefId = $DirectoryScopeId + "/providers/Microsoft.Authorization/roleDefinitions/$RoleId"
                $azBody = @{
                    properties = @{
                        principalId      = $userId
                        roleDefinitionId = $fullRoleDefId
                        requestType      = 'SelfDeactivate'
                        justification    = 'Deactivated via PIM Web'
                    }
                }
                $azBodyJson = $azBody | ConvertTo-Json -Depth 5 -Compress
                $response = Invoke-AzureApi -AccessToken $azToken -Method 'PUT' -Endpoint "$DirectoryScopeId/providers/Microsoft.Authorization/roleAssignmentScheduleRequests/$reqName" -Body $azBodyJson
                return @{
                    roleId = $RoleId; status = 'deactivated'; success = $true
                    deactivatedAt = (Get-Date -AsUTC).ToString('o')
                    timestamp = (Get-Date -AsUTC).ToString('o')
                }
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
