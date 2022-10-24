#####################################################
# HelloID-Conn-Prov-Source-RAET-IAM-API-Beaufort-Departments
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

            $maxTries = 3
            if ( ($auditErrorMessage -Like "*Too Many Requests*" -or $auditErrorMessage -Like "*Connection timed out*") -and $triesCounter -lt $maxTries ) {
                $triesCounter++
                $retry = $true
                $delay = 100
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

Write-Information "Starting department import. Base URL: $BaseUrl"

# Query organizationUnits
try {
    Write-Verbose "Querying organizationUnits"

    $organizationUnits = Invoke-RaetWebRequestList -Url "$BaseUrl/iam/v1.0/organizationUnits"

    Write-Information "Successfully queried organizationUnits. Result: $($organizationUnits.Count)"
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

    throw "Error querying organizationUnits. Error Message: $auditErrorMessage"
}

# Query roleAssignments
try {
    Write-Verbose "Querying roleAssignments"

    $roleAssignments = Invoke-RaetWebRequestList -Url "$BaseUrl/iam/v1.0/roleAssignments"
    # Sort Role assignments on personCode to make sure we always have the same manager with the same data
    $roleAssignments = $roleAssignments | Sort-Object -Property { [int]$_.personCode }

    Write-Information "Successfully queried roleAssignments. Result: $($roleAssignments.Count)"
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

    throw "Error querying roleAssignments. Error Message: $auditErrorMessage"
}

try {
    Write-Verbose 'Enhancing and exporting department objects to HelloID'

    # Set counter to keep track of actual exported person objects
    $exportedDepartments = 0

    $managerActiveCompareDate = Get-Date

    foreach ($organizationUnit in $organizationUnits) {
        $ouRoleAssignments = $roleAssignments | Where-Object { $_.organizationUnit -eq $organizationUnit.id }
        # Sort role assignments on person code to make sure the order is always the same (if the data is the same)
        $ouRoleAssignments = $ouRoleAssignments | Sort-Object personCode

        # Organizational units may contain multiple managers (per organizational unit). There's no way to specify which manager is primary
        # We check of the manager assignment is active and then select the first one we come across that's valid
        $managerId = $null
        foreach ($roleAssignment in $ouRoleAssignments) {
            if (![string]::IsNullOrEmpty($roleAssignment)) {
                if ($roleAssignment.ShortName -eq 'MGR') {
                    $startDate = ([Datetime]::ParseExact($roleAssignment.startDate, 'yyyy-MM-dd', $null))
                    $endDate = ([Datetime]::ParseExact($roleAssignment.endDate, 'yyyy-MM-dd', $null))

                    if ($startDate -lt $managerActiveCompareDate -and $endDate -ge $managerActiveCompareDate ) {
                        $managerId = $roleAssignment.personCode
                        break
                    }
                }
            }
        }

        $department = [PSCustomObject]@{
            ExternalId        = $organizationUnit.shortName
            ShortName         = $organizationUnit.shortName
            DisplayName       = $organizationUnit.fullName
            ManagerExternalId = $managerId
            ParentExternalId  = $organizationUnit.parentOrgUnit
        }

        # Sanitize and export the json
        $department = $department | ConvertTo-Json -Depth 10
        $department = $department.Replace("._", "__")

        Write-Output $department

        # Updated counter to keep track of actual exported person objects
        $exportedDepartments++
    }

    Write-Information "Succesfully enhanced and exported department objects to HelloID. Result count: $($exportedDepartments)"
    Write-Information "Department import completed"
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

    throw "Could not enhance and export department objects to HelloID. Error Message: $auditErrorMessage"
}
