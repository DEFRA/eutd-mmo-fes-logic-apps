
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
    [string]$storageAccountName,
    [Parameter(Mandatory = $true)]
    [string]$storageAccountRGName, 

    [Parameter(Mandatory = $true)]
    [string]$common_appSettingsKey,
    [Parameter(Mandatory = $true)]
    [string]$servicebus_appSettingsKey,
    [Parameter(Mandatory = $true)]
    [string]$storage_appSettingsKey
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

# Fetch the storage account connection string
Write-Host "Fetching Storage Account Connection String for '$storageAccountName'..."
$connectionString = (az storage account keys list --resource-group $storageAccountRGName --account-name $storageAccountName --query "[0].value" -o tsv)

if (-not $connectionString) {
    Write-Error "Failed to fetch Storage Account Connection String for '$storageAccountName'."
    exit 1
}
$connectionStringFormatted = "DefaultEndpointsProtocol=https;AccountName=$storageAccountName;AccountKey=$connectionString;EndpointSuffix=core.windows.net"


# Validate that runtime URLs and storage connection string were fetched
if (-not $apiConnectionRuntimeUrl -or -not $serviceBusConnectionRuntimeUrl -or -not $connectionStringFormatted) {
    Write-Error "Error: One or more required values are missing."
    Write-Error "API Connection URL: $apiConnectionRuntimeUrl"
    Write-Error "Service Bus URL: $serviceBusConnectionRuntimeUrl"
    Write-Error "Storage Connection String: $connectionStringFormatted"
    exit 1
}

# Write-Host "Fetched API Connection Runtime URL: $apiConnectionRuntimeUrl"
# Write-Host "Fetched Service Bus Connection Runtime URL: $serviceBusConnectionRuntimeUrl"
# Write-Host "Storage Connection String: $connectionStringFormatted"

# Update App Settings in the App Services
Write-Host "Updating App Settings for Logic App: $logicappsrefdataName..."
az webapp config appsettings set --name $logicappsrefdataName --resource-group $resourceGroupName --settings "$common_appSettingsKey=$apiConnectionRuntimeUrl"
az webapp config appsettings set --name $logicappsrefdataName --resource-group $resourceGroupName --settings "$servicebus_appSettingsKey=$serviceBusConnectionRuntimeUrl"
az webapp config appsettings set --name $logicappsrefdataName --resource-group $resourceGroupName --settings "$storage_appSettingsKey=$connectionStringFormatted"

Write-Host "Updating App Settings for Logic App: $logicappsprocessorName..."
az webapp config appsettings set --name $logicappsprocessorName --resource-group $resourceGroupName --settings "$common_appSettingsKey=$apiConnectionRuntimeUrl"
az webapp config appsettings set --name $logicappsprocessorName --resource-group $resourceGroupName --settings "$servicebus_appSettingsKey=$serviceBusConnectionRuntimeUrl"
az webapp config appsettings set --name $logicappsprocessorName --resource-group $resourceGroupName --settings "$storage_appSettingsKey=$connectionStringFormatted"

# Verify if the App Settings update was successful
if ($LASTEXITCODE -eq 0) {
    Write-Host "Successfully updated App Settings with key '$common_appSettingsKey' and '$servicebus_appSettingsKey' and '$storage_appSettingsKey' in Logic Apps."
} else {
    Write-Error "Error: Failed to update App Settings in Logic Apps."
    exit 1
}
