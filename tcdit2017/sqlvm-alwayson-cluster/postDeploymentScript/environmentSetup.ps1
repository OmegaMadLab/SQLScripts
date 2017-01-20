$mainDatacenterSubnet = '10.0.0.0/16'
$drDatacenterSubnet = '172.16.0.0/16'

$primaryReplica = 'mo3-sql-main0'
$secondaryReplica = 'mo3-sql-main1'
$drReplica = 'mo3-sql-dr0'

$clusterName = 'sqlhademo'
$fswPath = '\\mo3-fsw-main\cluster-fsw'

$sqlNodes = @()
$sqlNodes += $primaryReplica
$sqlNodes += $secondaryReplica
$sqlNodes += $drReplica

$sqlAgent = 'SQLSERVERAGENT'
$sqlSrv = 'MSSQLSERVER'

Import-Module FailoverClusters
Import-Module ActiveDirectory
pushd
Import-Module sqlPs -DisableNameChecking
popd


#==========================================================================
#        Create AD Topology
#==========================================================================


#Rename default-first-site-name
pushd
cd 'ad:CN=Sites,CN=Configuration*'
ren cn=def* cn=MainDatacenter
popd

#Add subnet to main AD site
$ADDC = Get-ADDomainController

$mainADSite = Get-ADReplicationSite
New-ADReplicationSubnet -Name $mainDatacenterSubnet -Site $mainADSite -Server $ADDC

#Add dr AD site with appropriate subnet
New-ADReplicationSite -Name 'DrDatacenter' -Server $ADDC
$drADSite = Get-ADReplicationSite -Identity 'DrDatacenter' -Server $ADDC
New-ADReplicationSubnet -Name $drDatacenterSubnet -Site $drADSite -Server $ADDC

#Create new site link and remove the default one
New-ADReplicationSiteLink -Name Main2DR -Cost 100 -InterSiteTransportProtocol IP -ReplicationFrequencyInMinutes 15 -SitesIncluded $mainADSite,$drADSite
Get-ADReplicationSiteLink -Identity DEFAULTIPSITELINK | Remove-ADReplicationSiteLink -Confirm:$false


#==========================================================================
#        Create multisubnet WSFC
#==========================================================================

#Create multisubnet WSFC
New-Cluster -Name $clusterName -Node $primaryReplica,$secondaryReplica,$drReplica -NoStorage
$cluster = Get-Cluster

#Change both IPs to Link Local IP addresses in order to avoid errors due to Azure DHCP, and bring cluster network name online
$clusterGroup = $cluster | Get-ClusterGroup
$clusterNameRes = $clusterGroup | Get-ClusterResource "Cluster Name"
$clusterNameRes | Stop-ClusterResource | Out-Null

$clusterIpAddrRes = $clusterGroup | Get-ClusterResource | Where-Object { $_.ResourceType.Name -eq "IP Address"}
          
$clusterIpAddrRes[0] | Stop-ClusterResource | Out-Null
$clusterIpAddrRes[0].Name = 'Cluster IP 1'
$clusterIpAddrRes[0] | Set-ClusterParameter -Multiple @{
    "Address" = "169.254.1.10"
    "SubnetMask" = "255.255.0.0"
    "EnableDhcp" = 0
    "OverrideAddressMatch" = 1
} -ErrorAction Stop

$clusterIpAddrRes[1] | Stop-ClusterResource | Out-Null
$clusterIpAddrRes[1].Name = 'Cluster IP 2'
$clusterIpAddrRes[1] | Set-ClusterParameter -Multiple @{
    "Address" = "169.254.10.10"
    "SubnetMask" = "255.255.0.0"
    "EnableDhcp" = 0
    "OverrideAddressMatch" = 1
} -ErrorAction Stop

Start-ClusterResource $clusterNameRes

#Change cluster quorum configuration to node and file share majority
Set-ClusterQuorum -FileShareWitness $fswPath

#Remove vote from dr node to avoid unwanted failover due to remote site connectivity issues
(Get-ClusterNode -Name $drReplica).NodeWeight = 0


#==========================================================================
#        Configure SQL AlwaysOn AG
#==========================================================================

#Enable TCP protocol on all instances
$smo = 'Microsoft.SqlServer.Management.Smo.'

ForEach ($sqlNode in $sqlNodes) {
    $wmi = new-object ($smo + 'Wmi.ManagedComputer')$sqlNode
    $uri = "ManagedComputer[@Name='" + $sqlNode + "']/ ServerInstance[@Name='MSSQLSERVER']/ServerProtocol[@Name='Tcp']"
    $Tcp = $wmi.GetSmoObject($uri)
    $Tcp.IsEnabled = $true
    $Tcp.Alter()
    $sqlsvc = $wmi.Services[$sqlSrv]
    $sqlsvc.stop()
    sleep 5
    $sqlsvc.refresh()
    $sqlsvc.start()
    $sqlsvc.refresh()
}
