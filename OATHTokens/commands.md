# OATHTokens PowerShell Module - Command Reference

This document provides a comprehensive reference for all implemented commands in the OATHTokens module, including their parameters and usage examples.

## Table of Contents

- [Core Commands](#core-commands)
  - [Add-OATHToken](#add-oathtoken)
  - [Get-OATHToken](#get-oathtoken)
  - [Remove-OATHToken](#remove-oathtoken)
  - [Set-OATHTokenUser](#set-oathtokenuser)
  - [Set-OATHTokenActive](#set-oathtokenactive)
- [Import/Export Commands](#importexport-commands)
  - [Import-OATHToken](#import-oathtoken)
  - [Export-OATHToken](#export-oathtoken)
- [Utility Commands](#utility-commands)
  - [Get-TOTP](#get-totp)
  - [New-OATHTokenSerial](#new-oathtokenserial)
  - [ConvertTo-Base32](#convertto-base32)
  - [Show-OATHTokenMenu](#show-oathtokenmenu)

## Core Commands

### Add-OATHToken

Adds OATH tokens to Microsoft Entra ID.

#### Syntax

```powershell
Add-OATHToken 
  -SerialNumber <String> 
  -SecretKey <String> 
  [-SecretFormat <String>] 
  [-Manufacturer <String>] 
  [-Model <String>] 
  [<CommonParameters>]
```

#### Parameters

| Parameter | Type | Description | Required | Default |
|-----------|------|-------------|----------|---------|
| SerialNumber | String | The unique serial number of the token | Yes | |
| SecretKey | String | The secret key for the token | Yes | |
| SecretFormat | String | Format of the secret key (Base32, Hex, Text) | No | Base32 |
| Manufacturer | String | Manufacturer of the token | No | "Generic" |
| Model | String | Model of the token | No | "OATH-TOTP" |

#### Examples

```powershell
# Add a token with a Base32 secret
Add-OATHToken -SerialNumber "12345678" -SecretKey "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

# Add a token with a hexadecimal secret
Add-OATHToken -SerialNumber "87654321" -SecretKey "3a085cfcd4618c61dc235c300d7a70c4" -SecretFormat Hex

# Add a token with a text secret
Add-OATHToken -SerialNumber "11223344" -SecretKey "MySecretPassword123" -SecretFormat Text

# Add a token with manufacturer and model details
Add-OATHToken -SerialNumber "YK-12345" -SecretKey "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567" -Manufacturer "Yubico" -Model "YubiKey 5 NFC"
```

### Get-OATHToken

Retrieves OATH tokens from Microsoft Entra ID with various filtering options.

#### Syntax

```powershell
Get-OATHToken 
  [-TokenId <String>] 
  [-SerialNumber <String>] 
  [-UserId <String>] 
  [-AvailableOnly] 
  [-ActivatedOnly] 
  [<CommonParameters>]
```

#### Parameters

| Parameter | Type | Description | Required | Default |
|-----------|------|-------------|----------|---------|
| TokenId | String | ID of a specific token to retrieve | No | |
| SerialNumber | String | Filter tokens by serial number (supports wildcards) | No | |
| UserId | String | Filter tokens by assigned user (ID, UPN, or display name) | No | |
| AvailableOnly | Switch | Return only unassigned tokens | No | False |
| ActivatedOnly | Switch | Return only activated tokens | No | False |

#### Examples

```powershell
# Get all tokens
Get-OATHToken

# Get a specific token by ID
Get-OATHToken -TokenId "00000000-0000-0000-0000-000000000000"

# Get tokens by serial number pattern
Get-OATHToken -SerialNumber "YK*"

# Get tokens assigned to a specific user
Get-OATHToken -UserId "user@example.com"

# Get all unassigned tokens
Get-OATHToken -AvailableOnly

# Get all activated tokens
Get-OATHToken -ActivatedOnly
```

### Remove-OATHToken

Removes OATH tokens from Microsoft Entra ID.

#### Syntax

```powershell
Remove-OATHToken 
  -TokenId <String> 
  [-Force] 
  [<CommonParameters>]
```

#### Parameters

| Parameter | Type | Description | Required | Default |
|-----------|------|-------------|----------|---------|
| TokenId | String | ID of the token to remove | Yes | |
| Force | Switch | Skip confirmation prompt | No | False |

#### Examples

```powershell
# Remove a token with confirmation
Remove-OATHToken -TokenId "00000000-0000-0000-0000-000000000000"

# Remove a token without confirmation
Remove-OATHToken -TokenId "00000000-0000-0000-0000-000000000000" -Force

# Remove multiple tokens
Get-OATHToken -SerialNumber "TEST*" | ForEach-Object { Remove-OATHToken -TokenId $_.id -Force }
```

### Set-OATHTokenUser

Assigns or unassigns an OATH token to/from a user.

#### Syntax

```powershell
Set-OATHTokenUser 
  -TokenId <String> 
  -UserId <String> 
  [<CommonParameters>]

Set-OATHTokenUser 
  -TokenId <String> 
  [-Unassign] 
  [<CommonParameters>]
```

#### Parameters

| Parameter | Type | Description | Required | Default |
|-----------|------|-------------|----------|---------|
| TokenId | String | ID of the token to assign/unassign | Yes | |
| UserId | String | ID, UPN, or display name of the user | Yes (for assignment) | |
| Unassign | Switch | Unassign the token from its current user | No | False |

#### Examples

```powershell
# Assign a token to a user by UPN
Set-OATHTokenUser -TokenId "00000000-0000-0000-0000-000000000000" -UserId "user@example.com"

# Assign a token to a user by ID
Set-OATHTokenUser -TokenId "00000000-0000-0000-0000-000000000000" -UserId "1a2b3c4d-5e6f-7g8h-9i0j-1k2l3m4n5o6p"

# Assign a token to a user by display name
Set-OATHTokenUser -TokenId "00000000-0000-0000-0000-000000000000" -UserId "John Doe"

# Unassign a token from its current user
Set-OATHTokenUser -TokenId "00000000-0000-0000-0000-000000000000" -Unassign
```

### Set-OATHTokenActive

Activates an OATH token using a verification code.

#### Syntax

```powershell
Set-OATHTokenActive 
  -TokenId <String> 
  -UserId <String> 
  -VerificationCode <String> 
  [<CommonParameters>]

Set-OATHTokenActive 
  -TokenId <String> 
  -UserId <String> 
  -Secret <String> 
  [-SecretFormat <String>] 
  [<CommonParameters>]
```

#### Parameters

| Parameter | Type | Description | Required | Default |
|-----------|------|-------------|----------|---------|
| TokenId | String | ID of the token to activate | Yes | |
| UserId | String | ID, UPN, or display name of the user | Yes | |
| VerificationCode | String | Current verification code from the token | Yes (or Secret) | |
| Secret | String | Secret key to auto-generate the verification code | Yes (or VerificationCode) | |
| SecretFormat | String | Format of the secret key (Base32, Hex, Text) | No | Base32 |

#### Examples

```powershell
# Activate a token with a manual verification code
Set-OATHTokenActive -TokenId "00000000-0000-0000-0000-000000000000" -UserId "user@example.com" -VerificationCode "123456"

# Activate a token using its secret key (auto-generates the code)
Set-OATHTokenActive -TokenId "00000000-0000-0000-0000-000000000000" -UserId "user@example.com" -Secret "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

# Activate a token using a hexadecimal secret
Set-OATHTokenActive -TokenId "00000000-0000-0000-0000-000000000000" -UserId "user@example.com" -Secret "3a085cfcd4618c61dc235c300d7a70c4" -SecretFormat Hex
```

## Import/Export Commands

### Import-OATHToken

Imports OATH tokens from a file.

#### Syntax

```powershell
Import-OATHToken 
  -FilePath <String> 
  [-Format <String>] 
  [-SchemaType <String>] 
  [-AssignToUsers] 
  [-Delimiter <Char>] 
  [<CommonParameters>]
```

#### Parameters

| Parameter | Type | Description | Required | Default |
|-----------|------|-------------|----------|---------|
| FilePath | String | Path to the import file | Yes | |
| Format | String | Format of the file (JSON, CSV) | No | JSON |
| SchemaType | String | Schema type for import (Inventory, UserAssignments) | No | Inventory |
| AssignToUsers | Switch | Assign tokens to users during import | No | False |
| Delimiter | Char | Delimiter for CSV files | No | , |

#### Examples

```powershell
# Import tokens from a JSON file
Import-OATHToken -FilePath "tokens.json"

# Import tokens from a CSV file
Import-OATHToken -FilePath "tokens.csv" -Format CSV

# Import tokens and assignments from a JSON file
Import-OATHToken -FilePath "tokens_users.json" -SchemaType UserAssignments

# Import tokens and automatically assign to users
Import-OATHToken -FilePath "tokens_users.json" -SchemaType UserAssignments -AssignToUsers

# Import from a CSV with a tab delimiter
Import-OATHToken -FilePath "tokens.csv" -Format CSV -Delimiter "`t"
```

### Export-OATHToken

Exports OATH tokens to a file.

#### Syntax

```powershell
Export-OATHToken 
  -FilePath <String> 
  [-Format <String>] 
  [-IncludeUsers] 
  [-IncludeSecrets] 
  [-Delimiter <Char>] 
  [<CommonParameters>]
```

#### Parameters

| Parameter | Type | Description | Required | Default |
|-----------|------|-------------|----------|---------|
| FilePath | String | Path to the export file | Yes | |
| Format | String | Format of the file (JSON, CSV) | No | CSV |
| IncludeUsers | Switch | Include user assignment information | No | False |
| IncludeSecrets | Switch | Include token secrets (if available) | No | False |
| Delimiter | Char | Delimiter for CSV files | No | , |

#### Examples

```powershell
# Export all tokens to a CSV file
Export-OATHToken -FilePath "tokens.csv"

# Export all tokens to a JSON file
Export-OATHToken -FilePath "tokens.json" -Format JSON

# Export tokens with user information
Export-OATHToken -FilePath "tokens_users.csv" -IncludeUsers

# Export tokens with secrets (if available)
Export-OATHToken -FilePath "tokens_with_secrets.json" -Format JSON -IncludeSecrets

# Export to a CSV with a tab delimiter
Export-OATHToken -FilePath "tokens.csv" -Delimiter "`t"
```

## Utility Commands

### Get-TOTP

Generates TOTP (Time-based One-Time Password) codes.

#### Syntax

```powershell
Get-TOTP 
  -Secret <String> 
  [-InputFormat <String>] 
  [-TimeStep <Int32>] 
  [-Digits <Int32>] 
  [-TimeOffset <Int32>] 
  [<CommonParameters>]
```

#### Parameters

| Parameter | Type | Description | Required | Default |
|-----------|------|-------------|----------|---------|
| Secret | String | The secret key for TOTP generation | Yes | |
| InputFormat | String | Format of the secret (Base32, Hex, Text) | No | Base32 |
| TimeStep | Int32 | Time interval in seconds | No | 30 |
| Digits | Int32 | Number of digits in the code | No | 6 |
| TimeOffset | Int32 | Time offset in seconds | No | 0 |

#### Examples

```powershell
# Generate a TOTP code from a Base32 secret
Get-TOTP -Secret "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

# Generate a TOTP code from a hexadecimal secret
Get-TOTP -Secret "3a085cfcd4618c61dc235c300d7a70c4" -InputFormat Hex

# Generate a TOTP code from a text secret
Get-TOTP -Secret "MySecretPassword123" -InputFormat Text

# Generate an 8-digit TOTP code
Get-TOTP -Secret "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567" -Digits 8
```

### New-OATHTokenSerial

Generates unique token serial numbers.

#### Syntax

```powershell
New-OATHTokenSerial 
  [-Prefix <String>] 
  [-Format <String>] 
  [-Length <Int32>] 
  [-Count <Int32>] 
  [-CheckExisting] 
  [<CommonParameters>]
```

#### Parameters

| Parameter | Type | Description | Required | Default |
|-----------|------|-------------|----------|---------|
| Prefix | String | Prefix for the serial number | No | "" |
| Format | String | Format of the serial (Numeric, Alphanumeric, Hex) | No | Numeric |
| Length | Int32 | Length of the random part | No | 8 |
| Count | Int32 | Number of serials to generate | No | 1 |
| CheckExisting | Switch | Check against existing serials | No | False |

#### Examples

```powershell
# Generate a numeric serial number
New-OATHTokenSerial

# Generate a serial number with a prefix
New-OATHTokenSerial -Prefix "YK-"

# Generate an alphanumeric serial number
New-OATHTokenSerial -Format Alphanumeric

# Generate a serial number with custom length
New-OATHTokenSerial -Length 12

# Generate multiple serial numbers
New-OATHTokenSerial -Count 5

# Generate a serial number checking for duplicates
New-OATHTokenSerial -CheckExisting
```

### Convert-Base32

Converts a string to Base32 encoding.

#### Syntax

```powershell
Convert-Base32 
  -InputString <String> 
  [-InputFormat <String>] 
  [-NoValidation] 
  [<CommonParameters>]
```

#### Parameters

| Parameter | Type | Description | Required | Default |
|-----------|------|-------------|----------|---------|
| InputString | String | Text string to convert | Yes | |
| InputFormat | String | Format of the input string (Base32, Hex, Text) | No | Hex |
| NoValidation | Switch | Skip validation of the input string | No | False |

#### Examples

```powershell
# Convert a text string to Base32
Convert-Base32 -InputString "MySecretPassword123" -InputFormat Text

# Convert a hexadecimal string to Base32
Convert-Base32 -InputString "3a085cfcd4618c61dc235c300d7a70c4"

# Convert an already Base32-encoded string
Convert-Base32 -InputString "JBSWY3DPEB3W64TMMQ======" -InputFormat Base32
```

And the bulk token processing example should be:

```powershell
# Generate multiple tokens and export to CSV
$tokens = @()
for ($i = 1; $i -le 10; $i++) {
    $serialNumber = New-OATHTokenSerial -Prefix "BULK-" -CheckExisting
    $secret = Convert-Base32 -InputString ([Guid]::NewGuid().ToString()) -InputFormat Text
    $token = Add-OATHToken -SerialNumber $serialNumber -SecretKey $secret
    $tokens += [PSCustomObject]@{
        TokenId = $token.id
        SerialNumber = $serialNumber
        SecretKey = $secret
    }
}

# Export the tokens to a file
$tokens | Export-Csv -Path "bulk_tokens.csv" -NoTypeInformation

```

### Show-OATHTokenMenu

Displays the interactive OATH token management menu.

#### Syntax

```powershell
Show-OATHTokenMenu [<CommonParameters>]
```

#### Examples

```powershell
# Launch the interactive menu
Show-OATHTokenMenu
```

## Advanced Usage Examples

### Automating Token Setup

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

### Bulk Token Processing

```powershell
# Generate multiple tokens and export to CSV
$tokens = @()
for ($i = 1; $i -le 10; $i++) {
    $serialNumber = New-OATHTokenSerial -Prefix "BULK-" -CheckExisting
    $secret = Convert-Base32 -InputString ([Guid]::NewGuid().ToString()) -InputFormat Text
    $token = Add-OATHToken -SerialNumber $serialNumber -SecretKey $secret
    $tokens += [PSCustomObject]@{
        TokenId = $token.id
        SerialNumber = $serialNumber
        SecretKey = $secret
    }
}

# Export the tokens to a file
$tokens | Export-Csv -Path "bulk_tokens.csv" -NoTypeInformation
```