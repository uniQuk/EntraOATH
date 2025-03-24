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
            #  Call private helper function
            ConvertTo-Base32 -InputString $InputString -InputFormat $InputFormat -NoValidation:$NoValidation
        }
        catch {
            Write-Error "Error in Convert-Base32: $_"
        }
    }
}

# Create an alias for backward compatibility - only if it doesn't already exist
if (-not (Get-Alias -Name 'Convert-Base32String' -ErrorAction SilentlyContinue)) {
    New-Alias -Name 'Convert-Base32String' -Value 'Convert-Base32'
}