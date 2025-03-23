<#
.SYNOPSIS
    Adds OATH hardware tokens to Microsoft Entra ID
.DESCRIPTION
    Adds one or more OATH hardware tokens to Microsoft Entra ID via the Microsoft Graph API.
    Supports different secret formats (Base32, Hex, and Text) and automatically converts
    them to the required Base32 format.
.PARAMETER Tokens
    An array of token objects to add. Each token must have at least serialNumber and secretKey properties.
.PARAMETER Token
    A single token object to add, with serialNumber and secretKey properties.
.PARAMETER SerialNumber
    The serial number of the token to add when using the simplified parameter set.
.PARAMETER SecretKey
    The secret key of the token to add when using the simplified parameter set.
.PARAMETER SecretFormat
    The format of the provided SecretKey (Base32, Hex, or Text). Defaults to Base32.
.PARAMETER Manufacturer
    The manufacturer of the token to add. Defaults to "Yubico".
.PARAMETER Model
    The model of the token to add. Defaults to "YubiKey".
.PARAMETER DisplayName
    A friendly name for the token. If not provided, the serial number will be used.
.PARAMETER ApiVersion
    The Microsoft Graph API version to use. Defaults to 'beta'.
.EXAMPLE
    $token = @{
        serialNumber = "12345678"
        secretKey = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        manufacturer = "Yubico"
        model = "YubiKey 5"
    }
    Add-OATHToken -Tokens @($token)
    
    Adds a single token with the specified properties.
.EXAMPLE
    Add-OATHToken -SerialNumber "12345678" -SecretKey "3a085cfcd4618c61dc235c300d7a70c4" -SecretFormat Hex
    
    Adds a token with the specified serial number and secret key in hexadecimal format.
.EXAMPLE
    $tokens = Import-Csv -Path "tokens.csv" | ForEach-Object {
        @{
            serialNumber = $_.SerialNumber
            secretKey = $_.SecretKey
            manufacturer = $_.Manufacturer
            model = $_.Model
        }
    }
    Add-OATHToken -Tokens $tokens
    
    Adds multiple tokens from a CSV file.
.NOTES
    Requires Microsoft.Graph.Authentication module and appropriate permissions:
    - Policy.ReadWrite.AuthenticationMethod
#>

function Add-OATHToken {
    [CmdletBinding(DefaultParameterSetName = 'Tokens')]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(ParameterSetName = 'Tokens', Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [object[]]$Tokens,
        
        [Parameter(ParameterSetName = 'Token', Mandatory = $true)]
        [object]$Token,
        
        [Parameter(ParameterSetName = 'Simple', Mandatory = $true)]
        [string]$SerialNumber,
        
        [Parameter(ParameterSetName = 'Simple', Mandatory = $true)]
        [string]$SecretKey,
        
        [Parameter(ParameterSetName = 'Simple')]
        [ValidateSet('Base32', 'Hex', 'Text')]
        [string]$SecretFormat = 'Base32',
        
        [Parameter(ParameterSetName = 'Simple')]
        [string]$Manufacturer = 'Yubico',
        
        [Parameter(ParameterSetName = 'Simple')]
        [string]$Model = 'YubiKey',
        
        [Parameter(ParameterSetName = 'Simple')]
        [string]$DisplayName,
        
        [Parameter()]
        [string]$ApiVersion = 'beta'
    )
    
    begin {
        # Ensure we're connected to Graph
        if (-not (Test-MgConnection)) {
            throw "Microsoft Graph connection required."
        }
        
        $baseEndpoint = "https://graph.microsoft.com/$ApiVersion/directory/authenticationMethodDevices/hardwareOathDevices"
        
        # Create a collection to store tokens to process
        $tokensToProcess = [System.Collections.Generic.List[object]]::new()
        
        # Get existing tokens to check for duplicates
        try {
            Write-Verbose "Retrieving existing tokens..."
            $existingTokens = (Invoke-MgGraphWithErrorHandling -Uri $baseEndpoint).value
            Write-Verbose "Found $($existingTokens.Count) existing tokens"
        }
        catch {
            Write-Warning "Failed to retrieve existing tokens: $_"
            $existingTokens = @()
        }
        
        # Counters for reporting
        $processedCount = 0
        $successCount = 0
        $skippedCount = 0
        $failedCount = 0
        $results = [System.Collections.Generic.List[object]]::new()
    }
    
    process {
        # Handle different parameter sets
        if ($PSCmdlet.ParameterSetName -eq 'Token') {
            $tokensToProcess.Add($Token)
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'Simple') {
            # Create a token object from the simple parameters
            $simpleToken = @{
                serialNumber = $SerialNumber
                secretKey = $SecretKey
                manufacturer = $Manufacturer
                model = $Model
            }
            
            if ($DisplayName) {
                $simpleToken.displayName = $DisplayName
            }
            
            if ($SecretFormat -ne 'Base32') {
                $simpleToken.secretFormat = $SecretFormat.ToLower()
            }
            
            $tokensToProcess.Add($simpleToken)
        }
        else {
            # Add each token from the pipeline
            foreach ($currentToken in $Tokens) {
                $tokensToProcess.Add($currentToken)
            }
        }
    }
    
    end {
        Write-Verbose "Processing $($tokensToProcess.Count) tokens..."
        
        foreach ($currentToken in $tokensToProcess) {
            $processedCount++
            
            try {
                # Validate the token has the required properties
                if (-not $currentToken.serialNumber) {
                    Write-Warning "Token #$processedCount is missing the required 'serialNumber' property"
                    $failedCount++
                    continue
                }
                
                if (-not $currentToken.secretKey) {
                    Write-Warning "Token with serial number $($currentToken.serialNumber) is missing the required 'secretKey' property"
                    $failedCount++
                    continue
                }
                
                # Check for duplicate serial number
                $existingToken = $existingTokens | Where-Object { $_.serialNumber -eq $currentToken.serialNumber }
                if ($existingToken) {
                    Write-Warning "Token with serial number $($currentToken.serialNumber) already exists (ID: $($existingToken.id))"
                    $skippedCount++
                    continue
                }
                
                # Convert secret key to Base32 if needed
                if ($currentToken.secretKey -and (-not [regex]::IsMatch($currentToken.secretKey, '^[A-Z2-7]+=*$'))) {
                    $originalKey = $currentToken.secretKey
                    $format = if ($currentToken.secretFormat -and $currentToken.secretFormat -in @('hex', 'text')) {
                        $currentToken.secretFormat
                    } else {
                        'Hex'  # Default assumption for non-Base32 keys is hex
                    }
                    
                    switch ($format.ToLower()) {
                        'hex' {
                            $currentToken.secretKey = ConvertTo-Base32 -InputString $originalKey -InputFormat 'Hex'
                        }
                        'text' {
                            $currentToken.secretKey = ConvertTo-Base32 -InputString $originalKey -InputFormat 'Text'
                        }
                    }
                    
                    if (-not $currentToken.secretKey) {
                        Write-Warning "Failed to convert secret key for token with serial number $($currentToken.serialNumber)"
                        $failedCount++
                        continue
                    }
                    
                    Write-Verbose "Converted secret key from format '$format' to Base32 for token $($currentToken.serialNumber)"
                }
                
                # Set default values for optional properties if not provided
                if (-not $currentToken.manufacturer) {
                    $currentToken.manufacturer = 'Yubico'
                }
                
                if (-not $currentToken.model) {
                    $currentToken.model = 'YubiKey'
                }
                
                if (-not $currentToken.timeIntervalInSeconds) {
                    $currentToken.timeIntervalInSeconds = 30
                }
                
                if (-not $currentToken.hashFunction) {
                    $currentToken.hashFunction = 'hmacsha1'
                }
                
                if (-not $currentToken.displayName) {
                    $currentToken.displayName = "YubiKey ($($currentToken.serialNumber))"
                }
                
                # Remove any non-Graph API properties
                $propertiesToRemove = @('secretFormat')
                foreach ($prop in $propertiesToRemove) {
                    if ($currentToken.ContainsKey($prop)) {
                        $currentToken.Remove($prop)
                    }
                }
                
                # Add the token
                Write-Verbose "Adding token with serial number: $($currentToken.serialNumber)"
                $body = $currentToken | ConvertTo-Json -Depth 10
                
                try {
                    $response = Invoke-MgGraphWithErrorHandling -Method POST -Uri $baseEndpoint -Body $body -ContentType "application/json"
                    
                    Write-Host "Successfully added token with serial number: $($currentToken.serialNumber)" -ForegroundColor Green
                    $successCount++
                    $results.Add($response)
                }
                catch {
                    Write-Warning "Failed to add token with serial number $($currentToken.serialNumber): $_"
                    $failedCount++
                }
            }
            catch {
                Write-Warning "Unexpected error processing token #$processedCount : $_"
                $failedCount++
            }
        }
        
        # Output summary
        Write-Host "`nToken Addition Summary:" -ForegroundColor Cyan
        Write-Host "  Total Processed: $processedCount" -ForegroundColor White
        Write-Host "  Successfully Added: $successCount" -ForegroundColor Green
        Write-Host "  Skipped (Already Exists): $skippedCount" -ForegroundColor Yellow
        Write-Host "  Failed: $failedCount" -ForegroundColor Red
        
        return $results
    }
}

# Add alias for backward compatibility
New-Alias -Name 'Add-HardwareOathToken' -Value 'Add-OATHToken'
