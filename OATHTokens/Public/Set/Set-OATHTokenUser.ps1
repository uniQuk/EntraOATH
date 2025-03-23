<#
.SYNOPSIS
    Assigns or unassigns OATH hardware tokens to users in Microsoft Entra ID
.DESCRIPTION
    Assigns an OATH hardware token to a user, or unassigns it from a user,
    in Microsoft Entra ID via the Microsoft Graph API.
.PARAMETER TokenId
    The ID of the token to assign
.PARAMETER SerialNumber
    The serial number of the token to assign
.PARAMETER UserId
    The ID or UPN of the user to assign the token to
.PARAMETER Unassign
    Unassign the token from its current user instead of assigning it
.PARAMETER ApiVersion
    The Microsoft Graph API version to use. Defaults to 'beta'.
.EXAMPLE
    Set-OATHTokenUser -TokenId "00000000-0000-0000-0000-000000000000" -UserId "user@contoso.com"
    
    Assigns the specified token to the user with the given UPN
.EXAMPLE
    Set-OATHTokenUser -SerialNumber "12345678" -UserId "00000000-0000-0000-0000-000000000000"
    
    Assigns the token with the specified serial number to the user with the given ID
.EXAMPLE
    Set-OATHTokenUser -TokenId "00000000-0000-0000-0000-000000000000" -Unassign
    
    Unassigns the specified token from its current user
.NOTES
    Requires Microsoft.Graph.Authentication module and appropriate permissions:
    - Policy.ReadWrite.AuthenticationMethod
    - Directory.Read.All
#>

function Set-OATHTokenUser {
    [CmdletBinding(DefaultParameterSetName = 'AssignById', SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'AssignById', Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)]
        [Parameter(ParameterSetName = 'UnassignById', Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)]
        [Alias('Id')]
        [string]$TokenId,
        
        [Parameter(ParameterSetName = 'AssignBySerial', Mandatory = $true)]
        [Parameter(ParameterSetName = 'UnassignBySerial', Mandatory = $true)]
        [string]$SerialNumber,
        
        [Parameter(ParameterSetName = 'AssignById', Mandatory = $true, Position = 1)]
        [Parameter(ParameterSetName = 'AssignBySerial', Mandatory = $true, Position = 1)]
        [string]$UserId,
        
        [Parameter(ParameterSetName = 'UnassignById', Mandatory = $true)]
        [Parameter(ParameterSetName = 'UnassignBySerial', Mandatory = $true)]
        [switch]$Unassign,
        
        [Parameter()]
        [string]$ApiVersion = 'beta',
        
        [Parameter()]
        [switch]$Force
    )
    
    begin {
        # Ensure we're connected to Graph
        if (-not (Test-MgConnection)) {
            throw "Microsoft Graph connection required."
        }
        
        # Define endpoints
        $baseEndpoint = "https://graph.microsoft.com/$ApiVersion/directory/authenticationMethodDevices/hardwareOathDevices"
        $userMethodsEndpoint = "https://graph.microsoft.com/$ApiVersion/users/{0}/authentication/hardwareOathMethods"
        $userOperationsEndpoint = "https://graph.microsoft.com/$ApiVersion/users/{0}/authentication/operations/hardwareOathMethodRegistration"
    }
    
    process {
        try {
            # Initialize the result object
            $result = [PSCustomObject]@{
                Success = $false
                Operation = if ($Unassign) { "Unassign" } else { "Assign" }
                TokenId = $null
                SerialNumber = $null
                UserId = $UserId
                UserName = $null
                PreviousStatus = $null
                CurrentStatus = $null
                Reason = $null
            }
            
            # Resolve token by ID or serial number
            $targetToken = $null
            
            if ($PSCmdlet.ParameterSetName -like '*ById') {
                # Validate token ID format
                if (-not (Test-OATHTokenId -TokenId $TokenId)) {
                    $result.Reason = "Invalid token ID format: $TokenId"
                    Write-Error $result.Reason
                    return $result
                }
                
                $result.TokenId = $TokenId
                
                # Get token details to check if it's already assigned
                $endpoint = "$baseEndpoint/$TokenId"
                try {
                    $targetToken = Invoke-MgGraphWithErrorHandling -Method GET -Uri $endpoint -Verbose:$VerbosePreference
                } catch {
                    $result.Reason = "Token not found with ID: $TokenId"
                    Write-Error $result.Reason
                    return $result
                }
            }
            else {
                # Find token by serial number
                $tokens = Get-OATHToken
                $matchingTokens = $tokens | Where-Object { $_.SerialNumber -eq $SerialNumber }
                
                if (-not $matchingTokens -or $matchingTokens.Count -eq 0) {
                    $result.Reason = "No token found with serial number: $SerialNumber"
                    Write-Error $result.Reason
                    return $result
                }
                
                if ($matchingTokens.Count -gt 1) {
                    Write-Warning "Multiple tokens found with serial number $SerialNumber. Using first match."
                }
                
                $targetToken = $matchingTokens | Select-Object -First 1
                $TokenId = $targetToken.Id
                $result.TokenId = $TokenId
                $endpoint = "$baseEndpoint/$TokenId"
            }
            
            # Update result object with token details
            $result.SerialNumber = $targetToken.serialNumber ?? $targetToken.SerialNumber
            $result.PreviousStatus = $targetToken.status ?? $targetToken.Status
            
            # Define display information for confirmation messages
            $displayName = if ($targetToken.displayName) { $targetToken.displayName } elseif ($targetToken.DisplayName) { $targetToken.DisplayName } else { $targetToken.id ?? $targetToken.Id }
            $serialDisplay = if ($targetToken.serialNumber) { " (S/N: $($targetToken.serialNumber))" } elseif ($targetToken.SerialNumber) { " (S/N: $($targetToken.SerialNumber))" } else { "" }
            
            # Handle unassign request
            if ($Unassign) {
                # Check if token is assigned to anyone
                $currentAssigneeId = if ($targetToken.assignedTo -and $targetToken.assignedTo.id) { 
                    $targetToken.assignedTo.id
                } elseif ($targetToken.AssignedToId) {
                    $targetToken.AssignedToId
                } else {
                    $null
                }
                
                if (-not $currentAssigneeId) {
                    $result.Success = $true
                    $result.Reason = "Token is not assigned to any user. No action needed."
                    Write-Warning $result.Reason
                    return $result
                }
                
                # Get user information for confirmation
                $assignedToName = if ($targetToken.assignedTo -and $targetToken.assignedTo.displayName) { 
                    $targetToken.assignedTo.displayName
                } elseif ($targetToken.AssignedToName) {
                    $targetToken.AssignedToName
                } else { 
                    "Unknown User" 
                }
                
                $result.UserId = $currentAssigneeId
                $result.UserName = $assignedToName
                
                # Confirm unassignment
                if ($Force -or $PSCmdlet.ShouldProcess("Token $displayName$serialDisplay from user $assignedToName", "Unassign")) {
                    # Try multiple approaches for unassigning
                    $unassignSuccess = $false
                    
                    # Method 1: Delete the method from the user
                    try {
                        $userOathMethodEndpoint = ($userMethodsEndpoint -f $currentAssigneeId) + "/$TokenId"
                        Write-Verbose "Trying to unassign using DELETE to user's hardwareOathMethods: $userOathMethodEndpoint"
                        
                        Invoke-MgGraphWithErrorHandling -Method DELETE -Uri $userOathMethodEndpoint -ErrorAction Stop -Verbose:$VerbosePreference
                        $unassignSuccess = $true
                    }
                    catch {
                        Write-Verbose "First unassignment method failed: $_"
                        
                        # Method 2: Patch the token with null userId
                        try {
                            Write-Verbose "Trying to unassign by setting userId to null on token"
                            $patchBody = @{ userId = $null } | ConvertTo-Json
                            
                            Invoke-MgGraphWithErrorHandling -Method PATCH -Uri $endpoint -Body $patchBody -ContentType "application/json" -ErrorAction Stop -Verbose:$VerbosePreference
                            $unassignSuccess = $true
                        }
                        catch {
                            $result.Reason = "Failed to unassign token: $_"
                            Write-Error $result.Reason
                            return $result
                        }
                    }
                    
                    if ($unassignSuccess) {
                        Write-Host "Successfully unassigned token $displayName$serialDisplay from user $assignedToName" -ForegroundColor Green
                        
                        $result.Success = $true
                        $result.CurrentStatus = "available"
                        return $result
                    }
                }
                else {
                    $result.Reason = "Unassignment canceled by user."
                    Write-Warning $result.Reason
                    return $result
                }
            }
            else {
                # Handle assignment request
                
                # Check if token is already assigned to someone
                $currentAssigneeId = if ($targetToken.assignedTo -and $targetToken.assignedTo.id) { 
                    $targetToken.assignedTo.id
                } elseif ($targetToken.AssignedToId) {
                    $targetToken.AssignedToId
                } else {
                    $null
                }
                
                if ($currentAssigneeId) {
                    $assignedToName = if ($targetToken.assignedTo -and $targetToken.assignedTo.displayName) { 
                        $targetToken.assignedTo.displayName
                    } elseif ($targetToken.AssignedToName) {
                        $targetToken.AssignedToName
                    } else { 
                        "Unknown User" 
                    }
                    
                    $result.Reason = "Token $displayName$serialDisplay is already assigned to user $assignedToName ($currentAssigneeId). Please unassign it first."
                    Write-Error $result.Reason
                    return $result
                }
                
                # Resolve user by ID or UPN
                $resolvedUser = Get-MgUserByIdentifier -Identifier $UserId
                if (-not $resolvedUser) {
                    $result.Reason = "User not found with identifier: $UserId"
                    Write-Error $result.Reason
                    return $result
                }
                
                $result.UserId = $resolvedUser.id
                $result.UserName = $resolvedUser.displayName
                
                # Confirm assignment
                if ($Force -or $PSCmdlet.ShouldProcess("Token $displayName$serialDisplay", "Assign to user $($resolvedUser.displayName)")) {
                    # Try all available methods for assigning tokens
                    $assignSuccess = $false
                    $assignmentMessage = "Assigned token $displayName$serialDisplay to user $($resolvedUser.displayName) ($($resolvedUser.id))"
                    
                    # Method 1: hardwareOathMethodRegistration operation
                    try {
                        $operationEndpoint = $userOperationsEndpoint -f $resolvedUser.id
                        $operationBody = @{ tokenId = $TokenId } | ConvertTo-Json
                        
                        Write-Verbose "Trying to assign using operation endpoint: $operationEndpoint"
                        Write-Verbose "Request body: $operationBody"
                        
                        Invoke-MgGraphWithErrorHandling -Method POST -Uri $operationEndpoint -Body $operationBody -ContentType "application/json" -ErrorAction Stop -Verbose:$VerbosePreference
                        $assignSuccess = $true
                    }
                    catch {
                        Write-Verbose "First assignment method failed: $_"
                        
                        # Method 2: POST to user's hardwareOathMethods
                        try {
                            $methodsEndpoint = $userMethodsEndpoint -f $resolvedUser.id
                            $methodsBody = @{
                                device = @{ id = $TokenId }
                            } | ConvertTo-Json -Depth 5
                            
                            Write-Verbose "Trying to assign using user methods endpoint: $methodsEndpoint"
                            Write-Verbose "Request body: $methodsBody"
                            
                            Invoke-MgGraphWithErrorHandling -Method POST -Uri $methodsEndpoint -Body $methodsBody -ContentType "application/json" -ErrorAction Stop -Verbose:$VerbosePreference
                            $assignSuccess = $true
                        }
                        catch {
                            Write-Verbose "Second assignment method failed: $_"
                            
                            # Method 3: PATCH the token directly
                            try {
                                Write-Verbose "Trying to assign by setting userId on token"
                                $patchBody = @{ userId = $resolvedUser.id } | ConvertTo-Json
                                
                                Invoke-MgGraphWithErrorHandling -Method PATCH -Uri $endpoint -Body $patchBody -ContentType "application/json" -ErrorAction Stop -Verbose:$VerbosePreference
                                $assignSuccess = $true
                            }
                            catch {
                                $result.Reason = "All assignment methods failed. Last error: $_"
                                Write-Error $result.Reason
                                return $result
                            }
                        }
                    }
                    
                    if ($assignSuccess) {
                        Write-Host $assignmentMessage -ForegroundColor Green
                        
                        # Check if assignment worked by validating token is no longer available
                        Start-Sleep -Seconds 1
                        $availableTokens = Get-OATHToken -AvailableOnly
                        $stillAvailable = $availableTokens | Where-Object { $_.Id -eq $TokenId }
                        
                        if ($stillAvailable) {
                            $result.Reason = "API call succeeded but token still shows as available. The assignment may be processing or there may be an issue with the assignment."
                            Write-Warning $result.Reason
                        }
                        
                        $result.Success = $true
                        $result.CurrentStatus = "assigned"
                        return $result
                    }
                }
                else {
                    $result.Reason = "Assignment canceled by user."
                    Write-Warning $result.Reason
                    return $result
                }
            }
        }
        catch {
            $result.Reason = "Error in Set-OATHTokenUser: $_"
            Write-Error $result.Reason
            return $result
        }
    }
}

# Add alias for backward compatibility - only if it doesn't already exist
if (-not (Get-Alias -Name 'Assign-HardwareOathToken' -ErrorAction SilentlyContinue)) {
    New-Alias -Name 'Assign-HardwareOathToken' -Value 'Set-OATHTokenUser'
    Export-ModuleMember -Alias 'Assign-HardwareOathToken'  # Only needed if using script-level exports
}
