
Param(
[string]$drNodeName,
[string]$sqlInstance='DEFAULT',
[string]$agName
)

import-module sqlps
import-module FailoverClusters

$timeout = New-Object System.TimeSpan -ArgumentList 0, 0, 120

#Force cluster start with single node online
Write-Output "Stopping cluster service on $($drNodeName)..."
$clusSvc = Get-Service -Name "Cluster Service" -ComputerName $drNodeName
Stop-Service -InputObject $clusSvc -ErrorAction SilentlyContinue
$clusSvc.WaitForStatus("Stopped", $timeout)
Write-Output "Cluster service stopped on $($drNodeName)."

Write-Output "Starting cluster service on $($drNodeName)..."
Start-ClusterNode -name $drNodeName -ForceQuorum

$clusSvc = Get-Service -Name "Cluster Service" -ComputerName $drNodeName
$clusSvc.WaitForStatus("Running", $timeout)

While((Get-ClusterNode $drNodeName).State -ne "Up") {
    Start-Sleep 30
    Write-Output "Waiting for cluster node to be online..."
}
Write-Output "Cluster node online."
Set-ClusterQuorum -NoWitness

#Fix node weight on DR node
$clNode = Get-ClusterNode $drNodeName
While($clNode.NodeWeight -ne 1)
{
    try {
        $clNode.NodeWeight = 1
    }
    catch { 
        Write-Output "Trying to change cluster node weight..."
    }
}
Write-Output "Cluster node weight changed."
Write-Output "Cluster service started with ForceQuorum on $($drNodeName)."

#Force AG failover with possible data loss
Write-Output "Forcing failover for $($agName) AVG..."
$SQLAvailabilityGroupPath = "SQLSERVER:\Sql\$($drNodeName)\$($sqlInstance)\AvailabilityGroups\$($agName)"
Switch-SqlAvailabilityGroup -Path $SQLAvailabilityGroupPath -AllowDataLoss -force
Write-Output "AVG online."
