$resourceGroupName = 'mo-tcdit17demo3'
$saName = 'mo3sqlsadr'
$scriptFile = '.\forceSqlDrFailover.ps1'

Add-AzureRmAccount

$keys = Get-AzureRmStorageAccountKey -ResourceGroupName $resourceGroupName -Name $saName
$storageContext = New-AzureStorageContext -StorageAccountName $saName -StorageAccountKey $keys[0].Value

$container = Get-AzureStorageContainer -Name 'script-container' -Context $storageContext
if(!$container) {
    $container = New-AzureStorageContainer -Name 'script-container' -Context $storageContext
}

$UploadFile = @{
    Context = $StorageContext;
    Container = $container.Name;
    File = $scriptFile;
    }
Set-AzureStorageBlobContent @UploadFile;