<#
.SYNOPSIS
    Displays the main OATH token management menu
.DESCRIPTION
    Presents a text-based menu interface for managing OATH tokens in Microsoft Entra ID.
    Provides options for listing, adding, removing, and managing tokens.
.PARAMETER DefaultAction
    The default action to perform if no menu selection is made. Valid values are Main, Get, Add, Remove.
.PARAMETER NonInteractive
    Run in non-interactive mode. Requires DefaultAction to be specified.
.EXAMPLE
    Show-OATHTokenMenu
    
    Displays the main menu and waits for user input.
.EXAMPLE
    Show-OATHTokenMenu -DefaultAction Get
    
    Opens the Get OATH menu directly.
.NOTES
    Requires Microsoft.Graph.Authentication module and appropriate permissions:
    - Policy.ReadWrite.AuthenticationMethod
    - Directory.Read.All
#>

function Show-OATHTokenMenu {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('Main', 'Get', 'Add', 'Remove')]
        [string]$DefaultAction = 'Main',
        
        [Parameter()]
        [switch]$NonInteractive
    )
    
    begin {
        # Ensure we're connected to Graph
        if (-not (Test-MgConnection)) {
            throw "Microsoft Graph connection required. Please run Connect-MgGraph with appropriate scopes first."
        }
        
        # Set console colors
        $headerColor = 'Cyan'
        $promptColor = 'Yellow'
        $successColor = 'Green'
        $errorColor = 'Red'
    }
    
    process {
        # Main menu function
        function Show-MainMenu {
            Clear-Host
            Write-Host "===== OATH Token Management =====" -ForegroundColor $headerColor
            Write-Host "1) Get OATH" -ForegroundColor $promptColor
            Write-Host "2) Add OATH" -ForegroundColor $promptColor
            Write-Host "3) Remove OATH" -ForegroundColor $promptColor
            Write-Host "0) Exit" -ForegroundColor $promptColor
            Write-Host ""
            
            $choice = Read-Host "Enter your choice"
            switch ($choice) {
                "1" { Show-GetMenu }
                "2" { Show-AddMenu }
                "3" { Show-RemoveMenu }
                "0" { return }
                default { 
                    Write-Host "Invalid option. Please try again." -ForegroundColor $errorColor
                    Start-Sleep -Seconds 2
                    Show-MainMenu
                }
            }
        }
        
        # Get OATH menu
        function Show-GetMenu {
            Clear-Host
            Write-Host "===== Get OATH Menu =====" -ForegroundColor $headerColor
            Write-Host "1) List All" -ForegroundColor $promptColor
            Write-Host "2) List Available" -ForegroundColor $promptColor
            Write-Host "3) List Activated" -ForegroundColor $promptColor
            Write-Host "4) Export to CSV" -ForegroundColor $promptColor
            Write-Host "5) Find by Serial Number" -ForegroundColor $promptColor
            Write-Host "6) Find by User ID/UPN" -ForegroundColor $promptColor
            Write-Host "0) Return to main menu" -ForegroundColor $promptColor
            Write-Host ""
            
            $choice = Read-Host "Enter your choice"
            switch ($choice) {
                "1" { 
                    Write-Host "Getting all tokens..." -ForegroundColor $headerColor
                    $tokens = Get-OATHToken
                    Write-Host "Found $($tokens.Count) tokens." -ForegroundColor $successColor
                    $tokens | Format-Table -AutoSize
                    Write-Host "Press any key to continue..." -ForegroundColor $promptColor
                    [void][System.Console]::ReadKey($true)
                    Show-GetMenu
                }
                "2" { 
                    Write-Host "Getting available tokens..." -ForegroundColor $headerColor
                    $tokens = Get-OATHToken -AvailableOnly
                    Write-Host "Found $($tokens.Count) available tokens." -ForegroundColor $successColor
                    $tokens | Format-Table -AutoSize
                    Write-Host "Press any key to continue..." -ForegroundColor $promptColor
                    [void][System.Console]::ReadKey($true)
                    Show-GetMenu
                }
                "3" { 
                    Write-Host "Getting activated tokens..." -ForegroundColor $headerColor
                    $tokens = Get-OATHToken -ActivatedOnly
                    Write-Host "Found $($tokens.Count) activated tokens." -ForegroundColor $successColor
                    $tokens | Format-Table -AutoSize
                    Write-Host "Press any key to continue..." -ForegroundColor $promptColor
                    [void][System.Console]::ReadKey($true)
                    Show-GetMenu
                }
                "4" {
                    $csvPath = Read-Host "Enter CSV file path (press Enter for default)"
                    if ([string]::IsNullOrWhiteSpace($csvPath)) {
                        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
                        $csvPath = Join-Path -Path $PWD -ChildPath "OATHTokens_$timestamp.csv"
                    }
                    
                    Write-Host "Exporting tokens to: $csvPath" -ForegroundColor $headerColor
                    $result = Export-OATHToken -FilePath $csvPath
                    if ($result) {
                        Write-Host "Tokens exported successfully." -ForegroundColor $successColor
                    } else {
                        Write-Host "Failed to export tokens." -ForegroundColor $errorColor
                    }
                    
                    Write-Host "Press any key to continue..." -ForegroundColor $promptColor
                    [void][System.Console]::ReadKey($true)
                    Show-GetMenu
                }
                "5" {
                    $serialNumber = Read-Host "Enter token serial number (can include wildcards)"
                    Write-Host "Searching for tokens with serial number: $serialNumber" -ForegroundColor $headerColor
                    $tokens = Get-OATHToken -SerialNumber $serialNumber
                    Write-Host "Found $($tokens.Count) matching tokens." -ForegroundColor $successColor
                    $tokens | Format-Table -AutoSize
                    Write-Host "Press any key to continue..." -ForegroundColor $promptColor
                    [void][System.Console]::ReadKey($true)
                    Show-GetMenu
                }
                "6" {
                    $userId = Read-Host "Enter user ID or UPN"
                    Write-Host "Searching for tokens assigned to: $userId" -ForegroundColor $headerColor
                    $tokens = Get-OATHToken -UserId $userId
                    Write-Host "Found $($tokens.Count) tokens assigned to this user." -ForegroundColor $successColor
                    $tokens | Format-Table -AutoSize
                    Write-Host "Press any key to continue..." -ForegroundColor $promptColor
                    [void][System.Console]::ReadKey($true)
                    Show-GetMenu
                }
                "0" { Show-MainMenu }
                default { 
                    Write-Host "Invalid option. Please try again." -ForegroundColor $errorColor
                    Start-Sleep -Seconds 2
                    Show-GetMenu
                }
            }
        }
        
        # Add OATH menu
        function Show-AddMenu {
            Clear-Host
            Write-Host "===== Add OATH Menu =====" -ForegroundColor $headerColor
            Write-Host "1) Add OATH inventory" -ForegroundColor $promptColor
            Write-Host "2) Add OATH user" -ForegroundColor $promptColor
            Write-Host "3) Assign OATH user" -ForegroundColor $promptColor
            Write-Host "4) Activate OATH token" -ForegroundColor $promptColor
            Write-Host "5) Bulk Add OATH Inventory" -ForegroundColor $promptColor
            Write-Host "6) Bulk Add OATH User" -ForegroundColor $promptColor
            Write-Host "7) Activate with TOTP" -ForegroundColor $promptColor
            Write-Host "0) Return to main menu" -ForegroundColor $promptColor
            Write-Host ""
            
            $choice = Read-Host "Enter your choice"
            switch ($choice) {
                "1" { 
                    # Add single token to inventory
                    $serialNumber = Read-Host "Enter token serial number"
                    $secretKey = Read-Host "Enter secret key"
                    $secretFormat = Read-Host "Enter secret format (Base32, Hex, Text) or leave blank for Base32"
                    
                    if ([string]::IsNullOrWhiteSpace($secretFormat)) {
                        $secretFormat = "Base32"
                    }
                    
                    Write-Host "Adding token with serial number: $serialNumber" -ForegroundColor $headerColor
                    $result = Add-OATHToken -SerialNumber $serialNumber -SecretKey $secretKey -SecretFormat $secretFormat
                    
                    if ($result) {
                        Write-Host "Token added successfully." -ForegroundColor $successColor
                    } else {
                        Write-Host "Failed to add token." -ForegroundColor $errorColor
                    }
                    
                    Write-Host "Press any key to continue..." -ForegroundColor $promptColor
                    [void][System.Console]::ReadKey($true)
                    Show-AddMenu
                }
                "2" {
                    # Add token and assign to user
                    $serialNumber = Read-Host "Enter token serial number"
                    $secretKey = Read-Host "Enter secret key"
                    $secretFormat = Read-Host "Enter secret format (Base32, Hex, Text) or leave blank for Base32"
                    $userId = Read-Host "Enter user ID or UPN"
                    
                    if ([string]::IsNullOrWhiteSpace($secretFormat)) {
                        $secretFormat = "Base32"
                    }
                    
                    Write-Host "Adding token and assigning to user..." -ForegroundColor $headerColor
                    
                    # First add the token
                    $token = Add-OATHToken -SerialNumber $serialNumber -SecretKey $secretKey -SecretFormat $secretFormat
                    
                    if ($token) {
                        # Then assign it to the user
                        $assignResult = Set-OATHTokenUser -TokenId $token.id -UserId $userId
                        
                        if ($assignResult) {
                            Write-Host "Token added and assigned successfully." -ForegroundColor $successColor
                        } else {
                            Write-Host "Token added but assignment failed." -ForegroundColor $errorColor
                        }
                    } else {
                        Write-Host "Failed to add token." -ForegroundColor $errorColor
                    }
                    
                    Write-Host "Press any key to continue..." -ForegroundColor $promptColor
                    [void][System.Console]::ReadKey($true)
                    Show-AddMenu
                }
                "3" {
                    # Assign existing token to user
                    $tokenId = Read-Host "Enter token ID"
                    $userId = Read-Host "Enter user ID or UPN"
                    
                    Write-Host "Assigning token to user..." -ForegroundColor $headerColor
                    $result = Set-OATHTokenUser -TokenId $tokenId -UserId $userId
                    
                    if ($result) {
                        Write-Host "Token assigned successfully." -ForegroundColor $successColor
                    } else {
                        Write-Host "Failed to assign token." -ForegroundColor $errorColor
                    }
                    
                    Write-Host "Press any key to continue..." -ForegroundColor $promptColor
                    [void][System.Console]::ReadKey($true)
                    Show-AddMenu
                }
                "4" {
                    # Activate token with verification code
                    $tokenId = Read-Host "Enter token ID"
                    $userId = Read-Host "Enter user ID or UPN"
                    $verificationCode = Read-Host "Enter verification code"
                    
                    Write-Host "Activating token..." -ForegroundColor $headerColor
                    $result = Set-OATHTokenActive -TokenId $tokenId -UserId $userId -VerificationCode $verificationCode
                    
                    if ($result) {
                        Write-Host "Token activated successfully." -ForegroundColor $successColor
                    } else {
                        Write-Host "Failed to activate token." -ForegroundColor $errorColor
                    }
                    
                    Write-Host "Press any key to continue..." -ForegroundColor $promptColor
                    [void][System.Console]::ReadKey($true)
                    Show-AddMenu
                }
                "5" {
                    # Bulk add tokens from JSON
                    $jsonPath = Read-Host "Enter JSON file path (press Enter for default tokens_inventory.json)"
                    
                    if ([string]::IsNullOrWhiteSpace($jsonPath)) {
                        $jsonPath = Join-Path -Path $PWD -ChildPath "tokens_inventory.json"
                    }
                    
                    if (-not (Test-Path -Path $jsonPath)) {
                        Write-Host "File not found: $jsonPath" -ForegroundColor $errorColor
                    } else {
                        Write-Host "Importing tokens from: $jsonPath" -ForegroundColor $headerColor
                        $result = Import-OATHToken -FilePath $jsonPath -Format JSON
                        
                        if ($result) {
                            Write-Host "Tokens imported successfully." -ForegroundColor $successColor
                        } else {
                            Write-Host "Failed to import tokens." -ForegroundColor $errorColor
                        }
                    }
                    
                    Write-Host "Press any key to continue..." -ForegroundColor $promptColor
                    [void][System.Console]::ReadKey($true)
                    Show-AddMenu
                }
                "6" {
                    # Bulk add tokens with user assignments
                    $jsonPath = Read-Host "Enter JSON file path (press Enter for default tokens_users.json)"
                    
                    if ([string]::IsNullOrWhiteSpace($jsonPath)) {
                        $jsonPath = Join-Path -Path $PWD -ChildPath "tokens_users.json"
                    }
                    
                    if (-not (Test-Path -Path $jsonPath)) {
                        Write-Host "File not found: $jsonPath" -ForegroundColor $errorColor
                    } else {
                        Write-Host "Importing tokens with user assignments from: $jsonPath" -ForegroundColor $headerColor
                        $result = Import-OATHToken -FilePath $jsonPath -Format JSON -SchemaType UserAssignments -AssignToUsers
                        
                        if ($result) {
                            Write-Host "Tokens imported and assigned successfully." -ForegroundColor $successColor
                        } else {
                            Write-Host "Failed to import tokens with user assignments." -ForegroundColor $errorColor
                        }
                    }
                    
                    Write-Host "Press any key to continue..." -ForegroundColor $promptColor
                    [void][System.Console]::ReadKey($true)
                    Show-AddMenu
                }
                "7" {
                    # Activate token with TOTP
                    $tokenId = Read-Host "Enter token ID"
                    $userId = Read-Host "Enter user ID or UPN"
                    $secret = Read-Host "Enter token secret"
                    $secretFormat = Read-Host "Enter secret format (Base32, Hex, Text) or leave blank for Base32"
                    
                    if ([string]::IsNullOrWhiteSpace($secretFormat)) {
                        $secretFormat = "Base32"
                    }
                    
                    Write-Host "Activating token with generated TOTP code..." -ForegroundColor $headerColor
                    $result = Set-OATHTokenActive -TokenId $tokenId -UserId $userId -Secret $secret -SecretFormat $secretFormat
                    
                    if ($result) {
                        Write-Host "Token activated successfully with generated TOTP code." -ForegroundColor $successColor
                    } else {
                        Write-Host "Failed to activate token with TOTP." -ForegroundColor $errorColor
                    }
                    
                    Write-Host "Press any key to continue..." -ForegroundColor $promptColor
                    [void][System.Console]::ReadKey($true)
                    Show-AddMenu
                }
                "0" { Show-MainMenu }
                default { 
                    Write-Host "Invalid option. Please try again." -ForegroundColor $errorColor
                    Start-Sleep -Seconds 2
                    Show-AddMenu
                }
            }
        }
        
        # Remove OATH menu
        function Show-RemoveMenu {
            Clear-Host
            Write-Host "===== Remove OATH Menu =====" -ForegroundColor $headerColor
            Write-Host "1) Remove OATH" -ForegroundColor $promptColor
            Write-Host "2) Bulk Remove OATH" -ForegroundColor $promptColor
            Write-Host "3) Unassign OATH token" -ForegroundColor $promptColor
            Write-Host "4) Remove with auto-unassign" -ForegroundColor $promptColor
            Write-Host "0) Return to main menu" -ForegroundColor $promptColor
            Write-Host ""
            
            $choice = Read-Host "Enter your choice"
            switch ($choice) {
                "1" { 
                    # Remove single token
                    $tokenIdentifier = Read-Host "Enter token ID or serial number"
                    
                    # Check if the input looks like a GUID
                    if ($tokenIdentifier -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
                        Write-Host "Removing token by ID..." -ForegroundColor $headerColor
                        $result = Remove-OATHToken -TokenId $tokenIdentifier
                    } else {
                        Write-Host "Removing token by serial number..." -ForegroundColor $headerColor
                        $result = Remove-OATHToken -SerialNumber $tokenIdentifier
                    }
                    
                    if ($result) {
                        Write-Host "Token removed successfully." -ForegroundColor $successColor
                    } else {
                        Write-Host "Failed to remove token." -ForegroundColor $errorColor
                    }
                    
                    Write-Host "Press any key to continue..." -ForegroundColor $promptColor
                    [void][System.Console]::ReadKey($true)
                    Show-RemoveMenu
                }
                "2" {
                    # Bulk remove tokens
                    $jsonPath = Read-Host "Enter JSON file path with token IDs to remove (press Enter for default tokens_remove.json)"
                    
                    if ([string]::IsNullOrWhiteSpace($jsonPath)) {
                        $jsonPath = Join-Path -Path $PWD -ChildPath "tokens_remove.json"
                    }
                    
                    if (-not (Test-Path -Path $jsonPath)) {
                        Write-Host "File not found: $jsonPath" -ForegroundColor $errorColor
                    } else {
                        try {
                            $jsonContent = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
                            
                            if (-not $jsonContent.remove -or $jsonContent.remove.Count -eq 0) {
                                Write-Host "No token IDs found in the file. Expected 'remove' array property." -ForegroundColor $errorColor
                            } else {
                                $tokenIds = $jsonContent.remove
                                Write-Host "Removing $($tokenIds.Count) tokens..." -ForegroundColor $headerColor
                                
                                $removedCount = 0
                                $failedCount = 0
                                
                                foreach ($tokenId in $tokenIds) {
                                    $result = Remove-OATHToken -TokenId $tokenId -Force
                                    if ($result) {
                                        $removedCount++
                                    } else {
                                        $failedCount++
                                    }
                                }
                                
                                Write-Host "Bulk removal completed: $removedCount removed, $failedCount failed." -ForegroundColor $successColor
                            }
                        } catch {
                            Write-Host "Error processing JSON file: $_" -ForegroundColor $errorColor
                        }
                    }
                    
                    Write-Host "Press any key to continue..." -ForegroundColor $promptColor
                    [void][System.Console]::ReadKey($true)
                    Show-RemoveMenu
                }
                "3" {
                    # Unassign token
                    $tokenId = Read-Host "Enter token ID to unassign"
                    
                    Write-Host "Unassigning token..." -ForegroundColor $headerColor
                    $result = Set-OATHTokenUser -TokenId $tokenId -Unassign
                    
                    if ($result) {
                        Write-Host "Token unassigned successfully." -ForegroundColor $successColor
                    } else {
                        Write-Host "Failed to unassign token." -ForegroundColor $errorColor
                    }
                    
                    Write-Host "Press any key to continue..." -ForegroundColor $promptColor
                    [void][System.Console]::ReadKey($true)
                    Show-RemoveMenu
                }
                "4" {
                    $tokenId = Read-Host "Enter token ID to unassign and remove"
                    if (-not [string]::IsNullOrWhiteSpace($tokenId)) {
                        $result = Remove-OATHToken -TokenId $tokenId -UnassignFirst
                        if ($result) {
                            Write-Host "Token unassigned and removed successfully." -ForegroundColor $successColor
                        } else {
                            Write-Host "Failed to unassign and remove token." -ForegroundColor $errorColor
                        }
                        Write-Host "Press any key to continue..." -ForegroundColor $promptColor
                        [void][System.Console]::ReadKey($true)
                    }
                    Show-RemoveMenu
                }
                "0" { Show-MainMenu }
                default { 
                    Write-Host "Invalid option. Please try again." -ForegroundColor $errorColor
                    Start-Sleep -Seconds 2
                    Show-RemoveMenu
                }
            }
        }
        
        # Start with the specified menu or the main menu by default
        switch ($DefaultAction) {
            'Get' { Show-GetMenu }
            'Add' { Show-AddMenu }
            'Remove' { Show-RemoveMenu }
            default { Show-MainMenu }
        }
    }
}

# Add alias for backward compatibility
New-Alias -Name 'Show-HardwareOathTokenMenu' -Value 'Show-OATHTokenMenu'
