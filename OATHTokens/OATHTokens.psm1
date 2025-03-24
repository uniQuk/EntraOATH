#Requires -Version 7.0
#Requires -Module Microsoft.Graph.Authentication

<#
.SYNOPSIS
    OATH Token Management module for Microsoft Entra ID
.DESCRIPTION
    PowerShell module for managing OATH tokens in Microsoft Entra ID via Microsoft Graph API.
    Provides functionality to add, assign, activate, list, and remove hardware OATH tokens.
.NOTES
    Version:        0.4.0
    Dev Version:    0.4.0
    Author:         Josh - https://github.com/uniQuk
    Creation Date:  2025-03-23
#>

#region Module Variables
$Script:OATHApiVersion = "beta"  # API version for Microsoft Graph
$Script:OATHTokenEndpoint = "https://graph.microsoft.com/$Script:OATHApiVersion/directory/authenticationMethodDevices/hardwareOathDevices"
#endregion

# Create a container for all private functions that will be available to public functions
$Script:PrivateFunctions = @{}

# Import all functions in the correct order to respect dependencies
# 1. Private utility functions first (no dependencies)
# 2. Private functions with dependencies on utilities
# 3. Public functions that depend on private functions

# Define the order of private module folders to ensure dependencies are loaded first
$privateLoadOrder = @(
    # Core Utilities (no dependencies)
    "Private\Base32Conversion.ps1",  # Base functionality with no dependencies
    "Private\ValidationHelpers.ps1",  # Basic validation functions
    "Private\GraphHelpers.ps1",       # Graph API helpers
    
    # Other private functions
    "Private\*.ps1"                   # Any remaining private functions
)

# Load private functions in the defined order
foreach ($privateModulePath in $privateLoadOrder) {
    # For specific files
    if ($privateModulePath -notlike "*\*.*") {
        $privatePath = Join-Path -Path $PSScriptRoot -ChildPath $privateModulePath
        if (Test-Path -Path $privatePath -PathType Container) {
            $files = Get-ChildItem -Path $privatePath -Filter "*.ps1" -Recurse
            foreach ($file in $files) {
                try {
                    Write-Verbose "Importing private module file: $($file.FullName)"
                    . $file.FullName
                    
                    # After sourcing the file, check for newly defined functions and add them to our private functions container
                    $definedFunctions = Get-ChildItem -Path Function: | Where-Object {
                        $_.ScriptBlock.File -and $_.ScriptBlock.File -eq $file.FullName
                    }
                    
                    foreach ($func in $definedFunctions) {
                        $Script:PrivateFunctions[$func.Name] = $func.ScriptBlock
                        Write-Verbose "Registered private function: $($func.Name)"
                    }
                }
                catch {
                    Write-Error "Failed to import private module file $($file.Name): $_"
                }
            }
        }
    }
    else {
        # For specific file patterns
        $files = Get-ChildItem -Path $PSScriptRoot -Include $privateModulePath -Recurse
        foreach ($file in $files) {
            try {
                Write-Verbose "Importing private module file: $($file.FullName)"
                . $file.FullName
                
                # After sourcing the file, check for newly defined functions and add them to our private functions container
                $definedFunctions = Get-ChildItem -Path Function: | Where-Object {
                    $_.ScriptBlock.File -and $_.ScriptBlock.File -eq $file.FullName
                }
                
                foreach ($func in $definedFunctions) {
                    $Script:PrivateFunctions[$func.Name] = $func.ScriptBlock
                    Write-Verbose "Registered private function: $($func.Name)"
                }
            }
            catch {
                Write-Error "Failed to import private module file $($file.Name): $_"
            }
        }
    }
}

# Create wrapper functions for each private function that will be accessible to public functions
foreach ($funcName in $Script:PrivateFunctions.Keys) {
    # Make the function available in the module's scope
    Set-Item -Path "function:script:$funcName" -Value $Script:PrivateFunctions[$funcName]
    Write-Verbose "Created script-level function for: $funcName"
}

# Define the order of public function categories to load
$publicCategories = @(
    "Public\Utility",  # Base utility functions first (like Convert-Base32)
    "Public\Get",      # Get functions next as many other functions depend on them
    "Public\Set",      # Set functions next
    "Public\Add",      # Add functions
    "Public\Remove",   # Remove functions
    "Public\Import",   # Import/Export functions
    "Public\Export",   # Import/Export functions 
    "Public\UI"        # UI functions last as they depend on everything else
)

# Load public functions in the defined order
foreach ($category in $publicCategories) {
    $publicPath = Join-Path -Path $PSScriptRoot -ChildPath $category
    if (Test-Path -Path $publicPath -PathType Container) {
        $files = Get-ChildItem -Path $publicPath -Filter "*.ps1" -Recurse
        foreach ($file in $files) {
            try {
                Write-Verbose "Importing public module file: $($file.FullName)"
                . $file.FullName
            }
            catch {
                Write-Error "Failed to import public module file $($file.Name) : $_"
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
