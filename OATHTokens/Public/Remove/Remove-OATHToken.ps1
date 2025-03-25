<#
.SYNOPSIS
    Removes OATH hardware tokens from Microsoft Entra ID
.DESCRIPTION
    Removes one or more OATH hardware tokens from Microsoft Entra ID via the Microsoft Graph API.
    Can remove tokens by ID, serial number, or other criteria.
.PARAMETER TokenId
    The ID of the token to remove
.PARAMETER SerialNumber
    The serial number of the token to remove
.PARAMETER Force
    Suppress confirmation prompts
.PARAMETER ApiVersion
    The Microsoft Graph API version to use. Defaults to 'beta'.
.EXAMPLE
    Remove-OATHToken -TokenId "00000000-0000-0000-0000-000000000000"
    
    Removes the token with the specified ID after confirmation
.EXAMPLE
    Remove-OATHToken -SerialNumber "12345678" -Force
    
    Removes the token with the specified serial number without confirmation
.EXAMPLE
    Get-OATHToken -AvailableOnly | Remove-OATHToken -Force
    
    Removes all available (unassigned) tokens without confirmation
.NOTES
    Requires Microsoft.Graph.Authentication module and appropriate permissions:
    - Policy.ReadWrite.AuthenticationMethod
#>

function Remove-OATHToken {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High', DefaultParameterSetName = 'ById')]
    [OutputType([bool])]
    param(
        [Parameter(ParameterSetName = 'ById', Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)]
        [Alias('Id')]
        [string]$TokenId,
        
        [Parameter(ParameterSetName = 'BySerial', Mandatory = $true)]
        [string]$SerialNumber,
        
        [Parameter()]
        [switch]$Force,
        
        [Parameter()]
        [string]$ApiVersion = 'beta'
    )
    
    begin {
        # Initialize the skip processing flag at the start of each function call
        $script:skipProcessing = $false
        
        # Ensure we're connected to Graph
        if (-not (Test-MgConnection)) {
            $script:skipProcessing = $true
            # Return here only exits the begin block, not the function
            return
        }
        
        $baseEndpoint = "https://graph.microsoft.com/$ApiVersion/directory/authenticationMethodDevices/hardwareOathDevices"
        
        # Initialize counters for reporting when processing multiple tokens
        $successCount = 0
        $failedCount = 0
        $processedCount = 0
    }
    
    process {
        # Skip all processing if the connection check failed
        if ($script:skipProcessing) {
            return $false
        }

        try {
            $processedCount++
            $targetTokens = @()
            
            # Resolve token by ID or serial number
            if ($PSCmdlet.ParameterSetName -eq 'ById') {
                # Validate token ID format
                if (-not (Test-OATHTokenId -TokenId $TokenId)) {
                    Write-Error "Invalid token ID format: $TokenId"
                    return $false
                }
                
                $targetTokens += @{
                    Id = $TokenId
                    DisplayName = $TokenId  # Use ID as display name if we don't fetch full details
                }
            }
            elseif ($PSCmdlet.ParameterSetName -eq 'BySerial') {
                # Find token by serial number
                $tokens = Get-OATHToken
                $matchingTokens = $tokens | Where-Object { $_.SerialNumber -eq $SerialNumber }
                
                if (-not $matchingTokens -or $matchingTokens.Count -eq 0) {
                    Write-Error "No token found with serial number: $SerialNumber"
                    return $false
                }
                
                if ($matchingTokens.Count -gt 1) {
                    Write-Warning "Multiple tokens found with serial number $SerialNumber. Using first match."
                }
                
                $targetTokens += $matchingTokens | Select-Object -First 1
            }
            elseif ($PSCmdlet.ParameterSetName -eq 'InputObject') {
                # This handles input from the pipeline (e.g., from Get-OATHToken)
                $targetTokens += $_
            }
            
            foreach ($token in $targetTokens) {
                $endpoint = "$baseEndpoint/$($token.Id)"
                $displayName = if ($token.DisplayName) { $token.DisplayName } else { $token.Id }
                $serialDisplay = if ($token.SerialNumber) { " (S/N: $($token.SerialNumber))" } else { "" }
                
                # Check if token is assigned to a user and warn
                if ($token.AssignedToId -or $token.assignedTo.id) {
                    $assignedToName = if ($token.AssignedToName) { $token.AssignedToName } elseif ($token.assignedTo.displayName) { $token.assignedTo.displayName } else { "Unknown User" }
                    $assignedToId = if ($token.AssignedToId) { $token.AssignedToId } elseif ($token.assignedTo.id) { $token.assignedTo.id } else { "Unknown ID" }
                    
                    # Extra warning for assigned tokens
                    if (-not $Force) {
                        Write-Warning "Token $displayName$serialDisplay is assigned to user $assignedToName ($assignedToId)."
                        Write-Warning "Removing this token will impact the user's ability to authenticate."
                    }
                }
                
                # Confirm removal unless Force is specified
                if ($Force -or $PSCmdlet.ShouldProcess("Token $displayName$serialDisplay", "Remove")) {
                    try {
                        Write-Verbose "Removing token: $displayName$serialDisplay"
                        Invoke-MgGraphWithErrorHandling -Method DELETE -Uri $endpoint -ErrorAction Stop
                        
                        Write-Host "Successfully removed token: $displayName$serialDisplay" -ForegroundColor Green
                        $successCount++
                        
                        # In single item mode, return true
                        if ($targetTokens.Count -eq 1) {
                            return $true
                        }
                    }
                    catch {
                        $errorMessage = "Failed to remove token $displayName$serialDisplay`: $_"
                        Write-Error $errorMessage
                        $failedCount++
                        
                        # In single item mode, return false
                        if ($targetTokens.Count -eq 1) {
                            return $false
                        }
                    }
                }
                else {
                    # User declined confirmation
                    Write-Warning "Removal of token $displayName$serialDisplay was canceled by user."
                    return $false
                }
            }
        }
        catch {
            Write-Error "Error in Remove-OATHToken: $_"
            return $false
        }
    }
    
    end {
        # Only show summary if processing multiple tokens
        if ($processedCount -gt 1) {
            Write-Host "`nToken Removal Summary:" -ForegroundColor Cyan
            Write-Host "  Total Processed: $processedCount" -ForegroundColor White
            Write-Host "  Successfully Removed: $successCount" -ForegroundColor Green
            Write-Host "  Failed: $failedCount" -ForegroundColor Red
            
            # Return true if at least one token was successfully removed
            return $successCount -gt 0
        }
    }
}

# Add alias for backward compatibility - only if it doesn't already exist
if (-not (Get-Alias -Name 'Remove-HardwareOathToken' -ErrorAction SilentlyContinue)) {
    New-Alias -Name 'Remove-HardwareOathToken' -Value 'Remove-OATHToken'
}
