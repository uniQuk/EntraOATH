<#
.SYNOPSIS
    Imports OATH hardware tokens from various sources
.DESCRIPTION
    Imports OATH hardware tokens from CSV, JSON, or other source formats and adds them 
    to Microsoft Entra ID. Can also assign tokens to users during import.
.PARAMETER FilePath
    Path to the file containing token data (JSON or CSV)
.PARAMETER InputObject
    Token data passed as an object (alternative to FilePath)
.PARAMETER Format
    The format of the input data. Options are JSON, CSV
.PARAMETER SchemaType
    The schema type of the input data. Options are Inventory, UserAssignments
.PARAMETER AssignToUsers
    When specified, attempts to assign tokens to users during import
.PARAMETER Force
    Skips confirmation prompts
.PARAMETER Delimiter
    The delimiter character used in CSV files. Defaults to comma (,)
.EXAMPLE
    Import-OATHToken -FilePath "C:\Temp\tokens.json" -Format JSON
    
    Imports tokens from a JSON file using the default schema
.EXAMPLE
    Import-OATHToken -FilePath "C:\Temp\tokens_with_users.json" -SchemaType UserAssignments -AssignToUsers
    
    Imports tokens from a JSON file and assigns them to the specified users
.EXAMPLE
    $tokens = Import-Csv -Path "C:\Temp\tokens.csv"
    Import-OATHToken -InputObject $tokens -Format CSV
    
    Imports tokens from a CSV file that was already loaded
.EXAMPLE
    Import-OATHToken -FilePath "C:\Temp\tokens.csv" -Format CSV -Delimiter "`t"
    
    Imports tokens from a tab-delimited CSV file
.NOTES
    Requires Microsoft.Graph.Authentication module and appropriate permissions:
    - Policy.ReadWrite.AuthenticationMethod
    - Directory.Read.All
#>

function Import-OATHToken {
    [CmdletBinding(DefaultParameterSetName = 'File', SupportsShouldProcess = $true)]
    param(
        [Parameter(ParameterSetName = 'File', Mandatory = $true)]
        [string]$FilePath,
        
        [Parameter(ParameterSetName = 'Object', Mandatory = $true)]
        [object]$InputObject,
        
        [Parameter()]
        [ValidateSet('JSON', 'CSV')]
        [string]$Format,
        
        [Parameter()]
        [ValidateSet('Inventory', 'UserAssignments')]
        [string]$SchemaType = 'Inventory',
        
        [Parameter()]
        [switch]$AssignToUsers,
        
        [Parameter()]
        [switch]$Force,
        
        [Parameter()]
        [string]$Delimiter = ','
    )
    
    begin {
        # Initialize the skip processing flag at the start of each function call
        $script:skipProcessing = $false
        
        # Ensure we're connected to Graph
        if (-not (Test-MgConnection)) {
            $script:skipProcessing = $true
            # Return here only exits the begin block, not the function
            return
        }
        
        # Function to determine format from file extension
        function Get-FormatFromExtension {
            param([string]$Path)
            $extension = [System.IO.Path]::GetExtension($Path).ToLower()
            switch ($extension) {
                '.json' { return 'JSON' }
                '.csv' { return 'CSV' }
                default { throw "Cannot determine format from file extension: $extension. Please specify -Format." }
            }
        }
        
        # Function to convert CSV or PSObject to token objects
        function ConvertTo-TokenObjects {
            param(
                [Parameter(Mandatory = $true)]
                [object[]]$InputData,
                
                [Parameter()]
                [switch]$HasUserAssignments
            )
            
            $tokens = [System.Collections.Generic.List[object]]::new()
            $counter = 1
            
            foreach ($item in $InputData) {
                # Basic token properties
                $token = @{
                    '@contentId' = "$counter"
                }
                
                # Try to detect if this is using export format
                $isExportFormat = $false
                if ($item.PSObject.Properties.Name -contains 'Id' -and 
                    $item.PSObject.Properties.Name -contains 'Status' -and
                    $item.PSObject.Properties.Name -contains 'LastUsed') {
                    $isExportFormat = $true
                }
                
                # Map properties from input
                if ($item.PSObject.Properties.Name -contains 'serialNumber' -or 
                    $item.PSObject.Properties.Name -contains 'SerialNumber') {
                    $token['serialNumber'] = if ($item.serialNumber) { $item.serialNumber } else { $item.SerialNumber }
                }
                elseif ($isExportFormat) {
                    $token['serialNumber'] = $item.SerialNumber
                }
                else {
                    Write-Error "Item #$counter is missing required 'serialNumber' property"
                    continue
                }
                
                if ($item.PSObject.Properties.Name -contains 'secretKey' -or 
                    $item.PSObject.Properties.Name -contains 'SecretKey') {
                    $token['secretKey'] = if ($item.secretKey) { $item.secretKey } else { $item.SecretKey }
                }
                # For export format, we need a secret key to be supplied (not in the export)
                elseif (-not $isExportFormat) {
                    Write-Error "Item #$counter is missing required 'secretKey' property"
                    continue
                }
                
                # Optional properties
                if ($item.PSObject.Properties.Name -contains 'manufacturer' -or 
                    $item.PSObject.Properties.Name -contains 'Manufacturer') {
                    $token['manufacturer'] = if ($item.manufacturer) { $item.manufacturer } else { $item.Manufacturer }
                }
                else {
                    $token['manufacturer'] = 'Yubico'
                }
                
                if ($item.PSObject.Properties.Name -contains 'model' -or 
                    $item.PSObject.Properties.Name -contains 'Model') {
                    $token['model'] = if ($item.model) { $item.model } else { $item.Model }
                }
                else {
                    $token['model'] = 'YubiKey'
                }
                
                if ($item.PSObject.Properties.Name -contains 'displayName' -or 
                    $item.PSObject.Properties.Name -contains 'DisplayName') {
                    $token['displayName'] = if ($item.displayName) { $item.displayName } else { $item.DisplayName }
                }
                
                if ($item.PSObject.Properties.Name -contains 'timeIntervalInSeconds' -or 
                    $item.PSObject.Properties.Name -contains 'TimeInterval') {
                    $token['timeIntervalInSeconds'] = if ($item.timeIntervalInSeconds) { [int]$item.timeIntervalInSeconds } else { [int]$item.TimeInterval }
                }
                else {
                    $token['timeIntervalInSeconds'] = 30
                }
                
                if ($item.PSObject.Properties.Name -contains 'hashFunction' -or 
                    $item.PSObject.Properties.Name -contains 'HashFunction') {
                    $token['hashFunction'] = if ($item.hashFunction) { $item.hashFunction } else { $item.HashFunction }
                }
                else {
                    $token['hashFunction'] = 'hmacsha1'
                }
                
                # Secret format
                if ($item.PSObject.Properties.Name -contains 'secretFormat' -or 
                    $item.PSObject.Properties.Name -contains 'SecretFormat') {
                    $token['secretFormat'] = if ($item.secretFormat) { $item.secretFormat } else { $item.SecretFormat }
                }
                
                # User assignment
                if ($HasUserAssignments) {
                    if ($item.PSObject.Properties.Name -contains 'assignTo') {
                        $token['assignTo'] = $item.assignTo
                    }
                    elseif ($item.PSObject.Properties.Name -contains 'AssignTo') {
                        $token['assignTo'] = $item.AssignTo
                    }
                    elseif ($item.PSObject.Properties.Name -contains 'userId' -or 
                           $item.PSObject.Properties.Name -contains 'UserId') {
                        $userId = if ($item.userId) { $item.userId } else { $item.UserId }
                        $token['assignTo'] = @{ id = $userId }
                    }
                    # Handle export format
                    elseif ($isExportFormat -and 
                           $item.PSObject.Properties.Name -contains 'AssignedToUpn' -and 
                           -not [string]::IsNullOrWhiteSpace($item.AssignedToUpn)) {
                        $token['assignTo'] = @{ id = $item.AssignedToUpn }
                    }
                }
                
                $tokens.Add($token)
                $counter++
            }
            
            return $tokens
        }
        
        # Function to validate JSON schema
        function Test-JsonSchema {
            param(
                [Parameter(Mandatory = $true)]
                [object]$JsonData,
                
                [Parameter(Mandatory = $true)]
                [ValidateSet('Inventory', 'UserAssignments')]
                [string]$SchemaType
            )
            
            try {
                switch ($SchemaType) {
                    'Inventory' {
                        # Check for inventory array
                        if (-not ($JsonData.PSObject.Properties.Name -contains 'inventory')) {
                            Write-Error "JSON does not contain an 'inventory' array property."
                            return $false
                        }
                        
                        if ($JsonData.inventory -isnot [array]) {
                            Write-Error "The 'inventory' property is not an array."
                            return $false
                        }
                        
                        return $true
                    }
                    'UserAssignments' {
                        # Check for either inventory with assignTo or assignments array
                        $hasInventory = $JsonData.PSObject.Properties.Name -contains 'inventory' -and 
                                      $JsonData.inventory -is [array]
                        
                        $hasAssignments = $JsonData.PSObject.Properties.Name -contains 'assignments' -and 
                                        $JsonData.assignments -is [array]
                        
                        if (-not ($hasInventory -or $hasAssignments)) {
                            Write-Error "JSON must contain either an 'inventory' array with 'assignTo' properties or an 'assignments' array."
                            return $false
                        }
                        
                        return $true
                    }
                    default {
                        Write-Error "Unsupported schema type: $SchemaType"
                        return $false
                    }
                }
            }
            catch {
                Write-Error "Error validating JSON schema: $_"
                return $false
            }
        }
    }
    
    process {
        # Skip all processing if the connection check failed
        if ($script:skipProcessing) {
            return $false
        }

        try {
            # Process input source
            if ($PSCmdlet.ParameterSetName -eq 'File') {
                # Check if file exists
                if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
                    throw "File not found: $FilePath"
                }
                
                # Determine format if not specified
                if (-not $Format) {
                    $Format = Get-FormatFromExtension -Path $FilePath
                }
                
                # Load the data
                switch ($Format) {
                    'JSON' {
                        Write-Verbose "Loading JSON data from $FilePath..."
                        $inputData = Get-Content -Path $FilePath -Raw | ConvertFrom-Json
                        
                        # Validate schema
                        if (-not (Test-JsonSchema -JsonData $inputData -SchemaType $SchemaType)) {
                            throw "Invalid JSON schema for type $SchemaType."
                        }
                        
                        if ($SchemaType -eq 'Inventory') {
                            $tokens = ConvertTo-TokenObjects -InputData $inputData.inventory -HasUserAssignments:$AssignToUsers
                        }
                        elseif ($SchemaType -eq 'UserAssignments') {
                            if ($inputData.PSObject.Properties.Name -contains 'inventory') {
                                $tokens = ConvertTo-TokenObjects -InputData $inputData.inventory -HasUserAssignments:$true
                            }
                            elseif ($inputData.PSObject.Properties.Name -contains 'assignments') {
                                # This is for the existing assignment format
                                $assignments = $inputData.assignments
                                $processedAssignments = @()
                                
                                # Process existing tokens with new assignments
                                foreach ($assignment in $assignments) {
                                    if (-not $assignment.userId -or -not $assignment.tokenId) {
                                        Write-Warning "Assignment missing userId or tokenId."
                                        continue
                                    }
                                    
                                    if ($Force -or $PSCmdlet.ShouldProcess($assignment.tokenId, "Assign to user $($assignment.userId)")) {
                                        $success = Set-OATHTokenUser -TokenId $assignment.tokenId -UserId $assignment.userId
                                        if ($success) {
                                            $processedAssignments += $assignment
                                        }
                                    }
                                }
                                
                                Write-Host "Assigned $($processedAssignments.Count) of $($assignments.Count) tokens to users." -ForegroundColor Green
                                return $processedAssignments.Count -gt 0
                            }
                        }
                    }
                    'CSV' {
                        Write-Verbose "Loading CSV data from $FilePath with delimiter '$Delimiter'..."
                        $csvData = Import-Csv -Path $FilePath -Delimiter $Delimiter
                        $tokens = ConvertTo-TokenObjects -InputData $csvData -HasUserAssignments:$AssignToUsers
                    }
                }
            }
            else {
                # Using InputObject parameter
                if (-not $Format) {
                    throw "Format must be specified when using InputObject."
                }
                
                switch ($Format) {
                    'JSON' {
                        # Validate schema
                        if (-not (Test-JsonSchema -JsonData $InputObject -SchemaType $SchemaType)) {
                            throw "Invalid JSON schema for type $SchemaType."
                        }
                        
                        if ($SchemaType -eq 'Inventory') {
                            $tokens = ConvertTo-TokenObjects -InputData $InputObject.inventory -HasUserAssignments:$AssignToUsers
                        }
                        elseif ($SchemaType -eq 'UserAssignments') {
                            if ($InputObject.PSObject.Properties.Name -contains 'inventory') {
                                $tokens = ConvertTo-TokenObjects -InputData $InputObject.inventory -HasUserAssignments:$true
                            }
                            elseif ($InputObject.PSObject.Properties.Name -contains 'assignments') {
                                # This is for the existing assignment format
                                $assignments = $InputObject.assignments
                                $processedAssignments = @()
                                
                                # Process existing tokens with new assignments
                                foreach ($assignment in $assignments) {
                                    if (-not $assignment.userId -or -not $assignment.tokenId) {
                                        Write-Warning "Assignment missing userId or tokenId."
                                        continue
                                    }
                                    
                                    if ($Force -or $PSCmdlet.ShouldProcess($assignment.tokenId, "Assign to user $($assignment.userId)")) {
                                        $success = Set-OATHTokenUser -TokenId $assignment.tokenId -UserId $assignment.userId
                                        if ($success) {
                                            $processedAssignments += $assignment
                                        }
                                    }
                                }
                                
                                Write-Host "Assigned $($processedAssignments.Count) of $($assignments.Count) tokens to users." -ForegroundColor Green
                                return $processedAssignments.Count -gt 0
                            }
                        }
                    }
                    'CSV' {
                        $tokens = ConvertTo-TokenObjects -InputData $InputObject -HasUserAssignments:$AssignToUsers
                    }
                }
            }
            
            # Check if we have tokens to process
            if ($tokens.Count -eq 0) {
                Write-Warning "No valid tokens found to import."
                return $false
            }
            
            # Process tokens
            Write-Verbose "Processing $($tokens.Count) tokens for import..."
            
            # Confirm before proceeding
            if (-not $Force -and -not $PSCmdlet.ShouldProcess("$($tokens.Count) tokens", "Import")) {
                Write-Warning "Import canceled by user."
                return $false
            }
            
            # Add tokens
            Write-Host "Adding $($tokens.Count) tokens to inventory..." -ForegroundColor Cyan
            $addedTokens = Add-OATHToken -Tokens $tokens
            
            if (-not $addedTokens -or $addedTokens.Count -eq 0) {
                Write-Warning "Failed to add any tokens."
                return $false
            }
            
            # Process user assignments if requested
            if ($AssignToUsers) {
                $assignmentCount = 0
                $totalEligible = 0
                
                foreach ($token in $tokens) {
                    if ($token.assignTo -and $token.assignTo.id) {
                        $totalEligible++
                        $userId = $token.assignTo.id
                        
                        # Find the added token with matching serial number
                        $addedToken = $addedTokens | Where-Object { $_.serialNumber -eq $token.serialNumber } | Select-Object -First 1
                        
                        if ($addedToken) {
                            Write-Verbose "Assigning token $($addedToken.id) to user $userId..."
                            $success = Set-OATHTokenUser -TokenId $addedToken.id -UserId $userId
                            if ($success) {
                                $assignmentCount++
                                
                                # Check if we should try to activate the token
                                if ($token.PSObject.Properties.Name -contains 'activate' -and $token.activate -eq $true -and 
                                    $token.PSObject.Properties.Name -contains 'secretKey') {
                                    
                                    Write-Verbose "Attempting to auto-activate token $($addedToken.id)..."
                                    try {
                                        $activateResult = Set-OATHTokenActive -TokenId $addedToken.id -UserId $userId -Secret $token.secretKey
                                        if ($activateResult) {
                                            Write-Verbose "Successfully activated token $($addedToken.id)."
                                        }
                                    }
                                    catch {
                                        Write-Warning "Failed to activate token $($addedToken.id): $_"
                                    }
                                }
                            }
                        }
                    }
                }
                
                if ($totalEligible -gt 0) {
                    Write-Host "Assigned $assignmentCount of $totalEligible tokens to users." -ForegroundColor Green
                }
            }
            
            Write-Host "Successfully imported $($addedTokens.Count) of $($tokens.Count) tokens." -ForegroundColor Green
            return $addedTokens
        }
        catch {
            Write-Error "Error importing tokens: $_"
            return $false
        }
    }
}

# Add aliases for backward compatibility - only if they don't already exist
if (-not (Get-Alias -Name 'Add-BulkHardwareOathTokens' -ErrorAction SilentlyContinue)) {
    New-Alias -Name 'Add-BulkHardwareOathTokens' -Value 'Import-OATHToken'
}
if (-not (Get-Alias -Name 'Add-BulkHardwareOathTokensToUsers' -ErrorAction SilentlyContinue)) {
    New-Alias -Name 'Add-BulkHardwareOathTokensToUsers' -Value 'Import-OATHToken'
}