#Requires -Version 7.0
#Requires -Module Microsoft.Graph.Authentication

<#
.SYNOPSIS
    OATH Token Management module for Microsoft Entra ID
.DESCRIPTION
    PowerShell module for managing OATH tokens in Microsoft Entra ID via Microsoft Graph API.
    Provides functionality to add, assign, activate, list, and remove hardware OATH tokens.
.NOTES
    Version:        0.1.0
    Author:         Josh - https://github.com/uniQuk
    Creation Date:  2023-03-25
#>

#region Module Variables
$Script:OATHApiVersion = "beta"  # API version for Microsoft Graph
$Script:OATHTokenEndpoint = "https://graph.microsoft.com/$Script:OATHApiVersion/directory/authenticationMethodDevices/hardwareOathDevices"
#endregion

#region Helper Functions

# Check if Microsoft Graph connection is established
function Test-GraphConnection {
    [CmdletBinding()]
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

#endregion

#region Module Initialization

# Import all functions
$functionTypes = @('Private', 'Public')

foreach ($functionType in $functionTypes) {
    $functionPath = Join-Path -Path $PSScriptRoot -ChildPath $functionType
    
    if (Test-Path -Path $functionPath) {
        $functionFiles = Get-ChildItem -Path $functionPath -Filter '*.ps1' -Recurse
        
        foreach ($function in $functionFiles) {
            try {
                Write-Verbose "Importing function: $($function.Name)"
                . $function.FullName
            }
            catch {
                Write-Error "Failed to import function $($function.Name): $_"
            }
        }
    }
}

# Export public functions and aliases defined in the module manifest
$manifestPath = Join-Path -Path $PSScriptRoot -ChildPath 'OATHTokens.psd1'
if (Test-Path -Path $manifestPath) {
    $manifest = Import-PowerShellDataFile -Path $manifestPath
    
    foreach ($function in $manifest.FunctionsToExport) {
        if (Get-Command -Name $function -ErrorAction SilentlyContinue) {
            Export-ModuleMember -Function $function
        }
    }
    
    foreach ($alias in $manifest.AliasesToExport) {
        if (Get-Alias -Name $alias -ErrorAction SilentlyContinue) {
            Export-ModuleMember -Alias $alias
        }
    }
}

# Log module loading
Write-Verbose "OATH Token Management module loaded"

#endregion
