# OATH Token Management for Microsoft Entra ID - Quick Start Guide

This quick start guide provides examples of the most common tasks using the OATH Tokens PowerShell module.

## Prerequisites

Before you begin, ensure you have:

1. Installed the module: `Install-Module -Name OATHTokens`
2. Connected to Microsoft Graph with appropriate permissions:
   ```powershell
   Connect-MgGraph -Scopes "Policy.ReadWrite.AuthenticationMethod","Directory.Read.All"
   ```

## Basic Token Management

### Viewing Tokens

```powershell
# Get all tokens
Get-OATHToken

# Get only available (unassigned) tokens
Get-OATHToken -AvailableOnly

# Get tokens assigned to a specific user
Get-OATHToken -UserId "user@contoso.com"

# Find tokens by serial number (supports wildcards)
Get-OATHToken -SerialNumber "YK-*"
```

### Adding Individual Tokens

```powershell
# Add a token with Base32 encoded secret
Add-OATHToken -SerialNumber "YK-12345678" -SecretKey "JBSWY3DPEHPK3PXP"

# Add a token with hexadecimal secret
Add-OATHToken -SerialNumber "YK-87654321" -SecretKey "3a085cfcd4618c61dc235c300d7a70c4" -SecretFormat Hex

# Add a token with custom manufacturer and model
Add-OATHToken -SerialNumber "FT-12345678" -SecretKey "JBSWY3DPEHPK3PXP" -Manufacturer "Feitian" -Model "K9"
```

### Assigning Tokens to Users

```powershell
# Assign a token to a user by token ID
Set-OATHTokenUser -TokenId "00000000-0000-0000-0000-000000000000" -UserId "user@contoso.com"

# Assign a token to a user by serial number
Set-OATHTokenUser -SerialNumber "YK-12345678" -UserId "user@contoso.com"

# Unassign a token from its current user
Set-OATHTokenUser -TokenId "00000000-0000-0000-0000-000000000000" -Unassign
```

### Activating Tokens

```powershell
# Activate a token with a verification code from the token
Set-OATHTokenActive -TokenId "00000000-0000-0000-0000-000000000000" -UserId "user@contoso.com" -VerificationCode "123456"

# Activate a token using its secret key (automatic TOTP generation)
Set-OATHTokenActive -TokenId "00000000-0000-0000-0000-000000000000" -UserId "user@contoso.com" -Secret "JBSWY3DPEHPK3PXP"

# Activate a token with a hexadecimal secret
Set-OATHTokenActive -TokenId "00000000-0000-0000-0000-000000000000" -UserId "user@contoso.com" -Secret "3a085cfcd4618c61dc235c300d7a70c4" -SecretFormat Hex
```

### Removing Tokens

```powershell
# Remove a token by ID
Remove-OATHToken -TokenId "00000000-0000-0000-0000-000000000000"

# Remove a token by serial number
Remove-OATHToken -SerialNumber "YK-12345678"

# Remove an assigned token by automatically unassigning it first
Remove-OATHToken -TokenId "00000000-0000-0000-0000-000000000000" -UnassignFirst

# Remove all available tokens (without asking for confirmation)
Get-OATHToken -AvailableOnly | Remove-OATHToken -Force
```

## Bulk Operations

### Importing Tokens

```powershell
# Import tokens from a JSON file
Import-OATHToken -FilePath "tokens.json"

# Import tokens from a CSV file
Import-OATHToken -FilePath "tokens.csv" -Format CSV

# Import tokens from a tab-delimited file
Import-OATHToken -FilePath "tokens.txt" -Format CSV -Delimiter "`t"

# Import tokens with user assignments
Import-OATHToken -FilePath "tokens_users.json" -SchemaType UserAssignments -AssignToUsers
```

### Validating Before Import

```powershell
# Validate a JSON file without importing any tokens
Import-OATHToken -FilePath "tokens.json" -TestOnly

# Auto-detect schema and validate
Import-OATHToken -FilePath "tokens.json" -DetectSchema -TestOnly

# Remove duplicates when validating
Import-OATHToken -FilePath "tokens.json" -RemoveDuplicates -TestOnly
```

### Exporting Tokens

```powershell
# Export all tokens to CSV
Export-OATHToken -FilePath "tokens.csv"

# Export tokens to JSON
Export-OATHToken -FilePath "tokens.json" -Format JSON

# Export only assigned tokens to CSV
Get-OATHToken -AssignedOnly | Export-OATHToken -FilePath "assigned_tokens.csv"
```

## Advanced Features

### Testing TOTP Generation

```powershell
# Generate a TOTP code from a secret
Get-TOTP -Secret "JBSWY3DPEHPK3PXP"

# Generate a TOTP code from a hexadecimal secret
Get-TOTP -Secret "3a085cfcd4618c61dc235c300d7a70c4" -InputFormat Hex

# Generate multiple time steps (for troubleshooting)
Get-TOTP -Secret "JBSWY3DPEHPK3PXP" -Window 3
```

### Base32 Encoding Utilities

```powershell
# Convert a hexadecimal string to Base32
Convert-Base32 -InputString "3a085cfcd4618c61dc235c300d7a70c4" -InputFormat Hex

# Convert plain text to Base32
Convert-Base32 -InputString "MySecretKey" -InputFormat Text
```

### Generating Serial Numbers

```powershell
# Generate a random numeric serial number
New-OATHTokenSerial

# Generate an alphanumeric serial with prefix
New-OATHTokenSerial -Prefix "YK-" -Format Alphanumeric

# Generate 10 unique serial numbers
New-OATHTokenSerial -Count 10 -Format Hexadecimal
```

## Complete Workflows

### Complete Token Lifecycle

```powershell
# 1. Generate a serial number
$serial = New-OATHTokenSerial -Prefix "YK-"

# 2. Generate a random secret key
$secretBytes = New-Object byte[] 20
[Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($secretBytes)
$secretHex = ($secretBytes | ForEach-Object { $_.ToString("X2") }) -join ""
$secretBase32 = Convert-Base32 -InputString $secretHex -InputFormat Hex

# 3. Add the token
$token = Add-OATHToken -SerialNumber $serial -SecretKey $secretBase32

# 4. Assign to a user
$assignResult = Set-OATHTokenUser -TokenId $token.id -UserId "user@contoso.com"

# 5. Activate the token (with auto-generated TOTP)
if ($assignResult.Success) {
    $activateResult = Set-OATHTokenActive -TokenId $token.id -UserId "user@contoso.com" -Secret $secretBase32
}

# Output results
[PSCustomObject]@{
    SerialNumber = $serial
    SecretKey = $secretBase32
    TokenId = $token.id
    Assignment = $assignResult
    Activation = $activateResult
}
```

### Bulk Import with Validation

```powershell
# 1. First validate the import file
$validationResult = Import-OATHToken -FilePath "tokens.json" -TestOnly -DetectSchema

# 2. If validation passes, proceed with import
if ($validationResult.Success) {
    Write-Host "Validation successful! Proceeding with import..." -ForegroundColor Green
    $importResult = Import-OATHToken -FilePath "tokens.json" -SchemaType $validationResult.SchemaType -AssignToUsers
    
    # 3. Report import results
    Write-Host "Import completed:" -ForegroundColor Cyan
    Write-Host "  - Added: $($importResult.Added.Count) tokens" -ForegroundColor Green
    Write-Host "  - Failed: $($importResult.Failed.Count) tokens" -ForegroundColor Red
    Write-Host "  - Assigned: $($importResult.AssignmentSuccesses.Count) tokens" -ForegroundColor Green
    Write-Host "  - Activated: $($importResult.ActivationSuccesses.Count) tokens" -ForegroundColor Green
}
else {
    Write-Host "Validation failed with $($validationResult.ValidationIssues.Count) issues:" -ForegroundColor Red
    $validationResult.ValidationIssues | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}
```

## Interactive Menu

For a guided experience, you can use the interactive menu:

```powershell
Show-OATHTokenMenu
```

This presents a text-based menu system that walks you through common token management tasks.
