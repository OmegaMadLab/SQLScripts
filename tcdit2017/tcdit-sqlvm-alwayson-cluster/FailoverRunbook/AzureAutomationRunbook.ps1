workflow ForceSqlDrFailover
{
    [OutputType([string])]

    param (
        [Object]$RecoveryPlanContext
    )

    #$VerbosePreference="Continue"

    if(!$RecoveryPlanContext)
    {
        $RecoveryPlanContext = inlineScript { 
            $obj = New-Object PSObject
            $obj | Add-Member -MemberType NoteProperty -Name "FailoverType" -Value "pfo/ufo"
            $obj
        }
        Write-Verbose "RecoveryPlanContext parameter object not present. A fake parameter object was created for demo purposes."
    }

    $connectionName = "AzureRunAsConnection"
    try
    {
        # Get the connection "AzureRunAsConnection "
        $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

        Write-Verbose "Logging in to Azure..."
        Add-AzureRmAccount `
            -ServicePrincipal `
            -TenantId $servicePrincipalConnection.TenantId `
            -ApplicationId $servicePrincipalConnection.ApplicationId `
            -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
    }
    catch {
        if (!$servicePrincipalConnection)
        {
            $ErrorMessage = "Connection $connectionName not found."
            throw $ErrorMessage
        } else{
            Write-Error -Message $_.Exception
            throw $_.Exception
        }
    }

    inLineScript {

        $resourceGroupName = 'tcdit17-sqlhademo'
        $saName = 'tcditsqlsadr'
        $scriptFile = 'forceSqlDrFailover.ps1'
        $sqlDrNode = 'tcdit-sql-dr0'
        $agName = 'alwayson-ag'

        Write-Verbose "Acquiring encryption keys for $($saName) Storage Account..."
        $saKey = (Get-AzureRmStorageAccountKey -ResourceGroupName $resourceGroupName -Name $saName).Key1
        Write-Verbose "Keys acquired."
      
        Write-Verbose "Creating storage context..."
        $storageContext = New-AzureStorageContext -StorageAccountName $saName -StorageAccountKey $saKey
        Write-Verbose "Storage context created."
     
        Write-Verbose "failovertype $($Using:RecoveryPlanContext.FailoverType)";
              
        if ($Using:RecoveryPlanContext.FailoverType -eq "Test")
        {
            Write-Verbose "tfo: Skipping SQL Failover";
        }
        else
        {
            Write-Verbose "pfo/ufo";
            
            $VM = Get-AzureRmVM -Name $sqlDrNode -ResourceGroupName $resourceGroupName;     
        
            $AGArgs="-drNodeName $($sqlDrNode) -agName $($agName)";

            Write-Verbose "Starting AG Failover to $($sqlDrNode)";  

            Set-AzureRmVMCustomScriptExtension -ResourceGroupName $resourceGroupName `
                                               -VMName $VM.name `
                                               -Location $VM.location `
                                               -Name "ForceSqlDrFailover" `
                                               -TypeHandlerVersion "1.1" `
                                               -StorageAccountName $saName `
                                               -StorageAccountKey $saKey `
                                               -FileName $scriptFile `
                                               -Run $scriptFile `
                                               -Argument $AGArgs `
                                               -ContainerName "script-container"
        
            Write-Verbose "Completed AG Failover";
        }    
    } 
}