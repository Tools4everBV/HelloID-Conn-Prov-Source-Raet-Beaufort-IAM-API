#####################################################
# HelloID-Conn-Prov-Source-RAET-IAM-API-Beaufort-Persons
#
# Version: 1.1.1
#####################################################
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

$Script:BaseUrl = "https://api.raet.com"

#region functions
function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = ''
        }
        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $httpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $httpErrorObj.ErrorMessage = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
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
        # Set TLS to accept TLS, TLS 1.1 and TLS 1.2
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

        $authorisationBody = @{
            'grant_type'    = "client_credentials"
            'client_id'     = $ClientId
            'client_secret' = $ClientSecret
        }        
        $splatAccessTokenParams = @{
            Uri             = "$($BaseUrl)/authentication/token"
            Headers         = @{'Cache-Control' = "no-cache" }
            Method          = 'POST'
            ContentType     = "application/x-www-form-urlencoded"
            Body            = $authorisationBody
            UseBasicParsing = $true
        }

        Write-Verbose "Creating Access Token at uri '$($splatAccessTokenParams.Uri)'"

        $result = Invoke-RestMethod @splatAccessTokenParams
        if ($null -eq $result.access_token) {
            throw $result
        }

        $Script:expirationTimeAccessToken = (Get-Date).AddSeconds($result.expires_in)

        $Script:AuthenticationHeaders = @{
            'X-Client-Id'      = $ClientId
            'Authorization'    = "Bearer $($result.access_token)"
            'X-Raet-Tenant-Id' = $TenantId
        }

        Write-Verbose "Successfully created Access Token at uri '$($splatAccessTokenParams.Uri)'"
    }
    catch {
        $ex = $PSItem
        if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $errorObject = Resolve-HTTPError -Error $ex
    
            $verboseErrorMessage = $errorObject.ErrorMessage
    
            $auditErrorMessage = $errorObject.ErrorMessage
        }
    
        # If error message empty, fall back on $ex.Exception.Message
        if ([String]::IsNullOrEmpty($verboseErrorMessage)) {
            $verboseErrorMessage = $ex.Exception.Message
        }
        if ([String]::IsNullOrEmpty($auditErrorMessage)) {
            $auditErrorMessage = $ex.Exception.Message
        }

        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"        

        throw "Error creating Access Token at uri ''$($splatAccessTokenParams.Uri)'. Please check credentials. Error Message: $auditErrorMessage"
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
            $accessTokenValid = Confirm-AccessTokenIsValid
            if ($true -ne $accessTokenValid) {
                New-RaetSession -ClientId $clientId -ClientSecret $clientSecret -TenantId $tenantId
            }

            $retry = $false

            if ($counter -gt 0 -and $null -ne $result.nextLink) {
                $SkipTakeUrl = $result.nextLink.Substring($result.nextLink.IndexOf("?"))
            }

            $counter++

            $splatGetDataParams = @{
                Uri             = "$Url$SkipTakeUrl"
                Headers         = $Script:AuthenticationHeaders
                Method          = 'GET'
                ContentType     = "application/json"
                UseBasicParsing = $true
            }
    
            Write-Verbose "Querying data from '$($splatGetDataParams.Uri)'"

            $result = Invoke-RestMethod @splatGetDataParams
            $ReturnValue.AddRange($result.value)

            # Wait for 0,6 seconds  - RAET IAM API allows a maximum of 100 requests a minute (https://community.visma.com/t5/Kennisbank-Youforce-API/API-Status-amp-Policy/ta-p/428099#toc-hId-339419904:~:text=3-,Spike%20arrest%20policy%20(max%20number%20of%20API%20calls%20per%20minute),100%20calls%20per%20minute,-*For%20the%20base).
            Start-Sleep -Milliseconds 600
        }
        catch {
            $ex = $PSItem
           
            if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
                $errorObject = Resolve-HTTPError -Error $ex
        
                $verboseErrorMessage = $errorObject.ErrorMessage
        
                $auditErrorMessage = $errorObject.ErrorMessage
            }
        
            # If error message empty, fall back on $ex.Exception.Message
            if ([String]::IsNullOrEmpty($verboseErrorMessage)) {
                $verboseErrorMessage = $ex.Exception.Message
            }
            if ([String]::IsNullOrEmpty($auditErrorMessage)) {
                $auditErrorMessage = $ex.Exception.Message
            }
    
            Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"        

            $maxTries = 10
            if ( ($auditErrorMessage -Like "*Too Many Requests*" -or $auditErrorMessage -Like "*Connection timed out*") -and $triesCounter -lt $maxTries ) {
                $triesCounter++
                $retry = $true
                $delay = 600 # Wait for 0,6 seconds  - RAET IAM API allows a maximum of 100 requests a minute (https://community.visma.com/t5/Kennisbank-Youforce-API/API-Status-amp-Policy/ta-p/428099#toc-hId-339419904:~:text=3-,Spike%20arrest%20policy%20(max%20number%20of%20API%20calls%20per%20minute),100%20calls%20per%20minute,-*For%20the%20base).
                Write-Warning "Error querying data from '$($splatGetDataParams.Uri)'. Error Message: $auditErrorMessage. Trying again in '$delay' milliseconds for a maximum of '$maxTries' tries."
                Start-Sleep -Milliseconds $delay
            }
            else {
                $retry = $false
                throw "Error querying data from '$($splatGetDataParams.Uri)'. Error Message: $auditErrorMessage"
            }
        }
    }while (-NOT[string]::IsNullOrEmpty($result.nextLink) -or $retry -eq $true)

    Write-Verbose "Successfully queried data from '$($Url)'. Result count: $($ReturnValue.Count)"

    return $ReturnValue
}
#endregion functions

Write-Information "Starting person import. Base URL: $BaseUrl"

# Query persons
try {
    Write-Verbose "Querying persons"

    $persons = Invoke-RaetWebRequestList -Url "$BaseUrl/iam/v1.0/employees"
    # Make sure persons are unique
    $persons = $persons | Sort-Object id -Unique

    Write-Information "Successfully queried persons. Result: $($persons.Count)"
}
catch {
    $ex = $PSItem
    if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObject = Resolve-HTTPError -Error $ex

        $verboseErrorMessage = $errorObject.ErrorMessage

        $auditErrorMessage = $errorObject.ErrorMessage
    }

    # If error message empty, fall back on $ex.Exception.Message
    if ([String]::IsNullOrEmpty($verboseErrorMessage)) {
        $verboseErrorMessage = $ex.Exception.Message
    }
    if ([String]::IsNullOrEmpty($auditErrorMessage)) {
        $auditErrorMessage = $ex.Exception.Message
    }

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"        

    throw "Error querying persons. Error Message: $auditErrorMessage"
}

# Query jobProfiles
try {
    Write-Verbose "Querying jobProfiles"
    
    $jobProfiles = Invoke-RaetWebRequestList -Url "$BaseUrl/iam/v1.0/jobProfiles"
    # Filter for only active jobProfiles
    $ActiveCompareDate = Get-Date
    $jobProfiles = $jobProfiles | Where-Object { $_.isActive -ne $false -and
        (([Datetime]::ParseExact($_.validFrom, 'yyyy-MM-dd', $null)) -le $ActiveCompareDate) -and
        (([Datetime]::ParseExact($_.validUntil, 'yyyy-MM-dd', $null)) -ge $ActiveCompareDate) }
    # Group by id
    $jobProfilesGrouped = $jobProfiles | Group-Object Id -AsHashTable

    Write-Information "Successfully queried jobProfiles. Result: $($jobProfiles.Count)"
}
catch {
    $ex = $PSItem
    if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObject = Resolve-HTTPError -Error $ex

        $verboseErrorMessage = $errorObject.ErrorMessage

        $auditErrorMessage = $errorObject.ErrorMessage
    }

    # If error message empty, fall back on $ex.Exception.Message
    if ([String]::IsNullOrEmpty($verboseErrorMessage)) {
        $verboseErrorMessage = $ex.Exception.Message
    }
    if ([String]::IsNullOrEmpty($auditErrorMessage)) {
        $auditErrorMessage = $ex.Exception.Message
    }

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"        

    throw "Error querying jobProfiles. Error Message: $auditErrorMessage"
}

# Query costAllocations
try {
    Write-Verbose "Querying costAllocations"
    
    $costAllocations = Invoke-RaetWebRequestList -Url "$BaseUrl/iam/v1.0/costAllocations"
    # Add ExternalId property as linking key to contract, linking key is PersonCode + "_" + employmentCode
    $costAllocations | Add-Member -MemberType NoteProperty -Name "ExternalId" -Value $null -Force
    $costAllocations | Foreach-Object {
        $_.ExternalId = $_.PersonCode + "_" + $_.employmentCode
    }
    # Group by ExternalId
    $costAllocationsGrouped = $costAllocations | Group-Object ExternalId -AsHashTable

    Write-Information "Successfully queried costAllocations. Result: $($costAllocations.Count)"
}
catch {
    $ex = $PSItem
    if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObject = Resolve-HTTPError -Error $ex

        $verboseErrorMessage = $errorObject.ErrorMessage

        $auditErrorMessage = $errorObject.ErrorMessage
    }

    # If error message empty, fall back on $ex.Exception.Message
    if ([String]::IsNullOrEmpty($verboseErrorMessage)) {
        $verboseErrorMessage = $ex.Exception.Message
    }
    if ([String]::IsNullOrEmpty($auditErrorMessage)) {
        $auditErrorMessage = $ex.Exception.Message
    }

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"        

    throw "Error querying costAllocations. Error Message: $auditErrorMessage"
}

# Query assignments
if ($true -eq $includeAssignments) {
    try {
        Write-Verbose "Querying assignments"
        
        $assignments = Invoke-RaetWebRequestList -Url "$BaseUrl/iam/v1.0/assignments"

        # Add ExternalId property as linking key to contract, linking key is PersonCode + "_" + employmentCode
        $assignments | Add-Member -MemberType NoteProperty -Name "ExternalId" -Value $null -Force
        $assignments | Foreach-Object {
            $_.ExternalId = $_.PersonCode + "_" + $_.employmentCode
        }
        # Group by ExternalId
        $assignmentsGrouped = $assignments | Group-Object ExternalId -AsHashTable

        Write-Information "Successfully queried assignments. Result: $($assignments.Count)"
    }
    catch {
        $ex = $PSItem
        if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $errorObject = Resolve-HTTPError -Error $ex
    
            $verboseErrorMessage = $errorObject.ErrorMessage
    
            $auditErrorMessage = $errorObject.ErrorMessage
        }
    
        # If error message empty, fall back on $ex.Exception.Message
        if ([String]::IsNullOrEmpty($verboseErrorMessage)) {
            $verboseErrorMessage = $ex.Exception.Message
        }
        if ([String]::IsNullOrEmpty($auditErrorMessage)) {
            $auditErrorMessage = $ex.Exception.Message
        }
    
        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"        
    
        throw "Error querying assignments. Error Message: $auditErrorMessage"
    }
}

try {
    Write-Verbose 'Enhancing and exporting person objects to HelloID'

    # Set counter to keep track of actual exported person objects
    $exportedPersons = 0

    # Enhance the persons model
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
                    # Add a property for each type of EmailAddress
                    $_ | Add-Member -MemberType NoteProperty -Name "$($emailAddress.type)EmailAddress" -Value $emailAddress -Force
                }
            }

            # Remove unneccesary fields from  object (to avoid unneccesary large objects)
            # Remove customFieldGroup, since the data is transformed into seperate properties
            $_.PSObject.Properties.Remove('emailAddresses')
        }

        # Transform phoneNumbers and add to the person
        if ($null -ne $_.phoneNumbers) {
            foreach ($phoneNumber in $_.phoneNumbers) {
                if (![string]::IsNullOrEmpty($phoneNumber)) {
                    # Add a property for each type of PhoneNumber
                    $_ | Add-Member -MemberType NoteProperty -Name "$($phoneNumber.type)PhoneNumber" -Value $phoneNumber -Force
                }
            }

            # Remove unneccesary fields from  object (to avoid unneccesary large objects)
            # Remove phoneNumbers, since the data is transformed into seperate properties
            $_.PSObject.Properties.Remove('phoneNumbers')
        }

        # Transform addresses and add to the person
        if ($null -ne $_.addresses) {
            foreach ($address in $_.addresses) {
                if (![string]::IsNullOrEmpty($address)) {
                    # Add a property for each type of address
                    $_ | Add-Member -MemberType NoteProperty -Name "$($address.type)Address" -Value $address -Force
                }
            }

            # Remove unneccesary fields from  object (to avoid unneccesary large objects)
            # Remove addresses, since the data is transformed into seperate properties
            $_.PSObject.Properties.Remove('addresses')
        }

        # Transform extensions and add to the person
        if ($null -ne $_.extensions) {
            foreach ($extension in $_.extensions) {
                # Add a property for each extension
                $_ | Add-Member -Name $extension.key -MemberType NoteProperty -Value $extension.value -Force
            }

            # Remove unneccesary fields from  object (to avoid unneccesary large objects)
            # Remove extensions, since the data is transformed into seperate properties
            $_.PSObject.Properties.Remove('extensions')
        }

        # Create contracts object
        $contractsList = [System.Collections.ArrayList]::new()
        if ($null -ne $_.employments) {
            foreach ($employment in $_.employments) {
                # Enhance employment with jobProfile for for extra information, such as: fullName
                $jobProfile = $jobProfilesGrouped["$($employment.jobProfile)"]
                if ($null -ne $jobProfile) {
                    # In the case multiple jobProfiles are found with the same ID, we always select the first one in the array
                    $employment | Add-Member -MemberType NoteProperty -Name "jobProfile" -Value $jobProfile[0] -Force
                }

                # Enhance employment with costAllocation for for extra information, such as: fullName
                # Get costAllocation for employment, linking key is PersonCode + "_" + employmentCode
                $costAllocation = $costAllocationsGrouped[($_.personCode + "_" + $employment.employmentCode)]
                if ($null -ne $costAllocation) {
                    # In the case multiple costAllocations are found with the same ID, we always select the first one in the array
                    $employment | Add-Member -MemberType NoteProperty -Name "costAllocation" -Value $costAllocation[0] -Force
                }

                if ($false -eq $includeAssignments) {
                    # Create Contract object(s) based on employments

                    # Create custom employment object to include prefix of properties
                    $employmentObject = [PSCustomObject]@{}
                    $employment.psobject.properties | ForEach-Object {
                        $employmentObject | Add-Member -MemberType $_.MemberType -Name "employment_$($_.Name)" -Value $_.Value -Force
                    }

                    [Void]$contractsList.Add($employmentObject)
                }
                else {
                    # Create Contract object(s) based on assignments
    
                    # Get assignments for employment, linking key is PersonCode + "_" + employmentCode
                    $assignments = $assignmentsGrouped[($_.personCode + "_" + $employment.employmentCode)]
    
                    # Add assignment and employment data to contracts
                    if ($null -ne $assignments) {
                        foreach ($assignment in $assignments) {
                            # Enhance assignment with jobProfile for for extra information, such as: fullName
                            $jobProfile = $jobProfilesGrouped["$($assignment.jobProfile)"]
                            if ($null -ne $jobProfile) {
                                # In the case multiple jobProfiles are found with the same ID, we always select the first one in the array
                                $assignment | Add-Member -MemberType NoteProperty -Name "jobProfile" -Value $jobProfile[0] -Force
                            }

                            # Enhance assignment with costAllocation for for extra information, such as: fullName
                            # Get costAllocation for assignment, linking key is PersonCode + "_" + assignmentCode
                            $costAllocation = $costAllocationsGrouped[($_.personCode + "_" + $assignment.employmentCode)]
                            if ($null -ne $costAllocation) {
                                # In the case multiple costAllocations are found with the same ID, we always select the first one in the array
                                $assignment | Add-Member -MemberType NoteProperty -Name "costAllocation" -Value $costAllocation[0] -Force
                            }

                            # Create custom assignment object to include prefix in properties
                            $assignmentObject = [PSCustomObject]@{}
    
                            # Add employment object with prefix for property names
                            $employment.psobject.properties | ForEach-Object {
                                $assignmentObject | Add-Member -MemberType $_.MemberType -Name "employment_$($_.Name)" -Value $_.Value -Force
                            }
    
                            # Add position object with prefix for property names
                            $assignment.psobject.properties | ForEach-Object {
                                $assignmentObject | Add-Member -MemberType $_.MemberType -Name "assignment_$($_.Name)" -Value $_.Value -Force
                            }
    
                            # Add employment and position data to contracts
                            [Void]$contractsList.Add($assignmentObject)
                        }
                    }
                    else {
                        if ($true -eq $includePersonsWithoutAssignments) {
                            # Add employment only data to contracts (in case of employments without assignments)

                            # Create custom employment object to include prefix of properties
                            $employmentObject = [PSCustomObject]@{}
                            $employment.psobject.properties | ForEach-Object {
                                $employmentObject | Add-Member -MemberType $_.MemberType -Name "employment_$($_.Name)" -Value $_.Value -Force
                            }
        
                            [Void]$contractsList.Add($employmentObject)
                        }
                    }
                }
            }

            # Remove unneccesary fields from object (to avoid unneccesary large objects)
            # Remove employments, since the data is transformed into a seperate object: contracts
            $_.PSObject.Properties.Remove('employments')
        }
        else {
            ### Be very careful when logging in a loop, only use this when the amount is below 100
            ### When this would log over 100 lines, please refer from using this in HelloID and troubleshoot this in local PS
            # Write-Warning "No employments found for person: $($_.ExternalId)"
        }

        # Add Contracts to person
        if ($contractsList.Count -ge 1) {
            $_.Contracts = $contractsList
        }
        elseif ($true -eq $excludePersonsWithoutContractsInHelloID) {
            ### Be very careful when logging in a loop, only use this when the amount is below 100
            ### When this would log over 100 lines, please refer from using this in HelloID and troubleshoot this in local PS
            # Write-Warning "Excluding person from export: $($_.ExternalId). Reason: Person has no contract data"
            return
        }     

        # Sanitize and export the json
        $person = $_ | ConvertTo-Json -Depth 10
        $person = $person.Replace("._", "__")

        Write-Output $person

        # Updated counter to keep track of actual exported person objects
        $exportedPersons++        
    }

    Write-Information "Succesfully enhanced and exported person objects to HelloID. Result count: $($exportedPersons)"
    Write-Information "Person import completed"
}
catch {
    $ex = $PSItem
    if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObject = Resolve-HTTPError -Error $ex

        $verboseErrorMessage = $errorObject.ErrorMessage

        $auditErrorMessage = $errorObject.ErrorMessage
    }

    # If error message empty, fall back on $ex.Exception.Message
    if ([String]::IsNullOrEmpty($verboseErrorMessage)) {
        $verboseErrorMessage = $ex.Exception.Message
    }
    if ([String]::IsNullOrEmpty($auditErrorMessage)) {
        $auditErrorMessage = $ex.Exception.Message
    }

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"        

    throw "Could not enhance and export person objects to HelloID. Error Message: $auditErrorMessage"
}
