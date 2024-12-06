#####################################################
# HelloID-Conn-Prov-Source-RAET-IAM-API-Beaufort-Persons
#
# Version: 2.2.0
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
$includeExtensions = $c.includeExtensions
$useTimelines = $c.useTimelines

$Script:AuthenticationUri = "https://connect.visma.com/connect/token"
$Script:BaseUri = "https://api.youforce.com"

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

function Get-ErrorMessage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $errorMessage = [PSCustomObject]@{
            VerboseErrorMessage = $null
            AuditErrorMessage   = $null
        }

        if ( $($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $httpErrorObject = Resolve-HTTPError -Error $ErrorObject

            $errorMessage.VerboseErrorMessage = $httpErrorObject.ErrorMessage

            $errorMessage.AuditErrorMessage = $httpErrorObject.ErrorMessage
        }

        # If error message empty, fall back on $ex.Exception.Message
        if ([String]::IsNullOrEmpty($errorMessage.VerboseErrorMessage)) {
            $errorMessage.VerboseErrorMessage = $ErrorObject.Exception.Message
        }
        if ([String]::IsNullOrEmpty($errorMessage.AuditErrorMessage)) {
            $errorMessage.AuditErrorMessage = $ErrorObject.Exception.Message
        }

        Write-Output $errorMessage
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
            'tenant_id'     = $TenantId
        }        
        $splatAccessTokenParams = @{
            Uri             = $Script:AuthenticationUri
            Headers         = @{'Cache-Control' = "no-cache" }
            Method          = 'POST'
            ContentType     = "application/x-www-form-urlencoded"
            Body            = $authorisationBody
            UseBasicParsing = $true
        }

        Write-Verbose "Creating Access Token at uri '$($splatAccessTokenParams.Uri)'"

        $result = Invoke-RestMethod @splatAccessTokenParams -Verbose:$false
        if ($null -eq $result.access_token) {
            throw $result
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
        $errorMessage = Get-ErrorMessage -ErrorObject $ex

        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($($errorMessage.VerboseErrorMessage))"

        $auditLogs.Add([PSCustomObject]@{
                # Action  = "" # Optional
                Message = "Error creating Access Token at uri ''$($splatAccessTokenParams.Uri)'. Please check credentials. Error Message: $($errorMessage.AuditErrorMessage)"
                IsError = $true
            })     
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
        $Url,

        [parameter(Mandatory = $false)]
        [string]
        $ValidOn
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
            else {
                $SkipTakeUrl = "?take=1000"

                if(-not([String]::IsNullOrEmpty($ValidOn)))
                {
                    $SkipTakeUrl = $SkipTakeUrl + "&ValidOn=$ValidOn"
                }
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
            $errorMessage = Get-ErrorMessage -ErrorObject $ex
    
            Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"
            
            $maxTries = 3
            if ( ($($errorMessage.AuditErrorMessage) -Like "*Too Many Requests*" -or $($errorMessage.AuditErrorMessage) -Like "*Connection timed out*") -and $triesCounter -lt $maxTries ) {
                $triesCounter++
                $retry = $true
                $delay = 601 # Wait for 0,601 seconds  - RAET IAM API allows a maximum of 100 requests a minute (https://community.visma.com/t5/Kennisbank-Youforce-API/API-Status-amp-Policy/ta-p/428099#toc-hId-339419904:~:text=3-,Spike%20arrest%20policy%20(max%20number%20of%20API%20calls%20per%20minute),100%20calls%20per%20minute,-*For%20the%20base).
                Write-Warning "Error querying data from '$($splatGetDataParams.Uri)'. Error Message: $($errorMessage.AuditErrorMessage). Trying again in '$delay' milliseconds for a maximum of '$maxTries' tries."
                Start-Sleep -Milliseconds $delay
            }
            else {
                $retry = $false
                throw "Error querying data from '$($splatGetDataParams.Uri)'. Error Message: $($errorMessage.AuditErrorMessage)"
            }
        }
    }while (-NOT[string]::IsNullOrEmpty($result.nextLink) -or $retry -eq $true)

    Write-Verbose "Successfully queried data from '$($Url)'. Result count: $($ReturnValue.Count)"

    return $ReturnValue
}
#endregion functions

Write-Information "Starting person import. Base URI: $BaseUri"

# Query persons
try {
    Write-Verbose "Querying persons"

    $personsList = Invoke-RaetWebRequestList -Url "$BaseUri/iam/v1.0/persons"

    # Make sure persons are unique
    $persons = $personsList | Where-Object { $_.personCode -ne $null } | Sort-Object id -Unique

    Write-Information "Successfully queried persons. Result: $($persons.Count)"
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"      

    throw "Error querying persons. Error Message: $($errorMessage.AuditErrorMessage)"
}

# Query person extensions
try {
    if ($true -eq $includeExtensions) {
        Write-Verbose "Querying person extensions"

        $personExtensionsList = Invoke-RaetWebRequestList -Url "$BaseUri/extensions/v1.0/iam/persons"

        # Group by personCode
        $personExtensionsGrouped = $personExtensionsList | Group-Object personCode -CaseSensitive -AsHashTable -AsString

        Write-Information "Successfully queried person extensions. Result: $($personExtensionsList.Count)"
    }
    else { 
        Write-Information "Ignored querying person extensions because the configuration toggle to include extensions is: $($includeExtensions)"
    }
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"       

    throw "Error querying person extensions. Error Message: $($errorMessage.AuditErrorMessage)"
}

# Query employments
try {
    Write-Verbose "Querying employments"

    if($useTimelines) {
        $now = Get-Date
        $validOn = (Get-Date -Format "yyyy-MM-dd")

        $employmentsList = Invoke-RaetWebRequestList -Url "$Script:BaseUri/iam/v1.0/employments/timelines" -ValidOn $validOn
        $employmentsList = $employmentsList | Where-Object { -not([String]::IsNullOrEmpty($_.hireDate)) -and (Get-Date $_.hireDate) -le $now }

        $employmentsListFuture = Invoke-RaetWebRequestList -Url "$Script:BaseUri/iam/v1.0/employments"
        $employmentsListFuture = $employmentsListFuture | Where-Object { -not([String]::IsNullOrEmpty($_.hireDate)) -and  (Get-Date $_.hireDate) -gt $now }

        # Group by personCode
        $employmentsGrouped = ($employmentsList + $employmentsListFuture) | Group-Object personCode -CaseSensitive -AsHashTable -AsString
    }
    else {
       $employmentsList = Invoke-RaetWebRequestList -Url "$Script:BaseUri/iam/v1.0/employments"
       
        # Group by personCode
        $employmentsGrouped = $employmentsList | Group-Object personCode -CaseSensitive -AsHashTable -AsString

    }
    Write-Information "Successfully queried employments. Result: $($employmentsList.Count)"
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"         

    throw "Error querying employments. Error Message: $($errorMessage.AuditErrorMessage)"
}

# Query employment extensions
try {
    if ($true -eq $includeExtensions) {
        Write-Verbose "Querying employment extensions"

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

        Write-Information "Successfully queried employment extensions. Result: $($employmentExtensionsList.Count)"
    }
    else { 
        Write-Information "Ignored querying employmens extensions because the configuration toggle to include extensions is: $($includeExtensions)"
    }
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"            

    throw "Error querying employment extensions. Error Message: $($errorMessage.AuditErrorMessage)"
}

# Query assignments
if ($true -eq $includeAssignments) {
    try {
        Write-Verbose "Querying assignments"
        
        $assignmentsList = Invoke-RaetWebRequestList -Url "$BaseUri/iam/v1.0/assignments"

        # Add ExternalId property as linking key to contract, linking key is PersonCode + "_" + employmentCode
        $assignmentsList | Add-Member -MemberType NoteProperty -Name "ExternalId" -Value $null -Force
        $assignmentsList | Foreach-Object {
            $_.ExternalId = $_.PersonCode + "_" + $_.employmentCode
        }

        # Group by ExternalId
        $assignmentsGrouped = $assignmentsList | Group-Object ExternalId -AsHashTable

        Write-Information "Successfully queried assignments. Result: $($assignmentsList.Count)"
    }
    catch {
        $ex = $PSItem
        $errorMessage = Get-ErrorMessage -ErrorObject $ex
    
        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"        
    
        throw "Error querying assignments. Error Message: $($errorMessage.AuditErrorMessage)"
    }
}

# Query jobProfiles
try {
    Write-Verbose "Querying jobProfiles"
    
    $jobProfilesList = Invoke-RaetWebRequestList -Url "$BaseUri/iam/v1.0/jobProfiles"

    # Group by id
    $jobProfilesGrouped = $jobProfilesList | Group-Object Id -AsHashTable

    Write-Information "Successfully queried jobProfiles. Result: $($jobProfilesList.Count)"
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"     

    throw "Error querying jobProfiles. Error Message: $($errorMessage.AuditErrorMessage)"
}

# Query costAllocations
try {
    Write-Verbose "Querying costAllocations"
    
    $costAllocationsList = Invoke-RaetWebRequestList -Url "$BaseUri/iam/v1.0/costAllocations"

    # Add ExternalId property as linking key to contract, linking key is PersonCode + "_" + employmentCode
    $costAllocationsList | Add-Member -MemberType NoteProperty -Name "ExternalId" -Value $null -Force
    $costAllocationsList | Foreach-Object {
        $_.ExternalId = $_.PersonCode + "_" + $_.employmentCode
    }
    
    # Group by ExternalId
    $costAllocationsGrouped = $costAllocationsList | Group-Object ExternalId -AsHashTable

    Write-Information "Successfully queried costAllocations. Result: $($costAllocationsList.Count)"
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"    

    throw "Error querying costAllocations. Error Message: $($errorMessage.AuditErrorMessage)"
}

# Query organizationUnits
try {
    Write-Verbose "Querying organizationUnits"

    $organizationUnits = Invoke-RaetWebRequestList -Url "$BaseUri/iam/v1.0/organizationUnits"

    # Group by ExternalId
    $organizationUnitsGrouped = $organizationUnits | Group-Object id -AsHashTable -AsString

    Write-Information "Successfully queried organizationUnits. Result: $($organizationUnits.Count)"
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"       

    throw "Error querying organizationUnits. Error Message: $($errorMessage.AuditErrorMessage)"
}

try {
    Write-Verbose 'Enhancing and exporting person objects to HelloID'

    # Set counter to keep track of actual exported person objects
    $exportedPersons = 0

    # Enhance the persons model
    $persons | Add-Member -MemberType NoteProperty -Name "ExternalId" -Value $null -Force
    $persons | Add-Member -MemberType NoteProperty -Name "DisplayName" -Value $null -Force
    $persons | Add-Member -MemberType NoteProperty -Name "Contracts" -Value $null -Force

    $persons  | ForEach-Object {
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

            # Remove unneccesary fields from  object (to avoid unneccesary large objects)
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

            # Remove unneccesary fields from object (to avoid unneccesary large objects)
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

            # Remove unneccesary fields from object (to avoid unneccesary large objects)
            $_.PSObject.Properties.Remove('addresses')
        }

        # Transform extensions and add to the person
        if ($true -eq $includeExtensions) {
            if ($null -ne $personExtensionsGrouped) {
                $personExtensions = $personExtensionsGrouped[$_.personCode]
                if ($null -ne $personExtensions) {
                    foreach ($personExtension in $personExtensions) {
                        # Add a property for each field in object
                        foreach ($property in $personExtension.PsObject.Properties) {
                            $_ | Add-Member -MemberType NoteProperty -Name ("extension_" + $personExtension.fieldNameAlias.Replace(' ', '') + "_" + $property.Name) -Value "$($property.value)" -Force
                        }
                    }
                }
            }
        }
        # Remove unneccesary fields from object (to avoid unneccesary large objects) - Extensions are available via a seperate endpoint
        $_.PSObject.Properties.Remove('extensions')

        # Create contracts object
        # Get employments for person, linking key is company personCode
        $personEmployments = $employmentsGrouped[$_.personCode]

        $contractsList = [System.Collections.ArrayList]::new()
        if ($null -ne $personEmployments) {
            foreach ($employment in $personEmployments) {
                if($useTimelines) {
                    foreach ($property in $employment.PsObject.Properties) {
                        if($property.value -ne $null)
                        {
                            $type = $property.value.GetType().fullname
                            if($type -eq 'System.Object[]')
                            {
                                $employment."$($property.name)" = $($property.value.value)
                            }
                        }
                    }
                    foreach ($property in $employment.workingAmount.PsObject.Properties) {
                        $type = $property.value.GetType().fullname
                        if($type -eq 'System.Object[]')
                        {
                            $employment.workingAmount."$($property.name)" = $($property.value.value)
                        }
                    }

                    

                    $employment | Add-Member -MemberType NoteProperty -Name "employmentCode" -Value $employment.contractCode -Force
                }

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

                #region Custom - Enhance assignment with upper department(s) information
                # Enhance employment with upper OU for extra information
                $upperOU = $organizationUnitsGrouped["$($employment.organizationUnit_parentOrgUnit)"]
                if ($null -ne $upperOU) {
                    # In case multiple are found with the same ID, we always select the first one in the array
                    $upperOU = $upperOU | Select-Object -First 1

                    if (![string]::IsNullOrEmpty($upperOU)) {
                        foreach ($property in $upperOU.PsObject.Properties) {
                            # Add a property for each field in object
                            $employment | Add-Member -MemberType NoteProperty -Name ("organizationUnitUpper_" + $property.Name) -Value $property.Value -Force
                        }
                    }
                }

                # Enhance employment with ipper upper OU for extra information
                $upperUpperOU = $organizationUnitsGrouped["$($employment.organizationUnitUpper_parentOrgUnit)"]
                if ($null -ne $upperUpperOU) {
                    # In case multiple are found with the same ID, we always select the first one in the array
                    $upperUpperOU = $upperUpperOU | Select-Object -First 1

                    if (![string]::IsNullOrEmpty($upperUpperOU)) {
                        foreach ($property in $upperUpperOU.PsObject.Properties) {
                            # Add a property for each field in object
                            $employment | Add-Member -MemberType NoteProperty -Name ("organizationUnitUpperUpper_" + $property.Name) -Value $property.Value -Force
                        }
                    }
                }
                #endregion Custom - Enhance assignment with upper department(s) information

                # Enhance employment with costAllocation for extra information, such as: fullName
                # Get costAllocation for employment, linking key is PersonCode + "_" + employmentCode
                $costAllocation = $costAllocationsGrouped[($_.personCode + "_" + $employment.employmentCode)]
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
                        $employmentExtensions = $employmentExtensionsGrouped[($_.personCode + "_" + $employment.employmentCode)]
                        if ($null -ne $employmentExtensions) {
                            foreach ($employmentExtension in $employmentExtensions) {
                                # Add a property for each field in object
                                foreach ($property in $employmentExtension.PsObject.Properties) {
                                    $employment | Add-Member -MemberType NoteProperty -Name ("extension_" + $employmentExtension.fieldNameAlias.Replace(' ', '') + "_" + $property.Name) -Value "$($property.value)" -Force
                                }
                            }
                        }
                    }
                }
                # Remove unneccesary fields from object (to avoid unneccesary large objects) - Extensions are available via a seperate endpoint
                $employment.PSObject.Properties.Remove('extensions')

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

                            #region Custom - Enhance assignment with upper department(s) information
                            # Enhance assignment with upper OU for extra information
                            $upperOU = $organizationUnitsGrouped["$($assignment.organizationUnit_parentOrgUnit)"]
                            if ($null -ne $upperOU) {
                                # In case multiple are found with the same ID, we always select the first one in the array
                                $upperOU = $upperOU | Select-Object -First 1

                                if (![string]::IsNullOrEmpty($upperOU)) {
                                    foreach ($property in $upperOU.PsObject.Properties) {
                                        # Add a property for each field in object
                                        $assignment | Add-Member -MemberType NoteProperty -Name ("organizationUnitUpper_" + $property.Name) -Value $property.Value -Force
                                    }
                                }
                            }

                            # Enhance assignment with upper upper OU for extra information
                            $upperUpperOU = $organizationUnitsGrouped["$($assignment.organizationUnitUpper_parentOrgUnit)"]
                            if ($null -ne $upperUpperOU) {
                                # In case multiple are found with the same ID, we always select the first one in the array
                                $upperUpperOU = $upperUpperOU | Select-Object -First 1

                                if (![string]::IsNullOrEmpty($upperUpperOU)) {
                                    foreach ($property in $upperUpperOU.PsObject.Properties) {
                                        # Add a property for each field in object
                                        $assignment | Add-Member -MemberType NoteProperty -Name ("organizationUnitUpperUpper_" + $property.Name) -Value $property.Value -Force
                                    }
                                }
                            }
                            #endregion Custom - Enhance assignment with upper department(s) information

                            # Enhance assignment with costAllocation for extra information, such as: fullName
                            # Get costAllocation for assignment, linking key is PersonCode + "_" + assignmentCode
                            $costAllocation = $costAllocationsGrouped[($_.personCode + "_" + $assignment.employmentCode)]
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
                        else {
                            Write-Warning "Excluding person from export: $($_.ExternalId). Reason: No assignments found for person"
                        }
                    }
                }
            }

             # Remove unneccesary fields from object (to avoid unneccesary large objects)
             # Remove employments, since the data is transformed into a seperate object: contracts
            # $_.PSObject.Properties.Remove('employments')
        }
        else {
            ### Be very careful when logging in a loop, only use this when the amount is below 100
            ### When this would log over 100 lines, please refer from using this in HelloID and troubleshoot this in local PS
            # Write-Warning "No employments found for person: $($_.ExternalId)"
        }

        # Add Contracts to person
        if ($null -ne $contractsList) {
            # This example can be used by the consultant if you want to filter out persons with an empty array as contract
            # *** Please consult with the Tools4ever consultant before enabling this code. ***
            if ($contractsList.Count -eq 0 -and $true -eq $excludePersonsWithoutContractsInHelloID) {
                # Write-Warning "Excluding person from export: $($_.ExternalId). Reason: Contracts is an empty array"
                return
            }
            else {
                $_.Contracts = $contractsList
            }
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

    Write-Information "Successfully enhanced and exported person objects to HelloID. Result count: $($exportedPersons)"
    Write-Information "Person import completed"
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"     

    throw "Could not enhance and export person objects to HelloID. Error Message: $($errorMessage.AuditErrorMessage)"
}
