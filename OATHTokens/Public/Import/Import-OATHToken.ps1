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
    The schema type of the input data. Options are Inventory, UserAssignments, Mixed
.PARAMETER AssignToUsers
    When specified as $false, skips user assignment even if tokens have assignTo properties.
    Defaults to $true to process user assignments automatically.
.PARAMETER Force
    Skips confirmation prompts
.PARAMETER Delimiter
    The delimiter character used in CSV files. Defaults to comma (,)
.EXAMPLE
    Import-OATHToken -FilePath "C:\Temp\tokens.json" -Format JSON
    
    Imports tokens from a JSON file using the default schema and assigns users automatically
.EXAMPLE
    Import-OATHToken -FilePath "C:\Temp\tokens.json" -Format JSON -AssignToUsers:$false
    
    Imports tokens from a JSON file but skips user assignments even if specified in the file
.EXAMPLE
    Import-OATHToken -FilePath "C:\Temp\tokens.csv" -Format CSV
    
    Imports tokens from a CSV file and assigns users automatically if specified
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
        [ValidateSet('Inventory', 'UserAssignments', 'Mixed')]
        [string]$SchemaType = 'Mixed',
        
        [Parameter()]
        [bool]$AssignToUsers = $true,
        
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
                [bool]$ProcessUserAssignments = $true
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
                if ($ProcessUserAssignments) {
                    $userId = $null
                    
                    if ($item.PSObject.Properties.Name -contains 'assignTo') {
                        if ($item.assignTo -and $item.assignTo.id) {
                            $userId = $item.assignTo.id
                        }
                        else {
                            Write-Warning "Token $($token.serialNumber): assignTo property has invalid format"
                        }
                    }
                    elseif ($item.PSObject.Properties.Name -contains 'AssignTo') {
                        if ($item.AssignTo -and $item.AssignTo.id) {
                            $userId = $item.AssignTo.id
                        }
                        else {
                            Write-Warning "Token $($token.serialNumber): AssignTo property has invalid format"
                        }
                    }
                    elseif ($item.PSObject.Properties.Name -contains 'userId' -or 
                           $item.PSObject.Properties.Name -contains 'UserId') {
                        $userId = if ($item.userId) { $item.userId } else { $item.UserId }
                    }
                    # Handle export format
                    elseif ($isExportFormat -and 
                           $item.PSObject.Properties.Name -contains 'AssignedToUpn' -and 
                           -not [string]::IsNullOrWhiteSpace($item.AssignedToUpn)) {
                        $userId = $item.AssignedToUpn
                    }
                    
                    # If userId is not empty, try to resolve it
                    if (-not [string]::IsNullOrWhiteSpace($userId)) {
                        # Check if it's not already a GUID
                        if (-not ($userId -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')) {
                            try {
                                # Resolve UPN to user ID
                                $resolvedUser = Get-MgUserByIdentifier -Identifier $userId
                                if ($resolvedUser) {
                                    Write-Verbose "Resolved user identifier '$userId' to ID: $($resolvedUser.id)"
                                    $userId = $resolvedUser.id
                                }
                                else {
                                    Write-Warning "Token $($token.serialNumber): Could not resolve user: $userId"
                                    $userId = $null
                                }
                            }
                            catch {
                                Write-Warning "Error resolving user $userId`: $_"
                                $userId = $null
                            }
                        }
                        
                        # Add the resolved user ID to the token
                        if (-not [string]::IsNullOrWhiteSpace($userId)) {
                            $token['assignTo'] = @{ id = $userId }
                        }
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
                [ValidateSet('Inventory', 'UserAssignments', 'Mixed')]
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
                    'Mixed' {
                        # Most flexible schema - allow any valid combination
                        if ($JsonData.PSObject.Properties.Name -contains 'inventory' -and $JsonData.inventory -is [array]) {
                            return $true
                        }
                        elseif ($JsonData.PSObject.Properties.Name -contains 'assignments' -and $JsonData.assignments -is [array]) {
                            return $true
                        }
                        else {
                            Write-Error "JSON must contain either an 'inventory' array (which may include 'assignTo' properties) or an 'assignments' array."
                            return $false
                        }
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
                        
                        # Process tokens based on schema type and what's available in the file
                        $processInventory = $true
                        $processAssignments = $AssignToUsers
                        
                        # Determine what to process based on SchemaType
                        if ($SchemaType -eq 'UserAssignments' -and $inputData.PSObject.Properties.Name -contains 'assignments') {
                            # When SchemaType is UserAssignments and assignments array exists, prioritize it
                            $processInventory = $false
                            $processAssignments = $true
                        }
                        elseif ($SchemaType -eq 'Inventory') {
                            # When SchemaType is Inventory, don't process assignments even if they exist
                            $processAssignments = $false
                        }
                        
                        $addedTokens = $null
                        $processedAssignments = 0
                        
                        # Step 1: Process inventory array if needed
                        if ($processInventory -and $inputData.PSObject.Properties.Name -contains 'inventory') {
                            # Convert inventory to token objects
                            $tokens = ConvertTo-TokenObjects -InputData $inputData.inventory -ProcessUserAssignments $AssignToUsers
                            
                            # Check if we have tokens to process
                            if ($tokens.Count -eq 0) {
                                Write-Warning "No valid tokens found in inventory array."
                            }
                            else {
                                # Process the inventory
                                Write-Host "Adding $($tokens.Count) tokens to inventory..." -ForegroundColor Cyan
                                
                                # Confirm before proceeding
                                if (-not $Force -and -not $PSCmdlet.ShouldProcess("$($tokens.Count) tokens", "Import")) {
                                    Write-Warning "Import canceled by user."
                                    return $false
                                }
                                
                                # Add tokens
                                $addedTokens = Add-OATHToken -Tokens $tokens
                                
                                if (-not $addedTokens -or $addedTokens.Count -eq 0) {
                                    Write-Warning "Failed to add any tokens from inventory."
                                }
                                else {
                                    # Process user assignments if requested and if there are any
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
                                                    try {
                                                        $success = Set-OATHTokenUser -TokenId $addedToken.id -UserId $userId -ErrorAction SilentlyContinue
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
                                                    catch {
                                                        # Already logged in Set-OATHTokenUser
                                                    }
                                                }
                                            }
                                        }
                                        
                                        if ($totalEligible -gt 0) {
                                            Write-Host "Assigned $assignmentCount of $totalEligible tokens to users from inventory." -ForegroundColor Green
                                        }
                                    }
                                    
                                    Write-Host "Successfully imported $($addedTokens.Count) of $($tokens.Count) tokens from inventory." -ForegroundColor Green
                                }
                            }
                        }
                        
                        # Step 2: Process assignments array if needed
                        if ($processAssignments && $inputData.PSObject.Properties.Name -contains 'assignments') {
                            $assignments = $inputData.assignments
                            $failedAssignments = 0
                            
                            if ($assignments -and $assignments.Count -gt 0) {
                                Write-Host "Processing $($assignments.Count) token assignments..." -ForegroundColor Cyan
                                
                                # Process existing tokens with new assignments
                                foreach ($assignment in $assignments) {
                                    if (-not $assignment.userId -or -not $assignment.tokenId) {
                                        Write-Warning "Assignment missing userId or tokenId."
                                        $failedAssignments++
                                        continue
                                    }
                                    
                                    # Validate token ID format
                                    if (-not ($assignment.tokenId -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')) {
                                        Write-Warning "Invalid token ID format in assignment: $($assignment.tokenId). Must be a valid GUID."
                                        $failedAssignments++
                                        continue
                                    }
                                    
                                    # Resolve user ID if it's not a GUID
                                    $userId = $assignment.userId
                                    if (-not ($userId -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')) {
                                        try {
                                            $resolvedUser = Get-MgUserByIdentifier -Identifier $userId
                                            if ($resolvedUser) {
                                                Write-Verbose "Resolved user identifier '$userId' to ID: $($resolvedUser.id)"
                                                $userId = $resolvedUser.id
                                            }
                                            else {
                                                Write-Warning "Could not resolve user: $userId - Skipping assignment"
                                                $failedAssignments++
                                                continue
                                            }
                                        }
                                        catch {
                                            Write-Warning "Error resolving user $userId`: $_ - Skipping assignment"
                                            $failedAssignments++
                                            continue
                                        }
                                    }
                                    
                                    if ($Force -or $PSCmdlet.ShouldProcess($assignment.tokenId, "Assign to user $userId")) {
                                        try {
                                            $success = Set-OATHTokenUser -TokenId $assignment.tokenId -UserId $userId -Force:$Force -ErrorAction SilentlyContinue
                                            if ($success) {
                                                $processedAssignments++
                                            }
                                            else {
                                                $failedAssignments++
                                            }
                                        }
                                        catch {
                                            # Error is already output by Set-OATHTokenUser
                                            $failedAssignments++
                                        }
                                    }
                                }
                                
                                Write-Host "Assigned $processedAssignments tokens to users ($failedAssignments failed)." -ForegroundColor Green
                            }
                        }
                        
                        # Return success if either inventory or assignments were processed
                        if ($addedTokens -and $addedTokens.Count -gt 0) {
                            return $addedTokens
                        }
                        elseif ($processedAssignments -gt 0) {
                            return $true
                        }
                        elseif ($processInventory -eq $false -and $processAssignments -eq $true) {
                            # This is a special case for UserAssignments where we processed assignments only
                            return $processedAssignments -gt 0
                        }
                        else {
                            # Only return false if nothing succeeded
                            return $false
                        }
                    }
                    'CSV' {
                        Write-Verbose "Loading CSV data from $FilePath with delimiter '$Delimiter'..."
                        $csvData = Import-Csv -Path $FilePath -Delimiter $Delimiter
                        $tokens = ConvertTo-TokenObjects -InputData $csvData -ProcessUserAssignments $AssignToUsers
                        
                        # Process the tokens as we do with inventory
                        if ($tokens.Count -eq 0) {
                            Write-Warning "No valid tokens found in CSV file."
                            return $false
                        }
                        
                        # Continue with normal inventory processing
                        # ...
                    }
                }
            }
            else {
                # Process InputObject parameter handling
                # ...existing code...
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