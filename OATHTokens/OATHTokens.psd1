@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'OATHTokens.psm1'

    # Version number of this module.
    ModuleVersion = '0.6.0'

    # ID used to uniquely identify this module
    GUID = '21b43a58-8d4f-4d60-9745-f993fb61efc4'

    # Author of this module
    Author = 'Josh - https://github.com/uniQuk'

    # Company or vendor of this module
    CompanyName = 'uniQuk'

    # Copyright statement for this module
    Copyright = 'MIT License (c) 2025 Josh'

    # Description of the functionality provided by this module
    Description = 'PowerShell module for managing OATH tokens in Microsoft Entra ID via Microsoft Graph API.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.0.0'

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules = @(
        @{
            ModuleName = 'Microsoft.Graph.Authentication'
            ModuleVersion = '2.26.1'
        }
    )

    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry
    FunctionsToExport = @(
        'Add-OATHToken',
        'Get-OATHToken',
        'Remove-OATHToken',
        'Set-OATHTokenUser',
        'Set-OATHTokenActive',
        'Import-OATHToken',
        'Export-OATHToken',
        'New-OATHTokenSerial',
        'Convert-Base32',  # Use the public wrapper name
        'Show-OATHTokenMenu',
        'Get-TOTP',
        'Test-TOTP'
    )

    # Cmdlets to export from this module
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = '*'

    # Aliases to export from this module
    AliasesToExport = @(
        'Convert-Base32String'  # Only include this alias, remove 'Convert-Base32' from aliases
    )

    # Private data to pass to the module specified in RootModule/ModuleToProcess
    PrivateData = @{
        PSData = @{
            # Tags applied to this module to indicate this is for EntraID/Azure AD
            Tags = @('EntraID', 'AzureAD', 'MFA', 'OATH', 'Authentication', 'Yubikey')

            # A URL to the license for this module
            LicenseUri = 'https://github.com/uniQuk/EntraOATH/blob/main/LICENSE'

            # A URL to the main website for this project
            ProjectUri = 'https://github.com/uniQuk/EntraOATH'

            # ReleaseNotes of this module
            ReleaseNotes = 'Enhance Add-OATHToken to support user assignment in a single step. Reduce menu complexity. Allow mixed assignments in bulk imports.'
        }
    }
}
