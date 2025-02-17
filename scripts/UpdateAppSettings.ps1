
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
    [string]$storageAccountRGName
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
Write-Host "Fetching Storage Account Connection String for $storageAccountRGName '$storageAccountName'..."
$connectionString = (az storage account keys list --resource-group $storageAccountRGName --account-name $storageAccountName --query "[0].value" -o tsv)

if (-not $connectionString) {
    Write-Error "Failed to fetch Storage Account Connection String for '$storageAccountName'."
    exit 1
}
$connectionStringFormatted = "DefaultEndpointsProtocol=https;AccountName=$storageAccountName;AccountKey=$connectionString;EndpointSuffix=core.windows.net"

# Get the Table Primary Endpoint
$tablePrimaryUrl = (az storage account show --name $storageAccountName --resource-group $storageAccountRGName --query "primaryEndpoints.table" --output tsv)
$tablePrimaryUrl = $tablePrimaryUrl -replace "/$",""

# Validate that runtime URLs and storage connection string were fetched
if (-not $apiConnectionRuntimeUrl -or -not $serviceBusConnectionRuntimeUrl -or -not $connectionStringFormatted -or -not $tablePrimaryUrl) {
    Write-Error "Error: One or more required values are missing."
    Write-Error "API Connection URL: $apiConnectionRuntimeUrl"
    Write-Error "Service Bus URL: $serviceBusConnectionRuntimeUrl"
    Write-Error "Storage Connection String: $connectionStringFormatted"
    Write-Error "Storage Account Primary URL: $tablePrimaryUrl"
    exit 1
}

# Update App Settings in the App Services
Write-Host "Updating App Settings for Logic App: $logicappsrefdataName..."
az webapp config appsettings set --name $logicappsrefdataName --resource-group $resourceGroupName --settings "COMMON_API_CONNECTION_RUNTIME_URL=$apiConnectionRuntimeUrl"
az webapp config appsettings set --name $logicappsrefdataName --resource-group $resourceGroupName --settings "SERVICEBUS_CONNECTION_RUNTIME_URL=$serviceBusConnectionRuntimeUrl"
az webapp config appsettings set --name $logicappsrefdataName --resource-group $resourceGroupName --settings "AzureWebJobsStorage=$connectionStringFormatted"
az webapp config appsettings set --name $logicappsrefdataName --resource-group $resourceGroupName --settings "STORAGEACCOUNT_URL=$tablePrimaryUrl"

Write-Host "Updating App Settings for Logic App: $logicappsprocessorName..."
az webapp config appsettings set --name $logicappsprocessorName --resource-group $resourceGroupName --settings "COMMON_API_CONNECTION_RUNTIME_URL=$apiConnectionRuntimeUrl"
az webapp config appsettings set --name $logicappsprocessorName --resource-group $resourceGroupName --settings "SERVICEBUS_CONNECTION_RUNTIME_URL=$serviceBusConnectionRuntimeUrl"
az webapp config appsettings set --name $logicappsprocessorName --resource-group $resourceGroupName --settings "AzureWebJobsStorage=$connectionStringFormatted"
az webapp config appsettings set --name $logicappsprocessorName --resource-group $resourceGroupName --settings "STORAGEACCOUNT_URL=$tablePrimaryUrl"

# Verify if the App Settings update was successful
if ($LASTEXITCODE -eq 0) {
    Write-Host "Successfully updated App Settings with key 'COMMON_API_CONNECTION_RUNTIME_URL', 'SERVICEBUS_CONNECTION_RUNTIME_URL', 'STORAGEACCOUNT_URL' and 'AzureWebJobsStorage' in Logic Apps."
} else {
    Write-Error "Error: Failed to update App Settings in Logic Apps."
    exit 1
}
