$resourceGroupName = 'mo-tcdit17demo3'
$saName = 'mo3sqlsadr'
$scriptFile = '.\forceSqlDrSwitch.ps1'

Login-AzureRMAccount

$keys = Get-AzureRmStorageAccountKey -ResourceGroupName $resourceGroupName -Name $saName
$storageContext = New-AzureStorageContext -StorageAccountName $saName -StorageAccountKey $keys[0].Value

$container = New-AzureStorageContainer -Name 'script-container' -Context $storageContext
$UploadFile = @{
    Context = $StorageContext;
    Container = 'script-container';
    File = $scriptFile;
    }
Set-AzureStorageBlobContent @UploadFile;