$mainDatacenterSubnet = '10.0.0.0/16'
$drDatacenterSubnet = '172.16.0.0/16'

$mainADDC = 'mo3-addc-main'
$drADDC = 'mo3-addc-dr'

$ilbIpMainSubnet = '10.0.1.9'
$ilbIpDrSubnet = '172.16.1.9'

$primaryReplicaName = 'mo3-sql-main0'
$secondaryReplicaName = 'mo3-sql-main1'
$drReplicaName = 'mo3-sql-dr0'
$domainFqdn = 'tcdit17demo.local'

$clusterName = 'sqlhademo'
$fswPath = '\\mo3-fsw-main\cluster-fsw'
$mainClusterNetName = 'Main datacenter network'
$drClusterNetName = 'DR datacenter network'
$mainClusterIpName = 'Main datacenter cluster IP'
$drClusterIpName = 'DR datacenter cluster IP'

$sqlNodes = @()
$sqlNodes += $primaryReplicaName
$sqlNodes += $secondaryReplicaName
$sqlNodes += $drReplicaName

$sqlAgent = 'SQLSERVERAGENT'
$sqlSrv = 'MSSQLSERVER'
$backupShare = "F:\Backup"
$sqlSvcAcctn = "tcdit17demo\sjSqlAdmin"
$db = 'TCDIT17DEMO'
$ag = 'AlwaysOn-AG'
$agListener = 'aglistener'

Import-Module FailoverClusters
Import-Module ActiveDirectory
pushd
Import-Module sqlPs -DisableNameChecking
popd


if($primaryReplicaName -ne $env:computername) {
    Write-Host "Please execute this script on "$primaryReplica
    Return
}



#==========================================================================
#        Create AD Topology
#==========================================================================


#Rename default-first-site-name
pushd
cd 'ad:CN=Sites,CN=Configuration*'
ren cn=def* cn=MainDatacenter
popd

#Add subnet to main AD site
$mainADSite = Get-ADReplicationSite
New-ADReplicationSubnet -Name $mainDatacenterSubnet -Site $mainADSite -Server $mainADDC

#Add dr AD site with appropriate subnet
New-ADReplicationSite -Name 'DrDatacenter' -Server $mainADDC
$drADSite = Get-ADReplicationSite -Identity 'DrDatacenter' -Server $mainADDC
New-ADReplicationSubnet -Name $drDatacenterSubnet -Site $drADSite -Server $mainADDC

#Create new site link and remove the default one
New-ADReplicationSiteLink -Name Main2DR -Cost 100 -InterSiteTransportProtocol IP -ReplicationFrequencyInMinutes 15 -SitesIncluded $mainADSite,$drADSite
Get-ADReplicationSiteLink -Identity DEFAULTIPSITELINK | Remove-ADReplicationSiteLink -Confirm:$false

#Move DR ADDC to appropriate site
Move-ADDirectoryServer -Identity $drADDC -Site $drADSite

#Enable intersite Change Notification - Be carefull on production environment!
$siteLink = Get-ADReplicationSiteLink -Identity Main2DR
Get-adobject -Identity $siteLink.DistinguishedName -properties options | set-adobject –replace @{options=$($_.options –bor 1)} 

#Reduce DNS -> AD polling interval - Be carefull on production environment!
invoke-command -Computername $mainADDC, $drADDC -scriptBlock{set-DnsServerDsSetting -PollingInterval 30|Restart-Service -Force dns}

#==========================================================================
#        Create multisubnet WSFC
#==========================================================================

#Create multisubnet WSFC
New-Cluster -Name $clusterName -Node $sqlNodes
$cluster = Get-Cluster

$clusterGroup = $cluster | Get-ClusterGroup
$clusterNameRes = $clusterGroup | Get-ClusterResource "Cluster Name"
$clusterNameRes | Stop-ClusterResource | Out-Null

#Rename cluster networks and change IPs to Link Local IP addresses in order to avoid errors due to Azure DHCP, and bring cluster network name online
$clusterNetworks = Get-ClusterNetwork

ForEach($clusterNetwork in $clusterNetworks) {
   
    if($clusterNetwork.Address.contains($mainDatacenterSubnet.Substring(0,$mainDatacenterSubnet.IndexOf('.')))){
        $clusterNetwork.Name = $mainClusterNetName
    }
    else {
        $clusterNetwork.Name = $drClusterNetName
    }
}

$clusterIpAddrRes = $clusterGroup | Get-ClusterResource | Where-Object { $_.ResourceType.Name -eq "IP Address"}          

ForEach($clusterIpAddr in $clusterIpAddrRes) {
    
    $clusterIpAddr | Stop-ClusterResource | Out-Null
    
    if(($clusterIpAddr | Get-ClusterParameter -Name 'Network').Value -eq $mainClusterNetName) {
        $clusterIpAddr.Name = $mainClusterIpName
        $IpAddr = '169.254.1.10'
    }
    else {
        $clusterIpAddr.Name = $drClusterIpName
        $IpAddr = '169.254.10.10'
    }

    $clusterIpAddr | Set-ClusterParameter -Multiple @{
        "Address" = "$ipAddr"
        "SubnetMask" = "255.255.0.0"
        "EnableDhcp" = 0
        "OverrideAddressMatch" = 1
    } -ErrorAction Stop
}

Start-ClusterResource $clusterNameRes

#Change cluster quorum configuration to node and file share majority
Set-ClusterQuorum -FileShareWitness $fswPath

#Remove vote from dr node to avoid unwanted failover due to remote site connectivity issues
(Get-ClusterNode -Name $drReplica).NodeWeight = 0


#==========================================================================
#        Configure SQL AlwaysOn AG
#==========================================================================

#Enable TCP protocol and HADR feature on all instances
$smo = 'Microsoft.SqlServer.Management.Smo.'
$timeout = New-Object System.TimeSpan -ArgumentList 0, 0, 30
Add-Type -AssemblyName System.ServiceProcess

ForEach ($sqlNode in $sqlNodes) {
    $wmi = new-object ($smo + 'Wmi.ManagedComputer')$sqlNode
    $uri = "ManagedComputer[@Name='" + $sqlNode + "']/ ServerInstance[@Name='MSSQLSERVER']/ServerProtocol[@Name='Tcp']"
    $Tcp = $wmi.GetSmoObject($uri)
    $Tcp.IsEnabled = $true
    $Tcp.Alter()

    Enable-SqlAlwaysOn `
     -Path SQLSERVER:\SQL\$sqlNode\Default `
     -NoServiceRestart

    $sqlSvc = get-service -ComputerName $sqlNode -Name $sqlSrv
    if($sqlSvc.Status -eq "Running") {
        $sqlSvc.Stop()
    }
    $sqlSvc.WaitForStatus("Stopped", $timeout)
    $sqlSvc.Start()
    $sqlSvc.WaitForStatus("Running", $timeout)
}

#Create backup share
New-Item $backupShare -ItemType directory
net share backup=$backupShare "/grant:$sqlSvcAcctn,FULL"
icacls.exe "$backupShare" /grant:r ("$sqlSvcAcctn" + ":(OI)(CI)F")

#Create database on every instance
Invoke-SqlCmd -Query "CREATE database $db"
Backup-SqlDatabase -Database $db -BackupFile "$backupShare\$db.bak" -ServerInstance $primaryReplicaName
Backup-SqlDatabase -Database $db -BackupFile "$backupShare\$db.log" -ServerInstance $primaryReplicaName -BackupAction Log
Restore-SqlDatabase -Database $db -BackupFile "\\$primaryReplicaName\backup\$db.bak" -ServerInstance $secondaryReplicaName -NoRecovery
Restore-SqlDatabase -Database $db -BackupFile "\\$primaryReplicaName\backup\$db.log" -ServerInstance $secondaryReplicaName -RestoreAction Log -NoRecovery
Restore-SqlDatabase -Database $db -BackupFile "\\$primaryReplicaName\backup\$db.bak" -ServerInstance $drReplicaName -NoRecovery
Restore-SqlDatabase -Database $db -BackupFile "\\$primaryReplicaName\backup\$db.log" -ServerInstance $drReplicaName -RestoreAction Log -NoRecovery

#Mirroring endpoint creation
ForEach ($sqlNode in $sqlNodes) {
    $endpoint =
        New-SqlHadrEndpoint SqlHaEndpoint `
        -Port 5022 `
        -Path "SQLSERVER:\SQL\$sqlNode\Default"
    Set-SqlHadrEndpoint `
        -InputObject $endpoint `
        -State "Started"
    Invoke-SqlCmd -Query "CREATE LOGIN [$sqlSvcAcctn] FROM WINDOWS" -ServerInstance $sqlNode
    Invoke-SqlCmd -Query "GRANT CONNECT ON ENDPOINT::[SqlHaEndpoint] TO [$sqlSvcAcctn]" -ServerInstance $sqlNode
}

#Availability Replicas creation
$primaryReplica =
    New-SqlAvailabilityReplica `
    -Name $primaryReplicaName `
    -EndpointURL "TCP://$primaryReplicaName.$domainFqdn`:5022" `
    -AvailabilityMode "SynchronousCommit" `
    -FailoverMode "Automatic" `
    -Version 11 `
    -AsTemplate
$secondaryReplica =
    New-SqlAvailabilityReplica `
    -Name $secondaryReplicaName `
    -EndpointURL "TCP://$secondaryReplicaName.$domainFqdn`:5022" `
    -AvailabilityMode "SynchronousCommit" `
    -FailoverMode "Automatic" `
    -Version 11 `
    -AsTemplate
$drReplica =
    New-SqlAvailabilityReplica `
    -Name $drReplicaName `
    -EndpointURL "TCP://$drReplicaName.$domainFqdn`:5022" `
    -AvailabilityMode "AsynchronousCommit" `
    -FailoverMode "Manual" `
    -Version 11 `
    -AsTemplate

#AVG Creation
New-SqlAvailabilityGroup `
     -Name $ag `
     -Path "SQLSERVER:\SQL\$primaryReplicaName\Default" `
     -AvailabilityReplica @($primaryReplica,$secondaryReplica,$drReplica) `
     -Database $db
Join-SqlAvailabilityGroup `
    -Path "SQLSERVER:\SQL\$secondaryReplicaName\Default" `
    -Name $ag
Add-SqlAvailabilityDatabase `
    -Path "SQLSERVER:\SQL\$secondaryReplicaName\Default\AvailabilityGroups\$ag" `
    -Database $db
Join-SqlAvailabilityGroup `
    -Path "SQLSERVER:\SQL\$drReplicaName\Default" `
    -Name $ag
Add-SqlAvailabilityDatabase `
    -Path "SQLSERVER:\SQL\$drReplicaName\Default\AvailabilityGroups\$ag" `
    -Database $db

#ReadOnly Replicas and routing list
$primaryReplica = Get-Item "SQLSERVER:\SQL\$primaryReplicaName\Default\availabilityGroups\$ag\availabilityReplicas\$primaryReplicaName"
$secondaryReplica = Get-Item "SQLSERVER:\SQL\$primaryReplicaName\Default\availabilityGroups\$ag\availabilityReplicas\$secondaryReplicaName"
$drReplica = Get-Item "SQLSERVER:\SQL\$primaryReplicaName\Default\availabilityGroups\$ag\availabilityReplicas\$drReplicaName"

Set-SqlAvailabilityReplica -ConnectionModeInPrimaryRole "AllowAllConnections" -InputObject $primaryReplica
Set-SqlAvailabilityReplica -ConnectionModeInSecondaryRole "AllowReadIntentConnectionsOnly" -InputObject $primaryReplica
Set-SqlAvailabilityReplica -ReadOnlyRoutingConnectionUrl "TCP://$primaryReplicaName.$domainFqdn`:1433" -InputObject $primaryReplica

Set-SqlAvailabilityReplica -ConnectionModeInPrimaryRole "AllowAllConnections" -InputObject $secondaryReplica
Set-SqlAvailabilityReplica -ConnectionModeInSecondaryRole "AllowReadIntentConnectionsOnly" -InputObject $secondaryReplica
Set-SqlAvailabilityReplica -ReadOnlyRoutingConnectionUrl "TCP://$secondaryReplicaName.$domainFqdn`:1433" -InputObject $secondaryReplica

Set-SqlAvailabilityReplica -ConnectionModeInPrimaryRole "AllowAllConnections" -InputObject $drReplica
Set-SqlAvailabilityReplica -ConnectionModeInSecondaryRole "AllowReadIntentConnectionsOnly" -InputObject $drReplica
Set-SqlAvailabilityReplica -ReadOnlyRoutingConnectionUrl "TCP://$drReplicaName.$domainFqdn`:1433" -InputObject $drReplica

Set-SqlAvailabilityReplica -ReadOnlyRoutingList "$secondaryReplicaName","$drReplicaName","$primaryReplicaName" -InputObject $primaryReplica
Set-SqlAvailabilityReplica -ReadOnlyRoutingList "$primaryReplicaName","$drReplicaName","$secondaryReplicaName" -InputObject $secondaryReplica
Set-SqlAvailabilityReplica -ReadOnlyRoutingList "$primaryReplicaName","$secondaryReplicaName","$drReplicaName" -InputObject $drReplica


#==========================================================================
#        Configure SQL AlwaysOn AG Listener
#==========================================================================

#Client Access Point creation
$agClusterGroup = Get-ClusterGroup -Name $ag
#1. Add a network name named as the AG Listener
$cap = Add-ClusterResource -Name $agListener -ResourceType "Network Name" -Group $agClusterGroup
#2. Set paramters
$cap | Set-ClusterParameter -Multiple @{
    "DnsName" = "$agListener"
    "HostRecordTTL" = 30
    "RegisterAllProvidersIP" = 1
} -ErrorAction Stop
#3. Create two IP Addresses, assigning them the Azure ILB ip created on each vnet
$capIpMain = Add-ClusterResource -Name "ILB IP main datacenter" -ResourceType "IP Address" -Group $agClusterGroup
$capIpMain | Set-ClusterParameter -Multiple @{
        "Address" = "$ilbIpMainSubnet"
        "SubnetMask" = "255.255.255.255"
        "Network" = "$mainClusterNetName"
        "EnableDHCP" = 0
        "ProbePort" = "59999"
    } -ErrorAction Stop

$capIpDr = Add-ClusterResource -Name "ILB IP dr datacenter" -ResourceType "IP Address" -Group $agClusterGroup
$capIpDr | Set-ClusterParameter -Multiple @{
        "Address" = "$ilbIpDrSubnet"
        "SubnetMask" = "255.255.255.255"
        "Network" = "$drClusterNetName"
        "EnableDHCP" = 0
        "ProbePort" = "59999"
    } -ErrorAction Stop
#4. Add dependencies on IPs to Network Name
Set-ClusterResourceDependency -InputObject $cap -Dependency "[$capIpMain] or [$capIpDr]"
#5. Add AG resource dependency on CAP network name
$agResource = Get-ClusterResource -Name $ag 
$agResource | Stop-ClusterResource
Add-ClusterResourceDependency -InputObject $agResource -Resource $cap
$cap|Start-ClusterResource
$agResource | Start-ClusterResource
#6. Assign port 1433 to SQL AG Listener
Set-SqlAvailabilityGroupListener -Port 1433

