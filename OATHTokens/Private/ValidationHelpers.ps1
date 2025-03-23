<#
.SYNOPSIS
    Input validation functions for OATH token management
.DESCRIPTION
    Private functions for validating user input, token properties, 
    and request parameters for OATH token management operations.
.NOTES
    These helpers ensure consistent validation across the module.
#>

function Test-OATHSerialNumber {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [string]$SerialNumber,
        
        [Parameter()]
        [switch]$AllowEmpty,
        
        [Parameter()]
        [int]$MinLength = 1,
        
        [Parameter()]
        [int]$MaxLength = 64
    )
    
    process {
        try {
            if ([string]::IsNullOrWhiteSpace($SerialNumber)) {
                if ($AllowEmpty) {
                    return $true
                }
                Write-Warning "Serial number cannot be empty"
                return $false
            }
            
            # Check length
            if ($SerialNumber.Length -lt $MinLength -or $SerialNumber.Length -gt $MaxLength) {
                Write-Warning "Serial number must be between $MinLength and $MaxLength characters"
                return $false
            }
            
            # Typical validations for YubiKey serial numbers: alphanumeric plus some symbols
            if (-not [regex]::IsMatch($SerialNumber, '^[a-zA-Z0-9._-]+$')) {
                Write-Warning "Serial number contains invalid characters. Use only letters, numbers, periods, underscores, and hyphens."
                return $false
            }
            
            return $true
        }
        catch {
            Write-Error "Error validating serial number: $_"
            return $false
        }
    }
}

function Test-OATHSecretKey {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [string]$SecretKey,
        
        [Parameter()]
        [ValidateSet('Base32', 'Hex', 'Text')]
        [string]$Format = 'Base32'
    )
    
    process {
        try {
            if ([string]::IsNullOrWhiteSpace($SecretKey)) {
                Write-Warning "Secret key cannot be empty"
                return $false
            }
            
            switch ($Format) {
                'Base32' {
                    # Base32 format: uppercase A-Z, digits 2-7, optional padding
                    if (-not [regex]::IsMatch($SecretKey, '^[A-Z2-7]+=*$')) {
                        Write-Warning "Invalid Base32 format. Must contain only A-Z, 2-7, with optional '=' padding."
                        return $false
                    }
                }
                'Hex' {
                    # Hex format: 0-9, a-f, A-F, even number of characters
                    $cleanHex = $SecretKey -replace '[-: ]', ''
                    if (-not [regex]::IsMatch($cleanHex, '^[0-9a-fA-F]+$')) {
                        Write-Warning "Invalid hexadecimal format. Must contain only 0-9, A-F."
                        return $false
                    }
                    
                    if ($cleanHex.Length % 2 -ne 0) {
                        Write-Warning "Hexadecimal string must have an even number of characters"
                        return $false
                    }
                }
                'Text' {
                    # Text format: any printable character, reasonable length
                    if ($SecretKey.Length -lt 1 -or $SecretKey.Length -gt 100) {
                        Write-Warning "Text secret must be between 1 and 100 characters"
                        return $false
                    }
                }
            }
            
            return $true
        }
        catch {
            Write-Error "Error validating secret key: $_"
            return $false
        }
    }
}

function Test-OATHTokenId {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [string]$TokenId
    )
    
    process {
        try {
            if ([string]::IsNullOrWhiteSpace($TokenId)) {
                Write-Warning "Token ID cannot be empty"
                return $false
            }
            
            # GUID format validation
            if (-not [regex]::IsMatch($TokenId, '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')) {
                Write-Warning "Invalid Token ID format. Must be a valid GUID."
                return $false
            }
            
            return $true
        }
        catch {
            Write-Error "Error validating Token ID: $_"
            return $false
        }
    }
}

function Test-OATHToken {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [object]$Token,
        
        [Parameter()]
        [switch]$SkipSecretValidation
    )
    
    try {
        # Check required properties
        if (-not $Token.serialNumber) {
            Write-Warning "Token is missing required 'serialNumber' property"
            return $false
        }
        
        # Validate serial number
        if (-not (Test-OATHSerialNumber -SerialNumber $Token.serialNumber)) {
            return $false
        }
        
        # Skip secret validation if requested (for existing tokens)
        if (-not $SkipSecretValidation) {
            if (-not $Token.secretKey) {
                Write-Warning "Token is missing required 'secretKey' property"
                return $false
            }
            
            # Determine format
            $format = 'Base32'
            if ($Token.secretFormat) {
                switch ($Token.secretFormat.ToLower()) {
                    'hex' { $format = 'Hex' }
                    'text' { $format = 'Text' }
                }
            }
            
            # Validate secret key
            if (-not (Test-OATHSecretKey -SecretKey $Token.secretKey -Format $format)) {
                return $false
            }
        }
        
        # Optional property validation
        if ($Token.hashFunction -and $Token.hashFunction -notin @('hmacsha1', 'hmacsha256', 'hmacsha512')) {
            Write-Warning "Invalid 'hashFunction' value. Must be one of: 'hmacsha1', 'hmacsha256', 'hmacsha512'"
            return $false
        }
        
        if ($Token.timeIntervalInSeconds -and -not ($Token.timeIntervalInSeconds -ge 10 -and $Token.timeIntervalInSeconds -le 120)) {
            Write-Warning "Invalid 'timeIntervalInSeconds' value. Must be between 10 and 120."
            return $false
        }
        
        return $true
    }
    catch {
        Write-Error "Error validating token: $_"
        return $false
    }
}

function Test-OATHVerificationCode {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [string]$VerificationCode,
        
        [Parameter()]
        [int]$ExpectedLength = 6
    )
    
    process {
        try {
            if ([string]::IsNullOrWhiteSpace($VerificationCode)) {
                Write-Warning "Verification code cannot be empty"
                return $false
            }
            
            if ($VerificationCode.Length -ne $ExpectedLength) {
                Write-Warning "Verification code must be exactly $ExpectedLength digits"
                return $false
            }
            
            if (-not [regex]::IsMatch($VerificationCode, '^\d+$')) {
                Write-Warning "Verification code must contain only digits"
                return $false
            }
            
            return $true
        }
        catch {
            Write-Error "Error validating verification code: $_"
            return $false
        }
    }
}
