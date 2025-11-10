#!/bin/sh
while true; do
  clear
  echo '=== PostgreSQL Real-time Monitoring ==='
  echo "Time: $(date)"
  echo ''
  
  echo '=== Primary Node (Port 5432) ==='
  PGPASSWORD=${POSTGRES_PASSWORD} psql -h postgres-primary-lab -p 5432 -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "
    SELECT 
      pid,
      usename,
      application_name,
      client_addr,
      state,
      query_start,
      state_change,
      LEFT(query, 50) as query_preview
    FROM pg_stat_activity 
    WHERE state != 'idle' 
    ORDER BY query_start DESC 
    LIMIT 10;
  " 2>/dev/null || echo 'Primary not available'
  
  echo ''
  echo '=== Standby Node (Port 5432) ==='
  PGPASSWORD=${POSTGRES_PASSWORD} psql -h postgres-standby-lab -p 5432 -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "
    SELECT 
      pid,
      usename,
      application_name,
      client_addr,
      state,
      query_start,
      state_change,
      LEFT(query, 50) as query_preview
    FROM pg_stat_activity 
    WHERE state != 'idle' 
    ORDER BY query_start DESC 
    LIMIT 10;
  " 2>/dev/null || echo 'Standby not available'
  
  echo ''
  echo '=== Database Sizes ==='
  PGPASSWORD=${POSTGRES_PASSWORD} psql -h postgres-primary-lab -p 5432 -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "
    SELECT 
      datname,
      pg_size_pretty(pg_database_size(datname)) as size
    FROM pg_database 
    WHERE datname NOT IN ('template0', 'template1')
    ORDER BY pg_database_size(datname) DESC;
  " 2>/dev/null || echo 'Database size info not available'
  
  echo ''
  echo '=== Replication Status ==='
  PGPASSWORD=${POSTGRES_PASSWORD} psql -h postgres-primary-lab -p 5432 -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "
    SELECT 
      client_addr,
      application_name,
      state,
      pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)) as lag_bytes,
      EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) as lag_seconds
    FROM pg_stat_replication;
  " 2>/dev/null || echo 'Replication info not available'
  
  echo ''
  echo 'Refreshing in 5 seconds... (Press Ctrl+C to exit)'
  sleep 5
done
