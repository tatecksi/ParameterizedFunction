#Purpose: This is to convert UTC time to Australian Eastern Time with Daylight Saving.
#Sample usage: AzureActivity | extend AUSTimeZone = ConvertUtcToAustraliaEastern(TimeGenerated)

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
// Daylight Savings Time (DST) for Australia East is defined as the first Sunday in October through first Sunday in April
// Time switchover happens at 2:00 AM local time
// Get the first day in October and April
let October = datetime_add("Hour", 2 ,startofmonth(startofyear(UtcDateTime),9));
let April = datetime_add("Hour", 2 ,startofmonth(startofyear(UtcDateTime),3));
// Get the number of days from start of month to correct Sunday
let FirstSundayOctober = ((7 - toint(dayofweek(October) / 1d)) % 7);
let FirstSundayApril = ((7 - toint(dayofweek(April) / 1d)) % 7);
// Get datetimes for the proper days for comparision
let DstStart = datetime_add("Day", FirstSundayOctober, October);
let DstEnd = datetime_add("Day", FirstSundayApril, April);
// Compare the input to the Dst window
iff(UtcDateTime between (DstEnd .. DstStart), datetime_add("Hour", +10, UtcDateTime), datetime_add("Hour", +11, UtcDateTime))

"@


[PSCustomObject]$body = @{
"properties" = @{
    "Category" = "Function"
    "DisplayName" = "ConvertUtcToAustraliaEastern"
    "FunctionAlias" = "ConvertUtcToAustraliaEastern"
    "FunctionParameters" = "UtcDateTime:datetime"
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


