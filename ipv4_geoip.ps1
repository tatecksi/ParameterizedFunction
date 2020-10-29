#Purpose: This function will provide the Country Name for a given IP. Note that the IP column must be named IpAddress
#Sample usage: AzureActivity | project-rename IpAddress = CallerIpAddress | invoke ipv4_geoip()

#Setup Variables
$ResourceGroup = "<ResourceGroup>"
$WorkspaceName = "<WorkspaceName>"
$SubscriptionID = "<SubscriptionID>"

#Setup the environment
$workspaceid = "https://management.azure.com/subscriptions/${SubscriptionID}/resourceGroups/${ResourceGroup}/providers/Microsoft.OperationalInsights/workspaces/${WorkspaceName}"

#Connect to your workspace
Clear-AzContext -force

Connect-AzAccount

Get-AzSubscription
Select-AzSubscription -SubscriptionId $SubscriptionID


#Create the Parameter Function

$Query = @"

let cidrBlocks = materialize(externaldata(network:string,geoname_id:string)
[@"https://raw.githubusercontent.com/tatecksi/GeoIP/main/GeoLite2-Country-Blocks-IPv4.csv"] with (ignoreFirstRecord=true, format="csv"));
let countryData = materialize(externaldata(geoname_id:string,locale_code:string,continent_code:string,continent_name:string,country_iso_code:string,country_name:string)
[@"https://raw.githubusercontent.com/tatecksi/GeoIP/main/GeoLite2-Country-Locations-en.csv"] with (ignoreFirstRecord=true, format="csv"));
let GeoLocation =materialize (
countryData 
| project geoname_id, continent_code,continent_name, country_code=country_iso_code, country_name
| join kind=inner hint.strategy=shuffle cidrBlocks on geoname_id
| project-rename list_CIDR=network
| project-away geoname_id, geoname_id1, continent_code);
let cidrLookup =toscalar(cidrBlocks | summarize list_CIDR=make_set(network));
T
| summarize by IpAddress
| mv-apply list_CIDR=cidrLookup to typeof(string) on
(
where ipv4_is_match (IpAddress, list_CIDR) 
)
| join kind=rightouter hint.strategy=shuffle (T) on IpAddress
| join kind=leftouter hint.strategy=shuffle
(
GeoLocation
) on list_CIDR
| project-away list_CIDR, list_CIDR1,IpAddress1

"@


[PSCustomObject]$body = @{
"properties" = @{
    "Category" = "Function"
    "DisplayName" = "ipv4_geoip"
    "FunctionAlias" = "ipv4_geoip"
    "FunctionParameters" = "T:(IpAddress:string)"
    "Query" = $Query    
}
}


#Get auth token
#$token = Get-AzCachedAccessToken
$azProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
if (-not $azProfile.Accounts.Count) {
       Write-Error "Ensure you have logged in (Connect-AzAccount) before calling this function."
    }

$currentAzureContext = Get-AzContext

$profileClient = New-Object Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient($azProfile)
Write-Output ("Getting access token for tenant" + $currentAzureContext.Subscription.TenantId)
$token = $profileClient.AcquireAccessToken($currentAzureContext.Subscription.TenantId)


#Build the API header with the auth token
$authHeader = @{
'Content-Type'='application/json'
'Authorization'='Bearer ' + $token.AccessToken
}


#Invoke WebRequest
try{
    $uri = "${workspaceId}/savedSearches/$((New-Guid).Guid)?api-version=2020-08-01"
    $result = Invoke-WebRequest -Uri $uri -Method Put -Headers $authHeader -Body($body | ConvertTo-Json -Depth 10)
    Write-Output "Successfully created function: $($DisplayName) with status: $($result.StatusDescription)"
    Write-Output ($body.properties | Format-Table)
    Write-Output $result.Content
    }
catch {
    Write-Verbose $_
    Write-Error "Unable to invoke webrequest with error message: $($_.Exception.Message)" -ErrorAction Stop
}


