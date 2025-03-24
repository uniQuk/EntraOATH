#Requires -Version 7.0
#Requires -Module Microsoft.Graph.Authentication

<#
.SYNOPSIS
    OATH Token Management module for Microsoft Entra ID
.DESCRIPTION
    PowerShell module for managing OATH tokens in Microsoft Entra ID via Microsoft Graph API.
    Provides functionality to add, assign, activate, list, and remove hardware OATH tokens.
.NOTES
    Version:        0.5.0
    Dev Version:    0.5.0
    Author:         Josh - https://github.com/uniQuk
    Creation Date:  2025-03-23
#>

#region Module Variables
$Script:OATHApiVersion = "beta"  # API version for Microsoft Graph
$Script:OATHTokenEndpoint = "https://graph.microsoft.com/$Script:OATHApiVersion/directory/authenticationMethodDevices/hardwareOathDevices"
#endregion

# Get public and private function definition files
$Private = @( Get-ChildItem -Path $PSScriptRoot\Private\*.ps1 -ErrorAction SilentlyContinue -Recurse )
$Public = @( Get-ChildItem -Path $PSScriptRoot\Public\*.ps1 -ErrorAction SilentlyContinue -Recurse )

# Dot source the files
foreach ($import in @($Private + $Public)) {
    try {
        Write-Verbose "Importing file: $($import.FullName)"
        . $import.FullName
    }
    catch {
        Write-Error "Failed to import function $($import.FullName): $_"
    }
}

# Export public functions and aliases defined in the module manifest
$manifestPath = Join-Path -Path $PSScriptRoot -ChildPath 'OATHTokens.psd1'
if (Test-Path -Path $manifestPath) {
    $manifest = Import-PowerShellDataFile -Path $manifestPath
    
    # Export functions from manifest
    foreach ($function in $manifest.FunctionsToExport) {
        if (Get-Command -Name $function -ErrorAction SilentlyContinue) {
            Export-ModuleMember -Function $function
        }
    }
    
    # Export aliases from manifest
    foreach ($alias in $manifest.AliasesToExport) {
        if (Get-Alias -Name $alias -ErrorAction SilentlyContinue) {
            Export-ModuleMember -Alias $alias
        }
    }
} else {
    # If no manifest is found, export everything (development mode)
    Export-ModuleMember -Function $Public.BaseName -Alias *
}

# Log module loading
Write-Verbose "OATH Token Management module loaded"
