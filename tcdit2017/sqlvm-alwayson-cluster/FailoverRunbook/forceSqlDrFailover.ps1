Param(
[string]$drNodeName,
[string]$sqlInstance='MSSQLSERVER',
[string]$agName
)

import-module sqlps
import-module FailoverClusters

$timeout = New-Object System.TimeSpan -ArgumentList 0, 0, 60

#Force cluster start with single node online
Stop-ClusterNode –Name $drNodeName
Start-ClusterNode –Name $drNodeName -FixQuorum

$clusSvc = Get-Service -ComputerName $drNodeName -Name "clussvc"
$clusSvc.WaitForStatus("Running", $timeout)

#Fix node weight on DR node
(Get-ClusterNode $drNodeName).NodeWeight = 1

#Force AG failover with possible data loss
$SQLAvailabilityGroupPath = "SQLSERVER:\Sql\$($drNodeName)\$($sqlInstance)\AvailabilityGroups\$($agName)"
Switch-SqlAvailabilityGroup -Path $SQLAvailabilityGroupPath -AllowDataLoss -force


