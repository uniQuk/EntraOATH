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
.PARAMETER TestOnly
    Validates the import file without actually importing tokens
.PARAMETER DetectSchema
    Automatically detect the schema type based on file content
.PARAMETER RemoveDuplicates
    Automatically remove duplicate token entries with the same serial number
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
.EXAMPLE
    Import-OATHToken -FilePath "C:\Temp\tokens.json" -TestOnly
    
    Validates a JSON file without actually importing tokens
.EXAMPLE
    Import-OATHToken -FilePath "C:\Temp\tokens.json" -DetectSchema -RemoveDuplicates
    
    Imports tokens, automatically detecting the schema and removing duplicate entries
.NOTES
    Requires Microsoft.Graph.Authentication module and appropriate permissions:
    - Policy.ReadWrite.AuthenticationMethod
    - Directory.Read.All
#>

function Import-OATHToken {
    [CmdletBinding(DefaultParameterSetName = 'File', SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
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
        [string]$Delimiter = ',',
        
        [Parameter()]
        [switch]$TestOnly,
        
        [Parameter()]
        [switch]$DetectSchema,
        
        [Parameter()]
        [switch]$RemoveDuplicates
    )
    
    begin {
        # Ensure we're connected to Graph
        if (-not (Test-MgConnection)) {
            throw "Microsoft Graph connection required."
        }
        
        # Initialize result object
        $importResult = [PSCustomObject]@{
            Success = $false
            InputType = $PSCmdlet.ParameterSetName
            SourcePath = if ($PSCmdlet.ParameterSetName -eq 'File') { $FilePath } else { "InputObject" }
            Format = $Format
            SchemaType = $SchemaType
            TestMode = $TestOnly.IsPresent
            DetectedSchema = $null
            DetectedOperations = $null  # Add this property to fix the error
            TotalProcessed = 0
            RemovedDuplicates = 0
            Valid = 0
            Invalid = 0
            ValidationIssues = @()
            DuplicateSerials = @()
            NonexistentUsers = @()
            Added = @()
            Skipped = @()
            Failed = @()
            AssignmentSuccesses = @()
            AssignmentFailures = @()
            ActivationSuccesses = @()
            ActivationFailures = @()
            Errors = @()
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
        
        # Function to better detect schema type and operations based on content
        function Detect-SchemaAndOperations {
            param(
                [Parameter(Mandatory = $true)]
                [object]$Data
            )
            
            try {
                $result = @{
                    SchemaType = 'Inventory'
                    Operations = @{
                        Add = $false
                        Assign = $false
                        Activate = $false
                    }
                }
                
                # Check if this is JSON data with an inventory array
                if ($Data.PSObject.Properties.Name -contains 'inventory' -and $Data.inventory -is [array]) {
                    $hasAssignTo = $false
                    $hasActivate = $false
                    
                    # Check inventory items for assignment and activation operations
                    foreach ($item in $Data.inventory) {
                        if ($item.PSObject.Properties.Name -contains 'assignTo') {
                            $hasAssignTo = $true
                        }
                        
                        if ($item.PSObject.Properties.Name -contains 'activate' -and $item.activate -eq $true) {
                            $hasActivate = $true
                        }
                        
                        # If we found both operations, we can stop checking
                        if ($hasAssignTo -and $hasActivate) {
                            break
                        }
                    }
                    
                    # Determine schema type based on operations
                    if ($hasAssignTo) {
                        $result.SchemaType = 'UserAssignments'
                        $result.Operations.Add = $true
                        $result.Operations.Assign = $true
                        
                        if ($hasActivate) {
                            $result.Operations.Activate = $true
                            Write-Verbose "Detected schema: UserAssignments with Add, Assign, and Activate operations"
                        } else {
                            Write-Verbose "Detected schema: UserAssignments with Add and Assign operations"
                        }
                    } else {
                        $result.SchemaType = 'Inventory'
                        $result.Operations.Add = $true
                        Write-Verbose "Detected schema: Inventory (Add only)"
                    }
                }
                # Check for assignments array
                elseif ($Data.PSObject.Properties.Name -contains 'assignments' -and $Data.assignments -is [array]) {
                    $result.SchemaType = 'UserAssignments'
                    $result.Operations.Assign = $true
                    Write-Verbose "Detected schema: UserAssignments (Assign only)"
                }
                # Check if this is a flat array (like CSV data)
                elseif ($Data -is [array] -and $Data.Count -gt 0) {
                    $hasAssignmentField = $false
                    $hasActivateField = $false
                    
                    $firstItem = $Data[0]
                    # Check for assignment fields
                    if ($firstItem.PSObject.Properties.Name -contains 'assignTo' -or 
                        $firstItem.PSObject.Properties.Name -contains 'AssignTo' -or 
                        $firstItem.PSObject.Properties.Name -contains 'userId' -or 
                        $firstItem.PSObject.Properties.Name -contains 'UserId' -or 
                        $firstItem.PSObject.Properties.Name -contains 'AssignedToUpn') {
                        $hasAssignmentField = $true
                    }
                    
                    # Check for activate field
                    if ($firstItem.PSObject.Properties.Name -contains 'activate' -or 
                        $firstItem.PSObject.Properties.Name -contains 'Activate') {
                        $hasActivateField = $true
                    }
                    
                    if ($hasAssignmentField) {
                        $result.SchemaType = 'UserAssignments'
                        $result.Operations.Add = $true
                        $result.Operations.Assign = $true
                        
                        if ($hasActivateField) {
                            $result.Operations.Activate = $true
                            Write-Verbose "Detected schema: UserAssignments with Add, Assign, and potentially Activate operations"
                        } else {
                            Write-Verbose "Detected schema: UserAssignments with Add and Assign operations"
                        }
                    } else {
                        $result.SchemaType = 'Inventory'
                        $result.Operations.Add = $true
                        Write-Verbose "Detected schema: Inventory (Add only)"
                    }
                }
                
                return $result
            }
            catch {
                Write-Warning "Error detecting schema and operations: $_. Defaulting to Inventory."
                return @{
                    SchemaType = 'Inventory'
                    Operations = @{
                        Add = $true
                        Assign = $false
                        Activate = $false
                    }
                }
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
        
        # Function to remove duplicate tokens keeping only the most complete entries
        function Remove-DuplicateTokens {
            param(
                [Parameter(Mandatory = $true)]
                [object[]]$Tokens
            )
            
            $uniqueTokens = [System.Collections.Generic.List[object]]::new()
            $serialMap = @{}
            $duplicateCount = 0
            
            # Define a function to score a token by completeness
            function Get-TokenCompletenessScore {
                param([object]$Token)
                
                $score = 0
                
                # Basic required properties
                if (-not [string]::IsNullOrWhiteSpace($Token.serialNumber)) { $score += 10 }
                if (-not [string]::IsNullOrWhiteSpace($Token.secretKey)) { $score += 10 }
                
                # Optional properties
                if (-not [string]::IsNullOrWhiteSpace($Token.manufacturer)) { $score += 1 }
                if (-not [string]::IsNullOrWhiteSpace($Token.model)) { $score += 1 }
                if (-not [string]::IsNullOrWhiteSpace($Token.displayName)) { $score += 1 }
                if ($Token.timeIntervalInSeconds -ne $null) { $score += 1 }
                if (-not [string]::IsNullOrWhiteSpace($Token.hashFunction)) { $score += 1 }
                
                # User assignment
                if ($Token.assignTo -and $Token.assignTo.id) { $score += 5 }
                
                # Activation flag - fix the validation logic to properly respect secretFormat
                if ($Token.activate -eq $true) { $score += 3 }
                
                return $score
            }
            
            # Process each token
            foreach ($token in $Tokens) {
                if ([string]::IsNullOrWhiteSpace($token.serialNumber)) {
                    # Skip tokens without serial numbers
                    continue
                }
                
                $serial = $token.serialNumber
                
                if (-not $serialMap.ContainsKey($serial)) {
                    # First time seeing this serial number
                    $serialMap[$serial] = @{
                        Token = $token
                        Score = Get-TokenCompletenessScore -Token $token
                    }
                }
                else {
                    # Duplicate serial - compare completeness scores
                    $currentScore = Get-TokenCompletenessScore -Token $token
                    if ($currentScore > $serialMap[$serial].Score) {
                        # Current token is more complete, replace the previous one
                        $serialMap[$serial] = @{
                            Token = $token
                            Score = $currentScore
                        }
                    }
                    
                    $duplicateCount++
                }
            }
            
            # Convert the map back to a list
            foreach ($entry in $serialMap.Values) {
                $uniqueTokens.Add($entry.Token)
            }
            
            Write-Verbose "Removed $duplicateCount duplicate tokens, keeping $($uniqueTokens.Count) unique tokens"
            
            return @{
                Tokens = $uniqueTokens
                DuplicateCount = $duplicateCount
            }
        }
        
        # Function to validate token fields
        function Test-TokenValidity {
            param(
                [Parameter(Mandatory = $true)]
                [object]$Token,
                
                [Parameter()]
                [int]$Index
            )
            
            $validationIssues = @()
            
            # Validate serial number
            if ([string]::IsNullOrWhiteSpace($Token.serialNumber)) {
                $validationIssues += "Token #$Index is missing required 'serialNumber' property"
            }
            elseif (-not (Test-OATHSerialNumber -SerialNumber $Token.serialNumber)) {
                $validationIssues += "Token #$Index has invalid 'serialNumber': $($Token.serialNumber)"
            }
            
            # Validate secret key (not required for validation-only if no activation is requested)
            if ([string]::IsNullOrWhiteSpace($Token.secretKey)) {
                if (-not $TestOnly -or ($TestOnly -and $Token.PSObject.Properties.Name -contains 'activate' -and $Token.activate -eq $true)) {
                    $validationIssues += "Token #$Index is missing required 'secretKey' property"
                }
            }
            else {
                # Important: Check if secretFormat is explicitly set and SKIP validation for Hex and Text formats
                if ($Token.PSObject.Properties.Name -contains 'secretFormat') {
                    $format = $Token.secretFormat.ToLower()
                    
                    # Skip validation for Hex and Text formats
                    if ($format -eq 'hex' -or $format -eq 'text') {
                        # These formats have different validation requirements, so we'll skip validation here
                        # and rely on conversion during the actual token addition
                        Write-Verbose "Token #$Index has secretFormat=$format, skipping Base32 validation"
                    }
                    elseif ($format -eq 'base32') {
                        # Only validate Base32 format which has specific character constraints
                        if (-not (Test-OATHSecretKey -SecretKey $Token.secretKey -Format 'Base32')) {
                            $validationIssues += "Token #$Index has invalid 'secretKey' for format 'Base32'"
                        }
                    }
                    else {
                        $validationIssues += "Token #$Index has invalid 'secretFormat': $format. Must be Base32, Hex, or Text."
                    }
                }
                else {
                    # No format specified - attempt to auto-detect format
                    if ([regex]::IsMatch($Token.secretKey, '^[A-Z2-7]+=*$')) {
                        # Looks like Base32, validate it
                        if (-not (Test-OATHSecretKey -SecretKey $Token.secretKey -Format 'Base32')) {
                            $validationIssues += "Token #$Index has invalid 'secretKey' for format 'Base32'"
                        }
                    }
                    # FIX: This is the line with the syntax error - added the missing { } block
                    elseif ([regex]::IsMatch($Token.secretKey, '^[0-9a-fA-F]+$')) {
                        # Looks like Hex, don't validate further
                        Write-Verbose "Token #$Index appears to have a Hex secret, assuming secretFormat=Hex"
                    }
                    else {
                        # Assume it's Text, don't validate further
                        Write-Verbose "Token #$Index appears to have a Text secret, assuming secretFormat=Text"
                    }
                }
            }
            
            # Validate hash function if provided
            if ($Token.PSObject.Properties.Name -contains 'hashFunction' -and 
                -not [string]::IsNullOrWhiteSpace($Token.hashFunction) -and
                $Token.hashFunction -notmatch '^(hmacsha1|hmacsha256|hmacsha512)$') {
                
                $validationIssues += "Token #$Index has invalid 'hashFunction': $($Token.hashFunction). Must be hmacsha1, hmacsha256, or hmacsha512."
            }
            
            # Validate time interval if provided
            if ($Token.PSObject.Properties.Name -contains 'timeIntervalInSeconds' -and 
                $Token.timeIntervalInSeconds -and
                ($Token.timeIntervalInSeconds -lt 10 -or $Token.timeIntervalInSeconds -gt 120)) {
                
                $validationIssues += "Token #$Index has invalid 'timeIntervalInSeconds': $($Token.timeIntervalInSeconds). Must be between 10 and 120."
            }
            
            # If there are no validation issues, return true
            if ($validationIssues.Count -eq 0) {
                return @{
                    IsValid = $true
                    Issues = @()
                }
            }
            else {
                return @{
                    IsValid = $false
                    Issues = $validationIssues
                }
            }
        }
        
        # Function to check for duplicate serials
        function Find-DuplicateSerials {
            param(
                [Parameter(Mandatory = $true)]
                [object[]]$Tokens
            )
            
            $serialCounts = @{}
            $duplicates = @()
            
            foreach ($token in $Tokens) {
                $serial = $token.serialNumber
                if (-not [string]::IsNullOrWhiteSpace($serial)) {
                    if (-not $serialCounts.ContainsKey($serial)) {
                        $serialCounts[$serial] = 1
                    }
                    else {
                        $serialCounts[$serial]++
                        if ($serialCounts[$serial] -eq 2) {
                            $duplicates += $serial
                        }
                    }
                }
            }
            
            return $duplicates
        }
        
        # Function to check if users exist
        function Test-UserExists {
            param(
                [Parameter(Mandatory = $true)]
                [string]$UserId
            )
            
            try {
                # Check if the identifier looks like a GUID
                if ($UserId -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
                    # Try to get user directly by ID
                    try {
                        $user = Get-MgUser -UserId $UserId -ErrorAction Stop
                        return $true
                    }
                    catch {
                        Write-Verbose "User not found by ID: $UserId"
                        return $false
                    }
                }
                
                # Check if it looks like an email/UPN
                if ($UserId -match '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$') {
                    # Try exact match by UPN
                    try {
                        $filter = "userPrincipalName eq '$UserId'"
                        $users = Get-MgUser -Filter $filter -ErrorAction Stop
                        
                        if ($users -and $users.Count -gt 0) {
                            return $true
                        }
                    }
                    catch {
                        Write-Verbose "Error searching by UPN: $_"
                    }
                    
                    # Try by mail
                    try {
                        $filter = "mail eq '$UserId'"
                        $users = Get-MgUser -Filter $filter -ErrorAction Stop
                        
                        if ($users -and $users.Count -gt 0) {
                            return $true
                        }
                    }
                    catch {
                        Write-Verbose "Error searching by mail: $_"
                    }
                }
                
                # Try by display name
                try {
                    $filter = "displayName eq '$UserId'"
                    $users = Get-MgUser -Filter $filter -ErrorAction Stop
                    
                    if ($users -and $users.Count -gt 0) {
                        return $true
                    }
                }
                catch {
                    Write-Verbose "Error searching by display name: $_"
                }
                
                # No user found with any method
                Write-Warning "No users found matching the identifier: $UserId"
                return $false
            }
            catch {
                Write-Verbose "Error checking if user exists: $_"
                return $false
            }
        }
        
        # Function to check for existing tokens with the same serial numbers
        function Find-ExistingTokens {
            param(
                [Parameter(Mandatory = $true)]
                [object[]]$Tokens
            )
            
            $existingTokens = @{}
            
            # Get all existing tokens in one call
            $allTokens = Get-OATHToken
            
            # Create a lookup table for existing tokens by serial number
            foreach ($token in $allTokens) {
                if (-not [string]::IsNullOrWhiteSpace($token.SerialNumber)) {
                    $existingTokens[$token.SerialNumber] = $token
                }
            }
            
            # Check which tokens already exist
            $alreadyExists = @()
            
            foreach ($token in $Tokens) {
                if (-not [string]::IsNullOrWhiteSpace($token.serialNumber) -and $existingTokens.ContainsKey($token.serialNumber)) {
                    $alreadyExists += [PSCustomObject]@{
                        SerialNumber = $token.serialNumber
                        ExistingTokenId = $existingTokens[$token.serialNumber].Id
                        Status = $existingTokens[$token.serialNumber].Status
                    }
                }
            }
            
            return $alreadyExists
        }
    }
    
    process {
        try {
            $tokens = @()
            
            # Process input source
            if ($PSCmdlet.ParameterSetName -eq 'File') {
                # Check if file exists
                if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
                    $errorMsg = "File not found: $FilePath"
                    $importResult.Errors += $errorMsg
                    throw $errorMsg
                }
                
                # Determine format if not specified
                if (-not $Format) {
                    $Format = Get-FormatFromExtension -Path $FilePath
                    $importResult.Format = $Format
                }
                
                # Load the data
                switch ($Format) {
                    'JSON' {
                        Write-Verbose "Loading JSON data from $FilePath..."
                        $inputData = Get-Content -Path $FilePath -Raw | ConvertFrom-Json
                        
                        # Auto-detect schema if requested
                        if ($DetectSchema) {
                            $detectionResult = Detect-SchemaAndOperations -Data $inputData
                            $SchemaType = $detectionResult.SchemaType
                            $importResult.SchemaType = $SchemaType
                            $importResult.DetectedSchema = $SchemaType
                            $importResult.DetectedOperations = $detectionResult.Operations
                            
                            # Show detailed schema detection results
                            Write-Host "Detected schema type: $SchemaType" -ForegroundColor Cyan
                            Write-Host "Detected operations:" -ForegroundColor Cyan
                            Write-Host "  - Add tokens: $($detectionResult.Operations.Add)" -ForegroundColor $(if ($detectionResult.Operations.Add) { "Green" } else { "Gray" })
                            Write-Host "  - Assign tokens: $($detectionResult.Operations.Assign)" -ForegroundColor $(if ($detectionResult.Operations.Assign) { "Green" } else { "Gray" })
                            Write-Host "  - Activate tokens: $($detectionResult.Operations.Activate)" -ForegroundColor $(if ($detectionResult.Operations.Activate) { "Green" } else { "Gray" })
                        }
                        
                        # Validate schema
                        if (-not (Test-JsonSchema -JsonData $inputData -SchemaType $SchemaType)) {
                            $errorMsg = "Invalid JSON schema for type $SchemaType."
                            $importResult.Errors += $errorMsg
                            throw $errorMsg
                        }
                        
                        if ($SchemaType -eq 'Inventory') {
                            $tokens = ConvertTo-TokenObjects -InputData $inputData.inventory -HasUserAssignments:$AssignToUsers
                        }
                        elseif ($SchemaType -eq 'UserAssignments') {
                            if ($inputData.PSObject.Properties.Name -contains 'inventory') {
                                $tokens = ConvertTo-TokenObjects -InputData $inputData.inventory -HasUserAssignments:$true
                            }
                            elseif ($inputData.PSObject.Properties.Name -contains 'assignments') {
                                # Handle assignment-only format for TestOnly mode
                                if ($TestOnly) {
                                    $assignments = $inputData.assignments
                                    $importResult.TotalProcessed = $assignments.Count
                                    
                                    $validUserIds = @()
                                    $validTokenIds = @()
                                    $nonexistentUsers = @()
                                    $nonexistentTokens = @()
                                    
                                    # Check token and user IDs
                                    foreach ($assignment in $assignments) {
                                        if (-not $assignment.userId -or -not $assignment.tokenId) {
                                            $importResult.ValidationIssues += "Assignment missing userId or tokenId"
                                            $importResult.Invalid++
                                            continue
                                        }
                                        
                                        $userExists = Test-UserExists -UserId $assignment.userId
                                        if (-not $userExists) {
                                            $nonexistentUsers += $assignment.userId
                                            $importResult.ValidationIssues += "User not found: $($assignment.userId)"
                                        }
                                        else {
                                            $validUserIds += $assignment.userId
                                        }
                                        
                                        $tokenExists = Test-OATHTokenId -TokenId $assignment.tokenId
                                        if (-not $tokenExists) {
                                            $nonexistentTokens += $assignment.tokenId
                                            $importResult.ValidationIssues += "Invalid token ID format: $($assignment.tokenId)"
                                        }
                                        else {
                                            $validTokenIds += $assignment.tokenId
                                        }
                                    }
                                    
                                    $importResult.Valid = $validUserIds.Count
                                    $importResult.Invalid = $assignments.Count - $validUserIds.Count
                                    $importResult.NonexistentUsers = $nonexistentUsers
                                    
                                    Write-Host "Validation Summary:" -ForegroundColor Cyan
                                    Write-Host "  Total Assignments: $($assignments.Count)" -ForegroundColor White
                                    Write-Host "  Valid User IDs: $($validUserIds.Count)" -ForegroundColor Green
                                    Write-Host "  Invalid User IDs: $($nonexistentUsers.Count)" -ForegroundColor Red
                                    Write-Host "  Valid Token IDs: $($validTokenIds.Count)" -ForegroundColor Green
                                    Write-Host "  Invalid Token IDs: $($nonexistentTokens.Count)" -ForegroundColor Red
                                    
                                    $importResult.Success = $importResult.ValidationIssues.Count -eq 0
                                    return $importResult
                                }
                                else {
                                    # Process assignments (original non-test behavior)
                                    $assignments = $inputData.assignments
                                    $processedAssignments = @()
                                    
                                    # Process existing tokens with new assignments
                                    foreach ($assignment in $assignments) {
                                        if (-not $assignment.userId -or -not $assignment.tokenId) {
                                            $importResult.AssignmentFailures += [PSCustomObject]@{
                                                TokenId = $assignment.tokenId
                                                UserId = $assignment.userId
                                                Reason = "Missing userId or tokenId"
                                            }
                                            Write-Warning "Assignment missing userId or tokenId."
                                            continue
                                        }
                                        
                                        if ($Force -or $PSCmdlet.ShouldProcess($assignment.tokenId, "Assign to user $($assignment.userId)")) {
                                            $result = Set-OATHTokenUser -TokenId $assignment.tokenId -UserId $assignment.userId
                                            if ($result.Success) {
                                                $processedAssignments += $assignment
                                                $importResult.AssignmentSuccesses += [PSCustomObject]@{
                                                    TokenId = $assignment.tokenId
                                                    UserId = $assignment.userId
                                                }
                                            }
                                            else {
                                                $importResult.AssignmentFailures += [PSCustomObject]@{
                                                    TokenId = $assignment.tokenId
                                                    UserId = $assignment.userId
                                                    Reason = $result.Reason
                                                }
                                            }
                                        }
                                    }
                                    
                                    Write-Host "Assigned $($processedAssignments.Count) of $($assignments.Count) tokens to users." -ForegroundColor Green
                                    $importResult.Success = $processedAssignments.Count -gt 0
                                    $importResult.TotalProcessed = $assignments.Count
                                    return $importResult
                                }
                            }
                        }
                    }
                    'CSV' {
                        Write-Verbose "Loading CSV data from $FilePath with delimiter '$Delimiter'..."
                        $csvData = Import-Csv -Path $FilePath -Delimiter $Delimiter
                        
                        # Auto-detect schema if requested
                        if ($DetectSchema) {
                            $detectionResult = Detect-SchemaAndOperations -Data $csvData
                            $SchemaType = $detectionResult.SchemaType
                            $importResult.SchemaType = $SchemaType
                            $importResult.DetectedSchema = $SchemaType
                            $importResult.DetectedOperations = $detectionResult.Operations
                            
                            # Show detailed schema detection results
                            Write-Host "Detected schema type: $SchemaType" -ForegroundColor Cyan
                            Write-Host "Detected operations:" -ForegroundColor Cyan
                            Write-Host "  - Add tokens: $($detectionResult.Operations.Add)" -ForegroundColor $(if ($detectionResult.Operations.Add) { "Green" } else { "Gray" })
                            Write-Host "  - Assign tokens: $($detectionResult.Operations.Assign)" -ForegroundColor $(if ($detectionResult.Operations.Assign) { "Green" } else { "Gray" })
                            Write-Host "  - Activate tokens: $($detectionResult.Operations.Activate)" -ForegroundColor $(if ($detectionResult.Operations.Activate) { "Green" } else { "Gray" })
                        }
                        
                        $tokens = ConvertTo-TokenObjects -InputData $csvData -HasUserAssignments:($SchemaType -eq 'UserAssignments' -or $AssignToUsers)
                    }
                }
            }
            else {
                # Using InputObject parameter
                if (-not $Format) {
                    $errorMsg = "Format must be specified when using InputObject."
                    $importResult.Errors += $errorMsg
                    throw $errorMsg
                }
                
                # Auto-detect schema if requested
                if ($DetectSchema) {
                    $detectionResult = Detect-SchemaAndOperations -Data $InputObject
                    $SchemaType = $detectionResult.SchemaType
                    $importResult.SchemaType = $SchemaType
                    $importResult.DetectedSchema = $SchemaType
                    $importResult.DetectedOperations = $detectionResult.Operations
                    
                    # Show detailed schema detection results
                    Write-Host "Detected schema type: $SchemaType" -ForegroundColor Cyan
                    Write-Host "Detected operations:" -ForegroundColor Cyan
                    Write-Host "  - Add tokens: $($detectionResult.Operations.Add)" -ForegroundColor $(if ($detectionResult.Operations.Add) { "Green" } else { "Gray" })
                    Write-Host "  - Assign tokens: $($detectionResult.Operations.Assign)" -ForegroundColor $(if ($detectionResult.Operations.Assign) { "Green" } else { "Gray" })
                    Write-Host "  - Activate tokens: $($detectionResult.Operations.Activate)" -ForegroundColor $(if ($detectionResult.Operations.Activate) { "Green" } else { "Gray" })
                }
                
                switch ($Format) {
                    'JSON' {
                        # Validate schema
                        if (-not (Test-JsonSchema -JsonData $InputObject -SchemaType $SchemaType)) {
                            $errorMsg = "Invalid JSON schema for type $SchemaType."
                            $importResult.Errors += $errorMsg
                            throw $errorMsg
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
                        $tokens = ConvertTo-TokenObjects -InputData $InputObject -HasUserAssignments:($SchemaType -eq 'UserAssignments' -or $AssignToUsers)
                    }
                }
            }
            
            # Check if we have tokens to process
            if ($tokens.Count -eq 0) {
                Write-Warning "No valid tokens found to import."
                $importResult.Errors += "No valid tokens found to import."
                return $importResult
            }
            
            $importResult.TotalProcessed = $tokens.Count
            
            # Remove duplicates if requested
            if ($RemoveDuplicates) {
                $removeResult = Remove-DuplicateTokens -Tokens $tokens
                $tokens = $removeResult.Tokens
                $importResult.RemovedDuplicates = $removeResult.DuplicateCount
                
                if ($removeResult.DuplicateCount -gt 0) {
                    Write-Host "Removed $($removeResult.DuplicateCount) duplicate tokens, keeping $($tokens.Count) unique tokens" -ForegroundColor Yellow
                }
            }
            
            # Perform validation
            $validationResults = @{
                Valid = 0
                Invalid = 0
                Issues = @()
            }
            
            for ($i = 0; $i -lt $tokens.Count; $i++) {
                $tokenValidation = Test-TokenValidity -Token $tokens[$i] -Index ($i + 1)
                
                if ($tokenValidation.IsValid) {
                    $validationResults.Valid++
                }
                else {
                    $validationResults.Invalid++
                    $validationResults.Issues += $tokenValidation.Issues
                }
            }
            
            # Capture validation results in the import result object
            $importResult.Valid = $validationResults.Valid
            $importResult.Invalid = $validationResults.Invalid
            $importResult.ValidationIssues = $validationResults.Issues
            
            # Check for duplicate serial numbers (after removing duplicates if requested)
            $duplicateSerials = Find-DuplicateSerials -Tokens $tokens
            $importResult.DuplicateSerials = $duplicateSerials
            
            if ($duplicateSerials.Count -gt 0) {
                Write-Warning "Found $($duplicateSerials.Count) duplicate serial numbers in the import data."
                foreach ($serial in $duplicateSerials) {
                    Write-Warning "Duplicate serial number: $serial"
                    $importResult.ValidationIssues += "Duplicate serial number: $serial"
                }
            }
            
            # Check for existing tokens with the same serial numbers
            $existingTokens = Find-ExistingTokens -Tokens $tokens
            if ($existingTokens.Count -gt 0) {
                Write-Warning "Found $($existingTokens.Count) tokens that already exist in the system."
                foreach ($token in $existingTokens) {
                    Write-Warning "Token with serial number $($token.SerialNumber) already exists (ID: $($token.ExistingTokenId), Status: $($token.Status))"
                    $importResult.ValidationIssues += "Token with serial number $($token.SerialNumber) already exists (ID: $($token.ExistingTokenId))"
                }
            }
            
            # Validate user assignments if requested
            if ($AssignToUsers -or $SchemaType -eq 'UserAssignments') {
                $userIdsToCheck = @()
                $userMap = @{}
                
                foreach ($token in $tokens) {
                    if ($token.assignTo -and $token.assignTo.id) {
                        $userId = $token.assignTo.id
                        if (-not $userMap.ContainsKey($userId)) {
                            $userIdsToCheck += $userId
                            $userMap[$userId] = $false
                        }
                    }
                }
                
                # Check if users exist
                $nonexistentUsers = @()
                foreach ($userId in $userIdsToCheck) {
                    $userExists = Test-UserExists -UserId $userId
                    if (-not $userExists) {
                        $nonexistentUsers += $userId
                        $importResult.ValidationIssues += "User not found: $userId"
                    }
                    else {
                        $userMap[$userId] = $true
                    }
                }
                
                $importResult.NonexistentUsers = $nonexistentUsers
                
                if ($nonexistentUsers.Count -gt 0) {
                    Write-Warning "Found $($nonexistentUsers.Count) user IDs that do not exist in the system."
                    foreach ($userId in $nonexistentUsers) {
                        Write-Warning "User not found: $userId"
                    }
                }
            }
            
            # Display validation summary
            Write-Host "Validation Summary:" -ForegroundColor Cyan
            Write-Host "  Total Tokens: $($tokens.Count)" -ForegroundColor White
            
            if ($RemoveDuplicates -and $importResult.RemovedDuplicates -gt 0) {
                Write-Host "  Duplicates Removed: $($importResult.RemovedDuplicates)" -ForegroundColor Yellow
            }
            
            Write-Host "  Valid Tokens: $($validationResults.Valid)" -ForegroundColor Green
            Write-Host "  Invalid Tokens: $($validationResults.Invalid)" -ForegroundColor Red
            Write-Host "  Duplicate Serial Numbers: $($duplicateSerials.Count)" -ForegroundColor Yellow
            Write-Host "  Already Existing Tokens: $($existingTokens.Count)" -ForegroundColor Yellow
            
            if ($AssignToUsers -or $SchemaType -eq 'UserAssignments') {
                Write-Host "  Nonexistent Users: $($nonexistentUsers.Count)" -ForegroundColor Red
            }
            
            # If in test-only mode, return validation results
            if ($TestOnly) {
                $importResult.Success = $validationResults.Issues.Count -eq 0 -and $duplicateSerials.Count -eq 0 -and $nonexistentUsers.Count -eq 0
                
                # Show validation issues
                if ($validationResults.Issues.Count -gt 0) {
                    Write-Host "`nValidation Issues:" -ForegroundColor Yellow
                    foreach ($issue in $validationResults.Issues) {
                        Write-Host "  $issue" -ForegroundColor Yellow
                    }
                }
                
                return $importResult
            }
            
            # For normal mode, continue with import if validation passed
            if ($validationResults.Invalid -gt 0 -or $duplicateSerials.Count -gt 0) {
                $errorMsg = "Validation failed with $($validationResults.Invalid) invalid tokens and $($duplicateSerials.Count) duplicate serial numbers."
                $importResult.Errors += $errorMsg
                Write-Error $errorMsg
                return $importResult
            }
            
            # Confirm before proceeding
            if (-not $Force -and -not $PSCmdlet.ShouldProcess("$($tokens.Count) tokens", "Import")) {
                Write-Warning "Import canceled by user."
                $importResult.Errors += "Import canceled by user."
                return $importResult
            }
            
            # Continue with the original import logic...
            Write-Host "Adding $($tokens.Count) tokens to inventory..." -ForegroundColor Cyan

            # Handle tokens with different secret formats
            $addedTokens = @()
            foreach ($token in $tokens) {
                try {
                    # Debug information to help diagnose the issue
                    Write-Verbose "Processing token: $($token | ConvertTo-Json -Compress)"
                    
                    # Extract the required properties directly
                    $serialNumber = $token.serialNumber
                    $secretKey = $token.secretKey
                    
                    # Verify required properties exist
                    if ([string]::IsNullOrWhiteSpace($serialNumber)) {
                        Write-Error "Token missing required serialNumber property: $($token | ConvertTo-Json -Compress)"
                        $importResult.Failed += "Unknown Serial"
                        continue
                    }
                    
                    if ([string]::IsNullOrWhiteSpace($secretKey)) {
                        Write-Error "Token with serial $serialNumber missing required secretKey property"
                        $importResult.Failed += $serialNumber
                        continue
                    }
                    
                    # Build parameters for Add-OATHToken
                    $addParams = @{
                        SerialNumber = $serialNumber
                        SecretKey = $secretKey
                    }
                    
                    # Determine secret format
                    $secretFormat = 'Base32'
                    if ($token.PSObject.Properties.Name -contains 'secretFormat') {
                        $secretFormat = $token.secretFormat
                        $addParams['SecretFormat'] = $secretFormat
                        Write-Verbose "Using specified secret format: $secretFormat for token $serialNumber"
                    }
                    # If no format specified but key doesn't look like Base32, try to determine format
                    elseif (-not [regex]::IsMatch($secretKey, '^[A-Z2-7]+=*$')) {
                        # Try to guess the format - if it looks like hex, assume hex
                        if ($secretKey -match '^[0-9a-fA-F]+$') {
                            $secretFormat = 'Hex'
                            $addParams['SecretFormat'] = $secretFormat
                            Write-Verbose "Auto-detected Hex format for token $serialNumber"
                        } else {
                            $secretFormat = 'Text'
                            $addParams['SecretFormat'] = $secretFormat
                            Write-Verbose "Auto-detected Text format for token $serialNumber"
                        }
                    }
                    
                    # Add optional properties if they exist
                    if ($token.PSObject.Properties.Name -contains 'manufacturer') {
                        $addParams['Manufacturer'] = $token.manufacturer
                    }
                    
                    if ($token.PSObject.Properties.Name -contains 'model') {
                        $addParams['Model'] = $token.model
                    }
                    
                    if ($token.PSObject.Properties.Name -contains 'displayName') {
                        $addParams['DisplayName'] = $token.displayName
                    }
                    
                    # Store user assignment information separately
                    $userAssignment = $null
                    if ($token.PSObject.Properties.Name -contains 'assignTo') {
                        $userAssignment = $token.assignTo
                        Write-Verbose "Found user assignment for token $serialNumber : $($userAssignment | ConvertTo-Json -Compress)"
                    }
                    
                    # Store activation flag separately
                    $tokenActivation = $false
                    if ($token.PSObject.Properties.Name -contains 'activate') {
                        $tokenActivation = $token.activate
                        Write-Verbose "Token $serialNumber has activation flag: $tokenActivation"
                    }
                    
                    # Add the token using the simplified parameter set
                    Write-Verbose "Adding token with parameters: $($addParams | ConvertTo-Json -Compress)"
                    $result = Add-OATHToken @addParams
                    
                    if ($result) {
                        Write-Verbose "Successfully added token $serialNumber"
                        
                        # Store user assignment info for later processing
                        if ($userAssignment) {
                            $result | Add-Member -NotePropertyName '_userAssignment' -NotePropertyValue $userAssignment -Force
                        }
                        
                        if ($tokenActivation) {
                            $result | Add-Member -NotePropertyName '_activate' -NotePropertyValue $true -Force
                        }
                        
                        # Store original token info for potential activation
                        $result | Add-Member -NotePropertyName '_originalToken' -NotePropertyValue $token -Force
                        $addedTokens += $result
                    } else {
                        Write-Warning "No result returned from Add-OATHToken for token $serialNumber"
                        $importResult.Failed += $serialNumber
                    }
                }
                catch {
                    if ($token.PSObject.Properties.Name -contains 'serialNumber') {
                        Write-Error "Failed to add token with serial number $($token.serialNumber): $_"
                        $importResult.Failed += $token.serialNumber
                    } else {
                        Write-Error "Failed to add token (unknown serial): $_"
                        $importResult.Failed += "Unknown Serial"
                    }
                }
            }
            
            # Update the result
            $importResult.Added = $addedTokens
            if ($addedTokens -and $addedTokens.Count -gt 0) {
                $importResult.Success = $true
            }
            else {
                $importResult.Errors += "Failed to add any tokens."
                Write-Warning "Failed to add any tokens."
                return $importResult
            }
            
            # Process user assignments if requested
            if ($AssignToUsers -or $SchemaType -eq 'UserAssignments') {
                $assignmentCount = 0
                $totalEligible = 0
                
                # Debug info - show tokens with user assignments
                Write-Verbose "Checking for tokens with user assignments..."
                Write-Verbose "Total added tokens: $($addedTokens.Count)"
                
                foreach ($addedToken in $addedTokens) {
                    Write-Verbose "Examining token: $($addedToken.serialNumber) (ID: $($addedToken.id))"
                    Write-Verbose "Token properties: $($addedToken.PSObject.Properties.Name -join ', ')"
                    
                    # Force the AssignToUsers parameter to true for UserAssignments schema
                    if ($SchemaType -eq 'UserAssignments') {
                        $AssignToUsers = $true
                    }
                    
                    # Get the original token that corresponds to this added token
                    $originalToken = $tokens | Where-Object { $_.serialNumber -eq $addedToken.serialNumber } | Select-Object -First 1
                    
                    if ($originalToken) {
                        Write-Verbose "Found original token with serial number: $($originalToken.serialNumber)"
                        Write-Verbose "Original token properties: $($originalToken.PSObject.Properties.Name -join ', ')"
                        
                        # Check if the original token has user assignment information
                        if ($originalToken.PSObject.Properties.Name -contains 'assignTo' -and $originalToken.assignTo.id) {
                            $userId = $originalToken.assignTo.id
                            Write-Verbose "Original token has assignTo.id: $userId"
                            
                            Write-Host "Assigning token $($addedToken.serialNumber) to user $userId..." -ForegroundColor Cyan
                            
                            # Skip assignment if user doesn't exist
                            if ($nonexistentUsers -contains $userId) {
                                Write-Warning "User not found: $userId - skipping assignment"
                                $importResult.AssignmentFailures += [PSCustomObject]@{
                                    TokenId = $addedToken.id
                                    SerialNumber = $addedToken.serialNumber
                                    UserId = $userId
                                    Reason = "User not found"
                                }
                                continue
                            }
                            
                            try {
                                # Attempt to assign the token directly using the original token's info
                                $assignResult = Set-OATHTokenUser -TokenId $addedToken.id -UserId $userId -ErrorAction Stop
                                
                                if ($assignResult.Success) {
                                    $assignmentCount++
                                    $totalEligible++
                                    Write-Host "Successfully assigned token $($addedToken.serialNumber) to user $userId" -ForegroundColor Green
                                    $importResult.AssignmentSuccesses += [PSCustomObject]@{
                                        TokenId = $addedToken.id
                                        SerialNumber = $addedToken.serialNumber
                                        UserId = $userId
                                    }
                                    
                                    # Check if we should activate the token
                                    if ($originalToken.PSObject.Properties.Name -contains 'activate' -and $originalToken.activate -eq $true) {
                                        Write-Host "Attempting to auto-activate token $($addedToken.serialNumber) for user $userId..." -ForegroundColor Cyan
                                        
                                        try {
                                            # Activate using the secret from the original token
                                            $activateResult = Set-OATHTokenActive -TokenId $addedToken.id -UserId $userId -Secret $originalToken.secretKey
                                            
                                            if ($activateResult.Success) {
                                                Write-Host "Successfully activated token $($addedToken.serialNumber) for user $userId" -ForegroundColor Green
                                                $importResult.ActivationSuccesses += [PSCustomObject]@{
                                                    TokenId = $addedToken.id
                                                    SerialNumber = $addedToken.serialNumber
                                                    UserId = $userId
                                                }
                                            }
                                            else {
                                                Write-Warning "Failed to activate token $($addedToken.serialNumber): $($activateResult.Reason)"
                                                $importResult.ActivationFailures += [PSCustomObject]@{
                                                    TokenId = $addedToken.id
                                                    SerialNumber = $addedToken.serialNumber
                                                    UserId = $userId
                                                    Reason = $activateResult.Reason
                                                }
                                            }
                                        }
                                        catch {
                                            Write-Warning "Error during token activation: $_"
                                            $importResult.ActivationFailures += [PSCustomObject]@{
                                                TokenId = $addedToken.id
                                                SerialNumber = $addedToken.serialNumber
                                                UserId = $userId
                                                Reason = $_.ToString()
                                            }
                                        }
                                    }
                                }
                                else {
                                    Write-Warning "Failed to assign token $($addedToken.serialNumber) to user $userId : $($assignResult.Reason)"
                                    $importResult.AssignmentFailures += [PSCustomObject]@{
                                        TokenId = $addedToken.id
                                        SerialNumber = $addedToken.serialNumber
                                        UserId = $userId
                                        Reason = $assignResult.Reason
                                    }
                                }
                            }
                            catch {
                                Write-Warning "Error assigning token $($addedToken.serialNumber) to user $userId : $_"
                                $importResult.AssignmentFailures += [PSCustomObject]@{
                                    TokenId = $addedToken.id
                                    SerialNumber = $addedToken.serialNumber
                                    UserId = $userId
                                    Reason = $_.ToString()
                                }
                            }
                        }
                        else {
                            Write-Verbose "Original token does not have assignTo information"
                        }
                    }
                    else {
                        Write-Warning "Could not find original token for $($addedToken.serialNumber)"
                    }
                }
                
                if ($totalEligible -gt 0) {
                    Write-Host "Assigned $assignmentCount of $totalEligible tokens to users." -ForegroundColor Green
                    
                    if ($importResult.ActivationSuccesses.Count -gt 0) {
                        Write-Host "Activated $($importResult.ActivationSuccesses.Count) tokens automatically." -ForegroundColor Green
                    }
                    
                    if ($importResult.ActivationFailures.Count -gt 0) {
                        Write-Host "Failed to activate $($importResult.ActivationFailures.Count) tokens." -ForegroundColor Yellow
                    }
                } else {
                    Write-Warning "No tokens with user assignments were found to process."
                }
            } else {
                Write-Verbose "Skipping user assignment processing (AssignToUsers: $AssignToUsers, SchemaType: $SchemaType)"
            }
            
            Write-Host "Successfully imported $($addedTokens.Count) of $($tokens.Count) tokens." -ForegroundColor Green
            return $importResult
        }
        catch {
            $errorMsg = "Error importing tokens: $_"
            $importResult.Errors += $errorMsg
            Write-Error $errorMsg
            return $importResult
        }
    }
}

# Add aliases for backward compatibility
New-Alias -Name 'Add-BulkHardwareOathTokens' -Value 'Import-OATHToken' 
New-Alias -Name 'Add-BulkHardwareOathTokensToUsers' -Value 'Import-OATHToken'