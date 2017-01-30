#Check cluster node status
Get-ClusterNode | select Name, ID, State, NodeWeight

#Check quorum configuration
Get-ClusterQuorum

#Check listener configuration
Get-ClusterResource 'aglistener'|Get-ClusterParameter