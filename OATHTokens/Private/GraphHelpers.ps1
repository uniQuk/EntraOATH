<#
.SYNOPSIS
    Helper functions for interacting with Microsoft Graph API
.DESCRIPTION
    Internal utility functions for handling Microsoft Graph API requests,
    connections, and error handling for OATH token management.
.NOTES
    These functions are not exported by the module and are for internal use only.
#>

function Test-MgConnection {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [string[]]$RequiredScopes = @(
            'Policy.ReadWrite.AuthenticationMethod',
            'Directory.Read.All'
        )
    )
    
    try {
        $context = Get-MgContext -ErrorAction Stop
        
        if (-not $context) {
            Write-Warning "Not connected to Microsoft Graph. Please run Connect-MgGraph first."
            return $false
        }
        
        $missingScopes = @()
        foreach ($scope in $RequiredScopes) {
            if ($context.Scopes -notcontains $scope) {
                $missingScopes += $scope
            }
        }
        
        if ($missingScopes.Count -gt 0) {
            $scopeString = $RequiredScopes -join "',''"
            Write-Warning "Missing recommended Microsoft Graph permissions: $($missingScopes -join ', ')"
            Write-Warning "Consider reconnecting with: Connect-MgGraph -Scopes '$scopeString'"
            # Still return true since we have a connection, just missing permissions
            # Let Graph API handle permission errors naturally
        }
        
        return $true
    }
    catch {
        Write-Warning "Error checking Microsoft Graph connection: $_"
        Write-Warning "Please run Connect-MgGraph to connect to Microsoft Graph."
        return $false
    }
}

function Invoke-MgGraphWithErrorHandling {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        
        [Parameter()]
        [string]$Method = "GET",
        
        [Parameter()]
        [string]$Body,
        
        [Parameter()]
        [string]$ContentType = "application/json",
        
        [Parameter()]
        [int]$MaxRetries = 3,
        
        [Parameter()]
        [int]$RetryDelaySeconds = 2,
        
        [Parameter()]
        [switch]$IncludeStatistics
    )
    
    # Ensure we're connected to Graph
    if (-not (Test-MgConnection)) {
        throw "Microsoft Graph connection required."
    }
    
    $retryCount = 0
    $statistics = @{
        StartTime = Get-Date
        EndTime = $null
        RetryCount = 0
        StatusCode = 0
        Uri = $Uri
        Method = $Method
    }
    
    while ($retryCount -le $MaxRetries) {
        try {
            $params = @{
                Method = $Method
                Uri = $Uri
                ErrorAction = "Stop"
            }
            
            if ($Body) {
                $params['Body'] = $Body
                $params['ContentType'] = $ContentType
            }
            
            $response = Invoke-MgGraphRequest @params
            
            $statistics.StatusCode = 200 # Success
            $statistics.EndTime = Get-Date
            
            if ($IncludeStatistics) {
                return [PSCustomObject]@{
                    Response = $response
                    Statistics = $statistics
                }
            } else {
                return $response
            }
        }
        catch {
            $errorDetails = @{
                Message = $_.Exception.Message
                StatusCode = $null
                ResponseContent = $null
                RequestId = $null
                ErrorCode = $null
                TenantId = $null
            }
            
            $retryCount++
            $statistics.RetryCount = $retryCount
            
            # Try to extract useful information from the error
            if ($_.Exception.Response) {
                $response = $_.Exception.Response
                $errorDetails.StatusCode = [int]$response.StatusCode
                $statistics.StatusCode = $errorDetails.StatusCode
                
                try {
                    $responseContent = $response.Content.ReadAsStringAsync().Result
                    $errorDetails.ResponseContent = $responseContent
                    
                    $errorJson = $responseContent | ConvertFrom-Json
                    if ($errorJson.error) {
                        $errorDetails.ErrorCode = $errorJson.error.code
                        
                        if ($errorJson.error.innerError -and $errorJson.error.innerError.requestId) {
                            $errorDetails.RequestId = $errorJson.error.innerError.requestId
                        }
                        
                        if ($errorJson.error.innerError -and $errorJson.error.innerError.date) {
                            $errorDetails.Date = $errorJson.error.innerError.date
                        }
                    }
                }
                catch {
                    Write-Verbose "Could not parse error response: $_"
                }
            }
            
            # Handle transient errors that can be retried
            $retryableStatusCodes = @(408, 429, 500, 502, 503, 504)
            $retryableErrorCodes = @('serviceUnavailable', 'quotaLimitExceeded', 'requestTimeout', 'tooManyRequests')
            
            $canRetry = $false
            if ($retryableStatusCodes -contains $errorDetails.StatusCode) {
                $canRetry = $true
            } elseif ($retryableErrorCodes -contains $errorDetails.ErrorCode) {
                $canRetry = $true
            }
            
            if ($canRetry -and $retryCount -le $MaxRetries) {
                $delay = $RetryDelaySeconds * [Math]::Pow(2, $retryCount - 1) # Exponential backoff
                Write-Warning "Request failed with $($errorDetails.StatusCode). Retrying in $delay seconds... (Attempt $retryCount of $MaxRetries)"
                Start-Sleep -Seconds $delay
                continue
            }
            
            # If we've reached max retries or it's not a retryable error, throw the exception
            $statistics.EndTime = Get-Date
            
            $errorMessage = "Graph API request failed: $($errorDetails.Message)"
            if ($errorDetails.ErrorCode) {
                $errorMessage += " (ErrorCode: $($errorDetails.ErrorCode))"
            }
            
            if ($IncludeStatistics) {
                throw [PSCustomObject]@{
                    Message = $errorMessage
                    ErrorDetails = $errorDetails
                    Statistics = $statistics
                }
            } else {
                throw $errorMessage
            }
        }
    }
}

function Get-MgUserByIdentifier {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [string]$Identifier,
        
        [Parameter()]
        [string]$ApiVersion = "beta"
    )
    
    process {
        try {
            # Ensure we're connected to Graph
            if (-not (Test-MgConnection)) {
                throw "Microsoft Graph connection required."
            }
            
            # Check if the identifier looks like a GUID (Object ID)
            if ($Identifier -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
                # First try to get user directly by ID
                try {
                    $endpoint = "https://graph.microsoft.com/$ApiVersion/users/$Identifier"
                    $user = Invoke-MgGraphWithErrorHandling -Uri $endpoint
                    return $user
                }
                catch {
                    Write-Verbose "User not found by ID, will try searching as UPN."
                }
            }
            
            # Try to find by UPN
            $encodedIdentifier = [System.Web.HttpUtility]::UrlEncode($Identifier)
            $endpoint = "https://graph.microsoft.com/$ApiVersion/users?`$filter=userPrincipalName eq '$encodedIdentifier'"
            $result = Invoke-MgGraphWithErrorHandling -Uri $endpoint
            
            if ($result.value.Count -eq 0) {
                # If still not found, try a more flexible search for display name or email
                $endpoint = "https://graph.microsoft.com/$ApiVersion/users?`$filter=startswith(displayName,'$encodedIdentifier') or startswith(mail,'$encodedIdentifier')"
                $result = Invoke-MgGraphWithErrorHandling -Uri $endpoint
                
                if ($result.value.Count -eq 0) {
                    Write-Warning "No users found matching the identifier: $Identifier"
                    return $null
                }
                elseif ($result.value.Count -gt 1) {
                    Write-Warning "Multiple users found matching the identifier: $Identifier"
                    $result.value | ForEach-Object {
                        Write-Host "ID: $($_.id), UPN: $($_.userPrincipalName), Name: $($_.displayName)" -ForegroundColor Yellow
                    }
                    return $null
                }
            }
            
            return $result.value[0]
        }
        catch {
            Write-Error "Error searching for user: $_"
            return $null
        }
    }
}
