#####################################################
# HelloID-Conn-Prov-Source-RAET-IAM-API-Beaufort-Departments
#
# Version: 2.1.1
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
            else {
                $SkipTakeUrl = "?take=1000"
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

Write-Information "Starting department import. Base URL: $BaseUrl"

# Query organizationUnits
try {
    Write-Verbose "Querying organizationUnits"

    $organizationUnits = Invoke-RaetWebRequestList -Url "$BaseUri/iam/v1.0/organizationUnits"

    Write-Information "Successfully queried organizationUnits. Result: $($organizationUnits.Count)"
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"      

    throw "Error querying organizationUnits. Error Message: $($errorMessage.AuditErrorMessage)"
}

# Query roleAssignments
try {
    Write-Verbose "Querying roleAssignments"

    $roleAssignments = Invoke-RaetWebRequestList -Url "$BaseUri/iam/v1.0/roleAssignments"
    # Sort Role assignments on personCode to make sure we always have the same manager with the same data
    $roleAssignments = $roleAssignments | Sort-Object -Property { [int]$_.personCode }

    Write-Information "Successfully queried roleAssignments. Result: $($roleAssignments.Count)"
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"     

    throw "Error querying roleAssignments. Error Message: $($errorMessage.AuditErrorMessage)"
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
            ExternalId        = $organizationUnit.id
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

    Write-Information "Successfully enhanced and exported department objects to HelloID. Result count: $($exportedDepartments)"
    Write-Information "Department import completed"
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"       

    throw "Could not enhance and export department objects to HelloID. Error Message: $($errorMessage.AuditErrorMessage)"
}