<#
.SYNOPSIS
    Simple interactive OATH token management workflow example
.DESCRIPTION
    This script demonstrates a simple end-to-end workflow for OATH token management
    with better user interaction and error handling.
.NOTES
    Author: Josh - https://github.com/uniQuk
    Version: 1.1
    Date: 2024-06-20
#>

# Set error action preference
$ErrorActionPreference = "Stop"

# Set styles for command output
$titleStyle = @{ForegroundColor = "Cyan"}
$successStyle = @{ForegroundColor = "Green"}
$errorStyle = @{ForegroundColor = "Red"}
$warningStyle = @{ForegroundColor = "Yellow"}
$infoStyle = @{ForegroundColor = "White"}
$inputStyle = @{ForegroundColor = "Magenta"}

Write-Host "`n=== OATH Token Management Example Workflow ===`n" @titleStyle

# Step 1: Connect to Microsoft Graph if not already connected
Write-Host "Step 1: Connecting to Microsoft Graph..." @titleStyle
try {
    $context = Get-MgContext -ErrorAction SilentlyContinue
    if (-not $context) {
        Write-Host "  Not connected to Microsoft Graph. Connecting now..." @infoStyle
        Connect-MgGraph -Scopes "Policy.ReadWrite.AuthenticationMethod", "Directory.Read.All"
    } else {
        $hasAllScopes = $true
        foreach ($scope in @("Policy.ReadWrite.AuthenticationMethod", "Directory.Read.All")) {
            if ($context.Scopes -notcontains $scope) {
                $hasAllScopes = $false
                break
            }
        }
        
        if (-not $hasAllScopes) {
            Write-Host "  Connected but missing required scopes. Reconnecting..." @warningStyle
            Disconnect-MgGraph
            Connect-MgGraph -Scopes "Policy.ReadWrite.AuthenticationMethod", "Directory.Read.All"
        } else {
            Write-Host "  Already connected with required scopes." @successStyle
        }
    }
} catch {
    Write-Host "  Error connecting to Microsoft Graph: $_" @errorStyle
    exit
}

# Step 2: Generate a unique token serial number
Write-Host "`nStep 2: Generate a unique token serial number" @titleStyle
$prefix = Read-Host -Prompt "  Enter a prefix for the serial number (or press Enter for 'DEMO-')"
if ([string]::IsNullOrWhiteSpace($prefix)) {
    $prefix = "DEMO-"
}

try {
    $serialNumber = New-OATHTokenSerial -Prefix $prefix -Format Alphanumeric -CheckExisting
    Write-Host "  Generated serial number: $serialNumber" @successStyle
} catch {
    Write-Host "  Error generating serial number: $_" @errorStyle
    exit
}

# Step 3: Generate a secure secret key
Write-Host "`nStep 3: Generate a secure secret key" @titleStyle
try {
    # Generate a random 160-bit (20-byte) secret key
    $secretBytes = [byte[]]::new(20)
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($secretBytes)
    
    # Convert to hex and Base32
    $hexSecret = ($secretBytes | ForEach-Object { $_.ToString("X2") }) -join ""
    $base32Secret = Convert-Base32 -InputString $hexSecret -InputFormat Hex
    
    Write-Host "  Generated hex secret key: $hexSecret" @infoStyle
    Write-Host "  Generated Base32 secret: $base32Secret" @successStyle
} catch {
    Write-Host "  Error generating secret key: $_" @errorStyle
    exit
}

# Step 4: Add the token to the system
Write-Host "`nStep 4: Add the token to the system" @titleStyle

# Check if token already exists
try {
    $existingTokens = Get-OATHToken -SerialNumber $serialNumber
    if ($existingTokens -and $existingTokens.Count -gt 0) {
        Write-Host "  Token with serial number $serialNumber already exists with ID: $($existingTokens[0].Id)" @warningStyle
        $response = Read-Host "  Do you want to continue anyway? (Y/N)"
        if ($response -ne "Y" -and $response -ne "y") {
            Write-Host "  Operation canceled by user." @infoStyle
            exit
        }
    } else {
        Write-Host "  No existing token found with serial number: $serialNumber. Proceeding with creation." @infoStyle
    }
} catch {
    Write-Host "  Error checking for existing token: $_" @warningStyle
}

# Add the token
try {
    Write-Host "  Adding token to the system..." @infoStyle
    $token = Add-OATHToken -SerialNumber $serialNumber -SecretKey $base32Secret -DisplayName "Example Token"
    
    if ($token -and $token.id) {
        Write-Host "  Successfully added token with ID: $($token.id)" @successStyle
        
        # Display token details
        Write-Host "  Token details:" @infoStyle
        Write-Host ""
        $token | Format-List Id, SerialNumber, DisplayName, Status, AssignedToName
        Write-Host ""
    } else {
        throw "Token creation failed. No token ID returned."
    }
} catch {
    Write-Host "  Error adding token: $_" @errorStyle
    exit
}

# Step 5: Find a user to assign the token to
Write-Host "`nStep 5: Find a user to assign the token to" @titleStyle
$userId = Read-Host "  Enter a user identifier (UPN, name, etc.) or press Enter to skip assignment"

if (-not [string]::IsNullOrWhiteSpace($userId)) {
    try {
        Write-Host "  Looking up user: $userId" @infoStyle
        
        # Use Get-MgUser directly instead of relying on Get-MgUserByIdentifier
        $filter = "userPrincipalName eq '$userId'"
        $user = Get-MgUser -Filter $filter -ErrorAction Stop
        
        if (-not $user) {
            # Try by display name as a fallback
            $filter = "displayName eq '$userId'"
            $user = Get-MgUser -Filter $filter -ErrorAction Stop
        }
        
        if ($user) {
            Write-Host "  Found user:" @successStyle
            Write-Host "    Display Name: $($user.DisplayName)" @infoStyle
            Write-Host "    UPN: $($user.UserPrincipalName)" @infoStyle
            Write-Host "    ID: $($user.Id)" @infoStyle
            Write-Host ""
            
            # Step 6: Assign the token to the user
            Write-Host "`nStep 6: Assign the token to the user" @titleStyle
            try {
                Write-Host "  Assigning token to user..." @infoStyle
                $assignResult = Set-OATHTokenUser -TokenId $token.id -UserId $user.Id
                
                if ($assignResult.Success) {
                    Write-Host "  Successfully assigned token to user" @successStyle
                } else {
                    throw "Assignment failed: $($assignResult.Reason)"
                }
            } catch {
                Write-Host "  Error assigning token: $_" @errorStyle
                # Continue to next step even if assignment fails
            }
            
            # Step 7: Activate the token
            Write-Host "`nStep 7: Activate the token" @titleStyle
            try {
                # Wait a moment for assignment to propagate
                Write-Host "  Waiting for token assignment to propagate..." @infoStyle
                Start-Sleep -Seconds 2
                
                # Verify assignment
                $assignedToken = Get-OATHToken -TokenId $token.id
                if ($assignedToken.AssignedToId -eq $user.Id) {
                    Write-Host "  Token is properly assigned to $($user.DisplayName)" @successStyle
                    
                    # Generate TOTP code
                    Write-Host "  Generating TOTP code from the secret..." @infoStyle
                    $totpCode = Get-TOTP -Secret $base32Secret
                    Write-Host "  Current TOTP code: $totpCode" @successStyle
                    Write-Host "  This code will change every 30 seconds" @infoStyle
                    
                    # Prompt for activation
                    $activateNow = Read-Host "  Do you want to activate the token now? (Y/N)"
                    if ($activateNow -eq "Y" -or $activateNow -eq "y") {
                        Write-Host "  Activating token with generated TOTP code..." @infoStyle
                        try {
                            Write-Host "  Sending direct API activation request with code: $totpCode" @infoStyle
                            $activateResult = Set-OATHTokenActive -TokenId $token.id -UserId $user.Id -VerificationCode $totpCode
                            
                            if ($activateResult.Success) {
                                Write-Host "  Successfully activated token using direct API call!" @successStyle
                            } else {
                                Write-Host "  Activation failed: $($activateResult.Reason)" @errorStyle
                                
                                # Try alternative activation with the secret
                                Write-Host "  Trying alternative activation method with secret..." @warningStyle
                                $altActivateResult = Set-OATHTokenActive -TokenId $token.id -UserId $user.Id -Secret $base32Secret
                                
                                if ($altActivateResult.Success) {
                                    Write-Host "  Successfully activated token using auto-generated TOTP!" @successStyle
                                } else {
                                    Write-Host "  Alternative activation also failed: $($altActivateResult.Reason)" @errorStyle
                                }
                            }
                        } catch {
                            Write-Host "  Error during activation: $_" @errorStyle
                        }
                    } else {
                        Write-Host "  Token activation skipped by user." @infoStyle
                    }
                } else {
                    Write-Host "  Token assignment verification failed. Current status: $($assignedToken.Status)" @warningStyle
                }
            } catch {
                Write-Host "  Error during token activation process: $_" @errorStyle
            }
        } else {
            Write-Host "  User not found: $userId" @errorStyle
        }
    } catch {
        Write-Host "  Error looking up user: $_" @errorStyle
    }
} else {
    Write-Host "  User assignment skipped." @infoStyle
}

# Step 8: Check token status
Write-Host "`nStep 8: Check token status" @titleStyle
try {
    Write-Host "  Waiting for status changes to propagate..." @infoStyle
    Start-Sleep -Seconds 2
    
    $finalToken = Get-OATHToken -TokenId $token.id
    Write-Host "  Current token status: $($finalToken.Status)" @successStyle
    if ($finalToken.AssignedToName) {
        Write-Host "  Assigned to: $($finalToken.AssignedToName)" @successStyle
    }
} catch {
    Write-Host "  Error checking token status: $_" @errorStyle
}

# Step 9: Clean up
Write-Host "`nStep 9: Clean up" @titleStyle
$removeToken = Read-Host "  Do you want to remove the demo token? (Y/N)"

if ($removeToken -eq "Y" -or $removeToken -eq "y") {
    try {
        Write-Host "  Removing token with ID: $($token.id)..." @infoStyle
        $removeResult = Remove-OATHToken -TokenId $token.id -Force -UnassignFirst
        
        if ($removeResult) {
            Write-Host "  Token successfully removed from the system." @successStyle
        } else {
            Write-Host "  Failed to remove token." @errorStyle
        }
    } catch {
        Write-Host "  Error removing token: $_" @errorStyle
    }
} else {
    Write-Host "  Token will remain in the system with ID: $($token.id)" @infoStyle
}

Write-Host "`nWorkflow completed!" @titleStyle
