
Param(
    [Parameter(Mandatory = $true)]
    [string]$resourceGroupName,
    [Parameter(Mandatory = $true)]
    [string]$apiConnectionName,
    [Parameter(Mandatory = $true)]
    [string]$servicebusConnectionName,
    [Parameter(Mandatory = $true)]
    [string]$logicappsrefdataName,
    [Parameter(Mandatory = $true)]
    [string]$logicappsprocessorName,
    [Parameter(Mandatory = $true)]
    [string]$appSettingsKey1,
    [Parameter(Mandatory = $true)]
    [string]$appSettingsKey2
)

# Fetch the API Connection runtime URL
Write-Host "Fetching API Connection Runtime URL for '$apiConnectionName'..."
$apiConnectionRuntimeUrl = az resource show `
    --resource-group $resourceGroupName `
    --name $apiConnectionName `
    --resource-type "Microsoft.Web/connections" `
    --query "properties.connectionRuntimeUrl" `
    -o tsv

Write-Host "Fetching Service Bus Connection Runtime URL for '$servicebusConnectionName'..."
$serviceBusConnectionRuntimeUrl = az resource show `
    --resource-group $resourceGroupName `
    --name $servicebusConnectionName `
    --resource-type "Microsoft.Web/connections" `
    --query "properties.connectionRuntimeUrl" `
    -o tsv

# Validate that both runtime URLs were fetched
if (-not $apiConnectionRuntimeUrl -or -not $serviceBusConnectionRuntimeUrl) {
    Write-Error "Error: One or both runtime URLs are missing."
    Write-Error "API Connection: $apiConnectionRuntimeUrl, Service Bus: $serviceBusConnectionRuntimeUrl"
    exit 1
}

# Write-Host "Fetched API Connection Runtime URL: $apiConnectionRuntimeUrl"
# Write-Host "Fetched Service Bus Connection Runtime URL: $serviceBusConnectionRuntimeUrl"

# Update App Settings in the App Services
Write-Host "Updating App Settings for Logic App: $logicappsrefdataName..."
az webapp config appsettings set --name $logicappsrefdataName --resource-group $resourceGroupName --settings "$appSettingsKey1=$apiConnectionRuntimeUrl"
az webapp config appsettings set --name $logicappsrefdataName --resource-group $resourceGroupName --settings "$appSettingsKey2=$serviceBusConnectionRuntimeUrl"

Write-Host "Updating App Settings for Logic App: $logicappsprocessorName..."
az webapp config appsettings set --name $logicappsprocessorName --resource-group $resourceGroupName --settings "$appSettingsKey1=$apiConnectionRuntimeUrl"
az webapp config appsettings set --name $logicappsprocessorName --resource-group $resourceGroupName --settings "$appSettingsKey2=$serviceBusConnectionRuntimeUrl"

# Verify if the App Settings update was successful
if ($LASTEXITCODE -eq 0) {
    Write-Host "Successfully updated App Settings with key '$appSettingsKey1' and '$appSettingsKey2' in Logic Apps."
} else {
    Write-Error "Error: Failed to update App Settings in Logic Apps."
    exit 1
}
