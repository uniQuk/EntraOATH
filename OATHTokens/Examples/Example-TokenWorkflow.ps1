<#
.SYNOPSIS
    Example workflow for OATH token management
.DESCRIPTION
    Demonstrates a complete workflow for adding, assigning, activating, and managing OATH tokens
    using the OATHTokens module.
.NOTES
    This script is provided as an example of how to use the OATHTokens module 
    for common token management tasks.
#>

# Import the module - use a relative path for the example
$modulePath = Join-Path -Path $PSScriptRoot -ChildPath ".."
Import-Module -Name $modulePath -Force -Verbose

# Connect to Microsoft Graph if not already connected
if (-not (Get-MgContext)) {
    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow
    Connect-MgGraph -Scopes "Policy.ReadWrite.AuthenticationMethod","Directory.Read.All"
}

Write-Host "=== OATH Token Management Example Workflow ===" -ForegroundColor Cyan

#region Step 1: Generate a unique token serial number
Write-Host "`nStep 1: Generate a unique token serial number" -ForegroundColor Green

# Generate a serial number for our new token
$serialNumber = New-OATHTokenSerial -Prefix "DEMO-" -Format Alphanumeric -CheckExisting
Write-Host "Generated serial number: $serialNumber" -ForegroundColor Yellow

#endregion

#region Step 2: Generate a secure secret key
Write-Host "`nStep 2: Generate a secure secret key" -ForegroundColor Green

# Generate a random secret key (32 hexadecimal characters)
$hexChars = "0123456789ABCDEF"
$secretKey = -join (1..32 | ForEach-Object { $hexChars[(Get-Random -Minimum 0 -Maximum $hexChars.Length)] })
Write-Host "Generated hex secret key: $secretKey" -ForegroundColor Yellow

# Create a proper Base32 string for the secret
# Base32 uses characters A-Z and 2-7
$base32Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
$base32Secret = -join (1..32 | ForEach-Object { $base32Chars[(Get-Random -Minimum 0 -Maximum $base32Chars.Length)] })
Write-Host "Generated Base32 secret: $base32Secret" -ForegroundColor Yellow

# Load the TOTP module if needed for other operations
$totpPath = Join-Path $modulePath "Public\Utility\TOTP.ps1"
if (Test-Path $totpPath) {
    . $totpPath
}

#endregion

#region Step 3: Add the token to the system
Write-Host "`nStep 3: Add the token to the system" -ForegroundColor Green

# First, check if we have any tokens with the same serial number (should be none)
$existingToken = Get-OATHToken -SerialNumber $serialNumber

# Fix the false positive detection by properly checking the existingToken result
if ($existingToken -and $existingToken.SerialNumber -eq $serialNumber) {
    Write-Host "Found existing token with the same serial number: $serialNumber" -ForegroundColor Red
    Write-Host "Token details: ID=$($existingToken.Id), Status=$($existingToken.Status)" -ForegroundColor Red
    Write-Host "Generating a new serial number..." -ForegroundColor Yellow
    $serialNumber = New-OATHTokenSerial -Prefix "DEMO-" -Format Alphanumeric -CheckExisting
    Write-Host "New serial number: $serialNumber" -ForegroundColor Yellow
}
else {
    # If we get here, there was no token with this serial number
    Write-Host "No existing token found with serial number: $serialNumber. Proceeding with creation." -ForegroundColor Green
}

# Create a token object
$token = @{
    serialNumber = $serialNumber
    secretKey = $base32Secret  # Now using the proper Base32 secret
    secretFormat = "base32"    # Changed to Base32 format
    manufacturer = "Example Corp"
    model = "Demo YubiKey"
    displayName = "Demo Token ($serialNumber)"
    timeIntervalInSeconds = 30
    hashFunction = "hmacsha1"
}

Write-Host "Adding token to the system..." -ForegroundColor Yellow
$addedToken = Add-OATHToken -Token $token

if ($addedToken) {
    Write-Host "Successfully added token with ID: $($addedToken.id)" -ForegroundColor Green
    $tokenId = $addedToken.id
}
else {
    Write-Host "Failed to add token. Exiting example." -ForegroundColor Red
    exit
}

# Retrieve and display the token
$retrievedToken = Get-OATHToken -TokenId $tokenId
Write-Host "Token details:" -ForegroundColor Yellow
$retrievedToken | Format-List

#endregion

#region Step 4: Find a user to assign the token to
Write-Host "`nStep 4: Find a user to assign the token to" -ForegroundColor Green

# Prompt for a user identifier (UPN, display name, etc.)
$userIdentifier = Read-Host "Enter a user identifier (UPN, name, etc.) or press Enter to skip assignment"

if (-not [string]::IsNullOrWhiteSpace($userIdentifier)) {
    # Look up the user
    Write-Host "Looking up user: $userIdentifier" -ForegroundColor Yellow
    $user = Get-MgUser -Filter "userPrincipalName eq '$userIdentifier'" -ErrorAction SilentlyContinue
    
    if (-not $user) {
        # Try to search by display name if UPN fails
        $user = Get-MgUser -Filter "startswith(displayName,'$userIdentifier')" -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    
    if ($user) {
        Write-Host "Found user:" -ForegroundColor Green
        Write-Host "  Display Name: $($user.displayName)" -ForegroundColor Yellow
        Write-Host "  UPN: $($user.userPrincipalName)" -ForegroundColor Yellow
        Write-Host "  ID: $($user.id)" -ForegroundColor Yellow
        
        #region Step 5: Assign the token to the user
        Write-Host "`nStep 5: Assign the token to the user" -ForegroundColor Green
        
        Write-Host "Assigning token to user..." -ForegroundColor Yellow
        $assignResult = Set-OATHTokenUser -TokenId $tokenId -UserId $user.id
        
        if ($assignResult) {
            Write-Host "Successfully assigned token to user" -ForegroundColor Green
            
            #region Step 6: Activate the token
            Write-Host "`nStep 6: Activate the token" -ForegroundColor Green
            
            # Wait longer for the assignment to propagate in Microsoft Graph
            Write-Host "Waiting for token assignment to propagate..." -ForegroundColor Yellow
            Start-Sleep -Seconds 10
            
            # Verify the token is properly assigned before attempting activation
            $assignedToken = Get-OATHToken -TokenId $tokenId
            if ($assignedToken -and $assignedToken.AssignedToName -match $user.displayName) {
                Write-Host "Token is properly assigned to $($assignedToken.AssignedToName)" -ForegroundColor Green
                $tokenAssigned = $true
            }
            else {
                Write-Host "Token assignment verification failed. Current status: $($assignedToken.Status)" -ForegroundColor Yellow
                Write-Host "Assigned to: $($assignedToken.AssignedToName)" -ForegroundColor Yellow
                
                # Try to re-assign the token
                Write-Host "Trying to re-assign the token..." -ForegroundColor Yellow
                $reassignResult = Set-OATHTokenUser -TokenId $tokenId -UserId $user.id
                if ($reassignResult) {
                    Write-Host "Re-assignment successful. Waiting for propagation..." -ForegroundColor Green
                    Start-Sleep -Seconds 10
                    $tokenAssigned = $true
                }
                else {
                    Write-Host "Re-assignment failed. Will still attempt activation." -ForegroundColor Red
                    $tokenAssigned = $false
                }
            }
            
            # Generate a TOTP code using our implementation
            Write-Host "Generating TOTP code from the secret..." -ForegroundColor Yellow
            try {
                # Make sure we have a valid Base32 secret before continuing
                if (-not [regex]::IsMatch($base32Secret, '^[A-Z2-7]+=*$')) {
                    Write-Host "Current secret is not valid Base32. Generating a new one..." -ForegroundColor Yellow
                    $base32Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
                    $base32Secret = -join (1..32 | ForEach-Object { $base32Chars[(Get-Random -Minimum 0 -Maximum $base32Chars.Length)] })
                    Write-Host "New Base32 secret: $base32Secret" -ForegroundColor Yellow
                }
                
                # Use Get-TOTP directly without any additional parameters
                $totpCode = Get-TOTP -Secret $base32Secret -InputFormat Base32
                Write-Host "Current TOTP code: $totpCode" -ForegroundColor Cyan
                Write-Host "This code will change every 30 seconds" -ForegroundColor Yellow
            }
            catch {
                Write-Host "Error generating TOTP code: $_" -ForegroundColor Red
                Write-Host "Generating a simpler Base32 secret and new TOTP code..." -ForegroundColor Yellow
                
                # Generate a simpler Base32 string to avoid any issues
                $base32Secret = "JBSWY3DPEB3W64TMMQQHGZLEORZHKIDUMVZXIYLE"
                try {
                    $totpCode = Get-TOTP -Secret $base32Secret -InputFormat Base32
                    Write-Host "Current TOTP code: $totpCode" -ForegroundColor Cyan
                }
                catch {
                    Write-Host "Still couldn't generate TOTP code. Using fallback code 123456" -ForegroundColor Red
                    $totpCode = "123456"
                }
            }
            
            $activateNow = Read-Host "Do you want to activate the token now? (Y/N)"
            if ($activateNow -eq "Y") {
                Write-Host "Activating token with generated TOTP code..." -ForegroundColor Yellow
                
                # Always attempt activation regardless of assignment status check
                try {
                    # Try with verification code first
                    $activateEndpoint = "https://graph.microsoft.com/beta/users/$($user.id)/authentication/hardwareOathMethods/$tokenId/activate"
                    $activateBody = @{
                        verificationCode = $totpCode
                    } | ConvertTo-Json
                    
                    Write-Host "Sending direct API activation request with code: $totpCode" -ForegroundColor Cyan
                    Invoke-MgGraphRequest -Method POST -Uri $activateEndpoint -Body $activateBody -ContentType "application/json"
                    Write-Host "Successfully activated token using direct API call!" -ForegroundColor Green
                    $activationSuccessful = $true
                }
                catch {
                    Write-Host "Direct activation failed: $_" -ForegroundColor Red
                    
                    Write-Host "Trying with Set-OATHTokenActive cmdlet..." -ForegroundColor Yellow
                    try {
                        $activateResult = Set-OATHTokenActive -TokenId $tokenId -UserId $user.id -VerificationCode $totpCode
                        
                        if ($activateResult) {
                            Write-Host "Successfully activated token with Set-OATHTokenActive!" -ForegroundColor Green
                            $activationSuccessful = $true
                        }
                        else {
                            throw "Set-OATHTokenActive returned false"
                        }
                    }
                    catch {
                        Write-Host "Cmdlet activation failed: $_" -ForegroundColor Red
                        $activationSuccessful = $false
                    }
                }
                
                # If all activation attempts failed, provide troubleshooting info
                if (-not $activationSuccessful) {
                    Write-Host "`nActivation troubleshooting information:" -ForegroundColor Magenta
                    Write-Host "- Token may still be in 'available' status due to propagation delay" -ForegroundColor Yellow
                    Write-Host "- TOTP code may have expired during propagation" -ForegroundColor Yellow
                    Write-Host "- Try manually activating later with:" -ForegroundColor Yellow
                    Write-Host "  Set-OATHTokenActive -TokenId $tokenId -UserId $($user.id) -VerificationCode <new-code>" -ForegroundColor Cyan
                }
            }
            else {
                Write-Host "Skipping activation." -ForegroundColor Yellow
            }
            #endregion
        }
        else {
            Write-Host "Failed to assign token to user." -ForegroundColor Red
        }
        #endregion
    }
    else {
        Write-Host "User not found. Skipping assignment." -ForegroundColor Red
    }
}
else {
    Write-Host "No user specified. Skipping assignment." -ForegroundColor Yellow
}

#endregion

#region Step 7: Check token status
Write-Host "`nStep 7: Check token status" -ForegroundColor Green

# Give time for activation to propagate if we attempted it
if ($activateNow -eq "Y") {
    Write-Host "Waiting for status changes to propagate..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
}

$updatedToken = Get-OATHToken -TokenId $tokenId
Write-Host "Current token status: $($updatedToken.Status)" -ForegroundColor Yellow
Write-Host "Assigned to: $($updatedToken.AssignedToName)" -ForegroundColor Yellow

# Additional diagnostic information
if ($updatedToken.Status -eq "available" -and -not [string]::IsNullOrEmpty($updatedToken.AssignedToName)) {
    Write-Host "Note: Token shows as 'available' but has user assignment - this indicates a propagation delay" -ForegroundColor Yellow
}

#endregion

#region Step 8: Clean up
Write-Host "`nStep 8: Clean up" -ForegroundColor Green

$removeNow = Read-Host "Do you want to remove the demo token? (Y/N)"
if ($removeNow -eq "Y") {
    Write-Host "Removing token..." -ForegroundColor Yellow
    $removeResult = Remove-OATHToken -TokenId $tokenId -Force
    
    if ($removeResult) {
        Write-Host "Successfully removed token." -ForegroundColor Green
    }
    else {
        Write-Host "Failed to remove token." -ForegroundColor Red
    }
}
else {
    Write-Host "Token will remain in the system with ID: $tokenId" -ForegroundColor Yellow
}

#endregion

Write-Host "`nExample workflow complete!" -ForegroundColor Cyan
