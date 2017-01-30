-- Verificare topologia del cluster

-- Verificare parametri cluster

-- Analizzare Proprietà AG

-- Source: https://blogs.msdn.microsoft.com/alwaysonpro/2014/01/22/modifying-alwayson-read-only-routing-lists/

SELECT ag.name as "Availability Group", ar.replica_server_name as "When Primary Replica Is",
        rl.routing_priority as "Routing Priority", ar2.replica_server_name as "RO Routed To",

        ar.secondary_role_allow_connections_desc, ar2.read_only_routing_url
FROM sys.availability_read_only_routing_lists rl
        inner join sys.availability_replicas ar on rl.replica_id = ar.replica_id

        inner join sys.availability_replicas ar2 on rl.read_only_replica_id = ar2.replica_id

        inner join sys.availability_groups ag on ar.group_id = ag.group_id
ORDER BY ag.name, ar.replica_server_name, rl.routing_priority

-- Failover da dashboard