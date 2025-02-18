#####################################################
# HelloID-Conn-Prov-Source-RAET-IAM-API-Beaufort-Persons
#
# Version: 2.2.0
#####################################################
$Script:expirationTimeAccessToken = $null
$Script:AuthenticationHeaders = $null

$c = $configuration | ConvertFrom-Json

# Set debug logging
switch ($($c.isDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

$clientId = $c.clientId
$clientSecret = $c.clientSecret
$tenantId = $c.tenantId
$includeAssignments = $c.includeAssignments
$includePersonsWithoutAssignments = $c.includePersonsWithoutAssignments
$excludePersonsWithoutContractsInHelloID = $c.excludePersonsWithoutContractsInHelloID
$includeExtensions = $c.includeExtensions
$managerRoleCode = $c.managerRoleCode

$Script:AuthenticationUri = "https://connect.visma.com/connect/token"
$Script:BaseUri = "https://api.youforce.com"

#region functions
function Resolve-RaetBeaufortIAMAPIError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {
            $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json)
            # Make sure to inspect the error result object and add only the error message as a FriendlyMessage.
            # $httpErrorObj.FriendlyMessage = $errorDetailsObject.message
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails # Temporarily assignment
        }
        catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
        }
        Write-Output $httpErrorObj
    }
}

function New-RaetSession {
    [CmdletBinding()]
    param (
        [Alias("Param1")] 
        [parameter(Mandatory = $true)]  
        [string]      
        $ClientId,

        [Alias("Param2")] 
        [parameter(Mandatory = $true)]  
        [string]
        $ClientSecret,

        [Alias("Param3")] 
        [parameter(Mandatory = $false)]  
        [string]
        $TenantId
    )

    #Check if the current token is still valid
    $accessTokenValid = Confirm-AccessTokenIsValid
    if ($true -eq $accessTokenValid) {
        return
    }

    try {
        $actionMessage = "creating Access Token at uri '$($AuthenticationUri)'"

        # Set TLS to accept TLS, TLS 1.1 and TLS 1.2
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

        $authorisationBody = @{
            'grant_type'    = "client_credentials"
            'client_id'     = $ClientId
            'client_secret' = $ClientSecret
            'tenant_id'     = $TenantId
        }        
        $splatAccessTokenParams = @{
            Uri         = $Script:AuthenticationUri
            Headers     = @{'Cache-Control' = "no-cache" }
            Method      = 'POST'
            ContentType = "application/x-www-form-urlencoded"
            Body        = $authorisationBody
        }

        $result = Invoke-RestMethod @splatAccessTokenParams -Verbose:$false -ErrorAction Stop

        if ($null -eq $result.access_token) {
            throw "Web request was successful, but no access token was returned."
        }

        $Script:expirationTimeAccessToken = (Get-Date).AddSeconds($result.expires_in)

        $Script:AuthenticationHeaders = @{
            'Authorization' = "Bearer $($result.access_token)"
            'Accept'        = "application/json"
        }

        Write-Verbose "Successfully created Access Token at uri '$($splatAccessTokenParams.Uri)'"
    }
    catch {
        $ex = $PSItem
        if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
            $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $errorObj = Resolve-RaetBeaufortIAMAPIError -ErrorObject $ex
            $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
            $warningMessage = "Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
        }
        else {
            $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
            $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        }

        Write-Warning $warningMessage
        throw $auditMessage
    }
}

function Confirm-AccessTokenIsValid {
    if ($null -ne $Script:expirationTimeAccessToken) {
        if ((Get-Date) -le $Script:expirationTimeAccessToken) {
            return $true
        }
    }
    return $false
}

function Invoke-RaetWebRequestList {
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true)]
        [string]
        $Url
    )
    
    # Set TLS to accept TLS, TLS 1.1 and TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

    [System.Collections.ArrayList]$ReturnValue = @()
    $counter = 0
    $triesCounter = 0
    do {
        try {
            $actionMessage = "checking if access token is valid"

            $accessTokenValid = Confirm-AccessTokenIsValid

            if ($true -ne $accessTokenValid) {
                $actionMessage = "creating new access token"

                New-RaetSession -ClientId $clientId -ClientSecret $clientSecret -TenantId $tenantId
            }

            $retry = $false

            if ($counter -gt 0 -and $null -ne $result.nextLink) {
                $SkipTakeUrl = $result.nextLink.Substring($result.nextLink.IndexOf("?"))
            }
            else {
                $SkipTakeUrl = "?take=1000"
            }

            $counter++

            $actionMessage = "querying data from '$($Url + $SkipTakeUrl)'. Retry: $($retry). Counter: $($counter)"

            $splatGetDataParams = @{
                Uri             = "$($Url + $SkipTakeUrl)"
                Headers         = $Script:AuthenticationHeaders
                Method          = 'GET'
                ContentType     = "application/json"
                UseBasicParsing = $true
            }

            $result = Invoke-RestMethod @splatGetDataParams
            # Check both the keys "values" and "value", since Extensions endpoint returns the data in "values" instead of "value"
            if ($result.values.Count -ne 0) {
                $resultObjects = $result.values
            }
            else {
                $resultObjects = $result.value
            }

            # Check if resultObjects are an array if so, add the entire range, otherwise add the single object
            if ($resultObjects -is [array]) {
                [void]$ReturnValue.AddRange($resultObjects)
            }
            else {
                [void]$ReturnValue.Add($resultObjects)
            }

            # Wait for 0,601 seconds  - RAET IAM API allows a maximum of 100 requests a minute (https://community.visma.com/t5/Kennisbank-Youforce-API/API-Status-amp-Policy/ta-p/428099#toc-hId-339419904:~:text=3-,Spike%20arrest%20policy%20(max%20number%20of%20API%20calls%20per%20minute),100%20calls%20per%20minute,-*For%20the%20base).
            Start-Sleep -Milliseconds 601
        }
        catch {           
            $ex = $PSItem
            if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
                $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
                $errorObj = Resolve-RaetBeaufortIAMAPIError -ErrorObject $ex
                $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
                $warningMessage = "Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
            }
            else {
                $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
                $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
            }

            $maxTries = 3
            if ( ($($auditMessage) -Like "*Too Many Requests*" -or $($auditMessage) -Like "*Connection timed out*") -and $triesCounter -lt $maxTries ) {
                $triesCounter++
                $retry = $true
                $delay = 601 # Wait for 0,601 seconds  - RAET IAM API allows a maximum of 100 requests a minute (https://community.visma.com/t5/Kennisbank-Youforce-API/API-Status-amp-Policy/ta-p/428099#toc-hId-339419904:~:text=3-,Spike%20arrest%20policy%20(max%20number%20of%20API%20calls%20per%20minute),100%20calls%20per%20minute,-*For%20the%20base).
                Write-Warning "$auditMessage. Trying again in '$delay' milliseconds for a maximum of '$maxTries' tries."
                Start-Sleep -Milliseconds $delay
            }
            else {
                $retry = $false
                throw "$auditMessage"
            }
        }
    }while (-NOT[string]::IsNullOrEmpty($result.nextLink) -or $retry -eq $true)

    Write-Verbose "Successfully queried data from '$($Url)'. Result count: $(@($ReturnValue).Count)"

    return $ReturnValue
}
#endregion functions

Write-Information "Starting person import. Base URI: $BaseUri"

# Query persons
try {
    $actionMessage = "querying persons at [$BaseUri/iam/v1.0/persons]"

    $personsList = Invoke-RaetWebRequestList -Url "$BaseUri/iam/v1.0/persons"

    # Make sure persons are unique
    $persons = $personsList | Where-Object { $_.personCode -ne $null } | Sort-Object id -Unique

    Write-Information "Successfully queried persons. Result: $(@($persons).Count)"
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-RaetBeaufortIAMAPIError -ErrorObject $ex
        $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
        $warningMessage = "Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }

    Write-Warning $warningMessage

    throw $auditMessage
}

# Query person extensions
try {
    if ($true -eq $includeExtensions) {
        $actionMessage = "querying person extensions at [$BaseUri/extensions/v1.0/iam/persons]"

        $personExtensionsList = Invoke-RaetWebRequestList -Url "$BaseUri/extensions/v1.0/iam/persons"

        # Group by personCode
        $personExtensionsGrouped = $personExtensionsList | Group-Object personCode -CaseSensitive -AsHashTable -AsString

        Write-Information "Successfully queried person extensions. Result: $(@($personExtensionsList).Count)"
    }
    else { 
        Write-Information "Ignored querying person extensions because the configuration toggle to include extensions is: $($includeExtensions)"
    }
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-RaetBeaufortIAMAPIError -ErrorObject $ex
        $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
        $warningMessage = "Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    
    Write-Warning $warningMessage

    throw $auditMessage
}

# Query employments
try {
    $actionMessage = "querying employments at [$BaseUri/iam/v1.0/employments]"

    $employmentsList = Invoke-RaetWebRequestList -Url "$BaseUri/iam/v1.0/employments"

    # Group by personCode
    $employmentsGrouped = $employmentsList | Group-Object personCode -CaseSensitive -AsHashTable -AsString

    Write-Information "Successfully queried employments. Result: $(@($employmentsList).Count)"
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-RaetBeaufortIAMAPIError -ErrorObject $ex
        $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
        $warningMessage = "Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    
    Write-Warning $warningMessage

    throw $auditMessage
}

# Query employment extensions
try {
    if ($true -eq $includeExtensions) {
        $actionMessage = "querying employment extensions at [$BaseUri/extensions/v1.0/iam/employments]"

        $employmentExtensionsList = Invoke-RaetWebRequestList -Url "$BaseUri/extensions/v1.0/iam/employments"

        if ($null -ne $employmentExtensionsList) {
            # Add ExternalId property as linking key to contract, linking key is PersonCode + "_" + employmentCode
            $employmentExtensionsList | Add-Member -MemberType NoteProperty -Name "ExternalId" -Value $null -Force
            $employmentExtensionsList | Foreach-Object {
                $_.ExternalId = $_.PersonCode + "_" + $_.employmentCode
            }
        }

        # Group by ExternalId
        $employmentExtensionsGrouped = $employmentExtensionsList | Group-Object ExternalId -CaseSensitive -AsHashTable -AsString

        Write-Information "Successfully queried employment extensions. Result: $(@($employmentExtensionsList).Count)"
    }
    else { 
        Write-Information "Ignored querying employmens extensions because the configuration toggle to include extensions is: $($includeExtensions)"
    }
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-RaetBeaufortIAMAPIError -ErrorObject $ex
        $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
        $warningMessage = "Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    
    Write-Warning $warningMessage

    throw $auditMessage
}

# Query assignments
if ($true -eq $includeAssignments) {
    try {
        $actionMessage = "querying assignments at [$BaseUri/iam/v1.0/assignments]"
        
        $assignmentsList = Invoke-RaetWebRequestList -Url "$BaseUri/iam/v1.0/assignments"

        Write-Information "Successfully queried assignments. Result: $(@($assignmentsList).Count)"

        # # Filter out archived assignments
        # $assignmentsList = $assignmentsList | Where-Object { $_.isActive -ne $false }

        # Write-Information "Successfully filtered out archived assignments. Result: $(@($assignmentsList).Count)"

        # Add ExternalId property as linking key to contract, linking key is PersonCode + "_" + employmentCode
        $assignmentsList | Add-Member -MemberType NoteProperty -Name "ExternalId" -Value $null -Force
        $assignmentsList | Foreach-Object {
            $_.ExternalId = $_.PersonCode + "_" + $_.employmentCode
        }

        # Group by ExternalId
        $assignmentsGrouped = $assignmentsList | Group-Object ExternalId -AsHashTable

    }
    catch {
        $ex = $PSItem
        if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
            $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $errorObj = Resolve-RaetBeaufortIAMAPIError -ErrorObject $ex
            $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
            $warningMessage = "Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
        }
        else {
            $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
            $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        }
    
        Write-Warning $warningMessage

        throw $auditMessage
    }
}

# Query jobProfiles
try {
    $actionMessage = "querying jobProfiles at [$BaseUri/iam/v1.0/jobProfiles]"
    
    $jobProfilesList = Invoke-RaetWebRequestList -Url "$BaseUri/iam/v1.0/jobProfiles"

    # Group by id
    $jobProfilesGrouped = $jobProfilesList | Group-Object Id -AsHashTable

    Write-Information "Successfully queried jobProfiles. Result: $(@($jobProfilesList).Count)"
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-RaetBeaufortIAMAPIError -ErrorObject $ex
        $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
        $warningMessage = "Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    
    Write-Warning $warningMessage

    throw $auditMessage
}

# Query costAllocations
try {
    $actionMessage = "querying costAllocations at [$BaseUri/iam/v1.0/costAllocations]"
    
    $costAllocationsList = Invoke-RaetWebRequestList -Url "$BaseUri/iam/v1.0/costAllocations"

    # Add ExternalId property as linking key to employment, linking key is PersonCode + "_" + employmentCode
    $costAllocationsList | Add-Member -MemberType NoteProperty -Name "EmploymentExternalId" -Value $null -Force
    $costAllocationsList | Add-Member -MemberType NoteProperty -Name "AssignmentExternalId" -Value $null -Force
    $costAllocationsList | Foreach-Object {
        $_.EmploymentExternalId = $_.PersonCode + "_" + $_.employmentCode
        $_.AssignmentExternalId = $_.PersonCode + "_" + $_.costCenterCode
    }
    
    # Group by EmploymentExternalId
    $costAllocationsGroupedForEmployment = $costAllocationsList | Group-Object EmploymentExternalId -AsHashTable

    # Group by AssignmentExternalId
    $costAllocationsGroupedForAssignment = $costAllocationsList | Group-Object AssignmentExternalId -AsHashTable

    Write-Information "Successfully queried costAllocations. Result: $(@($costAllocationsList).Count)"
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-RaetBeaufortIAMAPIError -ErrorObject $ex
        $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
        $warningMessage = "Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    
    Write-Warning $warningMessage

    throw $auditMessage
}

# Query organizationUnits
try {
    $actionMessage = "querying organizationUnits at [$BaseUri/iam/v1.0/organizationUnits]"

    $organizationUnits = Invoke-RaetWebRequestList -Url "$BaseUri/iam/v1.0/organizationUnits"

    # Group by ExternalId
    $organizationUnitsGrouped = $organizationUnits | Group-Object id -AsHashTable -AsString

    Write-Information "Successfully queried organizationUnits. Result: $(@($organizationUnits).Count)"
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-RaetBeaufortIAMAPIError -ErrorObject $ex
        $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
        $warningMessage = "Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    
    Write-Warning $warningMessage

    throw $auditMessage
}

# Query roleAssignments
try {
    $actionMessage = "querying roleAssignments at [$BaseUri/iam/v1.0/roleAssignments]"

    $roleAssignments = Invoke-RaetWebRequestList -Url "$BaseUri/iam/v1.0/roleAssignments"
    Write-Information "Successfully queried roleAssignments. Result: $(@($roleAssignments).Count)"

    # Filter Role assignments for only active and specific role, and sort descending on startDate and personCode to ensure consistent manager data
    $currentDate = Get-Date
    $roleAssignments = $roleAssignments | Where-Object { 
        $_.startDate -as [datetime] -le $currentDate -and
        ($_.endDate -eq $null -or $_.endDate -as [datetime] -ge $currentDate) -and
        $_.shortName -eq $managerRoleCode
    } | Sort-Object -Property { $_.startDate , [int]$_.personCode } -Descending

    # Group on personCode (to match to person)
    $roleAssignmentsGrouped = $roleAssignments | Group-Object personCode -AsHashTable -AsString

    Write-Information "Successfully filtered for only active roleAssignments of role [$managerRoleCode]. Result: $(@($roleAssignments).Count)"
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-RaetBeaufortIAMAPIError -ErrorObject $ex
        $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
        $warningMessage = "Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    
    Write-Warning $warningMessage

    throw $auditMessage
}
#endRegion

try {
    $actionMessage = "enhancing and exporting person objects to HelloID"

    # Set counter to keep track of actual exported person objects
    $exportedPersons = 0

    # Enhance the persons model with required properties
    $persons | Add-Member -MemberType NoteProperty -Name "ExternalId" -Value $null -Force
    $persons | Add-Member -MemberType NoteProperty -Name "DisplayName" -Value $null -Force
    $persons | Add-Member -MemberType NoteProperty -Name "Contracts" -Value $null -Force

    $persons | ForEach-Object {
        # Set required fields for HelloID
        $_.ExternalId = $_.personCode
        $_.DisplayName = "$($_.knownAs) $($_.lastNameAtBirth) ($($_.ExternalId))"

        # Transform emailAddresses and add to the person
        if ($null -ne $_.emailAddresses) {
            foreach ($emailAddress in $_.emailAddresses) {
                if (![string]::IsNullOrEmpty($emailAddress)) {
                    foreach ($property in $emailAddress.PsObject.Properties) {
                        # Add a property for each field in object
                        $_ | Add-Member -MemberType NoteProperty -Name ("$($emailAddress.type)EmailAddress_" + $property.Name) -Value $property.Value -Force
                    }
                }
            }

            # Remove unnecessary fields from  object (to avoid unnecessary large objects)
            $_.PSObject.Properties.Remove('emailAddresses')
        }

        # Transform phoneNumbers and add to the person
        if ($null -ne $_.phoneNumbers) {
            foreach ($phoneNumber in $_.phoneNumbers) {
                if (![string]::IsNullOrEmpty($phoneNumber)) {
                    foreach ($property in $phoneNumber.PsObject.Properties) {
                        # Add a property for each field in object
                        $_ | Add-Member -MemberType NoteProperty -Name ("$($phoneNumber.type)PhoneNumber_" + $property.Name) -Value $property.Value -Force
                    }
                }
            }

            # Remove unnecessary fields from object (to avoid unnecessary large objects)
            $_.PSObject.Properties.Remove('phoneNumbers')
        }

        # Transform addresses and add to the person
        if ($null -ne $_.addresses) {
            foreach ($address in $_.addresses) {
                if (![string]::IsNullOrEmpty($address)) {
                    foreach ($property in $address.PsObject.Properties) {
                        # Add a property for each field in object
                        $_ | Add-Member -MemberType NoteProperty -Name ("$($address.type)Address_" + $property.Name) -Value $property.Value -Force
                    }
                }
            }

            Remove unnecessary fields from object (to avoid unnecessary large objects)
            $_.PSObject.Properties.Remove('addresses')
        }

        if ($null -ne $_.addresses) {
            $_.PSObject.Properties.Remove('addresses')
        }
        #endRegion

        # Transform extensions and add to the person
        if ($true -eq $includeExtensions) {
            if ($null -ne $personExtensionsGrouped) {
                $personExtensions = $null
                $personExtensions = $personExtensionsGrouped[$_.personCode]
                if ($null -ne $personExtensions) {
                    foreach ($personExtension in $personExtensions) {
                        # Add fieldNameAlias, value and description as properties to employment object
                        foreach ($property in $personExtension.PsObject.Properties | Where-Object { $_.Name -in @('fieldNameAlias', 'value', 'description') }) {
                            $_ | Add-Member -MemberType NoteProperty -Name ("extension_" + $personExtension.bo4FieldCode.Replace(' ', '') + "_" + $property.Name) -Value "$($property.value)" -Force
                        }
                    }
                }
            }
        }
    
        # Remove unnecessary fields from object (to avoid unnecessary large objects) - Extensions are available via a separate endpoint
        $_.PSObject.Properties.Remove('extensions')

        # Create contracts object
        # Get employments for person, linking key is company personCode
        $personEmployments = $employmentsGrouped[$_.personCode]

        $contractsList = [System.Collections.ArrayList]::new()
        if ($null -ne $personEmployments) {
            foreach ($employment in $personEmployments) {
                # Enhance employment with jobProfile for extra information, such as: fullName
                $jobProfile = $jobProfilesGrouped["$($employment.jobProfile)"]
                if ($null -ne $jobProfile) {
                    # In case multiple are found with the same ID, we always select the first one in the array
                    $jobProfile = $jobProfile | Select-Object -First 1

                    if (![string]::IsNullOrEmpty($jobProfile)) {
                        foreach ($property in $jobProfile.PsObject.Properties) {
                            # Add a property for each field in object
                            $employment | Add-Member -MemberType NoteProperty -Name ("jobProfile_" + $property.Name) -Value $property.Value -Force
                        }
                    }
                }

                # Enhance employment with organizationalUnit for extra information, such as: parentOU
                $department = $organizationUnitsGrouped["$($employment.organizationUnit)"]
                if ($null -ne $department) {
                    # In case multiple are found with the same ID, we always select the first one in the array
                    $department = $department | Select-Object -First 1

                    if (![string]::IsNullOrEmpty($department)) {
                        foreach ($property in $department.PsObject.Properties) {
                            # Add a property for each field in object
                            $employment | Add-Member -MemberType NoteProperty -Name ("organizationUnit_" + $property.Name) -Value $property.Value -Force
                        }
                    }
                }

                # Enhance employment with comma seperated list of hierarchical department shortnames
                $departmentHierarchy = [System.Collections.ArrayList]::new()
                if ($null -ne $department) {
                    [void]$departmentHierarchy.add($department)
                    while (-NOT[String]::IsNullOrEmpty($department.parentOrgUnit)) {
                        # In case multiple departments are found with same id, always select first we encounter
                        $department = $organizationUnitsGrouped["$($department.parentOrgUnit)"] | Select-Object -First 1
                        [void]$departmentHierarchy.add($department)
                    }
                }

                $employment | Add-Member -MemberType NoteProperty -Name "DepartmentHierarchy" -Value ('"{0}"' -f ($departmentHierarchy.shortName -Join '","')) -Force

                # Enhance employment with costAllocation for extra information, such as: fullName
                # Get costAllocation for employment, linking key is PersonCode + "_" + employmentCode
                $costAllocation = $costAllocationsGroupedForEmployment[($_.personCode + "_" + $employment.employmentCode)]
                if ($null -ne $costAllocation) {
                    # In case multiple are found with the same ID, we always select the first one in the array
                    $costAllocation = $costAllocation | Select-Object -First 1

                    if (![string]::IsNullOrEmpty($costAllocation)) {
                        foreach ($property in $costAllocation.PsObject.Properties) {
                            # Add a property for each field in object
                            $employment | Add-Member -MemberType NoteProperty -Name ("costAllocation_" + $property.Name) -Value $property.Value -Force
                        }
                    }
                }

                # Enhance employment with extension for extra information
                # Get extension for employment, linking key is PersonCode + "_" + employmentCode
                if ($true -eq $includeExtensions) {
                    if ($null -ne $employmentExtensionsGrouped) {
                        $employmentExtensions = $null
                        $employmentExtensions = $employmentExtensionsGrouped[($_.personCode + "_" + $employment.employmentCode)]
                        if ($null -ne $employmentExtensions) {
                            foreach ($employmentExtension in $employmentExtensions) {
                                # Add fieldNameAlias, value and description as properties to employment object
                                foreach ($property in $employmentExtension.PsObject.Properties | Where-Object { $_.Name -in @('fieldNameAlias', 'value', 'description') }) {
                                    $employment | Add-Member -MemberType NoteProperty -Name ("extension_" + $employmentExtension.bo4FieldCode.Replace(' ', '') + "_" + $property.Name) -Value "$($property.value)" -Force
                                }
                            }
                        }
                    }
                }
                # Remove unnecessary fields from object (to avoid unnecessary large objects) - Extensions are available via a separate endpoint
                $employment.PSObject.Properties.Remove('extensions')

                if ($false -eq $includeAssignments) {
                    # Create Contract object(s) based on employments

                    # Create employment object to include prefix of properties
                    $employmentObject = [PSCustomObject]@{}
                    $employment.psobject.properties | ForEach-Object {
                        $employmentObject | Add-Member -MemberType $_.MemberType -Name "employment_$($_.Name)" -Value $_.Value -Force
                    }

                    # Add a property to indicate contract is employment
                    $employmentObject | Add-Member -MemberType NoteProperty -Name "Type" -Value "Employment" -Force

                    # Add employment data to contracts
                    [Void]$contractsList.Add($employmentObject)
                }
                else {
                    # Create Contract object(s) based on assignments
    
                    # Get assignments for employment, linking key is PersonCode + "_" + employmentCode
                    $assignments = $assignmentsGrouped[($_.personCode + "_" + $employment.employmentCode)]
    
                    # Add assignment and employment data to contracts
                    if ($null -ne $assignments) {
                        foreach ($assignment in $assignments) {
                            # Enhance assignment with jobProfile for extra information, such as: fullName
                            $jobProfile = $jobProfilesGrouped["$($assignment.jobProfile)"]
                            if ($null -ne $jobProfile) {
                                # In case multiple are found with the same ID, we always select the first one in the array
                                $jobProfile = $jobProfile | Select-Object -First 1

                                if (![string]::IsNullOrEmpty($jobProfile)) {
                                    foreach ($property in $jobProfile.PsObject.Properties) {
                                        # Add a property for each field in object
                                        $assignment | Add-Member -MemberType NoteProperty -Name ("jobProfile_" + $property.Name) -Value $property.Value -Force
                                    }
                                }
                            }

                            # Enhance assignment with organizationalUnit for extra information, such as: parentOU
                            $department = $organizationUnitsGrouped["$($assignment.organizationUnit)"]
                            if ($null -ne $department) {
                                # In case multiple are found with the same ID, we always select the first one in the array
                                $department = $department | Select-Object -First 1

                                if (![string]::IsNullOrEmpty($department)) {
                                    foreach ($property in $department.PsObject.Properties) {
                                        # Add a property for each field in object
                                        $assignment | Add-Member -MemberType NoteProperty -Name ("organizationUnit_" + $property.Name) -Value $property.Value -Force
                                    }
                                }
                            }

                            # Enhance employment with comma seperated list of hierarchical department shortnames
                            $departmentHierarchy = [System.Collections.ArrayList]::new()
                            if ($null -ne $department) {
                                [void]$departmentHierarchy.add($department)
                                while (-NOT[String]::IsNullOrEmpty($department.parentOrgUnit)) {
                                    # In case multiple departments are found with same id, always select first we encounter
                                    $department = $organizationUnitsGrouped["$($department.parentOrgUnit)"] | Select-Object -First 1
                                    [void]$departmentHierarchy.add($department)
                                }
                            }

                            $assignment | Add-Member -MemberType NoteProperty -Name "DepartmentHierarchy" -Value ('"{0}"' -f ($departmentHierarchy.shortName -Join '","')) -Force

                            # Enhance assignment with costAllocation for extra information, such as: fullName
                            # Get costAllocation for assignment, linking key is PersonCode + "_" + costCenter
                            $costAllocation = $costAllocationsGroupedForAssignment[($_.personCode + "_" + $assignment.costCenter)]
                            if ($null -ne $costAllocation) {
                                # In case multiple are found with the same ID, we always select the first one in the array
                                $costAllocation = $costAllocation | Select-Object -First 1

                                if (![string]::IsNullOrEmpty($costAllocation)) {
                                    foreach ($property in $costAllocation.PsObject.Properties) {
                                        # Add a property for each field in object
                                        $assignment | Add-Member -MemberType NoteProperty -Name ("costAllocation_" + $property.Name) -Value $property.Value -Force
                                    }
                                }
                            }

                            # Create assignment object to include prefix in properties
                            $assignmentObject = [PSCustomObject]@{}
    
                            # Add employment object with prefix for property names
                            $employment.psobject.properties | ForEach-Object {
                                $assignmentObject | Add-Member -MemberType $_.MemberType -Name "employment_$($_.Name)" -Value $_.Value -Force
                            }
    
                            # Add position object with prefix for property names
                            $assignment.psobject.properties | ForEach-Object {
                                $assignmentObject | Add-Member -MemberType $_.MemberType -Name "assignment_$($_.Name)" -Value $_.Value -Force
                            }

                            # Add a property to indicate contract is employment
                            $assignmentObject | Add-Member -MemberType NoteProperty -Name "Type" -Value "Assignment" -Force

                            # Add employment and position data to contracts
                            [Void]$contractsList.Add($assignmentObject)
                        }
                    }
                    else {
                        if ($true -eq $includePersonsWithoutAssignments) {
                            # Add employment only data to contracts (in case of employments without assignments)

                            # Create employment object to include prefix of properties
                            $employmentObject = [PSCustomObject]@{}
                            $employment.psobject.properties | ForEach-Object {
                                $employmentObject | Add-Member -MemberType $_.MemberType -Name "employment_$($_.Name)" -Value $_.Value -Force
                            }

                            # Add a property to indicate contract is employment
                            $employmentObject | Add-Member -MemberType NoteProperty -Name "Type" -Value "Employment" -Force

                            # Add employment data to contracts
                            [Void]$contractsList.Add($employmentObject)
                        }
                        else {
                            Write-Warning "Excluding person from export: $($_.ExternalId). Reason: No assignments found for person"
                        }
                    }
                }
            }

            # Remove unnecessary fields from object (to avoid unnecessary large objects)
            # Remove employments, since the data is transformed into a separate object: contracts
            $_.PSObject.Properties.Remove('employments')
        }
        else {
            Write-Warning "No employments found for person: $($_.ExternalId)"
        }

        # Add Contracts to person
        if ($null -ne $contractsList) {
            if ($contractsList.Count -eq 0 -and $true -eq $excludePersonsWithoutContractsInHelloID) {
                Write-Warning "Excluding person from export: $($_.ExternalId). Reason: Contracts is an empty array"
                return
            }
            else {
                $_.Contracts = $contractsList
            }
        }
        elseif ($true -eq $excludePersonsWithoutContractsInHelloID) {
            Write-Warning "Excluding person from export: $($_.ExternalId). Reason: Person has no contract data"
            return
        }

        # Sanitize and export the json
        $person = $_ | ConvertTo-Json -Depth 10
        $person = $person.Replace("._", "__")

        Write-Output $person

        # Updated counter to keep track of actual exported person objects
        $exportedPersons++
    }

    Write-Information "Successfully enhanced and exported person objects to HelloID. Result count: $($exportedPersons)"
    Write-Information "Person import completed"
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-RaetBeaufortIAMAPIError -ErrorObject $ex
        $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
        $warningMessage = "Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    
    Write-Warning $warningMessage

    throw $auditMessage
}