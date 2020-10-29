#Purpose: This will parse the WireData table into OSSEM schema
#Sample usage: WireDataParser() or WireDataParser("inbound") or WireDataParser("outbound")

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
WireData
| where Direction contains (NetworkDirection)
| extend EventType = "Traffic"
  , EventSchemaVersion="1.0.0"
  , EventCount=tolong(1) 
  , EventVendor = "Microsoft"
  , EventProduct = "WireData"
  , EventResult = "Success"
  , EventTimeIngested = ingestion_time()
  , EventOriginalUid = _ItemId
  , DstIpAddr =  iff(Direction == "Outbound", RemoteIP, LocalIP )
  , DstPortNumber =  iff(Direction == "Outbound", LocalPortNumber, RemotePortNumber)
  , SrcIpAddr = iff(Direction == "Outbound", LocalIP, RemoteIP  )
  , SrcPortNumber = iff(Direction == "Outbound", LocalPortNumber, RemotePortNumber )
  , SrcZone = iff(Direction == "Outbound", LocalSubnet, "")
  , DstZone = iff(Direction == "Inbound", LocalSubnet, "")
  , NetworkSessionId = tostring(SessionID)
  , EventSeverity = ""
| project-rename 
     DvcHostname = Computer, 
     EventEndTime = SessionEndTime, 
     EventStartTime = SessionStartTime, 
     EventResourceId = _ResourceId,
     NetworkApplicationProtocol =  ApplicationProtocol,
     SrcBytes = SentBytes,
     DstBytes = ReceivedBytes,
     NetworkBytes= TotalBytes,
     NetworkDirection =Direction,
     NetworkProtocol = ProtocolName,
     SrcPackets = SentPackets,
     DstPackets = ReceivedPackets

"@


[PSCustomObject]$body = @{
"properties" = @{
    "Category" = "Function"
    "DisplayName" = "WireDataParser"
    "FunctionAlias" = "WireDataParser"
    "FunctionParameters" = "NetworkDirection:string='bound'"
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


