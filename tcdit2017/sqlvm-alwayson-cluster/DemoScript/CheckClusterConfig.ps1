#Check cluster node status
Get-ClusterNode | select Name, ID, State, NodeWeight

#Check quorum configuration
Get-ClusterQuorum