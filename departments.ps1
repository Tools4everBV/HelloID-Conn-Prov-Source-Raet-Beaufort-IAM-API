$config = $configuration | ConvertFrom-Json 

$clientId = $config.connection.clientId
$clientSecret = $config.connection.clientSecret
$tenantId = $config.connection.tenantId

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
    } catch {
        if ($_.ErrorDetails) {
            Write-Error $_.ErrorDetails
        }elseif ($_.Exception.Response) {
            $result = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($result)
            $responseReader = $reader.ReadToEnd()
            $errorExceptionStreamResponse = $responseReader | ConvertFrom-Json
            $reader.Dispose()
            Write-Error $errorExceptionStreamResponse.error.message
        }else {
            Write-Error "Something went wrong while connecting to the RAET API";
        }
        Exit;
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
        $accessTokenValid = Confirm-AccessTokenIsValid
        if($accessTokenValid -ne $true)
        {
            New-RaetSession -ClientId $clientId -ClientSecret $clientSecret
        }

        [System.Collections.ArrayList]$ReturnValue = @()
        $counter = 0 
        do {
            if ($counter -gt 0) {
                $SkipTakeUrl = $resultSubset.nextLink.Substring($resultSubset.nextLink.IndexOf("?"))
            }    
            $counter++
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;
            $result = Invoke-WebRequest -Uri $Url$SkipTakeUrl -Method GET -ContentType "application/json" -Headers $Script:AuthenticationHeaders -UseBasicParsing
            $resultSubset = (ConvertFrom-Json  $result.Content)
            $ReturnValue.AddRange($resultSubset.value)
        }until([string]::IsNullOrEmpty($resultSubset.nextLink))
    }
    catch {
        if ($_.ErrorDetails) {
            Write-Error $_.ErrorDetails
        }elseif ($_.Exception.Response) {
            $result = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($result)
            $responseReader = $reader.ReadToEnd()
            $errorExceptionStreamResponse = $responseReader | ConvertFrom-Json
            $reader.Dispose()
            Write-Error $errorExceptionStreamResponse.error.message
        }else {
            Write-Error "Something went wrong while fetching data from the RAET API";
        }  
        exit;
    }
    return $ReturnValue
}

function Get-RaetOrganizationUnitsList { 
   
    $Script:BaseUrl = "https://api.raet.com/iam/v1.0"

    try {
        $organizationalUnits = Invoke-RaetWebRequestList -Url "$Script:BaseUrl/organizationUnits"
        $roleAssignments = Invoke-RaetWebRequestList -Url "$Script:BaseUrl/roleAssignments"
        $managerActiveCompareDate = Get-Date

        Write-Verbose -Verbose "Department import starting";
        $departments = @();
        foreach($item in $organizationalUnits)
        {
         
            $ouRoleAssignments = $roleAssignments | Select-Object * | Where-Object organizationUnit -eq $item.id

            $managerId = $null;
            $ExternalIdOu = $null;
            foreach ($roleAssignment in $ouRoleAssignments) {
                if (![string]::IsNullOrEmpty($roleAssignment)) {
                    if ($roleAssignment.ShortName -eq 'MGR') {
                        if($managerActiveCompareDate -ge $roleAssignment.startDate -and $roleAssignment.endDate -le $managerActiveCompareDate ){
                            $managerId = $roleAssignment.personCode
                            $ExternalIdOu = $roleAssignment.organizationUnit
                            break
                        }
                    }
                }
            }   

            $organizationUnit = [PSCustomObject]@{
                ExternalId=$ExternalIdOu
                ShortName=$iten.shortName
                DisplayName=$item.fullName
                ManagerExternalId=$managerId
                ParentExternalId=$item.parentOrgUnit
            }
            $departments += $organizationUnit;
        }
        Write-Verbose -Verbose "Department import completed";
        Write-Output $departments | ConvertTo-Json -Depth 10;
    } catch {
        throw "Could not Get-OrganizationUnitsList, message: $($_.Exception.Message)"      
    }
}

#call the Get-RaetOrganizationUnitsList function to get the data from the API
Get-RaetOrganizationUnitsList