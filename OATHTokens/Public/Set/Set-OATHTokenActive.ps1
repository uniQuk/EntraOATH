<#
.SYNOPSIS
    Activates an OATH hardware token for a user
.DESCRIPTION
    Activates an OATH hardware token for a user in Microsoft Entra ID via the Microsoft Graph API.
    Activation requires a verification code that matches the expected TOTP code for the token.
.PARAMETER TokenId
    The ID of the token to activate
.PARAMETER UserId
    The ID or UPN of the user who owns the token
.PARAMETER VerificationCode
    The TOTP code from the token to verify during activation
.PARAMETER Secret
    The token's secret key for automatic TOTP generation (if VerificationCode is not provided)
.PARAMETER SecretFormat
    The format of the provided Secret (Base32, Hex, or Text). Defaults to Base32.
.PARAMETER ApiVersion
    The Microsoft Graph API version to use. Defaults to 'beta'.
.EXAMPLE
    Set-OATHTokenActive -TokenId "00000000-0000-0000-0000-000000000000" -UserId "user@contoso.com" -VerificationCode "123456"
    
    Activates the specified token for the user with the given verification code
.EXAMPLE
    Set-OATHTokenActive -TokenId "00000000-0000-0000-0000-000000000000" -UserId "user@contoso.com" -Secret "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    
    Activates the specified token by automatically generating a TOTP code from the provided secret
.NOTES
    Requires Microsoft.Graph.Authentication module and appropriate permissions:
    - Policy.ReadWrite.AuthenticationMethod
    - Directory.Read.All
#>

function Set-OATHTokenActive {
    [CmdletBinding(DefaultParameterSetName = 'ManualCode', SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)]
        [Alias('Id')]
        [string]$TokenId,
        
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$UserId,
        
        [Parameter(ParameterSetName = 'ManualCode', Mandatory = $true, Position = 2)]
        [string]$VerificationCode,
        
        [Parameter(ParameterSetName = 'AutoCode', Mandatory = $true)]
        [string]$Secret,
        
        [Parameter(ParameterSetName = 'AutoCode')]
        [ValidateSet('Base32', 'Hex', 'Text')]
        [string]$SecretFormat = 'Base32',
        
        [Parameter()]
        [string]$ApiVersion = 'beta'
    )
    
    begin {
        # Ensure we're connected to Graph
        if (-not (Test-MgConnection)) {
            throw "Microsoft Graph connection required."
        }
        
        # Convert the verification code
        if ($PSCmdlet.ParameterSetName -eq 'AutoCode') {
            # Try to resolve the user first to make sure they exist
            $resolvedUser = Get-MgUserByIdentifier -Identifier $UserId
            if (-not $resolvedUser) {
                throw "User not found with identifier: $UserId"
            }
            
            $UserId = $resolvedUser.id
            
            # Generate TOTP code using the provided secret
            try {
                Write-Verbose "Generating TOTP code from secret..."
                
                # Convert secret to Base32 if needed
                $base32Secret = $Secret
                if ($SecretFormat -ne 'Base32') {
                    $base32Secret = ConvertTo-Base32 -InputString $Secret -InputFormat $SecretFormat
                    if (-not $base32Secret) {
                        throw "Failed to convert secret to Base32 format"
                    }
                    Write-Verbose "Converted secret from $SecretFormat to Base32: $base32Secret"
                }
                
                # Generate TOTP code - fix the parameter names to match the function in TOTP.ps1
                $totpParams = @{
                    Secret = $base32Secret
                    UnixTime = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() # Use this instead
                    Digits = 6
                    TimeStep = 30
                    Algorithm = 'SHA1'
                }
                
                # Try generating TOTP code using our external implementation from TOTP.ps1
                $generatedCode = Get-TOTP @totpParams # Note: Also changed from Get-Totp to Get-TOTP for consistency
                if (-not $generatedCode -or -not [regex]::IsMatch($generatedCode, '^\d{6}$')) {
                    throw "Failed to generate a valid 6-digit TOTP code"
                }
                
                Write-Verbose "Generated verification code: $generatedCode"
                $VerificationCode = $generatedCode
            }
            catch {
                throw "Error generating TOTP code: $_"
            }
        }
        else {
            # Validate verification code format
            if (-not (Test-OATHVerificationCode -VerificationCode $VerificationCode)) {
                throw "Invalid verification code format. Must be a 6-digit number."
            }
            
            # Try to resolve the user if needed
            $resolvedUser = Get-MgUserByIdentifier -Identifier $UserId
            if (-not $resolvedUser) {
                throw "User not found with identifier: $UserId"
            }
            
            $UserId = $resolvedUser.id
        }
    }
    
    process {
        try {
            # Validate token ID format
            if (-not (Test-OATHTokenId -TokenId $TokenId)) {
                throw "Invalid token ID format: $TokenId"
            }
            
            # Check if the token exists and is assigned to the specified user
            $token = Get-OATHToken -TokenId $TokenId -ErrorAction Stop
            if (-not $token) {
                throw "Token not found with ID: $TokenId"
            }
            
            # Verify the token is assigned to the correct user
            if (-not $token.AssignedToId -or $token.AssignedToId -ne $UserId) {
                throw "Token is not assigned to the specified user. Please assign it first."
            }
            
            # Check if token is already activated
            if ($token.Status -eq 'activated') {
                $serialDisplay = if ($token.SerialNumber) { " (S/N: $($token.SerialNumber))" } else { "" }
                $userName = if ($token.AssignedToName) { $token.AssignedToName } else { $UserId }
                Write-Host "Token $($token.Id)$serialDisplay is already activated for user $userName." -ForegroundColor Yellow
                Write-Host "To reactivate the token, you must first unassign it using Set-OATHTokenUser -TokenId $($token.Id) -Unassign" -ForegroundColor Yellow
                
                # Return a result object instead of boolean
                return [PSCustomObject]@{
                    Success = $true
                    AlreadyActivated = $true
                    TokenId = $TokenId
                    SerialNumber = $token.SerialNumber
                    UserId = $UserId
                    UserName = $userName
                    Status = $token.Status
                }
            }
            
            # Set up activation request
            $endpoint = "https://graph.microsoft.com/$ApiVersion/users/$UserId/authentication/hardwareOathMethods/$TokenId/activate"
            $body = @{
                verificationCode = $VerificationCode
            } | ConvertTo-Json
            
            # Display info for confirmation
            $displayName = if ($token.DisplayName) { $token.DisplayName } else { $token.Id }
            $serialDisplay = if ($token.SerialNumber) { " (S/N: $($token.SerialNumber))" } else { "" }
            $userName = if ($token.AssignedToName) { $token.AssignedToName } else { $UserId }
            
            # Confirm activation
            if ($PSCmdlet.ShouldProcess("Token $displayName$serialDisplay for user $userName", "Activate")) {
                Write-Verbose "Activating token with verification code: $VerificationCode"
                $response = Invoke-MgGraphWithErrorHandling -Method POST -Uri $endpoint -Body $body -ContentType "application/json" -ErrorAction Stop
                
                Write-Host "Successfully activated token $displayName$serialDisplay for user $userName" -ForegroundColor Green
                
                # Return a result object instead of boolean
                return [PSCustomObject]@{
                    Success = $true
                    AlreadyActivated = $false
                    TokenId = $TokenId
                    SerialNumber = $token.SerialNumber
                    UserId = $UserId
                    UserName = $userName
                    Status = 'activated'
                }
            }
            else {
                Write-Warning "Activation canceled by user."
                return [PSCustomObject]@{
                    Success = $false
                    Reason = "Canceled by user"
                    TokenId = $TokenId
                    SerialNumber = $token.SerialNumber
                    UserId = $UserId
                    UserName = $userName
                    Status = $token.Status
                }
            }
        }
        catch {
            Write-Error "Failed to activate token: $_"
            return [PSCustomObject]@{
                Success = $false
                Reason = $_.ToString()
                TokenId = $TokenId
                SerialNumber = $token.SerialNumber
                UserId = $UserId
                Status = $token.Status
            }
        }
    }
}

# Add alias for backward compatibility - only if it doesn't already exist
if (-not (Get-Alias -Name 'Activate-HardwareOathToken' -ErrorAction SilentlyContinue)) {
    New-Alias -Name 'Activate-HardwareOathToken' -Value 'Set-OATHTokenActive'
}
