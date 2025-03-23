# OATH Token Management for Microsoft Entra ID

A comprehensive PowerShell module for managing hardware OATH tokens in Microsoft Entra ID (formerly Azure AD) through the Microsoft Graph API.

[Manage OATH Tokens in Entra](https://learn.microsoft.com/en-us/entra/identity/authentication/how-to-mfa-manage-oath-tokens#scenario-admin-creates-token-that-users-self-assign-and-activate)



## Overview

The OATH Token Management module provides a complete solution for managing OATH-TOTP hardware tokens (such as YubiKeys) in Microsoft Entra ID. It offers both a command-line interface with individual cmdlets and an interactive menu system, making it suitable for both scripted automation and interactive use.

## Features

- 🔑 **Complete Token Lifecycle Management**
  - Add individual or bulk tokens to your inventory
  - Assign tokens to users by ID, UPN, or display name
  - Activate tokens with verification codes
  - Unassign tokens from users
  - Remove tokens from the system

- 📋 **Inventory Management**
  - List all tokens with filtering options
  - Export token data to CSV or JSON
  - Generate detailed reports

- 🔄 **Bulk Operations**
  - Import tokens from JSON or CSV
  - Bulk assign tokens to users
  - Bulk remove tokens

- 🔐 **TOTP Support**
  - Built-in TOTP code generation
  - Automated token activation
  - RFC 6238 compliant implementation

- 🧩 **Flexible Secret Handling**
  - Support for Base32 encoded secrets
  - Support for hexadecimal secrets
  - Support for plain text secrets

## Prerequisites

- PowerShell 5.1 or newer (PowerShell 7+ recommended)
- Microsoft Graph PowerShell SDK modules:
  - Microsoft.Graph.Authentication
- Appropriate permissions in Microsoft Entra ID

### Required Microsoft Graph Permissions

- `Policy.ReadWrite.AuthenticationMethod`
- `Directory.Read.All`

## Installation

### Option 1: Install from PowerShell Gallery (Recommended)

```powershell
Install-Module -Name OATHTokens -Scope CurrentUser
```

### Option 2: Manual Installation

1. Clone this repository or download the ZIP file
2. Copy the module folder to one of your PowerShell module directories:

```powershell
# Find your PSModulePath
$env:PSModulePath -split ';'

# Copy the module (replace PATH_TO_MODULE with the actual path)
Copy-Item -Path "PATH_TO_MODULE\OATHTokens" -Destination "$HOME\Documents\PowerShell\Modules\" -Recurse
```

## Quick Start

1. Import the module:
   ```powershell
   Import-Module OATHTokens
   ```

2. Connect to Microsoft Graph:
   ```powershell
   Connect-MgGraph -Scopes "Policy.ReadWrite.AuthenticationMethod","Directory.Read.All"
   ```

3. Start the interactive menu:
   ```powershell
   Show-OATHTokenMenu
   ```

4. Or use individual commands:
   ```powershell
   # List all tokens
   Get-OATHToken
   
   # Add a token
   Add-OATHToken -SerialNumber "12345678" -SecretKey "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
   
   # Assign a token to a user
   Set-OATHTokenUser -TokenId "00000000-0000-0000-0000-000000000000" -UserId "user@example.com"
   ```

## Module Structure

The module is organized into the following components:

- **Public**: Contains all user-accessible cmdlets
  - **Core**: Basic token management functions
  - **Import**: Bulk import operations
  - **Export**: Bulk export operations
  - **Set**: Token state management
  - **UI**: Interactive menu system
  - **Utility**: Helper functions

- **Private**: Internal helper functions
  - Base32 conversion utilities
  - Graph API request handlers
  - Validation functions

## Core Commands

| Command | Description |
|---------|-------------|
| `Add-OATHToken` | Adds OATH tokens to Entra ID |
| `Get-OATHToken` | Retrieves OATH tokens with filtering options |
| `Remove-OATHToken` | Removes OATH tokens from Entra ID |
| `Set-OATHTokenUser` | Assigns or unassigns tokens to/from users |
| `Set-OATHTokenActive` | Activates a token using a verification code |
| `Import-OATHToken` | Imports tokens from JSON or CSV files |
| `Export-OATHToken` | Exports tokens to various formats |
| `Show-OATHTokenMenu` | Displays the interactive management menu |
| `Get-TOTP` | Generates TOTP codes from secrets |
| `New-OATHTokenSerial` | Generates unique token serial numbers |

## JSON File Examples

### Token Inventory JSON

```json
{
  "inventory": [
    {
      "serialNumber": "12345678",
      "secretKey": "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    },
    {
      "serialNumber": "87654321",
      "secretKey": "3a085cfcd4618c61dc235c300d7a70c4",
      "secretFormat": "hex",
      "manufacturer": "Yubico",
      "model": "YubiKey 5 NFC"
    },
    {
      "serialNumber": "11223344",
      "secretKey": "MySecretPassword123",
      "secretFormat": "text"
    }
  ]
}
```

### Token Assignment JSON

```json
{
  "inventory": [
    {
      "serialNumber": "12345678",
      "secretKey": "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567",
      "assignTo": {
        "id": "user@example.com"
      }
    }
  ],
  "assignments": [
    {
      "userId": "user@example.com",
      "tokenId": "00000000-0000-0000-0000-000000000000"
    }
  ]
}
```

## Common Tasks

### Adding a Token

```powershell
# Add a token with a Base32 secret
Add-OATHToken -SerialNumber "12345678" -SecretKey "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

# Add a token with a hexadecimal secret
Add-OATHToken -SerialNumber "87654321" -SecretKey "3a085cfcd4618c61dc235c300d7a70c4" -SecretFormat Hex

# Add a token with a text secret
Add-OATHToken -SerialNumber "11223344" -SecretKey "MySecretPassword123" -SecretFormat Text
```

### Finding Tokens

```powershell
# Get all tokens
Get-OATHToken

# Get available (unassigned) tokens
Get-OATHToken -AvailableOnly

# Get activated tokens
Get-OATHToken -ActivatedOnly

# Find tokens by serial number (supports wildcards)
Get-OATHToken -SerialNumber "YK*"

# Find tokens by user
Get-OATHToken -UserId "user@example.com"
```

### Assigning Tokens

```powershell
# Assign by token ID
Set-OATHTokenUser -TokenId "00000000-0000-0000-0000-000000000000" -UserId "user@example.com"

# Unassign a token
Set-OATHTokenUser -TokenId "00000000-0000-0000-0000-000000000000" -Unassign
```

### Activating Tokens

```powershell
# Activate with a verification code
Set-OATHTokenActive -TokenId "00000000-0000-0000-0000-000000000000" -UserId "user@example.com" -VerificationCode "123456"

# Activate with a secret key (auto-generates the TOTP code)
Set-OATHTokenActive -TokenId "00000000-0000-0000-0000-000000000000" -UserId "user@example.com" -Secret "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
```

### Bulk Operations

```powershell
# Import tokens from JSON
Import-OATHToken -FilePath "tokens.json" -Format JSON

# Import tokens and assign to users
Import-OATHToken -FilePath "tokens_users.json" -Format JSON -SchemaType UserAssignments -AssignToUsers

# Export tokens to CSV
Export-OATHToken -FilePath "tokens.csv"

# Export tokens to JSON
Export-OATHToken -FilePath "tokens.json" -Format JSON
```

### Generating TOTP Codes

```powershell
# Generate a TOTP code from a Base32 secret
Get-TOTP -Secret "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

# Generate a TOTP code from a hexadecimal secret
Get-TOTP -Secret "3a085cfcd4618c61dc235c300d7a70c4" -InputFormat Hex

# Generate a TOTP code from a text secret
Get-TOTP -Secret "MySecretPassword123" -InputFormat Text
```

## Advanced Scenarios

### Automating Token Setup

This example script automates the full token lifecycle:

```powershell
# Generate a unique serial number
$serialNumber = New-OATHTokenSerial -Prefix "YK-" -Format Alphanumeric -CheckExisting

# Generate a random secret
$secret = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 32 | ForEach-Object {[char]$_})
$base32Secret = ConvertTo-Base32 -InputString $secret -IsTextSecret

# Add the token
$token = Add-OATHToken -SerialNumber $serialNumber -SecretKey $base32Secret

# Assign to a user
Set-OATHTokenUser -TokenId $token.id -UserId "user@example.com"

# Generate a TOTP code
$totpCode = Get-TOTP -Secret $base32Secret

Write-Host "Token serial: $serialNumber"
Write-Host "Token secret: $base32Secret"
Write-Host "Current TOTP: $totpCode"
```

### Integration with Other Systems

The module can be integrated with other identity management systems:

```powershell
# Example integration with a user onboarding process
function New-UserOnboarding {
    param($UserPrincipalName, $DisplayName)
    
    # Create the user in Entra ID (using separate commands)
    # ...
    
    # Get the user's ID
    $user = Get-MgUser -Filter "userPrincipalName eq '$UserPrincipalName'"
    
    # Generate a token
    $serialNumber = New-OATHTokenSerial -CheckExisting
    $secretKey = ConvertTo-Base32 -InputString ([Guid]::NewGuid().ToString()) -IsTextSecret
    
    # Add and assign the token
    $token = Add-OATHToken -SerialNumber $serialNumber -SecretKey $secretKey
    Set-OATHTokenUser -TokenId $token.id -UserId $user.id
    
    # Return the token details for record-keeping
    return @{
        UserPrincipalName = $UserPrincipalName
        TokenId = $token.id
        SerialNumber = $serialNumber
        SecretKey = $secretKey
    }
}
```

## Troubleshooting

### Common Issues

- **Error: Not connected to Microsoft Graph**
  - Solution: Run `Connect-MgGraph -Scopes "Policy.ReadWrite.AuthenticationMethod","Directory.Read.All"`

- **Error: Token not found**
  - Solution: Verify the token ID is correct with `Get-OATHToken`

- **Error: User not found**
  - Solution: Verify the user ID or UPN with `Get-MgUser`

- **Error: Token activation failed**
  - Solution: Ensure the verification code is valid and has not expired

### Diagnostic Steps

1. **Check Graph Connection**:
   ```powershell
   Get-MgContext
   ```

2. **Verify Permissions**:
   ```powershell
   (Get-MgContext).Scopes
   ```

3. **Enable Verbose Output**:
   ```powershell
   Set-OATHTokenUser -TokenId $id -UserId $user -Verbose
   ```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/new-feature`)
3. Commit your changes (`git commit -m 'Add some new feature'`)
4. Push to the branch (`git push origin feature/new-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- The TOTP implementation is based on RFC 6238 - modified the below script for TOTP.ps1
- Credits to: https://gist.github.com/jonfriesen/234c7471c3e3199f97d5#file-totp-ps1 

