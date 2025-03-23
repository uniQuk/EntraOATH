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
.PARAMETER UnassignFirst
    Automatically unassign tokens before removal if they are assigned to a user
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
.EXAMPLE
    Remove-OATHToken -TokenId "00000000-0000-0000-0000-000000000000" -UnassignFirst
    
    Unassigns the token from its user (if assigned) before removing it
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
        [switch]$UnassignFirst,
        
        [Parameter()]
        [string]$ApiVersion = 'beta'
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
            # Resolve token ID if searching by serial number
            if ($PSCmdlet.ParameterSetName -eq 'BySerial') {
                $tokens = Get-OATHToken -SerialNumber $SerialNumber
                
                if ($tokens.Count -eq 0) {
                    Write-Error "No token found with serial number $SerialNumber"
                    return $false
                }
                
                if ($tokens.Count -gt 1) {
                    Write-Warning "Multiple tokens found with serial number $SerialNumber. Using the first matching token."
                }
                
                $TokenId = $tokens[0].Id
            }
            
            # Validate token ID format
            if (-not (Test-OATHTokenId -TokenId $TokenId)) {
                Write-Error "Invalid token ID format: $TokenId"
                return $false
            }
            
            # Get token details to check if assigned
            $token = Get-OATHToken -TokenId $TokenId
            if (-not $token) {
                Write-Error "Token not found with ID: $TokenId"
                return $false
            }
            
            # Check if token is assigned to a user and handle based on UnassignFirst parameter
            $isAssigned = (-not [string]::IsNullOrEmpty($token.AssignedToId))
            
            if ($isAssigned) {
                $tokenDisplay = if ($token.SerialNumber) {
                    "$TokenId (S/N: $($token.SerialNumber))"
                } else {
                    $TokenId
                }
                
                $userDisplay = if ($token.AssignedToName) {
                    "$($token.AssignedToName) ($($token.AssignedToId))"
                } else {
                    $token.AssignedToId
                }
                
                if ($UnassignFirst) {
                    Write-Host "Token $tokenDisplay is assigned to $userDisplay. Attempting to unassign first..." -ForegroundColor Yellow
                    
                    if ($Force -or $PSCmdlet.ShouldProcess("Token $tokenDisplay", "Unassign from $userDisplay")) {
                        try {
                            $unassignResult = Set-OATHTokenUser -TokenId $TokenId -Unassign -Force:$Force
                            
                            if (-not $unassignResult.Success) {
                                Write-Error "Failed to unassign token: $($unassignResult.Reason)"
                                Write-Host "To manually unassign, run: Set-OATHTokenUser -TokenId '$TokenId' -Unassign" -ForegroundColor Yellow
                                return $false
                            }
                            
                            Write-Host "Token successfully unassigned." -ForegroundColor Green
                        } catch {
                            Write-Error "Error unassigning token: $_"
                            Write-Host "To manually unassign, run: Set-OATHTokenUser -TokenId '$TokenId' -Unassign" -ForegroundColor Yellow
                            return $false
                        }
                    } else {
                        Write-Warning "Unassignment canceled. Token was not removed."
                        return $false
                    }
                } else {
                    # Token is assigned but UnassignFirst not specified
                    $errorMsg = "Cannot delete an assigned token. Token is currently assigned to $userDisplay."
                    Write-Error $errorMsg
                    Write-Host "To unassign and remove this token, run either:" -ForegroundColor Yellow
                    Write-Host "  - Remove-OATHToken -TokenId '$TokenId' -UnassignFirst" -ForegroundColor Yellow
                    Write-Host "  or" -ForegroundColor Yellow
                    Write-Host "  - Set-OATHTokenUser -TokenId '$TokenId' -Unassign" -ForegroundColor Yellow
                    Write-Host "  - Remove-OATHToken -TokenId '$TokenId'" -ForegroundColor Yellow
                    return $false
                }
            }
            
            # Proceed with token removal
            $endpoint = "$baseEndpoint/$TokenId"
            $description = if ($token.SerialNumber) {
                "token with ID $TokenId (S/N: $($token.SerialNumber))"
            } else {
                "token with ID $TokenId"
            }
            
            if ($Force -or $PSCmdlet.ShouldProcess($description, "Remove")) {
                Invoke-MgGraphWithErrorHandling -Method DELETE -Uri $endpoint
                Write-Host "Successfully removed token: $TokenId" -ForegroundColor Green
                return $true
            } else {
                Write-Warning "Removal canceled by user."
                return $false
            }
        } catch {
            if ($_.ToString() -match "Cannot delete an assigned") {
                Write-Error "Failed to remove token $TokenId : Cannot delete an assigned hardware OATH token."
                Write-Host "To unassign and remove this token, run:" -ForegroundColor Yellow
                Write-Host "  Remove-OATHToken -TokenId '$TokenId' -UnassignFirst" -ForegroundColor Yellow
            } else {
                Write-Error "Error in Remove-OATHToken: $_"
            }
            return $false
        }
    }
    
    end {
        # No additional end-block logic needed
    }
}

# Add alias for backward compatibility
New-Alias -Name 'Remove-HardwareOathToken' -Value 'Remove-OATHToken'
