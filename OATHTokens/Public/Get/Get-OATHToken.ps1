<#
.SYNOPSIS
    Gets OATH hardware tokens from Microsoft Entra ID
.DESCRIPTION
    Retrieves OATH hardware tokens from Microsoft Entra ID via the Microsoft Graph API.
    Can filter by status, ID, serial number, or user assignment.
.PARAMETER TokenId
    The ID of a specific token to retrieve
.PARAMETER SerialNumber
    Filter tokens by serial number (can include wildcards)
.PARAMETER UserId
    Filter tokens assigned to a specific user ID or UPN
.PARAMETER Status
    Filter tokens by status (available, assigned, activated)
.PARAMETER IncludeAll
    Include all tokens regardless of status
.PARAMETER AvailableOnly
    Only include tokens that are available (not assigned)
.PARAMETER AssignedOnly
    Only include tokens that are assigned to users
.PARAMETER ActivatedOnly
    Only include tokens that are activated
.PARAMETER ApiVersion
    The Microsoft Graph API version to use. Defaults to 'beta'.
.EXAMPLE
    Get-OATHToken
    Gets all hardware OATH tokens in the tenant
.EXAMPLE
    Get-OATHToken -TokenId "00000000-0000-0000-0000-000000000000"
    Gets a specific token by ID
.EXAMPLE
    Get-OATHToken -SerialNumber "1234*"
    Gets all tokens with serial numbers starting with "1234"
.EXAMPLE
    Get-OATHToken -UserId "user@contoso.com"
    Gets all tokens assigned to the specified user
.EXAMPLE
    Get-OATHToken -AvailableOnly
    Gets only tokens that are available for assignment
.NOTES
    Requires Microsoft.Graph.Authentication module and appropriate permissions:
    - Policy.ReadWrite.AuthenticationMethod
    - Directory.Read.All
#>

function Get-OATHToken {
    [CmdletBinding(DefaultParameterSetName = 'All')]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(ParameterSetName = 'ById', Mandatory = $true)]
        [string]$TokenId,
        
        [Parameter(ParameterSetName = 'BySerial')]
        [string]$SerialNumber,
        
        [Parameter(ParameterSetName = 'ByUser')]
        [string]$UserId,
        
        [Parameter(ParameterSetName = 'ByStatus')]
        [ValidateSet('available', 'assigned', 'activated')]
        [string]$Status,
        
        [Parameter(ParameterSetName = 'All')]
        [switch]$IncludeAll,
        
        [Parameter(ParameterSetName = 'ByStatus')]
        [switch]$AvailableOnly,
        
        [Parameter(ParameterSetName = 'ByStatus')]
        [switch]$AssignedOnly,
        
        [Parameter(ParameterSetName = 'ByStatus')]
        [switch]$ActivatedOnly,
        
        [Parameter()]
        [string]$ApiVersion = "beta"
    )
    
    begin {
        # Ensure we're connected to Graph
        if (-not (Test-MgConnection)) {
            throw "Microsoft Graph connection required."
        }
        
        $baseEndpoint = "https://graph.microsoft.com/$ApiVersion/directory/authenticationMethodDevices/hardwareOathDevices"
    }
    
    process {
        try {
            # Handle single token retrieval by ID
            if ($PSCmdlet.ParameterSetName -eq 'ById') {
                if (-not (Test-OATHTokenId -TokenId $TokenId)) {
                    Write-Error "Invalid token ID format"
                    return
                }
                
                $endpoint = "$baseEndpoint/$TokenId"
                $token = Invoke-MgGraphWithErrorHandling -Uri $endpoint
                
                # Transform and return token
                return [PSCustomObject]@{
                    PSTypeName = 'OATHToken'
                    Id = $token.id
                    SerialNumber = $token.serialNumber
                    DisplayName = $token.displayName
                    Manufacturer = $token.manufacturer
                    Model = $token.model
                    Status = $token.status
                    HashFunction = $token.hashFunction
                    TimeInterval = $token.timeIntervalInSeconds
                    LastUsed = if ($token.lastUsedDateTime) { [datetime]$token.lastUsedDateTime } else { $null }
                    AssignedToId = $token.assignedTo.id
                    AssignedToName = $token.assignedTo.displayName
                    AssignedToUpn = $token.assignedTo.userPrincipalName
                    Created = if ($token.createdDateTime) { [datetime]$token.createdDateTime } else { $null }
                    RawObject = $token
                }
            }
            else {
                # Handle user resolution if needed
                if ($UserId) {
                    $user = Get-MgUserByIdentifier -Identifier $UserId
                    if (-not $user) {
                        Write-Error "User not found: $UserId"
                        return
                    }
                    $UserId = $user.id
                }
                
                # Get all tokens first
                $tokens = Invoke-MgGraphWithErrorHandling -Uri $baseEndpoint
                
                # Filter by status if needed
                if ($Status -or $AvailableOnly -or $AssignedOnly -or $ActivatedOnly) {
                    $statusFilter = if ($Status) { $Status }
                                   elseif ($AvailableOnly) { 'available' }
                                   elseif ($AssignedOnly) { 'assigned' }
                                   elseif ($ActivatedOnly) { 'activated' }
                                   else { $null }
                    
                    if ($statusFilter) {
                        $tokens.value = $tokens.value | Where-Object { $_.status -eq $statusFilter }
                    }
                }
                
                # Filter by serial number if provided
                if ($SerialNumber) {
                    if ($SerialNumber -like "*[?*]*") {
                        # Wildcard search
                        $wildcardPattern = $SerialNumber -replace '\*', '.*' -replace '\?', '.'
                        $tokens.value = $tokens.value | Where-Object { $_.serialNumber -match "^$wildcardPattern$" }
                    }
                    else {
                        # Exact match
                        $tokens.value = $tokens.value | Where-Object { $_.serialNumber -eq $SerialNumber }
                    }
                }
                
                # Filter by user if provided
                if ($UserId) {
                    $tokens.value = $tokens.value | Where-Object { $_.assignedTo.id -eq $UserId }
                }
                
                # Transform and return tokens
                return $tokens.value | ForEach-Object {
                    [PSCustomObject]@{
                        PSTypeName = 'OATHToken'
                        Id = $_.id
                        SerialNumber = $_.serialNumber
                        DisplayName = $_.displayName
                        Manufacturer = $_.manufacturer
                        Model = $_.model
                        Status = $_.status
                        HashFunction = $_.hashFunction
                        TimeInterval = $_.timeIntervalInSeconds
                        LastUsed = if ($_.lastUsedDateTime) { [datetime]$_.lastUsedDateTime } else { $null }
                        AssignedToId = $_.assignedTo.id
                        AssignedToName = $_.assignedTo.displayName
                        AssignedToUpn = $_.assignedTo.userPrincipalName
                        Created = if ($_.createdDateTime) { [datetime]$_.createdDateTime } else { $null }
                        RawObject = $_
                    }
                }
            }
        }
        catch {
            Write-Error "Error retrieving OATH tokens: $_"
        }
    }
}

# Add type formatting for better console display
Update-TypeData -TypeName 'OATHToken' -DefaultDisplayPropertySet Id, SerialNumber, DisplayName, Status, AssignedToName -ErrorAction SilentlyContinue

# Add alias for backward compatibility
New-Alias -Name 'Get-HardwareOathTokens' -Value 'Get-OATHToken'
