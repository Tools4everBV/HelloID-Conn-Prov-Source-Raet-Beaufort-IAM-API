# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

$c = $configuration | ConvertFrom-Json

$clientId = $c.clientId
$clientSecret = $c.clientSecret
$tenantId = $c.tenantId

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

Write-Information "Starting department import"

# Query organizationUnits
try {
    Write-Verbose "Querying organizationUnits"

    $organizationUnits = Invoke-RaetWebRequestList -Url "$Script:BaseUrl/organizationUnits"

    Write-Information "Successfully queried organizationUnits. Result: $($organizationUnits.Count)"
}
catch {
    throw "Could not retrieve organizationUnits. Error: $($_.Exception.Message)"
}

# Query roleAssignments
try {
    Write-Verbose "Querying roleAssignments"

    $roleAssignments = Invoke-RaetWebRequestList -Url "$Script:BaseUrl/roleAssignments"
    # Sort Role assignments on personCode to make sure we always have the same manager with the same data
    $roleAssignments = $roleAssignments | Sort-Object -Property { [int]$_.personCode }

    Write-Information "Successfully queried roleAssignments. Result: $($roleAssignments.Count)"
}
catch {
    throw "Could not retrieve roleAssignments. Error: $($_.Exception.Message)"
}

try {
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
    }

    Write-Information "Department import completed"
}
catch {
    Write-Error "Error at line: $($_.InvocationInfo.PositionMessage)"
    throw "Error: $_"
}