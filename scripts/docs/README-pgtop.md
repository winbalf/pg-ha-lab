# pgtop.sh - PostgreSQL Real-time Monitoring Tool

This shell script provides a real-time monitoring dashboard for PostgreSQL replication environments. It continuously displays active queries, database sizes, and replication status for both primary and standby nodes in a top-like interface.

## Overview

The pgtop script is a lightweight monitoring tool that:
1. Displays active queries on primary and standby nodes
2. Shows database sizes across all databases
3. Monitors replication lag in bytes and seconds
4. Refreshes every 5 seconds with a clear, readable output
5. Runs continuously until interrupted (Ctrl+C)

## Line-by-Line Explanation

### Script Header

```bash
#!/bin/sh
```

- **`#!/bin/sh`**: Shebang tells the system to use `/bin/sh` (POSIX shell) to execute this script
  - **Why `/bin/sh`**: Lightweight and widely available, suitable for Alpine Linux containers
  - **Why needed**: Ensures the script runs with the correct interpreter

### Main Loop Structure

```bash
while true; do
```

- **`while true`**: Creates an infinite loop that runs continuously
  - **Why needed**: Provides real-time monitoring that updates periodically
  - **Exit condition**: User must press Ctrl+C to stop

### Clear Screen

```bash
  clear
```

- **`clear`**: Clears the terminal screen
  - **Why needed**: Provides a clean display for each refresh cycle, making it easier to read current status
  - **Effect**: Removes previous output so new data appears at the top

### Display Header

```bash
  echo '=== PostgreSQL Real-time Monitoring ==='
  echo "Time: $(date)"
  echo ''
```

- **`echo '=== PostgreSQL Real-time Monitoring ==='`**: Prints a header title
  - **Why needed**: Identifies what the monitoring tool is displaying
- **`echo "Time: $(date)"`**: Prints current timestamp
  - **`$(date)`**: Command substitution - executes `date` command and inserts its output
  - **Why needed**: Shows when the current snapshot was taken, useful for tracking changes over time
- **`echo ''`**: Prints an empty line
  - **Why needed**: Adds visual spacing between sections

### Primary Node Active Queries Section

```bash
  echo '=== Primary Node (Port 5432) ==='
  PGPASSWORD=${POSTGRES_PASSWORD} psql -h postgres-primary-lab -p 5432 -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "
```

- **`echo '=== Primary Node (Port 5432) ==='`**: Section header for primary node monitoring
  - **Why needed**: Clearly labels which node's data is being displayed
- **`PGPASSWORD=${POSTGRES_PASSWORD}`**: Sets password environment variable for psql
  - **`${POSTGRES_PASSWORD}`**: Uses environment variable (defaults to `secure_password_123` if not set)
  - **Why needed**: Avoids password prompts and allows non-interactive execution
- **`psql`**: PostgreSQL command-line client
- **`-h postgres-primary-lab`**: Connects to the primary server hostname
  - **Why needed**: Specifies which PostgreSQL instance to query
- **`-p 5432`**: Connects to port 5432 (default PostgreSQL port)
  - **Why needed**: Port where PostgreSQL is listening
- **`-U ${POSTGRES_USER}`**: Uses the specified database user
  - **`${POSTGRES_USER}`**: Environment variable (defaults to `postgres` if not set)
  - **Why needed**: Authenticates with the correct user account
- **`-d ${POSTGRES_DB}`**: Connects to the specified database
  - **`${POSTGRES_DB}`**: Environment variable (defaults to `testdb` if not set)
  - **Why needed**: Connects to the correct database context
- **`-c "..."`**: Executes SQL command directly (non-interactive mode)
  - **Why needed**: Allows scripted execution without entering psql interactive mode

### Primary Node Query - Active Connections

```sql
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
```

- **`SELECT pid`**: Process ID of the database connection
  - **Why needed**: Unique identifier for each connection, useful for debugging
- **`usename`**: Username of the connection
  - **Why needed**: Shows which user is running each query
- **`application_name`**: Application identifier (e.g., "psql", "pgAdmin")
  - **Why needed**: Identifies which application/client is making the connection
- **`client_addr`**: Client IP address
  - **Why needed**: Shows where connections are coming from (useful for security monitoring)
- **`state`**: Current state of the query (e.g., "active", "idle in transaction")
  - **Why needed**: Indicates what the connection is doing
- **`query_start`**: Timestamp when the query started
  - **Why needed**: Shows how long queries have been running
- **`state_change`**: Timestamp when the state last changed
  - **Why needed**: Tracks when connections transitioned to their current state
- **`LEFT(query, 50) as query_preview`**: First 50 characters of the SQL query
  - **`LEFT(query, 50)`**: String function that truncates query to 50 characters
  - **Why needed**: Shows a preview of what query is running without overwhelming the display
- **`FROM pg_stat_activity`**: PostgreSQL system view containing connection information
  - **Why needed**: This is the standard view for monitoring active database connections
- **`WHERE state != 'idle'`**: Filters out idle connections
  - **Why needed**: Only shows connections that are actively doing work, reducing noise
- **`ORDER BY query_start DESC`**: Sorts by query start time, newest first
  - **Why needed**: Shows the most recently started queries first
- **`LIMIT 10`**: Limits results to 10 rows
  - **Why needed**: Keeps output manageable and focused on most recent activity

### Error Handling for Primary Node

```bash
  " 2>/dev/null || echo 'Primary not available'
```

- **`"`**: Closes the SQL command string
- **`2>/dev/null`**: Redirects stderr (error messages) to /dev/null
  - **Why needed**: Suppresses connection error messages if the primary is unavailable
- **`|| echo 'Primary not available'`**: If psql fails, print a friendly message
  - **`||`**: Logical OR operator - executes right side if left side fails
  - **Why needed**: Provides user-friendly feedback when the primary node is down or unreachable

### Standby Node Active Queries Section

```bash
  echo ''
  echo '=== Standby Node (Port 5432) ==='
  PGPASSWORD=${POSTGRES_PASSWORD} psql -h postgres-standby-lab -p 5432 -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "
```

- **`echo ''`**: Empty line for spacing
  - **Why needed**: Visual separation between sections
- **`echo '=== Standby Node (Port 5432) ==='`**: Section header for standby node
  - **Why needed**: Labels the standby node's monitoring section
- **`-h postgres-standby-lab`**: Connects to the standby server hostname
  - **Why needed**: Queries the standby instance instead of primary
- **Note**: The SQL query is identical to the primary node query
  - **Why needed**: Provides consistent monitoring view across both nodes

### Standby Node Error Handling

```bash
  " 2>/dev/null || echo 'Standby not available'
```

- **Same pattern as primary**: Suppresses errors and shows friendly message if standby is unavailable
  - **Why needed**: Allows monitoring to continue even if one node is down

### Database Sizes Section

```bash
  echo ''
  echo '=== Database Sizes ==='
  PGPASSWORD=${POSTGRES_PASSWORD} psql -h postgres-primary-lab -p 5432 -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "
```

- **`echo '=== Database Sizes ==='`**: Section header for database size information
  - **Why needed**: Labels the database size monitoring section
- **`-h postgres-primary-lab`**: Queries primary node for database sizes
  - **Why needed**: Primary node has the authoritative database size information

### Database Sizes Query

```sql
    SELECT 
      datname,
      pg_size_pretty(pg_database_size(datname)) as size
    FROM pg_database 
    WHERE datname NOT IN ('template0', 'template1')
    ORDER BY pg_database_size(datname) DESC;
```

- **`SELECT datname`**: Database name
  - **Why needed**: Identifies which database the size refers to
- **`pg_size_pretty(pg_database_size(datname)) as size`**: Human-readable database size
  - **`pg_database_size(datname)`**: Returns database size in bytes
  - **`pg_size_pretty(...)`**: Converts bytes to human-readable format (e.g., "1.5 GB")
  - **Why needed**: Makes sizes easy to read and understand
- **`FROM pg_database`**: System catalog containing database information
  - **Why needed**: Source of database metadata
- **`WHERE datname NOT IN ('template0', 'template1')`**: Excludes template databases
  - **Why needed**: Template databases are system databases, not user data - filtering them reduces noise
- **`ORDER BY pg_database_size(datname) DESC`**: Sorts by size, largest first
  - **Why needed**: Shows largest databases first, making it easy to identify space usage

### Database Sizes Error Handling

```bash
  " 2>/dev/null || echo 'Database size info not available'
```

- **Same error handling pattern**: Shows friendly message if query fails
  - **Why needed**: Graceful degradation when primary is unavailable

### Replication Status Section

```bash
  echo ''
  echo '=== Replication Status ==='
  PGPASSWORD=${POSTGRES_PASSWORD} psql -h postgres-primary-lab -p 5432 -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "
```

- **`echo '=== Replication Status ==='`**: Section header for replication monitoring
  - **Why needed**: Labels the replication status section
- **`-h postgres-primary-lab`**: Queries primary node
  - **Why needed**: Primary node maintains replication status information in `pg_stat_replication`

### Replication Status Query

```sql
    SELECT 
      client_addr,
      application_name,
      state,
      pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)) as lag_bytes,
      EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) as lag_seconds
    FROM pg_stat_replication;
```

- **`SELECT client_addr`**: IP address of the standby server
  - **Why needed**: Identifies which standby is replicating
- **`application_name`**: Application identifier for the replication connection
  - **Why needed**: Shows how the standby identifies itself
- **`state`**: Current replication state (e.g., "streaming", "catchup")
  - **Why needed**: Indicates health of replication (should be "streaming" for healthy replication)
- **`pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)) as lag_bytes`**: Human-readable replication lag in bytes
  - **`pg_current_wal_lsn()`**: Current WAL position on primary
  - **`replay_lsn`**: Last WAL position applied on standby
  - **`pg_wal_lsn_diff(...)`**: Calculates byte difference between two LSN positions
  - **`pg_size_pretty(...)`**: Converts bytes to human-readable format (e.g., "256 KB")
  - **Why needed**: Shows how far behind the standby is in terms of data volume
- **`EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) as lag_seconds`**: Replication lag in seconds
  - **`pg_last_xact_replay_timestamp()`**: Timestamp of last transaction replayed on standby
  - **`now() - ...`**: Calculates time difference
  - **`EXTRACT(EPOCH FROM ...)`**: Converts time interval to seconds
  - **Why needed**: Shows how far behind the standby is in terms of time (critical for RPO/RTO metrics)
- **`FROM pg_stat_replication`**: System view containing replication connection information
  - **Why needed**: Standard PostgreSQL view for monitoring replication status

### Replication Status Error Handling

```bash
  " 2>/dev/null || echo 'Replication info not available'
```

- **Same error handling pattern**: Shows friendly message if replication query fails
  - **Why needed**: Handles cases where replication is not configured or primary is unavailable

### Refresh Message and Delay

```bash
  echo ''
  echo 'Refreshing in 5 seconds... (Press Ctrl+C to exit)'
  sleep 5
```

- **`echo ''`**: Empty line for spacing
  - **Why needed**: Visual separation before refresh message
- **`echo 'Refreshing in 5 seconds... (Press Ctrl+C to exit)'`**: User instruction message
  - **Why needed**: Informs user about refresh behavior and how to exit
- **`sleep 5`**: Pauses execution for 5 seconds
  - **Why needed**: Controls refresh rate - updates every 5 seconds to balance real-time monitoring with system load

### Loop Closure

```bash
done
```

- **`done`**: Closes the `while true` loop
  - **Why needed**: Completes the infinite loop structure, causing the script to repeat after the sleep

## Usage

The script is designed to run in a Docker container with:
- PostgreSQL client tools installed (`postgresql-client`)
- Environment variables set: `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`
- Network access to `postgres-primary-lab` and `postgres-standby-lab` hosts

## Environment Variables

- **`POSTGRES_USER`**: Database username (default: `postgres`)
- **`POSTGRES_PASSWORD`**: Database password (default: `secure_password_123`)
- **`POSTGRES_DB`**: Database name (default: `testdb`)

## Output Format

The script displays:
1. **Header**: Title and current timestamp
2. **Primary Node**: Top 10 active queries on primary
3. **Standby Node**: Top 10 active queries on standby
4. **Database Sizes**: All user databases sorted by size
5. **Replication Status**: Lag metrics and replication state

## Exit

Press `Ctrl+C` to stop the monitoring loop and exit the script.

