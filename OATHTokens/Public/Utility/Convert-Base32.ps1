function Convert-Base32 {
    [CmdletBinding(DefaultParameterSetName = 'String')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ParameterSetName = 'String')]
        [string]$InputString,
        
        [Parameter(ParameterSetName = 'String')]
        [ValidateSet('Base32', 'Hex', 'Text')]
        [string]$InputFormat = 'Hex',
        
        [Parameter(ParameterSetName = 'String')]
        [switch]$NoValidation
    )
    
    process {
        try {
            # Source the private function directly - this avoids the script: scope issues
            . "$PSScriptRoot\..\..\Private\Base32Conversion.ps1"
            
            # Now call the function directly instead of through a script variable
            ConvertTo-Base32 -InputString $InputString -InputFormat $InputFormat -NoValidation:$NoValidation
        }
        catch {
            Write-Error "Error in Convert-Base32: $_"
        }
    }
}

# Create an alias for backward compatibility
New-Alias -Name 'Convert-Base32String' -Value 'Convert-Base32'