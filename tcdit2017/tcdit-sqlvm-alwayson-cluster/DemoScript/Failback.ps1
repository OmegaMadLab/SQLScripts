$node01 = "tcdit-sql-main0"
$node02 = "tcdit-sql-main1"
$nodeDR = "tcdit-sql-dr0"
$SqlInstance = "DEFAULT"
$AGResource = "alwayson-ag"
$Database = "TCDIT17DEMO"

$path01 = "SQLSERVER:\Sql\$($node01)\$($SqlInstance)\AvailabilityGroups\$($AGResource)"
$path02 = "SQLSERVER:\Sql\$($node02)\$($SqlInstance)\AvailabilityGroups\$($AGResource)"

$dbPath01 = "$($path01)\AvailabilityDatabases\$($Database)"
$dbPath02 = "$($path02)\AvailabilityDatabases\$($Database)"

$Repl01fromDRpath = "SQLSERVER:\Sql\$($nodeDR)\$($SqlInstance)\AvailabilityGroups\$($AGResource)\AvailabilityReplicas\$($node01)"
$Repl02fromDRpath = "SQLSERVER:\Sql\$($nodeDR)\$($SqlInstance)\AvailabilityGroups\$($AGResource)\AvailabilityReplicas\$($node02)"
$ReplDRfromDRpath = "SQLSERVER:\Sql\$($nodeDR)\$($SqlInstance)\AvailabilityGroups\$($AGResource)\AvailabilityReplicas\$($nodeDR)"

$Repl02from01path = "SQLSERVER:\Sql\$($node01)\$($SqlInstance)\AvailabilityGroups\$($AGResource)\AvailabilityReplicas\$($node02)"
$ReplDRfrom01path = "SQLSERVER:\Sql\$($node01)\$($SqlInstance)\AvailabilityGroups\$($AGResource)\AvailabilityReplicas\$($nodeDR)"


Write-host "Resuming databases on secondary replicas..." -ForegroundColor Green
Resume-SqlAvailabilityDatabase -Path $dbPath01 
Write-host "Database resumed on $($node01)."  -ForegroundColor Green
Write-host ""
Write-host "Resuming database on $($node02)..." -ForegroundColor Green
Resume-SqlAvailabilityDatabase -Path $dbPath02 
Write-host "Database resumed on $($node02)." -ForegroundColor Green
Write-host ""
Write-host "Changing replicas configuration to synchronize primary datacenter with secondary datacenter" -ForegroundColor Green
Set-SqlAvailabilityReplica -AvailabilityMode "AsynchronousCommit" -FailoverMode "Manual" -Path $Repl02fromDRpath
Write-host ""
Write-host "$($node02) replica configuration changed to async with manual failover." -ForegroundColor Green
Write-host ""
Set-SqlAvailabilityReplica -AvailabilityMode "SynchronousCommit" -FailoverMode "Automatic" -Path $Repl01fromDRpath
Write-host ""
Write-host "$($node01) replica configuration changed to sync with automatic failover." -ForegroundColor Green
Write-host ""
Set-SqlAvailabilityReplica -AvailabilityMode "SynchronousCommit" -FailoverMode "Manual" -Path $ReplDRfromDRpath
Write-host ""
Write-host "$($nodeDR) replica configuration changed to sync with manual failover." -ForegroundColor Green
Write-host ""
Write-Host "Failing back to on-premises server $($node01)..." -ForegroundColor Green
Switch-SqlAvailabilityGroup -Path $path01
Write-host ""
Write-host "Failback completed." -ForegroundColor Green

Write-host ""
Write-host "Restore original replicas configuration" -ForegroundColor Green
Set-SqlAvailabilityReplica -AvailabilityMode "SynchronousCommit" -FailoverMode "Automatic" -Path $Repl02from01path
Write-host ""
Write-host "$($node02) replica configuration changed to sync with automatic failover." -ForegroundColor Green
Write-host ""
Set-SqlAvailabilityReplica -AvailabilityMode "AsynchronousCommit" -FailoverMode "Manual" -Path $ReplDRfrom01path
Write-host ""
Write-host "$($nodeDR) replica configuration changed to async with manual failover." -ForegroundColor Green


