<#
.SYNOPSIS
    User-related helper functions for OATH Token Management
.DESCRIPTION
    Provides utility functions for working with users in Microsoft Entra ID
.NOTES
    These functions are used for finding users by various identifiers
#>

function Get-MgUserByIdentifier {
    [CmdletBinding()]
    [OutputType([Microsoft.Graph.PowerShell.Models.MicrosoftGraphUser])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Identifier
    )
    
    try {
        # Check if the identifier looks like a GUID
        if ($Identifier -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
            # Try to get user directly by ID
            try {
                $user = Get-MgUser -UserId $Identifier -ErrorAction Stop
                if ($user) {
                    Write-Verbose "User found by ID: $($user.DisplayName) ($($user.UserPrincipalName))"
                    return $user
                }
            }
            catch {
                Write-Verbose "User not found by ID: $_"
            }
        }
        
        # Check if it looks like an email/UPN
        if ($Identifier -match '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$') {
            # Try exact match by UPN
            try {
                $filter = "userPrincipalName eq '$Identifier'"
                Write-Verbose "Looking up user by UPN filter: $filter"
                $users = Get-MgUser -Filter $filter -ErrorAction Stop
                
                if ($users -and $users.Count -gt 0) {
                    Write-Verbose "User found by UPN: $($users[0].DisplayName) ($($users[0].UserPrincipalName))"
                    return $users[0]
                }
            }
            catch {
                Write-Verbose "Error searching by UPN: $_"
            }
            
            # Try by mail
            try {
                $filter = "mail eq '$Identifier'"
                Write-Verbose "Looking up user by mail filter: $filter"
                $users = Get-MgUser -Filter $filter -ErrorAction Stop
                
                if ($users -and $users.Count -gt 0) {
                    Write-Verbose "User found by mail: $($users[0].DisplayName) ($($users[0].UserPrincipalName))"
                    return $users[0]
                }
            }
            catch {
                Write-Verbose "Error searching by mail: $_"
            }
        }
        
        # Try by display name
        try {
            $filter = "displayName eq '$Identifier' or startswith(displayName,'$Identifier')"
            Write-Verbose "Looking up user by display name filter: $filter"
            $users = Get-MgUser -Filter $filter -Top 10 -ErrorAction Stop
            
            if ($users -and $users.Count -gt 0) {
                if ($users.Count -gt 1) {
                    Write-Warning "Multiple users found matching '$Identifier'. Using first match: $($users[0].UserPrincipalName)"
                }
                Write-Verbose "User found by display name: $($users[0].DisplayName) ($($users[0].UserPrincipalName))"
                return $users[0]
            }
        }
        catch {
            Write-Verbose "Error searching by display name: $_"
        }
        
        # No user found with any method
        Write-Warning "No users found matching the identifier: $Identifier"
        return $null
    }
    catch {
        Write-Error "Error searching for user $Identifier`: $_"
        return $null
    }
}

# Create function to check if a user exists without returning the full object
function Test-MgUserExists {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Identifier
    )
    
    try {
        # Try a direct approach without Get-MgUserByIdentifier
        # This focuses on the actual existence check rather than returning the object
        
        # Check if the identifier looks like a GUID
        if ($Identifier -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
            try {
                $user = Get-MgUser -UserId $Identifier -Property Id -ErrorAction Stop
                return $null -ne $user
            }
            catch {
                Write-Verbose "User ID not found: $Identifier"
                return $false
            }
        }
        
        # Check if it looks like an email/UPN
        if ($Identifier -match '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$') {
            try {
                $filter = "userPrincipalName eq '$Identifier'"
                $users = Get-MgUser -Filter $filter -Property Id -Top 1 -ErrorAction Stop
                return ($users -and $users.Count -gt 0)
            }
            catch {
                try {
                    # Try by mail as fallback
                    $filter = "mail eq '$Identifier'"
                    $users = Get-MgUser -Filter $filter -Property Id -Top 1 -ErrorAction Stop
                    return ($users -and $users.Count -gt 0)
                }
                catch {
                    Write-Verbose "User email not found: $Identifier"
                    return $false
                }
            }
        }
        
        # Try by display name as a last resort
        try {
            $filter = "displayName eq '$Identifier'"
            $users = Get-MgUser -Filter $filter -Property Id -Top 1 -ErrorAction Stop
            return ($users -and $users.Count -gt 0)
        }
        catch {
            Write-Verbose "User name not found: $Identifier"
            return $false
        }
    }
    catch {
        Write-Verbose "Error checking if user exists: $_"
        return $false
    }
}

# Export the functions
Export-ModuleMember -Function Get-MgUserByIdentifier, Test-MgUserExists
