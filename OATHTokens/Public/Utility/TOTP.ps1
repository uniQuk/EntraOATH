<#
.SYNOPSIS
    Time-Based One-Time Password (TOTP) Generator
.DESCRIPTION
    Generates TOTP codes according to RFC 6238 (TOTP) and RFC 4226 (HOTP)
    for use with OATH hardware tokens, authenticator apps, and more.
.PARAMETER Secret
    The secret key used to generate the TOTP code
.PARAMETER Digits
    The number of digits in the generated TOTP code. Defaults to 6.
.PARAMETER TimeStep
    The time step in seconds. Defaults to 30.
.PARAMETER UnixTime
    Unix timestamp to use for TOTP generation. If not specified, current time is used.
.PARAMETER Window
    Time window for which the code is valid (in steps). Defaults to 1.
.PARAMETER InputFormat
    Format of the input secret key. Can be Base32, Hex, or Text. Defaults to Base32.
.EXAMPLE
    Get-TOTP -Secret "JBSWY3DPEB3W64TMMQ======"
    
    Generates a TOTP code using a Base32-encoded secret key
.EXAMPLE
    Get-TOTP -Secret "3a085cfcd4618c61dc235c300d7a70c4" -InputFormat Hex
    
    Generates a TOTP code using a hexadecimal secret key
.EXAMPLE
    Get-TOTP -Secret "MySecretKey" -InputFormat Text -Digits 8 -TimeStep 60
    
    Generates an 8-digit TOTP code with a 60-second validity using a text secret
.NOTES
    This implementation follows the RFC specifications for TOTP and works 
    with common authenticator apps and hardware tokens.
#>

function Get-TOTP {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Secret,
        
        [Parameter()]
        [ValidateRange(6, 10)]
        [int]$Digits = 6,
        
        [Parameter()]
        [ValidateRange(10, 300)]
        [int]$TimeStep = 30,
        
        [Parameter()]
        [int64]$UnixTime = -1,
        
        [Parameter()]
        [ValidateRange(1, 10)]
        [int]$Window = 1,
        
        [Parameter()]
        [ValidateSet('Base32', 'Hex', 'Text')]
        [string]$InputFormat = 'Base32',
        
        [Parameter()]
        [ValidateSet('SHA1', 'SHA256', 'SHA512')]
        [string]$Algorithm = 'SHA1'
    )
    
    begin {
        # Convert Base32 to bytes
        function ConvertFrom-Base32 {
            param([string]$Base32)
            
            # Remove any padding and spaces
            $Base32 = $Base32.ToUpper() -replace '=+$' -replace '\s', ''
            
            $Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
            $bitsBuffer = ""
            
            foreach ($char in $Base32.ToCharArray()) {
                $index = $Alphabet.IndexOf($char)
                if ($index -lt 0) {
                    throw "Invalid Base32 character: $char"
                }
                
                $bitsBuffer += [Convert]::ToString($index, 2).PadLeft(5, '0')
            }
            
            # Group bits into 8-bit chunks for bytes
            $bytes = [System.Collections.Generic.List[byte]]::new()
            for ($i = 0; $i -lt $bitsBuffer.Length; $i += 8) {
                # If we don't have 8 bits left, we've reached partial padding that should be ignored
                if ($i + 8 -gt $bitsBuffer.Length) {
                    break
                }
                
                $byteValue = [Convert]::ToByte($bitsBuffer.Substring($i, 8), 2)
                $bytes.Add($byteValue)
            }
            
            return $bytes.ToArray()
        }
        
        # Convert hex to bytes
        function ConvertFrom-Hex {
            param([string]$HexString)
            
            # Clean up the hex string (remove spaces, dashes, etc.)
            $HexString = $HexString -replace '[-: ]', ''
            
            # Ensure it's even length
            if ($HexString.Length % 2 -ne 0) {
                throw "Hexadecimal string must have an even number of characters"
            }
            
            # Convert to bytes
            $bytes = [byte[]]::new($HexString.Length / 2)
            for ($i = 0; $i -lt $HexString.Length; $i += 2) {
                $bytes[$i/2] = [Convert]::ToByte($HexString.Substring($i, 2), 16)
            }
            
            return $bytes
        }
    }
    
    process {
        try {
            # Remove spaces from secret
            $Secret = $Secret -replace "\s", ""
            
            # Convert secret to bytes based on input format
            $secretBytes = $null
            
            switch ($InputFormat) {
                'Base32' {
                    $secretBytes = ConvertFrom-Base32 -Base32 $Secret
                }
                'Hex' {
                    $secretBytes = ConvertFrom-Hex -HexString $Secret
                }
                'Text' {
                    $secretBytes = [System.Text.Encoding]::UTF8.GetBytes($Secret)
                }
                default {
                    throw "Invalid input format: $InputFormat"
                }
            }
            
            # Verify we have valid secret bytes
            if ($null -eq $secretBytes -or $secretBytes.Length -eq 0) {
                throw "Failed to convert secret to byte array"
            }
            
            # Use current Unix time if not specified
            if ($UnixTime -lt 0) {
                $UnixTime = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            }
            
            # Calculate counter value (time steps from Unix epoch)
            $counter = [Math]::Floor($UnixTime / $TimeStep)
            
            # Initialize result array with the current time's TOTP
            $results = @()
            
            # Calculate TOTP for the current counter and adjacent windows if requested
            for ($i = -($Window - 1); $i -lt $Window; $i++) {
                $currentCounter = $counter + $i
                
                # Convert counter to bytes (big-endian)
                $counterBytes = [BitConverter]::GetBytes([int64]$currentCounter)
                if ([BitConverter]::IsLittleEndian) {
                    [Array]::Reverse($counterBytes)
                }
                
                # Create the HMAC object
                $hmac = switch ($Algorithm) {
                    'SHA1'   { New-Object System.Security.Cryptography.HMACSHA1 }
                    'SHA256' { New-Object System.Security.Cryptography.HMACSHA256 }
                    'SHA512' { New-Object System.Security.Cryptography.HMACSHA512 }
                }
                
                $hmac.Key = $secretBytes
                
                # Compute the HMAC
                $hash = $hmac.ComputeHash($counterBytes)
                
                # Get the offset
                $offset = $hash[$hash.Length - 1] -band 0x0F
                
                # Get the 4 bytes at the offset
                $binary = (($hash[$offset] -band 0x7F) -shl 24) -bor
                           (($hash[$offset + 1] -band 0xFF) -shl 16) -bor
                           (($hash[$offset + 2] -band 0xFF) -shl 8) -bor
                           ($hash[$offset + 3] -band 0xFF)
                
                # Calculate the OTP code
                $otp = $binary % [Math]::Pow(10, $Digits)
                
                # Format the OTP code with leading zeros
                # Fix: Use explicit int cast before ToString to avoid floating point issues
                $otpInt = [int]$otp
                $otpString = $otpInt.ToString("D$Digits")
                
                # Create a result object
                $result = [PSCustomObject]@{
                    OTP = $otpString
                    Counter = $currentCounter
                    Time = [DateTimeOffset]::FromUnixTimeSeconds($currentCounter * $TimeStep)
                    IsCurrentWindow = ($i -eq 0)
                }
                
                $results += $result
            }
            
            # Return the single result for the current time or an array if multiple windows
            if ($Window -eq 1) {
                return $results[0].OTP
            }
            else {
                return $results
            }
        }
        catch {
            Write-Error "Error generating TOTP: $_"
            return $null
        }
    }
}

# Helper function to check if a given TOTP code is valid for a secret
function Test-TOTP {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Secret,
        
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$Code,
        
        [Parameter()]
        [int]$Digits = 6,
        
        [Parameter()]
        [int]$TimeStep = 30,
        
        [Parameter()]
        [int]$Window = 1,
        
        [Parameter()]
        [ValidateSet('Base32', 'Hex', 'Text')]
        [string]$InputFormat = 'Base32',
        
        [Parameter()]
        [ValidateSet('SHA1', 'SHA256', 'SHA512')]
        [string]$Algorithm = 'SHA1'
    )
    
    try {
        # Ensure code is the expected length
        if ($Code.Length -ne $Digits) {
            Write-Warning "Code length mismatch: expected $Digits digits, got $($Code.Length)"
            return $false
        }
        
        # Get valid TOTPs for the current time window
        $validTotps = Get-TOTP -Secret $Secret -Digits $Digits -TimeStep $TimeStep -Window $Window -InputFormat $InputFormat -Algorithm $Algorithm
        
        # Handle single vs. multiple results
        if ($Window -eq 1) {
            return $validTotps -eq $Code
        }
        else {
            return $validTotps.OTP -contains $Code
        }
    }
    catch {
        Write-Error "Error validating TOTP: $_"
        return $false
    }
}

# Better export logic that works in both module and script contexts
if ($MyInvocation.MyCommand.ScriptBlock.Module) {
    # Module context - use standard PowerShell module export
    Export-ModuleMember -Function Get-TOTP, Test-TOTP
}
else {
    # Script context (e.g., dot-sourced) - define in global scope
    Write-Verbose "Not in module context, making functions available in global scope"
    
    # Create function in global scope if they don't exist
    if (-not (Get-Command -Name 'Get-TOTP' -ErrorAction SilentlyContinue)) {
        Set-Item -Path function:global:Get-TOTP -Value ${function:Get-TOTP}
    }
    
    if (-not (Get-Command -Name 'Test-TOTP' -ErrorAction SilentlyContinue)) {
        Set-Item -Path function:global:Test-TOTP -Value ${function:Test-TOTP}
    }
}
