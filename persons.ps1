# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

$c = $configuration | ConvertFrom-Json

$clientId = $c.clientId
$clientSecret = $c.clientSecret
$tenantId = $c.tenantId
$includeAssignments = $c.includeAssignments
$includePersonsWithoutAssignments = $c.includePersonsWithoutAssignments
$excludePersonsWithoutContractsInHelloID = $c.excludePersonsWithoutContractsInHelloID

$Script:BaseUrl = "https://api.raet.com/iam/v1.0"

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
    if (Confirm-AccessTokenIsValid -eq $true) {
        return
    }

    $url = "https://api.raet.com/authentication/token"
    $authorisationBody = @{
        'grant_type'    = "client_credentials"
        'client_id'     = $ClientId
        'client_secret' = $ClientSecret
    }
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        $result = Invoke-WebRequest -Uri $url -Method Post -Body $authorisationBody -ContentType 'application/x-www-form-urlencoded' -Headers @{'Cache-Control' = "no-cache" } -Proxy:$Proxy -UseBasicParsing
        $accessToken = $result.Content | ConvertFrom-Json
        $Script:expirationTimeAccessToken = (Get-Date).AddSeconds($accessToken.expires_in)

        $Script:AuthenticationHeaders = @{
            'X-Client-Id'      = $ClientId
            'Authorization'    = "Bearer $($accessToken.access_token)"
            'X-Raet-Tenant-Id' = $TenantId
        }
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq "Forbidden") {
            $errorMessage = "Something went wrong $($_.ScriptStackTrace). Error message: '$($_.Exception.Message)'"
        }
        elseif (![string]::IsNullOrEmpty($_.ErrorDetails.Message)) {
            $errorMessage = "Something went wrong $($_.ScriptStackTrace). Error message: '$($_.ErrorDetails.Message)'"
        }
        else {
            $errorMessage = "Something went wrong $($_.ScriptStackTrace). Error message: '$($_)'"
        }
        throw $errorMessage
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
    try {
        [System.Collections.ArrayList]$ReturnValue = @()
        $counter = 0
        do {
            if ($counter -gt 0) {
                $SkipTakeUrl = $resultSubset.nextLink.Substring($resultSubset.nextLink.IndexOf("?"))
            }
            $counter++
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
            $accessTokenValid = Confirm-AccessTokenIsValid
            if ($accessTokenValid -ne $true) {
                New-RaetSession -ClientId $clientId -ClientSecret $clientSecret -TenantId $tenantId
            }
            $result = Invoke-WebRequest -Uri $Url$SkipTakeUrl -Method GET -ContentType "application/json" -Headers $Script:AuthenticationHeaders -UseBasicParsing
            $resultSubset = (ConvertFrom-Json  $result.Content)
            $ReturnValue.AddRange($resultSubset.value)
        } until([string]::IsNullOrEmpty($resultSubset.nextLink))
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq "Forbidden") {
            $errorMessage = "Something went wrong $($_.ScriptStackTrace). Error message: '$($_.Exception.Message)'"
        }
        elseif (![string]::IsNullOrEmpty($_.ErrorDetails.Message)) {
            $errorMessage = "Something went wrong $($_.ScriptStackTrace). Error message: '$($_.ErrorDetails.Message)'"
        }
        else {
            $errorMessage = "Something went wrong $($_.ScriptStackTrace). Error message: '$($_)'"
        }
        throw $errorMessage
    }
    return $ReturnValue
}

Write-Information "Starting person import"

# Query persons
try {
    Write-Verbose "Querying persons"

    $persons = Invoke-RaetWebRequestList -Url "$Script:BaseUrl/employees"
    # Make sure persons are unique
    $persons = $persons | Sort-Object id -Unique

    Write-Information "Successfully queried persons. Result: $($persons.Count)"
}
catch {
    throw "Could not retrieve persons. Error: $($_.Exception.Message)"
}

# Query jobProfiles
try {
    Write-Verbose "Querying jobProfiles"
    
    $jobProfiles = Invoke-RaetWebRequestList -Url "$Script:BaseUrl/jobProfiles"
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
    throw "Could not retrieve jobProfiles. Error: $($_.Exception.Message)"
}

# Query costAllocations
try {
    Write-Verbose "Querying costAllocations"
    
    $costAllocations = Invoke-RaetWebRequestList -Url "$Script:BaseUrl/costAllocations"
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
    throw "Could not retrieve costAllocations. Error: $($_.Exception.Message)"
}

# Query assignments
if ($true -eq $includeAssignments) {
    try {
        Write-Verbose "Querying assignments"
        
        $assignments = Invoke-RaetWebRequestList -Url "$Script:BaseUrl/assignments"

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
        throw "Could not retrieve assignments. Error: $($_.Exception.Message)"
    }
}

try {
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
                $_ | Add-Member -Name $_.extensions.key -MemberType NoteProperty -Value $_.extensions.value -Force
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
        } elseif($true -eq $excludePersonsWithoutContractsInHelloID){
            ### Be very careful when logging in a loop, only use this when the amount is below 100
            ### When this would log over 100 lines, please refer from using this in HelloID and troubleshoot this in local PS
            # Write-Warning "Excluding person from export: $($_.ExternalId). Reason: Person has no contract data"
            return
        }

        # Sanitize and export the json
        $person = $_ | ConvertTo-Json -Depth 10
        $person = $person.Replace("._", "__")

        Write-Output $person
    }

    Write-Information "Person import completed"
}
catch {
    Write-Error "Error at line: $($_.InvocationInfo.PositionMessage)"
    throw "Error: $_"
}