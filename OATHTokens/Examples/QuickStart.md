# OATH Token Management Quick Start Guide

This guide provides a quick introduction to the most common tasks you can perform with the OATH Token Management module.

## Installation

1. Clone or download the module to your local machine
2. Import the module:

```powershell
Import-Module -Path "C:\Path\To\OATHTokens"
```

## Connection

Before using the module, you need to connect to Microsoft Graph with the appropriate permissions:

```powershell
Connect-MgGraph -Scopes "Policy.ReadWrite.AuthenticationMethod","Directory.Read.All"
```

## Common Tasks

### List All Tokens

```powershell
Get-OATHToken
```

### Find Available Tokens

```powershell
Get-OATHToken -AvailableOnly
```

### Find Tokens By Serial Number

```powershell
Get-OATHToken -SerialNumber "YK12345"
# Supports wildcards
Get-OATHToken -SerialNumber "YK*"
```

### Add a New Token

```powershell
# Simple approach
Add-OATHToken -SerialNumber "YK123456" -SecretKey "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

# Add token and assign to user in one step
Add-OATHToken -SerialNumber "YK123456" -SecretKey "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567" -UserId "user@example.com"

# Using a token object
$token = @{
    serialNumber = "YK123456"
    secretKey = "48656c6c6f20576f726c6421"  # "Hello World!" in hex
    secretFormat = "hex"
    manufacturer = "Yubico"
    model = "YubiKey 5"
    assignTo = @{ id = "user@example.com" }  # Can specify user upn or id
}
Add-OATHToken -Token $token
```

### Assign a Token to a User

```powershell
# By user ID
Set-OATHTokenUser -TokenId "00000000-0000-0000-0000-000000000000" -UserId "user@example.com"

# By serial number
Set-OATHTokenUser -SerialNumber "YK123456" -UserId "user@example.com"
```

### Activate a Token

```powershell
# Using a verification code from the physical token
Set-OATHTokenActive -TokenId "00000000-0000-0000-0000-000000000000" -UserId "user@example.com" -VerificationCode "123456"

# Using a verification from Get-TOTP
Set-OATHTokenActive -TokenId "00000000-0000-0000-0000-000000000000" -UserId "user@example.com" -VerificationCode (Get-TOTP -Secret "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

# Using the known secret to auto-generate the code
Set-OATHTokenActive -TokenId "00000000-0000-0000-0000-000000000000" -UserId "user@example.com" -Secret "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
```

### Remove a Token

```powershell
Remove-OATHToken -TokenId "00000000-0000-0000-0000-000000000000"
```

### Unassign a Token

```powershell
Set-OATHTokenUser -TokenId "00000000-0000-0000-0000-000000000000" -Unassign
```

## Bulk Operations

### Import Tokens from JSON

Create a JSON file with your tokens:

```json
{
  "inventory": [
    {
      "serialNumber": "YK123456",
      "secretKey": "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    },
    {
      "serialNumber": "YK789012",
      "secretKey": "48656c6c6f20576f726c6421",
      "secretFormat": "hex",
      "manufacturer": "Yubico",
      "model": "YubiKey 5 NFC"
    }
  ]
}
```

Then import:

```powershell
Import-OATHToken -FilePath "C:\path\to\tokens.json" -Format JSON
```

### Export Tokens to CSV

```powershell
Export-OATHToken -FilePath "C:\path\to\export.csv"
```

## Utility Functions

### Generate a Token Serial Number

```powershell
# Generate a simple numeric serial
New-OATHTokenSerial

# Generate an alphanumeric serial with a prefix
New-OATHTokenSerial -Prefix "YK-" -Format Alphanumeric

# Generate a serial and check if it already exists in the tenant
New-OATHTokenSerial -CheckExisting
```

### Generate TOTP Codes

```powershell
# Generate a TOTP code from a Base32 secret
Get-TOTP -Secret "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

# Generate a TOTP from a hex secret
Get-TOTP -Secret "48656c6c6f20576f726c6421" -InputFormat Hex
```

## Interactive Menu

For an interactive experience, use the menu system:

```powershell
Show-OATHTokenMenu
```

## Additional Help

To get detailed help for any command, use:

```powershell
Get-Help <CommandName> -Full
```

For example:

```powershell
Get-Help Add-OATHToken -Full
```
