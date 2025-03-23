<#
.SYNOPSIS
    Helper functions for validating OATH token data
.DESCRIPTION
    These functions validate various aspects of OATH token data including
    serial numbers, secret keys, token IDs, and verification codes.
.NOTES
    These are internal functions used by the module.
#>

function Test-OATHSerialNumber {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SerialNumber
    )
    
    # Serial number must not be empty
    if ([string]::IsNullOrWhiteSpace($SerialNumber)) {
        return $false
    }
    
    # Serial number must be between 1 and 30 characters
    # Based on Entra ID's limitations
    if ($SerialNumber.Length -gt 30) {
        return $false
    }
    
    # Serial number should have valid characters (alphanumeric, hyphen, underscore)
    if ($SerialNumber -notmatch '^[a-zA-Z0-9\-_]+$') {
        return $false
    }
    
    return $true
}

# Update Test-OATHSecretKey function to be more lenient with formats other than Base32
function Test-OATHSecretKey {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SecretKey,
        
        [Parameter()]
        [ValidateSet('Base32', 'Hex', 'Text')]
        [string]$Format = 'Base32'
    )
    
    # Secret key must not be empty
    if ([string]::IsNullOrWhiteSpace($SecretKey)) {
        return $false
    }
    
    # Validate based on format
    switch ($Format.ToLower()) {
        'base32' {
            # Base32 must only contain characters A-Z, 2-7
            # Allow for optional padding with = at the end
            if ($SecretKey -notmatch '^[A-Z2-7]+=*$') {
                Write-Verbose "Secret key fails Base32 format validation: $SecretKey"
                return $false
            }
        }
        'hex' {
            # Hex must only contain hexadecimal characters
            if ($SecretKey -notmatch '^[0-9a-fA-F]+$') {
                Write-Verbose "Secret key fails Hex format validation: $SecretKey"
                return $false
            }
            
            # Hex string length should be even (as it represents bytes)
            if ($SecretKey.Length % 2 -ne 0) {
                Write-Verbose "Hex secret key has odd length: $($SecretKey.Length)"
                return $false
            }
        }
        'text' {
            # Text can be any non-empty string
            # No specific validation beyond being non-empty
            return $true
        }
        default {
            Write-Warning "Unknown format: $Format. Defaulting to Base32 validation rules."
            # Apply Base32 rules as default
            if ($SecretKey -notmatch '^[A-Z2-7]+=*$') {
                Write-Verbose "Secret key fails Base32 format validation (default): $SecretKey"
                return $false
            }
        }
    }
    
    return $true
}

function Test-OATHTokenId {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TokenId
    )
    
    # Token ID must be a valid GUID
    if ($TokenId -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
        return $true
    }
    
    return $false
}

function Test-OATHVerificationCode {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VerificationCode
    )
    
    # Verification code must be 6 digits
    if ($VerificationCode -match '^\d{6}$') {
        return $true
    }
    
    return $false
}
