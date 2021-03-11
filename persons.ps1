$config = $configuration | ConvertFrom-Json 

$clientId = $config.connection.clientId
$clientSecret = $config.connection.clientSecret
$tenantId = $config.connection.tenantId
$includeAssignments = $config.switchIncludeAssignments

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
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;
        $result = Invoke-WebRequest -Uri $url -Method Post -Body $authorisationBody -ContentType 'application/x-www-form-urlencoded' -Headers @{'Cache-Control' = "no-cache" } -Proxy:$Proxy -UseBasicParsing
        $accessToken = $result.Content | ConvertFrom-Json
        $Script:expirationTimeAccessToken = (Get-Date).AddSeconds($accessToken.expires_in)

        $Script:AuthenticationHeaders = @{
            'X-Client-Id'      = $ClientId;
            'Authorization'    = "Bearer $($accessToken.access_token)";
            'X-Raet-Tenant-Id' = $TenantId;
           
        }     
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq "Forbidden") {
            $errorMessage = "Something went wrong $($_.ScriptStackTrace). Error message: '$($_.Exception.Message)'"
        } elseif (![string]::IsNullOrEmpty($_.ErrorDetails.Message)) {
            $errorMessage = "Something went wrong $($_.ScriptStackTrace). Error message: '$($_.ErrorDetails.Message)'" 
        } else {
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
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;
            $accessTokenValid = Confirm-AccessTokenIsValid
            if ($accessTokenValid -ne $true) {
                New-RaetSession -ClientId $clientId -ClientSecret $clientSecret
            }
            $result = Invoke-WebRequest -Uri $Url$SkipTakeUrl -Method GET -ContentType "application/json" -Headers $Script:AuthenticationHeaders -UseBasicParsing
            $resultSubset = (ConvertFrom-Json  $result.Content)
            $ReturnValue.AddRange($resultSubset.value)
        }until([string]::IsNullOrEmpty($resultSubset.nextLink))
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq "Forbidden") {
            $errorMessage = "Something went wrong $($_.ScriptStackTrace). Error message: '$($_.Exception.Message)'"
        } elseif (![string]::IsNullOrEmpty($_.ErrorDetails.Message)) {
            $errorMessage = "Something went wrong $($_.ScriptStackTrace). Error message: '$($_.ErrorDetails.Message)'" 
        } else {
            $errorMessage = "Something went wrong $($_.ScriptStackTrace). Error message: '$($_)'" 
        }  
        throw $errorMessage
    }
    return $ReturnValue
}

function Get-RaetPersonDataList { 
    [CmdletBinding()]
    param ()
    
    $Script:BaseUrl = "https://api.raet.com/iam/v1.0"
    
    try {
        $persons = Invoke-RaetWebRequestList -Url "$Script:BaseUrl/employees"

        # Make sure persons are unique
        $persons = $persons | Sort-Object id -Unique

        $jobProfiles = Invoke-RaetWebRequestList -Url "$Script:BaseUrl/jobProfiles"
        $jobProfiles = $jobProfiles | Select-Object * -ExcludeProperty extensions
        $jobProfileGrouped = $jobProfiles | Group-Object Id -AsHashTable

        if($true -eq $includeAssignments){
            $assignments = Invoke-RaetWebRequestList -Url "$Script:BaseUrl/assignments"

            $assignmentHashtable = @{}
            foreach ($record in $assignments) {
                $tmpKey = $record.personCode + "_" + $record.employmentCode
                if (![string]::IsNullOrEmpty($tmpKey)) {
                    if($assignmentHashtable.Contains($tmpKey)) {
                        $assignmentHashtable.$tmpKey += ($record)
                    } else {
                        $assignmentHashtable.Add($tmpKey, @($record))
                    } 
                }
            }   
        }
      

        # Extend the persons model
        $persons | Add-Member -MemberType NoteProperty -Name "BusinessEmailAddress" -Value $null -Force
        $persons | Add-Member -MemberType NoteProperty -Name "PrivateEmailAddress" -Value $null -Force
        $persons | Add-Member -MemberType NoteProperty -Name "BusinessPhoneNumber" -Value $null -Force
        $persons | Add-Member -MemberType NoteProperty -Name "MobilePhoneNumber" -Value $null -Force
        $persons | Add-Member -MemberType NoteProperty -Name "HomePhoneNumber" -Value $null -Force
        
        foreach ($person in $persons) { 
            #Validate the required person fields
            if (($null -ne $person.knownAs) -And ($null -ne $person.lastNameAtBirth)) {
                $person | Add-Member -Name "ExternalId" -MemberType NoteProperty -Value $person.personCode

                $displayName = ($person.knownAs + ' ' + $person.lastNameAtBirth)
                $person | Add-Member -Name "DisplayName" -MemberType NoteProperty -Value $displayName
                                                            
                $contracts = New-Object System.Collections.Generic.List[System.Object]
                foreach ($employment in $person.employments) {                
                    $jobProfile = $jobProfileGrouped["$($employment.jobProfile)"]    
                    
                    if($true -eq $includeAssignments){
                        # Create Contract object(s) based on assignments
                        $lookingFor = $person.personCode + "_" + $employment.employmentCode
                        #$personAssignments = $assignmentsGrouped[$person.personCode + "_" + $employment.employmentCode]

                        $personAssignments = $assignmentHashtable.$lookingFor
                        foreach($assignment in $personAssignments){
                            if ($assignment.employmentCode -eq $employment.employmentCode) {
                                $jobProfile = $jobProfileGrouped["$($assignment.jobProfile)"]                                                                                    
                                    
                                #Contract result object used in HelloID
                                $Contract = [PSCustomObject]@{
                                    ExternalId       = $assignment.id
                                    EmploymentType   = @{
                                        ShortName = $employment.employmentType
                                        FullName  = $null
                                    }
                                    PersonCode       = $person.personCode
                                    EmploymentCode   = $employment.employmentCode
                                    StartDate        = $assignment.startDate
                                    EndDate          = $assignment.endDate
                                    DischargeDate    = $employment.dischargeDate
                                    HireDate         = $employment.hireDate
                                    JobProfile       = @{
                                        ShortName = $assignment.jobProfile
                                        FullName  = $($jobProfile.fullName)
                                    }
                                    WorkingAmount    = @{
                                        AmountOfWork = $assignment.workingAmount.amountOfWork
                                        UnitOfWork   = $assignment.workingAmount.unitOfWork
                                        PeriodOfWork = $assignment.workingAmount.periodOfWork
                                    }
                                    OrganizationUnit = @{
                                        ShortName = $assignment.organizationUnit
                                        FullName  = $null
                                    }
                                }
                                $contracts.add($Contract)
                            }
                        } 
                    }else{
                        # Create Contract object(s) based on employments

                        #Contract result object used in HelloID
                        $Contract = [PSCustomObject]@{
                            ExternalId       = $person.personCode + '_' + $employment.employmentCode
                            EmploymentType   = @{
                                ShortName = $employment.employmentType
                                FullName  = $null
                            }
                            PersonCode       = $person.personCode
                            EmploymentCode   = $employment.employmentCode
                            StartDate        = $employment.hireDate
                            EndDate          = $employment.dischargeDate
                            DischargeDate    = $employment.dischargeDate
                            HireDate         = $employment.hireDate
                            JobProfile       = @{
                                ShortName = $employment.jobProfile
                                FullName  = $($jobProfile.fullName)
                            }
                            WorkingAmount    = @{
                                AmountOfWork = $employment.workingAmount.amountOfWork
                                UnitOfWork   = $employment.workingAmount.unitOfWork
                                PeriodOfWork = $employment.workingAmount.periodOfWork
                            }
                            OrganizationUnit = @{
                                ShortName = $employment.organizationUnit
                                FullName  = $null
                            }
                        }
                        $contracts.add($Contract)
                    }
                                                                                
                    $person | Add-Member -Name "Contracts" -MemberType NoteProperty -Value $contracts -Force

                    # Add emailAddresses to the person
                    foreach ($emailAddress in $person.emailAddresses) {
                        if (![string]::IsNullOrEmpty($emailAddress)) {
                            if ($emailAddress.type -eq "Business") {
                                $person.BusinessEmailAddress = $emailAddress.address
                            } 
                            if ($emailAddress.type -eq "Private") {
                                $person.PrivateEmailAddress = $emailAddress.address
                            }                           
                        }
                    }

                    # Add phoneNumbers  to the person
                    foreach ($phoneNumber in $person.phoneNumbers) {
                        if (![string]::IsNullOrEmpty($phoneNumber)) {
                            if ($phoneNumber.type -eq "Business") {
                                $person.BusinessPhoneNumber = $phoneNumber.number
                            }
                            if ($phoneNumber.type -eq "Mobile") {
                                $person.MobilePhoneNumber = $phoneNumber.number
                            }
                            if ($phoneNumber.type -eq "Home") {
                                $person.HomePhoneNumber = $phoneNumber.number
                            }       
                        }
                    }

                    #Extend the person model using the person field extensions
                    foreach ($extension in $person.extensions) {
                        $person | Add-Member -Name $person.extensions.key -MemberType NoteProperty -Value $person.extensions.value -Force
                    }
                }

                # Convert naming convention codes to standard
                Switch($person.nameAssembleOrder ){
                    "E" {
                        $person.nameAssembleOrder = "B"
                    }
                    "P" {
                        $person.nameAssembleOrder = "P"
                    }
                    "C" {
                        $person.nameAssembleOrder = "BP"
                    }
                    "B" {
                        $person.nameAssembleOrder = "PB"
                    }
                    "D" {
                        $person.nameAssembleOrder = "BP"
                    }
                }

                Write-Output $person | ConvertTo-Json -Depth 10
            }
        }
        Write-Verbose -Verbose "Persons import completed: $($persons.count)"
    }
    catch {
        Throw "Could not Get-RaetPersonDataList, message: $($_.Exception.Message)"
    } 
}

#call the Get-RaetPersonDataList function to get the data from the API
Get-RaetPersonDataList