#Purpose: This function will summarize UEBA Activity Insights for a user.
#Sample usage: AzureActivity | where CategoryValue =="Administrative" | where Caller has "@" | distinct Caller | extend UserInsights = getUserInsights Caller]

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

toscalar(BehaviorAnalytics
| evaluate bag_unpack(ActivityInsights)
| project UserPrincipalName,ActionType,EventSource,
FirstTimeConnectionFromCountryObservedInTenant=iif(FirstTimeConnectionFromCountryObservedInTenant==True,1,0),
BrowserUncommonlyUsedAmongPeers=iif(BrowserUncommonlyUsedAmongPeers==True,1,0), 
FirstTimeUserConnectedFromCountry=iff(FirstTimeUserConnectedFromCountry==True,1,0),
AppIdUncommonlyAccessedInTenant=iff(AppIdUncommonlyAccessedInTenant==True,1,0),
CountryUncommonlyConnectedFromInTenant=iff(CountryUncommonlyConnectedFromInTenant==True,1,0),
ResourceUncommonlyAccessedAmongPeers=iff(ResourceUncommonlyAccessedAmongPeers==True,1,0),
ResourceUncommonlyAccessedInTenant=iff(ResourceUncommonlyAccessedInTenant==True,1,0), 
BrowserUncommonlyUsedInTenant=iff(BrowserUncommonlyUsedInTenant==True,1,0),
AppUncommonlyUsedAmongPeers=iff(AppUncommonlyUsedAmongPeers==True,1,0),
ISPUncommonlyUsedAmongPeers=iff(ISPUncommonlyUsedAmongPeers==True,1,0),
ISPUncommonlyUsedInTenant=iff(ISPUncommonlyUsedInTenant==True,1,0)
| summarize FirstTimeConnectionFromCountryObservedInTenant=sum(FirstTimeConnectionFromCountryObservedInTenant), 
            BrowserUncommonlyUsedAmongPeers=sum(BrowserUncommonlyUsedAmongPeers),
            FirstTimeUserConnectedFromCountry=sum(FirstTimeUserConnectedFromCountry),
            AppIdUncommonlyAccessedInTenant=sum(AppIdUncommonlyAccessedInTenant),
            CountryUncommonlyConnectedFromInTenant=sum(CountryUncommonlyConnectedFromInTenant),
            ResourceUncommonlyAccessedAmongPeers=sum(ResourceUncommonlyAccessedAmongPeers),
            ResourceUncommonlyAccessedInTenant=sum(ResourceUncommonlyAccessedInTenant),
            BrowserUncommonlyUsedInTenant=sum(BrowserUncommonlyUsedInTenant),
            AppUncommonlyUsedAmongPeers=sum(AppUncommonlyUsedAmongPeers),
            ISPUncommonlyUsedAmongPeers=sum(ISPUncommonlyUsedAmongPeers),
            ISPUncommonlyUsedInTenant=sum(ISPUncommonlyUsedInTenant) by UserPrincipalName
| summarize Insights= make_bag(pack("FirstTimeConnectionFromCountryObservedInTenant",FirstTimeConnectionFromCountryObservedInTenant,
                                        "BrowserUncommonlyUsedAmongPeers",BrowserUncommonlyUsedAmongPeers,
                                        "FirstTimeUserConnectedFromCountry",FirstTimeUserConnectedFromCountry,
                                        "AppIdUncommonlyAccessedInTenant",AppIdUncommonlyAccessedInTenant,
                                        "CountryUncommonlyConnectedFromInTenant",CountryUncommonlyConnectedFromInTenant,
                                        "ResourceUncommonlyAccessedAmongPeers",ResourceUncommonlyAccessedAmongPeers,
                                        "ResourceUncommonlyAccessedInTenant",ResourceUncommonlyAccessedInTenant,
                                        "BrowserUncommonlyUsedInTenant",BrowserUncommonlyUsedInTenant,
                                        "AppUncommonlyUsedAmongPeers",AppUncommonlyUsedAmongPeers,
                                        "ISPUncommonlyUsedAmongPeers",ISPUncommonlyUsedAmongPeers,
                                        "ISPUncommonlyUsedInTenant",ISPUncommonlyUsedInTenant)) by UserPrincipalName
| summarize make_bag(pack(tostring(UserPrincipalName),Insights))
)

"@


[PSCustomObject]$body = @{
"properties" = @{
    "Category" = "Function"
    "DisplayName" = "getUserInsights"
    "FunctionAlias" = "getUserInsights"
    "FunctionParameters" = ""
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


