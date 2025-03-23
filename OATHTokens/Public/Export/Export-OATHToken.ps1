<#
.SYNOPSIS
    Exports OATH hardware tokens to various formats
.DESCRIPTION
    Exports OATH hardware tokens from Microsoft Entra ID to various formats like CSV, JSON, or as PowerShell objects.
.PARAMETER Tokens
    An array of token objects to export. If not provided, all tokens will be retrieved.
.PARAMETER FilePath
    The path where the export file should be created
.PARAMETER Format
    The format to export to. Options are CSV, JSON, and PS (PowerShell objects)
.PARAMETER Delimiter
    The delimiter character to use for CSV format. Defaults to comma (,).
.PARAMETER Force
    Overwrite the file if it already exists
.EXAMPLE
    Export-OATHToken -FilePath "C:\Temp\tokens.csv"
    
    Exports all tokens to a CSV file
.EXAMPLE
    Get-OATHToken -AvailableOnly | Export-OATHToken -FilePath "C:\Temp\available_tokens.json" -Format JSON
    
    Exports only available tokens to a JSON file
.EXAMPLE
    Export-OATHToken -Format PS
    
    Returns token objects as PowerShell objects
.EXAMPLE
    Export-OATHToken -FilePath "C:\Temp\tokens.tsv" -Delimiter "`t"
    
    Exports tokens to a tab-separated values file
.NOTES
    Requires Microsoft.Graph.Authentication module and appropriate permissions:
    - Policy.ReadWrite.AuthenticationMethod
    - Directory.Read.All
#>

function Export-OATHToken {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [object[]]$Tokens,
        
        [Parameter()]
        [string]$FilePath,
        
        [Parameter()]
        [ValidateSet('CSV', 'JSON', 'PS')]
        [string]$Format = 'CSV',
        
        [Parameter()]
        [string]$Delimiter = ',',
        
        [Parameter()]
        [switch]$Force
    )
    
    begin {
        # Create a collection to store tokens
        $allTokens = [System.Collections.Generic.List[object]]::new()
        
        # Set default file path if not provided
        if (-not $FilePath -and $Format -ne 'PS') {
            $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
            $extension = if ($Format -eq 'CSV' -and $Delimiter -eq "`t") { 'tsv' } else { $Format.ToLower() }
            $FilePath = Join-Path -Path $PWD -ChildPath "OATHTokens_$timestamp.$extension"
        }
        
        # Create directory if it doesn't exist
        if ($FilePath) {
            $directory = Split-Path -Path $FilePath -Parent
            if ($directory -and -not (Test-Path -Path $directory)) {
                New-Item -Path $directory -ItemType Directory -Force | Out-Null
            }
            
            # Check if file exists and Force wasn't specified
            if (Test-Path -Path $FilePath -PathType Leaf) {
                if (-not $Force -and -not $PSCmdlet.ShouldProcess($FilePath, "Overwrite existing file")) {
                    throw "File already exists. Use -Force to overwrite."
                }
            }
        }
    }
    
    process {
        # If tokens were provided, add them to our collection
        if ($Tokens) {
            foreach ($token in $Tokens) {
                $allTokens.Add($token)
            }
        }
    }
    
    end {
        try {
            # If no tokens were provided via the pipeline, get them all
            if ($allTokens.Count -eq 0) {
                Write-Verbose "No tokens provided via pipeline. Retrieving all tokens..."
                $retrievedTokens = Get-OATHToken
                foreach ($token in $retrievedTokens) {
                    $allTokens.Add($token)
                }
            }
            
            Write-Verbose "Processing $($allTokens.Count) tokens for export."
            
            # Export in the requested format
            switch ($Format) {
                'CSV' {
                    if ($PSCmdlet.ShouldProcess($FilePath, "Export $($allTokens.Count) tokens to $Format")) {
                        # Select properties suitable for CSV format
                        $csvTokens = $allTokens | Select-Object Id, SerialNumber, DisplayName, Manufacturer, 
                            Model, HashFunction, TimeInterval, Status, LastUsed, Created,
                            AssignedToId, AssignedToName, AssignedToUpn
                        
                        $csvTokens | Export-Csv -Path $FilePath -NoTypeInformation -Delimiter $Delimiter
                        Write-Host "Successfully exported $($allTokens.Count) tokens to $Format : $FilePath" -ForegroundColor Green
                    }
                }
                'JSON' {
                    if ($PSCmdlet.ShouldProcess($FilePath, "Export $($allTokens.Count) tokens to $Format")) {
                        $allTokens | ConvertTo-Json -Depth 10 | Set-Content -Path $FilePath
                        Write-Host "Successfully exported $($allTokens.Count) tokens to $Format : $FilePath" -ForegroundColor Green
                    }
                }
                'PS' {
                    # Just return the tokens as PowerShell objects
                    return $allTokens
                }
            }
            
            # Return true for non-PS formats to indicate success
            if ($Format -ne 'PS') {
                return $true
            }
        }
        catch {
            Write-Error "Error exporting tokens: $_"
            if ($Format -ne 'PS') {
                return $false
            }
        }
    }
}

# Add alias for backward compatibility
New-Alias -Name 'Export-HardwareOathTokensToCsv' -Value 'Export-OATHToken'
