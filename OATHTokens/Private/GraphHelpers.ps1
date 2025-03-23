<#
.SYNOPSIS
    Helper functions for Microsoft Graph API interactions
.DESCRIPTION
    Private functions to simplify Microsoft Graph API requests and error handling
.NOTES
    These functions are used internally by the OATH token management module
#>

function Test-MgConnection {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    try {
        $context = Get-MgContext -ErrorAction Stop
        if (-not $context) {
            Write-Warning "Not connected to Microsoft Graph. Please run Connect-MgGraph first."
            return $false
        }
        
        # Verify required permissions
        $requiredScopes = @(
            "Policy.ReadWrite.AuthenticationMethod",
            "Directory.Read.All"
        )
        
        $hasRequiredScopes = $true
        foreach ($scope in $requiredScopes) {
            if ($context.Scopes -notcontains $scope) {
                $hasRequiredScopes = $false
                Write-Warning "Missing required permission: $scope"
            }
        }
        
        if (-not $hasRequiredScopes) {
            Write-Warning "Please connect with: Connect-MgGraph -Scopes $($requiredScopes -join ',')"
            return $false
        }
        
        return $true
    }
    catch {
        Write-Warning "Error checking Graph connection: $_"
        return $false
    }
}

function Invoke-MgGraphWithErrorHandling {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Method = "GET",
        
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        
        [Parameter()]
        [string]$Body,
        
        [Parameter()]
        [string]$ContentType = "application/json",
        
        [Parameter()]
        [int]$MaxRetries = 2,
        
        [Parameter()]
        [int]$RetryDelaySeconds = 2
    )
    
    $retryCount = 0
    $success = $false
    $lastException = $null
    
    while (-not $success -and $retryCount -le $MaxRetries) {
        try {
            $params = @{
                Method = $Method
                Uri = $Uri
            }
            
            if ($Body) {
                $params['Body'] = $Body
                $params['ContentType'] = $ContentType
            }
            
            Write-Verbose "Invoking Graph API: $Method $Uri"
            
            $response = Invoke-MgGraphRequest @params -ErrorAction Stop
            $success = $true
            return $response
        }
        catch {
            $lastException = $_
            $retryCount++
            
            # Check if error is retryable (e.g., throttling, temporary outage)
            $shouldRetry = $false
            
            # Check for specific error status codes that indicate retryable errors
            # Note: This removes the dependency on GraphOpenServiceException type
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                $statusCode = $_.Exception.Response.StatusCode.value__  # Get the integer value
                if ($statusCode -eq 429 -or $statusCode -eq 503 -or $statusCode -eq 504) {
                    $shouldRetry = $true
                }
            }
            
            if ($shouldRetry -and $retryCount -le $MaxRetries) {
                $delay = $RetryDelaySeconds * [Math]::Pow(2, $retryCount - 1)
                Write-Warning "Request failed. Retrying in $delay seconds... (Attempt $retryCount of $MaxRetries)"
                Start-Sleep -Seconds $delay
            }
            else {
                if ($retryCount -gt 1) {
                    Write-Warning "Request failed after $($retryCount - 1) retries."
                }
                
                Write-Verbose "Graph API Error: $($_)"
                throw "Graph API request failed: $($_)"
            }
        }
    }
    
    # If we get here, we've exhausted retries
    throw $lastException
}

function Get-MgUserByIdentifier {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Identifier
    )
    
    try {
        # Check if the identifier looks like a GUID
        if ($Identifier -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
            # Try to get user directly by ID
            try {
                return Get-MgUser -UserId $Identifier -ErrorAction Stop
            }
            catch {
                # If this fails, continue and try as UPN/email
                Write-Verbose "User not found by ID, trying as UPN: $_"
            }
        }
        
        # Check if it looks like an email/UPN
        if ($Identifier -match '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$') {
            # Try exact match by UPN
            try {
                $filter = "userPrincipalName eq '$Identifier'"
                $users = Get-MgUser -Filter $filter -ErrorAction Stop
                
                if ($users -and $users.Count -gt 0) {
                    return $users[0]
                }
            }
            catch {
                Write-Verbose "Error searching by UPN: $_"
            }
            
            # Try by mail
            try {
                $filter = "mail eq '$Identifier'"
                $users = Get-MgUser -Filter $filter -ErrorAction Stop
                
                if ($users -and $users.Count -gt 0) {
                    return $users[0]
                }
            }
            catch {
                Write-Verbose "Error searching by mail: $_"
            }
        }
        
        # Try by display name or part of name
        try {
            $filter = "displayName eq '$Identifier' or startswith(displayName,'$Identifier')"
            $users = Get-MgUser -Filter $filter -Top 10 -ErrorAction Stop
            
            if ($users -and $users.Count -gt 0) {
                if ($users.Count -gt 1) {
                    Write-Warning "Multiple users found matching '$Identifier'. Using first match: $($users[0].UserPrincipalName)"
                }
                return $users[0]
            }
        }
        catch {
            Write-Verbose "Error searching by display name: $_"
        }
        
        # No user found
        Write-Warning "No users found matching the identifier: $Identifier"
        return $null
    }
    catch {
        Write-Error "Error searching for user $Identifier`: $_"
        return $null
    }
}
