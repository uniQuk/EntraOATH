<#
.SYNOPSIS
    Generates unique serial numbers for OATH tokens
.DESCRIPTION
    Creates unique, properly formatted serial numbers for use with OATH hardware tokens.
    Provides several options for format and ensures uniqueness when checking against existing tokens.
.PARAMETER Prefix
    A prefix to add to the generated serial number (e.g., company identifier)
.PARAMETER Length
    The total length of the numeric portion of the serial number
.PARAMETER Format
    The format of the serial number (Numeric, Alphanumeric, Hexadecimal)
.PARAMETER CheckExisting
    If specified, checks that generated serial numbers don't already exist in the tenant
.PARAMETER Count
    The number of serial numbers to generate
.EXAMPLE
    New-OATHTokenSerial
    
    Generates a new random 8-digit numeric serial number
.EXAMPLE
    New-OATHTokenSerial -Prefix "ACME-" -Length 6 -Format Alphanumeric -Count 5
    
    Generates 5 unique alphanumeric serial numbers with "ACME-" prefix, like "ACME-A7B23X"
.EXAMPLE
    New-OATHTokenSerial -Prefix "YK" -Format Hexadecimal -CheckExisting
    
    Generates a hexadecimal serial number with "YK" prefix and checks that it doesn't exist in the tenant
.NOTES
    Requires Microsoft.Graph.Authentication module and appropriate permissions when using -CheckExisting:
    - Policy.ReadWrite.AuthenticationMethod
#>

function New-OATHTokenSerial {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter()]
        [string]$Prefix = "",
        
        [Parameter()]
        [ValidateRange(4, 16)]
        [int]$Length = 8,
        
        [Parameter()]
        [ValidateSet('Numeric', 'Alphanumeric', 'Hexadecimal')]
        [string]$Format = 'Numeric',
        
        [Parameter()]
        [switch]$CheckExisting,
        
        [Parameter()]
        [ValidateRange(1, 1000)]
        [int]$Count = 1
    )
    
    begin {
        # Initialize skip processing flag when checking existing tokens
        $script:skipProcessing = $false
        
        # Generate character sets based on selected format
        function Get-CharacterSet {
            param([string]$Format)
            
            switch ($Format) {
                'Numeric' {
                    return '0123456789'
                }
                'Alphanumeric' {
                    return 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
                }
                'Hexadecimal' {
                    return '0123456789ABCDEF'
                }
                default {
                    throw "Invalid format: $Format"
                }
            }
        }
        
        $charSet = Get-CharacterSet -Format $Format
        $existingSerials = @()
        
        # Retrieve existing tokens if needed
        if ($CheckExisting) {
            if (-not (Test-MgConnection)) {
                $script:skipProcessing = $true
                Write-Warning "Not connected to Microsoft Graph. Cannot check for existing tokens."
                # Not throwing - we'll continue without checking duplicates
            }
            
            if (-not $script:skipProcessing) {
                try {
                    Write-Verbose "Retrieving existing tokens to check for duplicate serial numbers..."
                    $tokens = Get-OATHToken
                    $existingSerials = $tokens | Select-Object -ExpandProperty SerialNumber
                    Write-Verbose "Found $($existingSerials.Count) existing tokens"
                }
                catch {
                    Write-Warning "Failed to retrieve existing tokens: $_"
                    # Don't throw - we'll continue and just not check for duplicates
                }
            }
        }
    }
    
    process {
        $results = @()
        $generateCount = 0
        $attemptCount = 0
        $maxAttempts = $Count * 3  # Allow for some retries in case of duplicates
        
        while ($generateCount -lt $Count -and $attemptCount -lt $maxAttempts) {
            $attemptCount++
            
            # Generate a random serial
            $serial = ""
            for ($i = 0; $i -lt $Length; $i++) {
                $randomIndex = Get-Random -Minimum 0 -Maximum $charSet.Length
                $serial += $charSet[$randomIndex]
            }
            
            # Add prefix if specified
            $completeSerial = "$Prefix$serial"
            
            # Check if it already exists
            if ($CheckExisting -and $existingSerials -contains $completeSerial) {
                Write-Verbose "Serial $completeSerial already exists, generating another..."
                continue
            }
            
            # Check if we've already generated this one
            if ($results -contains $completeSerial) {
                Write-Verbose "Serial $completeSerial is a duplicate of a previously generated serial, generating another..."
                continue
            }
            
            # Add to results and track to avoid duplicates
            $results += $completeSerial
            $existingSerials += $completeSerial
            $generateCount++
        }
        
        if ($generateCount -lt $Count) {
            Write-Warning "Could only generate $generateCount unique serial numbers out of $Count requested after $maxAttempts attempts"
        }
        
        return $results
    }
}
