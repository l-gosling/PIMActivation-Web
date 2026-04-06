#requires -Version 7.0

<#
.SYNOPSIS
    PIM API Layer - Microsoft Graph REST API calls for PIM role management
.DESCRIPTION
    Provides functions to query, activate, and deactivate PIM roles
    using the Microsoft Graph API and Azure Management API.
    Uses Invoke-WebRequest for HTTP calls. IPv6 DNS resolution issues on
    Alpine Linux are mitigated by setting DOTNET_SYSTEM_NET_DISABLEIPV6=1
    in the container environment.
#>

function Get-GraphBaseUrl {
    [CmdletBinding()]
    param()
    return 'https://graph.microsoft.com/v1.0'
}

function Get-AzureBaseUrl {
    [CmdletBinding()]
    param()
    return 'https://management.azure.com'
}

<#
.SYNOPSIS
    Refresh the Graph access token using the stored refresh token
.DESCRIPTION
    Retrieves the current session's refresh token, exchanges it for a new
    access token via the Entra ID token endpoint, and updates the session.
    Returns the new access token on success, or $null on failure.
#>
function Update-SessionTokens {
    [CmdletBinding()]
    param()

    $ctx = Get-CurrentSessionContext
    if (-not $ctx.SessionId) { return $null }
    $session = $ctx.Session
    if (-not $session -or -not $session.RefreshToken) { return $null }

    $oauth = Get-OAuthConfig
    $tokenBody = @{
        client_id     = $oauth.ClientId
        client_secret = $oauth.ClientSecret
        refresh_token = $session.RefreshToken
        grant_type    = 'refresh_token'
        scope         = $oauth.Scopes
    }
    $tokenResult = Invoke-WebRequest -Uri $oauth.TokenUrl -Method Post -Body $tokenBody -ContentType 'application/x-www-form-urlencoded' -SkipHttpErrorCheck
    $tokenResponse = $tokenResult.Content | ConvertFrom-Json
    if ($tokenResponse.error) { return $null }

    # Update session with new tokens
    $session.AccessToken = $tokenResponse.access_token
    if ($tokenResponse.refresh_token) { $session.RefreshToken = $tokenResponse.refresh_token }
    $session.ExpiresAt = (Get-Date).AddSeconds([int]($env:SESSION_TIMEOUT ?? '3600'))
    Set-AuthSession -SessionId $ctx.SessionId -Data $session
    Write-Log -Message "Graph token refreshed" -Level 'Debug'

    return $tokenResponse.access_token
}

<#
.SYNOPSIS
    Make an Azure Management REST API request
.PARAMETER AccessToken
    Bearer token for the Azure Management API
.PARAMETER Method
    HTTP method (GET, POST, PUT, PATCH, DELETE). Default: GET
.PARAMETER Endpoint
    API path appended to https://management.azure.com
.PARAMETER Body
    Optional JSON request body
.PARAMETER ApiVersion
    Azure API version query parameter. Default: 2020-10-01
#>
function Invoke-AzureApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$AccessToken,

        [string]$Method = 'GET',

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Endpoint,

        [string]$Body = $null,

        [string]$ApiVersion = '2020-10-01'
    )

    $separator = if ($Endpoint -match '\?') { '&' } else { '?' }
    $url = "$(Get-AzureBaseUrl)$Endpoint${separator}api-version=$ApiVersion"

    $params = @{
        Uri                = $url
        Method             = $Method
        Headers            = @{ Authorization = "Bearer $AccessToken" }
        ContentType        = 'application/json'
        SkipHttpErrorCheck = $true
    }
    if ($Body) { $params.Body = $Body }

    $response = Invoke-WebRequest @params

    if (-not $response.Content -or $response.Content.Length -eq 0) {
        throw "Empty response from Azure API: $Method $Endpoint"
    }

    $result = $response.Content | ConvertFrom-Json -AsHashtable

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
    [CmdletBinding()]
    param()

    $ctx = Get-CurrentSessionContext
    if ($ctx.Session) { return $ctx.AzureAccessToken }
    return $null
}

<#
.SYNOPSIS
    Make a Graph API request with automatic token refresh on 401
.DESCRIPTION
    If the first call returns InvalidAuthenticationToken, the session's refresh token
    is exchanged for a new access token and the request is retried once.
.PARAMETER AccessToken
    Bearer token for Microsoft Graph
.PARAMETER Method
    HTTP method. Default: GET
.PARAMETER Endpoint
    API path appended to https://graph.microsoft.com/v1.0
.PARAMETER Body
    Optional JSON request body
#>
function Invoke-GraphApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$AccessToken,

        [string]$Method = 'GET',

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Endpoint,

        [string]$Body = $null
    )

    $url = "$(Get-GraphBaseUrl)$Endpoint"
    $params = @{
        Uri                = $url
        Method             = $Method
        Headers            = @{ Authorization = "Bearer $AccessToken" }
        ContentType        = 'application/json'
        SkipHttpErrorCheck = $true
    }
    if ($Body) { $params.Body = $Body }

    $response = Invoke-WebRequest @params

    if (-not $response.Content -or $response.Content.Length -eq 0) {
        throw "Empty response from Graph API: $Method $Endpoint"
    }

    $result = $response.Content | ConvertFrom-Json -AsHashtable

    if ($result.ContainsKey('error') -and $result.error) {
        $errorCode = $result.error.code
        $errorMsg = $result.error.message

        # Auto-refresh token on 401/InvalidAuthenticationToken and retry once
        if ($errorCode -eq 'InvalidAuthenticationToken') {
            $newToken = Update-SessionTokens
            if ($newToken) {
                $params.Headers = @{ Authorization = "Bearer $newToken" }
                $retryResponse = Invoke-WebRequest @params
                $retryResult = $retryResponse.Content | ConvertFrom-Json -AsHashtable
                if ($retryResult.ContainsKey('error') -and $retryResult.error) {
                    throw "Graph API error: $($retryResult.error.message) ($($retryResult.error.code))"
                }
                return $retryResult
            }
        }

        throw "Graph API error: $errorMsg ($errorCode)"
    }

    return $result
}

<#
.SYNOPSIS
    Get the current user's ID from the access token
.PARAMETER AccessToken
    Bearer token to call /me endpoint
#>
function Get-CurrentUserId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$AccessToken
    )

    $me = Invoke-GraphApi -AccessToken $AccessToken -Endpoint '/me?$select=id'
    return $me.id
}

# ────────────────────────────────────────────────────────────────────
# Helper functions for role data construction (used by both eligible
# and active role queries to avoid duplicating hashtable layouts)
# ────────────────────────────────────────────────────────────────────

<#
.SYNOPSIS
    Resolve a directory scope ID to a human-readable display string
.DESCRIPTION
    Converts a directoryScopeId like '/' to 'Directory' or
    '/administrativeUnits/<guid>' to 'AU: <displayName>'.
    Results are cached in the provided AuCache hashtable so each AU
    is looked up at most once per request.
.PARAMETER Scope
    The raw directoryScopeId from the Graph API response
.PARAMETER AccessToken
    Bearer token for looking up AU display names
.PARAMETER AuCache
    Hashtable mapping AU GUID -> display string. Mutated in place to cache lookups.
#>
function Resolve-DirectoryScopeDisplay {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Scope,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$AccessToken,

        [Parameter(Mandatory)]
        [hashtable]$AuCache
    )

    if ($Scope -eq '/' -or $Scope -notmatch '/administrativeUnits/(.+)') {
        return 'Directory'
    }

    $auId = $Matches[1]
    if ($AuCache.ContainsKey($auId)) {
        return $AuCache[$auId]
    }

    try {
        $au = Invoke-GraphApi -AccessToken $AccessToken -Endpoint "/directory/administrativeUnits/$auId`?`$select=displayName"
        $display = "AU: $($au.displayName)"
    }
    catch {
        Write-Log -Message "AU lookup failed for ${auId}: $($_.Exception.Message)" -Level 'Warning'
        $display = "AU: $auId"
    }

    $AuCache[$auId] = $display
    return $display
}

<#
.SYNOPSIS
    Build a standardized Entra role hashtable from a Graph API role assignment/eligibility object
.PARAMETER RoleData
    The raw role object from the Graph API response (hashtable via -AsHashtable)
.PARAMETER Status
    'Eligible' or 'Active'
.PARAMETER ScopeDisplay
    Pre-resolved display string for the directory scope
.PARAMETER Scope
    The raw directoryScopeId value
#>
function New-EntraRoleEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$RoleData,
        [Parameter(Mandatory)][ValidateSet('Eligible', 'Active')][string]$Status,
        [Parameter(Mandatory)][string]$ScopeDisplay,
        [Parameter(Mandatory)][string]$Scope
    )

    $roleName = if ($RoleData.roleDefinition) { $RoleData.roleDefinition.displayName } else { "Role $($RoleData.roleDefinitionId)" }
    return @{
        id               = $RoleData.roleDefinitionId
        uid              = "$($RoleData.roleDefinitionId)|$Scope"
        name             = $roleName
        type             = 'Entra'
        status           = $Status
        source           = 'EntraID'
        resourceName     = 'Entra ID Directory'
        scope            = $ScopeDisplay
        startDateTime    = $RoleData.startDateTime
        endDateTime      = $RoleData.endDateTime
        memberType       = ($RoleData.memberType ?? 'Direct')
        directoryScopeId = $Scope
        principalId      = $RoleData.principalId
    }
}

<#
.SYNOPSIS
    Build a standardized Group role hashtable from a Graph API group assignment/eligibility object
.PARAMETER RoleData
    The raw group role object from the Graph API response
.PARAMETER Status
    'Eligible' or 'Active'
#>
function New-GroupRoleEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$RoleData,
        [Parameter(Mandatory)][ValidateSet('Eligible', 'Active')][string]$Status
    )

    $groupName = if ($RoleData.group) { $RoleData.group.displayName } else { "Group $($RoleData.groupId)" }
    $accessId = $RoleData.accessId ?? 'member'
    # Title-case the accessId for display (e.g., 'member' -> 'Member')
    $accessLabel = ([string]$accessId).Substring(0, 1).ToUpper() + ([string]$accessId).Substring(1)

    return @{
        id               = $RoleData.groupId
        uid              = "group|$($RoleData.groupId)|$accessId"
        name             = $groupName
        type             = 'Group'
        status           = $Status
        source           = 'PIMGroup'
        resourceName     = $groupName
        scope            = "Directory ($accessLabel)"
        startDateTime    = $RoleData.startDateTime
        endDateTime      = $RoleData.endDateTime
        memberType       = 'Direct'
        directoryScopeId = $null
        principalId      = $RoleData.principalId
    }
}

<#
.SYNOPSIS
    Build a standardized Azure Resource role hashtable from an Azure Management API response
.PARAMETER RoleData
    The raw role object from the Azure Management API response
.PARAMETER Status
    'Eligible' or 'Active'
.PARAMETER SubscriptionName
    Display name of the Azure subscription
.PARAMETER SubscriptionScope
    The /subscriptions/<id> scope string, used to compute relative scope display
#>
function New-AzureRoleEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$RoleData,
        [Parameter(Mandatory)][ValidateSet('Eligible', 'Active')][string]$Status,
        [Parameter(Mandatory)][string]$SubscriptionName,
        [Parameter(Mandatory)][string]$SubscriptionScope
    )

    $roleName = $RoleData.properties.expandedProperties.roleDefinition.displayName ?? 'Azure Role'
    $scopeDisplay = $SubscriptionName
    if ($RoleData.properties.scope -ne $SubscriptionScope) {
        $scopeDisplay = "$SubscriptionName / $($RoleData.properties.scope -replace "^$SubscriptionScope/", '')"
    }
    $roleDefId = $RoleData.properties.roleDefinitionId -replace '.*/roleDefinitions/', ''

    return @{
        id               = $roleDefId
        uid              = "azure|$roleDefId|$($RoleData.properties.scope)"
        name             = $roleName
        type             = 'AzureResource'
        status           = $Status
        source           = 'Azure'
        resourceName     = $SubscriptionName
        scope            = $scopeDisplay
        startDateTime    = $RoleData.properties.startDateTime
        endDateTime      = $RoleData.properties.endDateTime
        memberType       = if ($Status -eq 'Active') { ($RoleData.properties.assignmentType ?? 'Direct') } else { 'Direct' }
        directoryScopeId = $RoleData.properties.scope
        principalId      = $RoleData.properties.principalId
        roleDefinitionId = $RoleData.properties.roleDefinitionId
    }
}

# ────────────────────────────────────────────────────────────────────
# Role query functions
# ────────────────────────────────────────────────────────────────────

<#
.SYNOPSIS
    Get eligible roles for current user (Entra ID, Groups, and optionally Azure Resources)
.DESCRIPTION
    Queries eligible role assignments from up to three sources, resolves display names
    and scopes, batch-fetches Entra policy requirements, and returns a unified list.
.PARAMETER UserContext
    Pode auth context (unused but passed by the route handler)
.PARAMETER IncludeEntraRoles
    Include Entra ID directory role eligibilities
.PARAMETER IncludeGroups
    Include PIM-enabled group eligibilities
.PARAMETER IncludeAzureResources
    Include Azure resource role eligibilities (requires Azure Management token)
#>
function Get-PIMEligibleRolesForWeb {
    [CmdletBinding()]
    param(
        [hashtable]$UserContext,
        [switch]$IncludeEntraRoles,
        [switch]$IncludeGroups,
        [switch]$IncludeAzureResources
    )

    try {
        $ctx = Get-CurrentSessionContext
        $accessToken = $ctx.AccessToken
        if (-not $accessToken) {
            return @{ roles = @(); success = $false; error = "No access token"; timestamp = (Get-Date -AsUTC).ToString('o') }
        }

        $userId = Get-CurrentUserId -AccessToken $accessToken
        $allRoles = [System.Collections.ArrayList]::new()
        $auCache = @{}

        # ── Entra ID eligible roles ──
        if ($IncludeEntraRoles) {
            try {
                $filter = [System.Web.HttpUtility]::UrlEncode("principalId eq '$userId'")
                $entraRoles = Invoke-GraphApi -AccessToken $accessToken -Endpoint "/roleManagement/directory/roleEligibilityScheduleInstances?`$filter=$filter&`$expand=roleDefinition"
                $entraValues = @($entraRoles.value)
                Write-Log -Message "Entra eligible: found $($entraValues.Count) role(s)" -Level 'Debug'

                foreach ($roleAssignment in $entraValues) {
                    $scope = $roleAssignment.directoryScopeId ?? '/'
                    $scopeDisplay = Resolve-DirectoryScopeDisplay -Scope $scope -AccessToken $accessToken -AuCache $auCache
                    $null = $allRoles.Add((New-EntraRoleEntry -RoleData $roleAssignment -Status 'Eligible' -ScopeDisplay $scopeDisplay -Scope $scope))
                }
            }
            catch {
                Write-Log -Message "Error fetching Entra eligible roles: $($_.Exception.Message)" -Level 'Error'
            }
        }

        # ── PIM-enabled Groups eligible ──
        if ($IncludeGroups) {
            try {
                $filter = [System.Web.HttpUtility]::UrlEncode("principalId eq '$userId'")
                $groupRoles = Invoke-GraphApi -AccessToken $accessToken -Endpoint "/identityGovernance/privilegedAccess/group/eligibilityScheduleInstances?`$filter=$filter&`$expand=group"
                $groupValues = @($groupRoles.value)
                Write-Log -Message "Group eligible: found $($groupValues.Count) role(s)" -Level 'Debug'

                foreach ($roleAssignment in $groupValues) {
                    $null = $allRoles.Add((New-GroupRoleEntry -RoleData $roleAssignment -Status 'Eligible'))
                }
            }
            catch {
                Write-Log -Message "Error fetching Group eligible roles: $($_.Exception.Message)" -Level 'Error'
            }
        }

        # ── Azure resource eligible roles ──
        if ($IncludeAzureResources) {
            $azToken = Get-AzureSessionToken
            if ($azToken) {
                try {
                    $subs = Invoke-AzureApi -AccessToken $azToken -Endpoint '/subscriptions' -ApiVersion '2022-01-01'
                    foreach ($sub in @($subs.value)) {
                        try {
                            $subScope = "/subscriptions/$($sub.subscriptionId)"
                            $eligible = Invoke-AzureApi -AccessToken $azToken -Endpoint "$subScope/providers/Microsoft.Authorization/roleEligibilityScheduleInstances?`$filter=asTarget()" -ApiVersion '2020-10-01'
                            foreach ($roleAssignment in @($eligible.value)) {
                                $null = $allRoles.Add((New-AzureRoleEntry -RoleData $roleAssignment -Status 'Eligible' -SubscriptionName $sub.displayName -SubscriptionScope $subScope))
                            }
                        }
                        catch {
                            Write-Log -Message "Azure eligible roles failed for sub $($sub.displayName): $($_.Exception.Message)" -Level 'Error'
                        }
                    }
                    Write-Log -Message "Azure eligible: found roles across $(@($subs.value).Count) subscription(s)" -Level 'Debug'
                }
                catch {
                    Write-Log -Message "Error fetching Azure subscriptions: $($_.Exception.Message)" -Level 'Error'
                }
            }
        }

        # ── Batch fetch Entra policies ──
        # Get all policy assignments in one call, deduplicate policy IDs, then fetch each unique policy once
        $policyCache = @{}
        try {
            $entraRoleIds = @($allRoles | Where-Object { $_.type -eq 'Entra' } | ForEach-Object { $_.id } | Select-Object -Unique)
            if ($entraRoleIds.Count -gt 0) {
                $filter = [System.Web.HttpUtility]::UrlEncode("scopeId eq '/' and scopeType eq 'DirectoryRole'")
                $allAssignments = Invoke-GraphApi -AccessToken $accessToken -Endpoint "/policies/roleManagementPolicyAssignments?`$filter=$filter"

                # Map roleDefinitionId -> policyId, and collect unique policyIds
                $roleToPolicyId = @{}
                $uniquePolicyIds = @{}
                foreach ($assignment in @($allAssignments.value)) {
                    if ($assignment.roleDefinitionId -and $assignment.roleDefinitionId -in $entraRoleIds) {
                        $roleToPolicyId[$assignment.roleDefinitionId] = $assignment.policyId
                        $uniquePolicyIds[$assignment.policyId] = $true
                    }
                }

                # Fetch each unique policy only once
                $policyById = @{}
                foreach ($polId in $uniquePolicyIds.Keys) {
                    try {
                        $policy = Invoke-GraphApi -AccessToken $accessToken -Endpoint "/policies/roleManagementPolicies/$polId`?`$expand=rules"
                        $info = @{ maxDurationHours = 8; requiresMfa = $false; requiresJustification = $false; requiresTicket = $false; requiresApproval = $false }
                        foreach ($rule in @($policy.rules)) {
                            $ruleType = $rule.'@odata.type'
                            if ($ruleType -eq '#microsoft.graph.unifiedRoleManagementPolicyExpirationRule' -and $rule.maximumDuration) {
                                try { $info.maxDurationHours = [int][System.Xml.XmlConvert]::ToTimeSpan($rule.maximumDuration).TotalHours } catch {}
                            }
                            elseif ($ruleType -eq '#microsoft.graph.unifiedRoleManagementPolicyEnablementRule' -and $rule.enabledRules) {
                                $enabled = @($rule.enabledRules)
                                $info.requiresJustification = 'Justification' -in $enabled
                                $info.requiresTicket = 'Ticketing' -in $enabled
                                $info.requiresMfa = 'MultiFactorAuthentication' -in $enabled
                            }
                            elseif ($ruleType -eq '#microsoft.graph.unifiedRoleManagementPolicyApprovalRule' -and $rule.setting -and $rule.setting.isApprovalRequired) {
                                $info.requiresApproval = $true
                            }
                        }
                        $policyById[$polId] = $info
                    }
                    catch { Write-Log -Message "Policy fetch failed for ${polId}: $($_.Exception.Message)" -Level 'Warning' }
                }

                # Map policies back to roles
                foreach ($roleId in $roleToPolicyId.Keys) {
                    $polId = $roleToPolicyId[$roleId]
                    if ($policyById.ContainsKey($polId)) {
                        $policyCache[$roleId] = $policyById[$polId]
                    }
                }
                Write-Log -Message "Policies: $($uniquePolicyIds.Count) unique policies for $($entraRoleIds.Count) Entra roles" -Level 'Debug'
            }
        }
        catch {
            Write-Log -Message "Batch policy fetch error: $($_.Exception.Message)" -Level 'Error'
        }

        # Apply policies to roles (defaults for Group/Azure when no policy found)
        foreach ($role in $allRoles) {
            if ($role.type -eq 'Entra' -and $policyCache.ContainsKey($role.id)) {
                $p = $policyCache[$role.id]
                $role.requiresMfa = $p.requiresMfa
                $role.requiresJustification = $p.requiresJustification
                $role.requiresTicket = $p.requiresTicket
                $role.requiresApproval = $p.requiresApproval
                $role.maxDurationHours = $p.maxDurationHours
            }
            elseif ($role.type -in @('Group', 'AzureResource')) {
                $role.requiresJustification = $true
            }
        }

        Write-Log -Message "Returning $($allRoles.Count) eligible roles" -Level 'Debug'
        return @{
            roles     = @($allRoles)
            success   = $true
            timestamp = (Get-Date -AsUTC).ToString('o')
        }
    }
    catch {
        Write-Log -Message "EligibleRoles ERROR: $($_.Exception.Message)" -Level 'Error'
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
    Get active roles for current user (Entra ID, Groups, and optionally Azure Resources)
.PARAMETER UserContext
    Pode auth context (unused but passed by the route handler)
.PARAMETER IncludeEntraRoles
    Include Entra ID directory role assignments
.PARAMETER IncludeGroups
    Include PIM-enabled group assignments
.PARAMETER IncludeAzureResources
    Include Azure resource role assignments (requires Azure Management token)
#>
function Get-PIMActiveRolesForWeb {
    [CmdletBinding()]
    param(
        [hashtable]$UserContext,
        [switch]$IncludeEntraRoles,
        [switch]$IncludeGroups,
        [switch]$IncludeAzureResources
    )

    try {
        $ctx = Get-CurrentSessionContext
        $accessToken = $ctx.AccessToken
        if (-not $accessToken) {
            return @{ roles = @(); success = $false; error = 'No access token'; timestamp = (Get-Date -AsUTC).ToString('o') }
        }

        $userId = Get-CurrentUserId -AccessToken $accessToken
        $allRoles = [System.Collections.ArrayList]::new()
        $auCache = @{}

        # ── Entra ID active roles ──
        if ($IncludeEntraRoles) {
            try {
                $filter = [System.Web.HttpUtility]::UrlEncode("principalId eq '$userId'")
                $entraRoles = Invoke-GraphApi -AccessToken $accessToken -Endpoint "/roleManagement/directory/roleAssignmentScheduleInstances?`$filter=$filter&`$expand=roleDefinition"

                foreach ($roleAssignment in @($entraRoles.value)) {
                    if (-not $roleAssignment.roleDefinitionId) { continue }

                    $scope = $roleAssignment.directoryScopeId ?? '/'
                    $scopeDisplay = Resolve-DirectoryScopeDisplay -Scope $scope -AccessToken $accessToken -AuCache $auCache
                    $null = $allRoles.Add((New-EntraRoleEntry -RoleData $roleAssignment -Status 'Active' -ScopeDisplay $scopeDisplay -Scope $scope))
                }
            }
            catch {
                Write-Log -Message "Error fetching Entra active roles: $($_.Exception.Message)" -Level 'Error'
            }
        }

        # ── PIM-enabled Groups active ──
        if ($IncludeGroups) {
            try {
                $filter = [System.Web.HttpUtility]::UrlEncode("principalId eq '$userId'")
                $groupRoles = Invoke-GraphApi -AccessToken $accessToken -Endpoint "/identityGovernance/privilegedAccess/group/assignmentScheduleInstances?`$filter=$filter&`$expand=group"

                foreach ($roleAssignment in @($groupRoles.value)) {
                    $null = $allRoles.Add((New-GroupRoleEntry -RoleData $roleAssignment -Status 'Active'))
                }
            }
            catch {
                Write-Log -Message "Error fetching Group active roles: $($_.Exception.Message)" -Level 'Error'
            }
        }

        # ── Azure resource active roles ──
        if ($IncludeAzureResources) {
            $azToken = Get-AzureSessionToken
            if ($azToken) {
                try {
                    $subs = Invoke-AzureApi -AccessToken $azToken -Endpoint '/subscriptions' -ApiVersion '2022-01-01'
                    foreach ($sub in @($subs.value)) {
                        try {
                            $subScope = "/subscriptions/$($sub.subscriptionId)"
                            $active = Invoke-AzureApi -AccessToken $azToken -Endpoint "$subScope/providers/Microsoft.Authorization/roleAssignmentScheduleInstances?`$filter=asTarget()" -ApiVersion '2020-10-01'
                            Write-Log -Message "Azure active for $($sub.displayName): $(@($active.value).Count) role(s)" -Level 'Debug'
                            foreach ($roleAssignment in @($active.value)) {
                                $null = $allRoles.Add((New-AzureRoleEntry -RoleData $roleAssignment -Status 'Active' -SubscriptionName $sub.displayName -SubscriptionScope $subScope))
                            }
                        }
                        catch {
                            Write-Log -Message "Azure active roles failed for sub $($sub.displayName): $($_.Exception.Message)" -Level 'Error'
                        }
                    }
                }
                catch {
                    Write-Log -Message "Error fetching Azure active subscriptions: $($_.Exception.Message)" -Level 'Error'
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

# ────────────────────────────────────────────────────────────────────
# Role activation / deactivation
# ────────────────────────────────────────────────────────────────────

<#
.SYNOPSIS
    Activate a PIM role
.DESCRIPTION
    Sends a selfActivate request for Entra, Group, or Azure Resource roles.
    Duration is converted to ISO 8601 format (PT{n}H or PT{n}M) as required
    by both the Graph API and Azure Management API.
.PARAMETER RoleId
    The role definition ID (GUID) to activate
.PARAMETER UserContext
    Pode auth context (unused but passed by the route handler)
.PARAMETER RoleType
    'User' for Entra directory roles, 'Group' for PIM groups, 'AzureResource' for Azure
.PARAMETER DirectoryScopeId
    Scope of the role assignment (e.g., '/' for directory, or an Azure resource scope)
.PARAMETER Justification
    Reason for the activation (required by some policies)
.PARAMETER TicketNumber
    Optional change ticket reference
.PARAMETER Duration
    How long the role should remain active
#>
function Invoke-PIMRoleActivationForWeb {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
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
        $ctx = Get-CurrentSessionContext
        $accessToken = $ctx.AccessToken
        if (-not $accessToken) {
            return @{ roleId = $RoleId; status = 'failed'; success = $false; error = 'No access token' }
        }

        $userId = Get-CurrentUserId -AccessToken $accessToken

        # Convert duration to ISO 8601 format: PT{hours}H for >= 1 hour, PT{minutes}M otherwise
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
                # Azure uses the Management API instead of Graph
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
        $errMsg = $_.Exception.Message

        # Detect MFA / authentication context errors and provide clear message
        if ($errMsg -match 'AcrsValidationFailed|MultiFactorAuthentication|StrongAuthenticationRequired|InteractionRequired|claims') {
            $errMsg = "This role requires MFA or additional authentication. Please sign out and sign back in, then try again."
        }
        elseif ($errMsg -match 'RoleAssignmentExists|already active') {
            $errMsg = "This role is already active or a request is pending."
        }

        return @{
            roleId    = $RoleId
            status    = 'failed'
            success   = $false
            error     = $errMsg
            timestamp = (Get-Date -AsUTC).ToString('o')
        }
    }
}

<#
.SYNOPSIS
    Deactivate a PIM role
.PARAMETER RoleId
    The role definition ID (GUID) to deactivate
.PARAMETER UserContext
    Pode auth context (unused but passed by the route handler)
.PARAMETER RoleType
    'User' for Entra directory roles, 'Group' for PIM groups, 'AzureResource' for Azure
.PARAMETER DirectoryScopeId
    Scope of the role assignment
#>
function Invoke-PIMRoleDeactivationForWeb {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RoleId,

        [hashtable]$UserContext,

        [ValidateSet('User', 'Group', 'AzureResource')]
        [string]$RoleType = 'User',

        [string]$DirectoryScopeId = '/'
    )

    try {
        $ctx = Get-CurrentSessionContext
        $accessToken = $ctx.AccessToken
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
    Get policy requirements for a role (max duration, MFA, justification, ticket, approval)
.PARAMETER RoleId
    The role definition ID (GUID)
.PARAMETER AccessToken
    Optional bearer token. If not provided, retrieved from the current session.
.PARAMETER RoleType
    'Entra' or 'Group'. Azure resource policies are not fetched here.
#>
function Get-PIMRolePolicyForWeb {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RoleId,

        [string]$AccessToken = $null,

        [string]$RoleType = 'Entra'
    )

    try {
        if (-not $AccessToken) {
            $ctx = Get-CurrentSessionContext
            $AccessToken = $ctx.AccessToken
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
                Write-Log -Message "Entra policy lookup failed for ${RoleId}: $($_.Exception.Message)" -Level 'Warning'
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
                Write-Log -Message "Group policy lookup failed for ${RoleId}: $($_.Exception.Message)" -Level 'Warning'
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
