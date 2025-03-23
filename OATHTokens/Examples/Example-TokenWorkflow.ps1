<#
.SYNOPSIS
    Example workflow for OATH token management
.DESCRIPTION
    This script demonstrates a complete end-to-end workflow for OATH token management
    including adding tokens, assigning them to users, and activating them.
.NOTES
    Author: Josh - https://github.com/uniQuk
    Version: 1.1
    Date: 2024-06-20
#>

# Connect to Microsoft Graph with required permissions
if (-not (Get-MgContext)) {
    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
    Connect-MgGraph -Scopes "Policy.ReadWrite.AuthenticationMethod", "Directory.Read.All"
}

# Verify connection
if (-not (Get-MgContext)) {
    Write-Error "Not connected to Microsoft Graph. Please run Connect-MgGraph with appropriate scopes first."
    return
}

# Define test users - using valid test accounts
$users = @(
    "MeganB@n7.uk",
    "LynneR@n7.uk",
    "LidiaH@n7.uk"
)

# Section 1: Adding individual tokens
Write-Host "PART 1: ADDING INDIVIDUAL TOKENS" -ForegroundColor Cyan

# Generate serial numbers with prefix - use a timestamp to ensure uniqueness
# Added time component to make it more unique
$timestamp = Get-Date -Format "yyMMddHHmmss"
$serialNumbers = @(
    "YK-$timestamp-01",
    "YK-$timestamp-02",
    "YK-$timestamp-03"
)

Write-Host "Generated unique serial numbers with timestamp $timestamp" -ForegroundColor Yellow

# Add tokens with different secret formats - using improved error handling
$tokens = @()

try {
    Write-Host "Adding token 1 with Base32 secret..." -ForegroundColor Yellow
    $token1 = Add-OATHToken -SerialNumber $serialNumbers[0] -SecretKey "JBSWY3DPEHPK3PXP" -DisplayName "Token for $($users[0])"
    if ($token1 -and $token1.id) {
        Write-Host "Added token 1 with Base32 secret: $($token1.id)" -ForegroundColor Green
        $tokens += @{ Token = $token1; User = $users[0]; Index = 1; Secret = "JBSWY3DPEHPK3PXP"; Format = "Base32" }
    } else {
        Write-Host "Failed to create token 1" -ForegroundColor Red
    }
} catch {
    Write-Host "Error creating token 1: $_" -ForegroundColor Red
}

try {
    Write-Host "Adding token 2 with Hex secret..." -ForegroundColor Yellow
    $token2 = Add-OATHToken -SerialNumber $serialNumbers[1] -SecretKey "3a085cfcd4618c61dc235c300d7a70c4" -SecretFormat Hex -DisplayName "Token for $($users[1])"
    if ($token2 -and $token2.id) {
        Write-Host "Added token 2 with Hex secret: $($token2.id)" -ForegroundColor Green
        $tokens += @{ Token = $token2; User = $users[1]; Index = 2; Secret = "3a085cfcd4618c61dc235c300d7a70c4"; Format = "Hex" }
    } else {
        Write-Host "Failed to create token 2" -ForegroundColor Red
    }
} catch {
    Write-Host "Error creating token 2: $_" -ForegroundColor Red
}

try {
    Write-Host "Adding token 3 with Text secret..." -ForegroundColor Yellow
    $token3 = Add-OATHToken -SerialNumber $serialNumbers[2] -SecretKey "MySecretPhrase123!" -SecretFormat Text -DisplayName "Token for $($users[2])"
    if ($token3 -and $token3.id) {
        Write-Host "Added token 3 with Text secret: $($token3.id)" -ForegroundColor Green
        $tokens += @{ Token = $token3; User = $users[2]; Index = 3; Secret = "MySecretPhrase123!"; Format = "Text" }
    } else {
        Write-Host "Failed to create token 3" -ForegroundColor Red
    }
} catch {
    Write-Host "Error creating token 3: $_" -ForegroundColor Red
}

# If no tokens were created, handle the error gracefully
if ($tokens.Count -eq 0) {
    Write-Host "`nNo tokens could be created. Skipping assignment and activation steps." -ForegroundColor Red
}

# Section 2: Assigning tokens to users
Write-Host "`nPART 2: ASSIGNING TOKENS TO USERS" -ForegroundColor Cyan

$assignedTokens = @()

foreach ($tokenInfo in $tokens) {
    $token = $tokenInfo.Token
    $user = $tokenInfo.User
    $index = $tokenInfo.Index
    
    try {
        Write-Host "Attempting to assign token $index to $user..." -ForegroundColor Yellow
        
        # First try to get the user directly with Get-MgUser
        $userFound = $false
        try {
            $filter = "userPrincipalName eq '$user'"
            $resolvedUser = Get-MgUser -Filter $filter -ErrorAction Stop
            if ($resolvedUser) {
                $userFound = $true
                Write-Host "Found user: $($resolvedUser.DisplayName)" -ForegroundColor Green
                
                # Use the direct PATCH method to assign the token
                $tokenEndpoint = "https://graph.microsoft.com/beta/directory/authenticationMethodDevices/hardwareOathDevices/$($token.id)"
                $body = @{ userId = $resolvedUser.Id } | ConvertTo-Json
                
                try {
                    Write-Verbose "Assigning token directly with PATCH request"
                    Invoke-MgGraphRequest -Method PATCH -Uri $tokenEndpoint -Body $body -ContentType "application/json"
                    Write-Host "Assigned token $index to $user" -ForegroundColor Green
                    $assignedTokens += $tokenInfo
                }
                catch {
                    Write-Host "Failed to assign token $index : $($_)" -ForegroundColor Red
                }
            }
        }
        catch {
            Write-Verbose "Error finding user: $_"
        }
        
        if (-not $userFound) {
            Write-Host "User not found: $user" -ForegroundColor Red
        }
    } catch {
        Write-Host "Error assigning token $index : $_" -ForegroundColor Red
    }
}

# Section 3: Activating tokens
Write-Host "`nPART 3: ACTIVATING TOKENS" -ForegroundColor Cyan

foreach ($tokenInfo in $assignedTokens) {
    $token = $tokenInfo.Token
    $user = $tokenInfo.User
    $index = $tokenInfo.Index
    $secret = $tokenInfo.Secret
    $format = $tokenInfo.Format
    
    try {
        # For demonstration, we'll use the automatic activation with secret
        Write-Host "Activating token $index for $user with $format secret..." -ForegroundColor Yellow
        $activation = Set-OATHTokenActive -TokenId $token.id -UserId $user -Secret $secret -SecretFormat $format
        
        if ($activation.Success) {
            if ($activation.AlreadyActivated) {
                Write-Host "Token $index was already activated for $user" -ForegroundColor Yellow
            } else {
                Write-Host "Successfully activated token $index for $user" -ForegroundColor Green
            }
        } else {
            Write-Host "Failed to activate token $index : $($activation.Reason)" -ForegroundColor Red
            
            # Try with a generated TOTP code as a fallback
            if ($format -eq "Base32") {
                try {
                    $totpCode = Get-TOTP -Secret $secret
                    Write-Host "Generated TOTP code: $totpCode. Trying manual activation..." -ForegroundColor Yellow
                    $manualActivation = Set-OATHTokenActive -TokenId $token.id -UserId $user -VerificationCode $totpCode
                    
                    if ($manualActivation.Success) {
                        Write-Host "Successfully activated token $index with manual TOTP code" -ForegroundColor Green
                    } else {
                        Write-Host "Manual activation also failed: $($manualActivation.Reason)" -ForegroundColor Red
                    }
                } catch {
                    Write-Host "Error generating TOTP code: $_" -ForegroundColor Red
                }
            }
        }
    } catch {
        Write-Host "Error activating token $index : $_" -ForegroundColor Red
    }
}

# Section 4: Demonstrate validation features
Write-Host "`nPART 4: DEMONSTRATING VALIDATION FEATURES" -ForegroundColor Cyan

# Create sample JSON with both valid and invalid data
$jsonPath = Join-Path -Path $PWD -ChildPath "sample_tokens.json"

$jsonContent = @"
{
  "inventory": [
    {
      "serialNumber": "VALID-123456",
      "secretKey": "JBSWY3DPEHPK3PXP",
      "manufacturer": "Yubico",
      "assignTo": {
        "id": "$($users[0])"
      }
    },
    {
      "serialNumber": "INVALID-TOO-LONG-123456789012345678901234567890",
      "secretKey": "INVALID-NOT-BASE32!@#",
      "hashFunction": "invalid-hash-function"
    },
    {
      "serialNumber": "VALID-WITH-USER",
      "secretKey": "JBSWY3DPEHPK3PXP",
      "assignTo": {
        "id": "nonexistent-user@example.com"
      }
    }
  ]
}
"@

Set-Content -Path $jsonPath -Value $jsonContent
Write-Host "Created sample JSON file with mixed valid/invalid data: $jsonPath" -ForegroundColor Yellow

# Test validation
$validation = Import-OATHToken -FilePath $jsonPath -TestOnly -DetectSchema
Write-Host "Validation result success: $($validation.Success)" -ForegroundColor ($validation.Success ? "Green" : "Red")
Write-Host "Total processed: $($validation.TotalProcessed)" -ForegroundColor White
Write-Host "Valid entries: $($validation.Valid)" -ForegroundColor Green
Write-Host "Invalid entries: $($validation.Invalid)" -ForegroundColor Red

if ($validation.ValidationIssues.Count -gt 0) {
    Write-Host "`nValidation issues:" -ForegroundColor Yellow
    $validation.ValidationIssues | ForEach-Object { Write-Host "- $_" -ForegroundColor Yellow }
}

if ($validation.NonexistentUsers.Count -gt 0) {
    Write-Host "`nNonexistent users:" -ForegroundColor Yellow
    $validation.NonexistentUsers | ForEach-Object { Write-Host "- $_" -ForegroundColor Yellow }
}

# Section 5: Clean up (optional)
Write-Host "`nPART 5: CLEANUP (OPTIONAL)" -ForegroundColor Cyan
$response = Read-Host "Do you want to remove the created tokens? (y/n)"

if ($response -eq "y") {
    foreach ($tokenInfo in $tokens) {
        $token = $tokenInfo.Token
        try {
            if ($token -and $token.id) {
                Write-Host "Removing token $($tokenInfo.Index)..." -ForegroundColor Yellow
                $result = Remove-OATHToken -TokenId $token.id -Force -UnassignFirst
                if ($result) {
                    Write-Host "Successfully removed token $($tokenInfo.Index)" -ForegroundColor Green
                } else {
                    Write-Host "Failed to remove token $($tokenInfo.Index)" -ForegroundColor Red
                }
            }
        } catch {
            Write-Host "Error removing token $($tokenInfo.Index): $_" -ForegroundColor Red
        }
    }
    
    if (Test-Path -Path $jsonPath) {
        Remove-Item -Path $jsonPath -Force
        Write-Host "Removed test JSON file" -ForegroundColor Green
    }
    
    Write-Host "Cleanup completed." -ForegroundColor Green
} else {
    Write-Host "Tokens were not removed. You can manually remove them later." -ForegroundColor Yellow
}

# Summary
Write-Host "`nWORKFLOW SUMMARY" -ForegroundColor Cyan
Write-Host "Added $($tokens.Count) tokens with different secret formats" -ForegroundColor White
Write-Host "Assigned $($assignedTokens.Count) tokens to users" -ForegroundColor White
Write-Host "Demonstrated validation features" -ForegroundColor White
Write-Host "Workflow complete!" -ForegroundColor Green
