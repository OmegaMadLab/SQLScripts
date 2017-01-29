$sqlAgent = 'SQLSERVERAGENT'
$sqlSrv = 'MSSQLSERVER'
$cluster = 'clusSvc'

$sqlNodes = @()
$sqlNodes += 'tcdit-sql-main0'
$sqlNodes += 'tcdit-sql-main1'

$fswServer = 'tcdit-fsw-main'
$fswShare = 'cluster-fsw'
$drNode = 'tcdit-sql-dr0'

$timeout = New-Object System.TimeSpan -ArgumentList 0, 0, 30

ForEach($srvName in $sqlNodes)
{

    write-host 'Starting SQL Server services on ' $srvName '...' -ForegroundColor Green
    Write-Host ''

    $AgentSvc = Get-Service -ComputerName $srvName  -name $sqlAgent| ?{$_.Status -eq 'Stopped'}
    if($AgentSvc) {
       Start-Service $AgentSvc
       $agentSvc.WaitForStatus("Running", $timeout)
       write-host $sqlAgent $AgentSvc.Status
    }

    Write-Host ''

    $SqlSvc = Get-Service -ComputerName $srvName  -name $sqlSrv| ?{$_.Status -eq 'Stopped'}
    if($SqlSvc) {
       Start-Service $SqlSvc
       $SqlSvc.WaitForStatus("Running", $timeout)
       write-host $sqlSrv $SqlSvc.Status
    }
    Write-Host ''
    write-host 'SQL Server services on ' $srvName ' started.' -ForegroundColor Green
    Write-Host ''

    Write-host 'Starting Cluster service on ' $srvName '...' -ForegroundColor Green
    Write-Host ''

    $clusSvc = Get-Service -ComputerName $srvName -name $cluster| ?{$_.Status -eq 'Stopped'}
    if($clusSvc) {
       Start-Service $clusSvc
       $clusSvc.WaitForStatus("Running", $timeout)
       write-host $clusSvc $clusSvc.Status
    }

    Write-Host ''
    write-host 'Cluster service on ' $srvName ' started.' -ForegroundColor Green
    Write-Host ''

}

invoke-command -Computername $fswServer -scriptBlock{Set-NetFirewallRule -DisplayGroup "File and Printer Sharing" -Enabled True}
Write-Host ''
write-host 'Firewall rules for Witness Share enabled on' $fswServer'.' -ForegroundColor Green
Write-Host ''

Write-Host 'Restoring cluster quorum configuration after failback...' -ForegroundColor Green
Write-Host ''
#Change cluster quorum configuration to node and file share majority
Set-ClusterQuorum -FileShareWitness "\\$($fswServer)\$($fswShare)"

#Remove vote from dr node to avoid unwanted failover due to remote site connectivity issues
(Get-ClusterNode -Name $drNode).NodeWeight = 0
Write-Host 'Cluster quorum configuration restored.' -ForegroundColor Green
Write-Host ''