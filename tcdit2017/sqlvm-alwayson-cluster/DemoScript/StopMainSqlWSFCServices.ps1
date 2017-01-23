$sqlAgent = 'SQLSERVERAGENT'
$sqlSrv = 'MSSQLSERVER'
$cluster = 'clusSvc'

$sqlNodes = @()
$sqlNodes += 'mo3-sql-main0'
$sqlNodes += 'mo3-sql-main1'

$fswServer = 'mo3-fsw-main'

$timeout = New-Object System.TimeSpan -ArgumentList 0, 0, 30

ForEach($srvName in $sqlNodes)
{

    write-host 'Stopping SQL Server services on ' $srvName '...' -ForegroundColor Red
    Write-Host ''

    $AgentSvc = Get-Service -ComputerName $srvName  -name $sqlAgent| ?{$_.Status -eq 'running'}
    if($AgentSvc) {
       Stop-Service $AgentSvc
       $agentSvc.WaitForStatus("Stopped", $timeout)
       write-host $sqlAgent $AgentSvc.Status
    }

    Write-Host ''

    $SqlSvc = Get-Service -ComputerName $srvName  -name $sqlSrv| ?{$_.Status -eq 'running'}
    if($SqlSvc) {
       Stop-Service $SqlSvc
       $SqlSvc.WaitForStatus("Stopped", $timeout)
       write-host $sqlSrv $SqlSvc.Status
    }
    Write-Host ''
    write-host 'SQL Server services on ' $srvName ' stopped.' -ForegroundColor Red
    Write-Host ''

    Write-host 'Stopping Cluster service on ' $srvName '...' -ForegroundColor Red
    Write-Host ''

    $clusSvc = Get-Service -ComputerName $srvName -name $cluster| ?{$_.Status -eq 'running'}
    if($clusSvc) {
       Stop-Service $clusSvc
       $clusSvc.WaitForStatus("Stopped", $timeout)
       write-host $clusSvc $clusSvc.Status
    }

    Write-Host ''
    write-host 'Cluster service on ' $srvName ' stopped.' -ForegroundColor Red
    Write-Host ''

}

invoke-command -Computername $fswServer -scriptBlock{Set-NetFirewallRule -DisplayGroup "SMB Witness" -Enabled False}
Write-Host ''
write-host 'Firewall rules for SMB Witness disabled on' $fswServer'.' -ForegroundColor Red
Write-Host ''