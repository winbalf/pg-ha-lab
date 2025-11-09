# pg-replication-exporter.py - PostgreSQL Replication Metrics Exporter

This Python script collects comprehensive replication metrics from PostgreSQL primary and standby instances and exposes them in Prometheus format via HTTP. It provides real-time monitoring of replication lag, connection status, WAL activity, replication slots, and overall health scores.

## Overview

The exporter is a Prometheus-compatible metrics exporter that:
1. Connects to both primary and standby PostgreSQL instances
2. Collects replication lag (bytes, seconds, megabytes)
3. Monitors replication connections and sync states
4. Tracks WAL senders/receivers and generation rates
5. Monitors replication slots (active/inactive counts)
6. Calculates health scores based on multiple factors
7. Performs cross-instance data consistency checks
8. Exposes all metrics via HTTP endpoint on port 9188

## Line-by-Line Explanation

### Script Header and Imports

```python
#!/usr/bin/env python3
```

- **`#!/usr/bin/env python3`**: Shebang line that tells the system to use Python 3 interpreter
  - **`/usr/bin/env`**: Finds Python 3 in the system PATH (more portable than hardcoding `/usr/bin/python3`)
  - **Why needed**: Allows the script to be executed directly (`./pg-replication-exporter.py`) without explicitly calling `python3`

```python
"""
Custom PostgreSQL Replication Metrics Exporter
Provides additional replication-specific metrics for Prometheus
"""
```

- **Docstring**: Describes the purpose of the script
  - **Why needed**: Documentation for developers and users

```python
import os
import sys
import time
import psycopg2
import psycopg2.extras
from prometheus_client import start_http_server, Gauge, Counter, Histogram
import logging
```

- **`import os`**: Operating system interface - used to read environment variables
  - **Why needed**: Reads database connection parameters from environment variables
- **`import sys`**: System-specific parameters and functions
  - **Why needed**: System utilities (though not heavily used in this script)
- **`import time`**: Time-related functions
  - **Why needed**: `time.sleep()` for the metrics collection loop interval
- **`import psycopg2`**: PostgreSQL adapter for Python
  - **Why needed**: Connects to PostgreSQL databases and executes SQL queries
- **`import psycopg2.extras`**: Additional utilities for psycopg2
  - **Why needed**:**: Extended functionality (though not explicitly used, good practice to import
- **`from prometheus_client import start_http_server, Gauge, Counter, Histogram`**: Prometheus client library
  - **`start_http_server`**: Starts HTTP server to expose metrics
  - **`Gauge`**: Metric type that can go up or down (used for lag, counts, scores)
  - **`Counter`**: Metric type that only increases (imported but not used in this script)
  - **`Histogram`**: Metric type for distributions (imported but not used in this script)
  - **Why needed**: Provides the framework for exposing metrics in Prometheus format
- **`import logging`**: Python logging module
  - **Why needed**: Logs errors, debug info, and status messages

### Logging Configuration

```python
# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)
```

- **`logging.basicConfig(level=logging.INFO)`**: Configures root logger
  - **`level=logging.INFO`**: Sets log level to INFO (shows INFO, WARNING, ERROR, CRITICAL messages, but not DEBUG)
  - **Why needed**: Provides visibility into exporter operation without being too verbose
- **`logger = logging.getLogger(__name__)`**: Creates a logger instance for this module
  - **`__name__`**: Module name (useful when script is imported as a module)
  - **Why needed**: Allows logging with context (module name appears in log messages)

### Prometheus Metrics Definitions

```python
# Prometheus metrics
pg_replication_lag_bytes = Gauge('pg_replication_lag_bytes', 'Replication lag in bytes', ['instance'])
```

- **`pg_replication_lag_bytes`**: Metric name in Prometheus
- **`Gauge`**: Metric type - value can increase or decrease
- **`'pg_replication_lag_bytes'`**: Metric name (appears in Prometheus as `pg_replication_lag_bytes`)
- **`'Replication lag in bytes'`**: Help text describing the metric (shown in Prometheus UI)
- **`['instance']`**: Label dimension - allows multiple values (e.g., `pg_replication_lag_bytes{instance="primary"}` and `pg_replication_lag_bytes{instance="standby"}`)
- **Why needed**: Exposes replication lag in bytes with instance label for filtering/grouping

```python
pg_replication_lag_seconds = Gauge('pg_replication_lag_seconds', 'Replication lag in seconds', ['instance'])
```

- **Similar to above**: Exposes replication lag in time units (seconds)
- **Why needed**: Time-based lag is often more intuitive than byte-based lag for monitoring

```python
pg_replication_lag_mb = Gauge('pg_replication_lag_mb', 'Replication lag in megabytes', ['instance'])
```

- **Exposes lag in megabytes**: Human-readable format (bytes / 1024 / 1024)
- **Why needed**: Easier to understand than raw bytes (e.g., "10 MB" vs "10485760 bytes")

```python
pg_replication_connections = Gauge('pg_replication_connections', 'Number of replication connections', ['instance'])
```

- **Counts replication connections**: Number of active replication connections from primary's perspective
- **Why needed**: Indicates if standby is connected (should be > 0 for healthy replication)

```python
pg_replication_sync_state = Gauge('pg_replication_sync_state', 'Replication sync state (0=async, 1=sync)', ['instance', 'client_addr'])
```

- **Sync state metric**: Indicates if replication is synchronous (1) or asynchronous (0)
- **`['instance', 'client_addr']`**: Two labels - instance and client IP address
- **Why needed**: Monitors synchronous replication status (critical for zero data loss configurations)

```python
pg_wal_senders = Gauge('pg_wal_senders', 'Number of WAL senders', ['instance'])
```

- **WAL senders count**: Number of processes sending WAL data from primary
- **Why needed**: Should match number of connected standby servers

```python
pg_wal_receivers = Gauge('pg_wal_receivers', 'Number of WAL receivers', ['instance'])
```

- **WAL receivers count**: Number of processes receiving WAL data on standby
- **Why needed**: Should be 1 if standby is actively replicating

```python
pg_wal_generation_rate = Gauge('pg_wal_generation_rate', 'WAL generation rate in bytes per second', ['instance'])
```

- **WAL generation metric**: Tracks total WAL bytes generated (simplified implementation)
- **Why needed**: Monitors write activity and WAL volume

```python
pg_replication_slots_total = Gauge('pg_replication_slots_total', 'Total number of replication slots', ['instance'])
pg_replication_slots_active = Gauge('pg_replication_slots_active', 'Number of active replication slots', ['instance'])
pg_replication_slots_inactive = Gauge('pg_replication_slots_inactive', 'Number of inactive replication slots', ['instance'])
```

- **Replication slot metrics**: Track replication slot counts
  - **Total**: All slots (active + inactive)
  - **Active**: Slots currently in use by replication connections
  - **Inactive**: Slots defined but not currently used
- **Why needed**: Replication slots prevent WAL deletion - monitoring ensures slots are configured correctly

```python
pg_replication_health_score = Gauge('pg_replication_health_score', 'Overall replication health score (0-100)', ['instance'])
```

- **Health score**: Composite metric representing overall replication health (0-100 scale)
- **Why needed**: Single metric for alerting - low score indicates replication problems

```python
pg_data_consistency_check = Gauge('pg_data_consistency_check', 'Data consistency check result (1=consistent, 0=inconsistent)', ['instance'])
```

- **Consistency check**: Compares record counts between primary and standby
- **Why needed**: Detects data divergence issues (though simple count check has limitations)

### Database Connection Configuration

```python
# Database connection configuration
DB_CONFIG = {
    'primary': {
        'host': os.getenv('PRIMARY_HOST', 'localhost'),
        'port': os.getenv('PRIMARY_PORT', '5432'),
        'database': os.getenv('POSTGRES_DB', 'testdb'),
        'user': os.getenv('POSTGRES_USER', 'postgres'),
        'password': os.getenv('POSTGRES_PASSWORD', 'secure_password_123')
    },
    'standby': {
        'host': os.getenv('STANDBY_HOST', 'localhost'),
        'port': os.getenv('STANDBY_PORT', '5433'),
        'database': os.getenv('POSTGRES_DB', 'testdb'),
        'user': os.getenv('POSTGRES_USER', 'postgres'),
        'password': os.getenv('POSTGRES_PASSWORD', 'secure_password_123')
    }
}
```

- **`DB_CONFIG`**: Dictionary containing connection parameters for both instances
- **`os.getenv('PRIMARY_HOST', 'localhost')`**: Reads environment variable `PRIMARY_HOST`, defaults to `'localhost'` if not set
  - **Why needed**: Allows configuration via environment variables (Docker, Kubernetes, etc.) without code changes
- **Primary configuration**: Connection details for primary PostgreSQL instance
- **Standby configuration**: Connection details for standby PostgreSQL instance (default port 5433)
- **Why needed**: Centralized configuration makes it easy to change connection parameters

### Database Connection Function

```python
def get_db_connection(instance):
    """Get database connection for specified instance"""
    config = DB_CONFIG[instance]
    try:
        conn = psycopg2.connect(
            host=config['host'],
            port=config['port'],
            database=config['database'],
            user=config['user'],
            password=config['password']
        )
        return conn
    except psycopg2.Error as e:
        logger.error(f"Failed to connect to {instance}: {e}")
        return None
```

- **`def get_db_connection(instance)`**: Function to create database connection
  - **`instance`**: String parameter - either `'primary'` or `'standby'`
- **`config = DB_CONFIG[instance]`**: Gets connection config for the specified instance
- **`psycopg2.connect(...)`**: Creates PostgreSQL connection using psycopg2
  - **Connection parameters**: host, port, database, user, password from config
- **`try/except psycopg2.Error`**: Error handling for connection failures
  - **Why needed**: Network issues, wrong credentials, or database down will raise exceptions
- **`logger.error(...)`**: Logs connection errors
- **`return None`**: Returns None on failure (caller must check for None)
- **Why needed**: Reusable function to connect to either primary or standby

### Replication Lag Metrics Function

```python
def get_replication_lag_metrics(instance, conn):
    """Get replication lag metrics"""
    try:
        cursor = conn.cursor()
        
        if instance == 'primary':
            # Get lag from primary perspective
            cursor.execute("""
                SELECT 
                    COALESCE(
                        pg_wal_lsn_diff(
                            pg_current_wal_lsn(),
                            MIN(replay_lsn)
                        ), 0
                    ) as lag_bytes,
                    COALESCE(
                        EXTRACT(EPOCH FROM (
                            now() - MIN(pg_last_xact_replay_timestamp())
                        )), 0
                    ) as lag_seconds
                FROM pg_stat_replication;
            """)
```

- **`def get_replication_lag_metrics(instance, conn)`**: Function to collect lag metrics
  - **`instance`**: 'primary' or 'standby'
  - **`conn`**: Active database connection
- **`cursor = conn.cursor()`**: Creates cursor for executing SQL queries
- **`if instance == 'primary'`**: Different SQL queries for primary vs standby
- **Primary query explanation**:
  - **`pg_current_wal_lsn()`**: Current WAL position on primary (latest write)
  - **`MIN(replay_lsn)`**: Most advanced replay position among all standbys
  - **`pg_wal_lsn_diff(...)`**: Calculates byte difference between two LSN positions
  - **`COALESCE(..., 0)`**: Returns 0 if result is NULL (no replication connections)
  - **`EXTRACT(EPOCH FROM ...)`**: Converts time difference to seconds
  - **`pg_last_xact_replay_timestamp()`**: Timestamp of last replayed transaction on standby
  - **`MIN(...)`**: Most recent replay time among all standbys
  - **Why needed**: Primary-side lag shows how far behind the slowest standby is

```python
        else:
            # Get lag from standby perspective
            cursor.execute("""
                SELECT 
                    COALESCE(
                        pg_wal_lsn_diff(
                            pg_last_wal_receive_lsn(),
                            pg_last_wal_replay_lsn()
                        ), 0
                    ) as lag_bytes,
                    COALESCE(
                        EXTRACT(EPOCH FROM (
                            now() - pg_last_xact_replay_timestamp()
                        )), 0
                    ) as lag_seconds;
            """)
```

- **Standby query explanation**:
  - **`pg_last_wal_receive_lsn()`**: Last WAL position received from primary
  - **`pg_last_wal_replay_lsn()`**: Last WAL position replayed (applied to database)
  - **Difference**: Shows how much WAL is received but not yet applied
  - **`pg_last_xact_replay_timestamp()`**: Timestamp of last replayed transaction
  - **Why needed**: Standby-side lag shows internal processing delay (receive vs replay)

```python
        result = cursor.fetchone()
        if result:
            lag_bytes, lag_seconds = result
            lag_mb = lag_bytes / (1024 * 1024)
            
            pg_replication_lag_bytes.labels(instance=instance).set(lag_bytes)
            pg_replication_lag_seconds.labels(instance=instance).set(lag_seconds)
            pg_replication_lag_mb.labels(instance=instance).set(lag_mb)
            
            logger.debug(f"{instance} replication lag: {lag_bytes} bytes, {lag_seconds} seconds")
        
        cursor.close()
        
    except psycopg2.Error as e:
        logger.error(f"Failed to get replication lag metrics for {instance}: {e}")
```

- **`cursor.fetchone()`**: Retrieves one row from query result
- **`lag_bytes, lag_seconds = result`**: Unpacks tuple into variables
- **`lag_mb = lag_bytes / (1024 * 1024)`**: Converts bytes to megabytes
- **`.labels(instance=instance).set(value)`**: Sets Prometheus metric value with instance label
  - **Why needed**: Labels allow filtering by instance in Prometheus queries
- **`logger.debug(...)`**: Logs lag values (only shown if log level is DEBUG)
- **`cursor.close()`**: Closes cursor to free resources
- **Error handling**: Logs errors if query fails

### Replication Connection Metrics Function

```python
def get_replication_connection_metrics(instance, conn):
    """Get replication connection metrics"""
    try:
        cursor = conn.cursor()
        
        if instance == 'primary':
            # Count replication connections from primary
            cursor.execute("""
                SELECT 
                    COUNT(*) as connection_count,
                    COUNT(*) FILTER (WHERE sync_state = 'sync') as sync_count
                FROM pg_stat_replication;
            """)
```

- **`def get_replication_connection_metrics(instance, conn)`**: Collects connection-related metrics
- **Primary query**:
  - **`COUNT(*)`**: Total number of replication connections
  - **`COUNT(*) FILTER (WHERE sync_state = 'sync')`**: Count of synchronous replication connections
  - **`pg_stat_replication`**: System view showing replication connections from primary's perspective
  - **Why needed**: Monitors if standby is connected and if sync replication is active

```python
            result = cursor.fetchone()
            if result:
                total_connections, sync_connections = result
                pg_replication_connections.labels(instance=instance).set(total_connections)
                
                # Set sync state (1 if any sync connections, 0 otherwise)
                sync_state = 1 if sync_connections > 0 else 0
                pg_replication_sync_state.labels(instance=instance, client_addr='all').set(sync_state)
```

- **Sets connection count metric**: Total number of replication connections
- **Calculates aggregate sync state**: 1 if any sync connections exist, 0 otherwise
- **`.labels(instance=instance, client_addr='all')`**: Sets metric with two labels
  - **Why needed**: Aggregate sync state for overall monitoring

```python
            # Get individual sync states
            cursor.execute("""
                SELECT 
                    client_addr,
                    CASE WHEN sync_state = 'sync' THEN 1 ELSE 0 END as sync_state
                FROM pg_stat_replication;
            """)
            
            for row in cursor.fetchall():
                client_addr, sync_state = row
                pg_replication_sync_state.labels(instance=instance, client_addr=str(client_addr)).set(sync_state)
```

- **Individual sync states**: Gets sync state for each replication connection
- **`CASE WHEN sync_state = 'sync' THEN 1 ELSE 0 END`**: Converts text to numeric (1=sync, 0=async)
- **`cursor.fetchall()`**: Gets all rows (one per replication connection)
- **Loop through connections**: Sets metric for each client address
- **`str(client_addr)`**: Converts IP address to string for label
- **Why needed**: Allows monitoring sync state per standby server

### WAL Metrics Function

```python
def get_wal_metrics(instance, conn):
    """Get WAL-related metrics"""
    try:
        cursor = conn.cursor()
        
        if instance == 'primary':
            # WAL senders count
            cursor.execute("SELECT COUNT(*) FROM pg_stat_replication;")
            wal_senders = cursor.fetchone()[0]
            pg_wal_senders.labels(instance=instance).set(wal_senders)
```

- **`def get_wal_metrics(instance, conn)`**: Collects WAL-related metrics
- **Primary: WAL senders count**:
  - **`COUNT(*) FROM pg_stat_replication`**: Number of active WAL sender processes
  - **Why needed**: Should match number of connected standby servers

```python
            # WAL generation rate (simplified)
            cursor.execute("""
                SELECT 
                    pg_wal_lsn_diff(
                        pg_current_wal_lsn(),
                        '0/0'
                    ) as total_wal_bytes;
            """)
            total_wal_bytes = cursor.fetchone()[0]
            pg_wal_generation_rate.labels(instance=instance).set(total_wal_bytes)
```

- **WAL generation metric**:
  - **`pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0')`**: Total WAL bytes generated since start
  - **Note**: This is cumulative, not a rate. True rate would require time-based calculation.
  - **Why needed**: Monitors total WAL volume (though not a true rate)

```python
        else:
            # WAL receivers count
            cursor.execute("SELECT COUNT(*) FROM pg_stat_wal_receiver;")
            wal_receivers = cursor.fetchone()[0]
            pg_wal_receivers.labels(instance=instance).set(wal_receivers)
```

- **Standby: WAL receivers count**:
  - **`pg_stat_wal_receiver`**: System view showing WAL receiver process on standby
  - **Why needed**: Should be 1 if standby is actively receiving WAL data

### Replication Slot Metrics Function

```python
def get_replication_slot_metrics(instance, conn):
    """Get replication slot metrics"""
    try:
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT 
                COUNT(*) as total_slots,
                COUNT(*) FILTER (WHERE active = true) as active_slots,
                COUNT(*) FILTER (WHERE active = false) as inactive_slots
            FROM pg_replication_slots;
        """)
```

- **`def get_replication_slot_metrics(instance, conn)`**: Collects replication slot metrics
- **Query explanation**:
  - **`pg_replication_slots`**: System catalog showing all replication slots
  - **`COUNT(*)`**: Total number of slots
  - **`COUNT(*) FILTER (WHERE active = true)`**: Slots currently in use
  - **`COUNT(*) FILTER (WHERE active = false)`**: Slots defined but not in use
  - **Why needed**: Replication slots prevent WAL deletion - monitoring ensures proper configuration

```python
        result = cursor.fetchone()
        if result:
            total_slots, active_slots, inactive_slots = result
            pg_replication_slots_total.labels(instance=instance).set(total_slots)
            pg_replication_slots_active.labels(instance=instance).set(active_slots)
            pg_replication_slots_inactive.labels(instance=instance).set(inactive_slots)
```

- **Sets all slot metrics**: Total, active, and inactive counts
- **Why needed**: Helps identify misconfigured slots or slots that should be active but aren't

### Data Consistency Metrics Function

```python
def get_data_consistency_metrics():
    """Get data consistency metrics by comparing record counts"""
    try:
        primary_conn = get_db_connection('primary')
        standby_conn = get_db_connection('standby')
        
        if not primary_conn or not standby_conn:
            return
```

- **`def get_data_consistency_metrics()`**: Compares data between primary and standby
- **Connects to both instances**: Requires connections to primary and standby
- **Early return**: If either connection fails, skip consistency check
- **Why needed**: Detects data divergence (though simple count check has limitations)

```python
        primary_cursor = primary_conn.cursor()
        standby_cursor = standby_conn.cursor()
        
        # Get record counts from both instances
        primary_cursor.execute("SELECT COUNT(*) FROM test_data;")
        primary_count = primary_cursor.fetchone()[0]
        
        standby_cursor.execute("SELECT COUNT(*) FROM test_data;")
        standby_count = standby_cursor.fetchone()[0]
```

- **Counts records**: Gets row count from `test_data` table on both instances
- **Why needed**: Simple consistency check - if counts differ, data may be inconsistent
- **Limitation**: Count match doesn't guarantee data consistency (could have different rows with same count)

```python
        # Set consistency metric (1 if consistent, 0 if not)
        consistency = 1 if primary_count == standby_count else 0
        pg_data_consistency_check.labels(instance='cluster').set(consistency)
        
        logger.debug(f"Data consistency check: Primary={primary_count}, Standby={standby_count}, Consistent={consistency}")
```

- **Compares counts**: Sets metric to 1 if counts match, 0 if they differ
- **`instance='cluster'`**: Uses 'cluster' label since this is a cluster-wide metric
- **Why needed**: Simple health check for data synchronization

### Health Score Calculation Function

```python
def calculate_health_score(instance, conn):
    """Calculate overall replication health score"""
    try:
        cursor = conn.cursor()
        health_score = 100
```

- **`def calculate_health_score(instance, conn)`**: Calculates composite health score (0-100)
- **`health_score = 100`**: Starts at 100 (perfect health), deducts points for issues
- **Why needed**: Single metric for alerting - low score indicates problems

```python
        if instance == 'primary':
            # Check replication connections
            cursor.execute("SELECT COUNT(*) FROM pg_stat_replication;")
            replication_count = cursor.fetchone()[0]
            
            if replication_count == 0:
                health_score -= 50  # No replication connections
            elif replication_count < 1:
                health_score -= 20  # Less than expected connections
```

- **Primary: Connection check**:
  - **No connections**: -50 points (critical - replication broken)
  - **Less than expected**: -20 points (warning - may be misconfigured)
  - **Why needed**: Replication requires active connections

```python
            # Check replication lag
            cursor.execute("""
                SELECT 
                    COALESCE(
                        pg_wal_lsn_diff(
                            pg_current_wal_lsn(),
                            MIN(replay_lsn)
                        ), 0
                    ) as lag_bytes
                FROM pg_stat_replication;
            """)
            
            result = cursor.fetchone()
            if result:
                lag_bytes = result[0]
                if lag_bytes > 10485760:  # > 10MB
                    health_score -= 30
                elif lag_bytes > 1048576:  # > 1MB
                    health_score -= 10
```

- **Primary: Lag check**:
  - **> 10MB lag**: -30 points (critical lag)
  - **> 1MB lag**: -10 points (warning lag)
  - **Why needed**: High lag indicates replication problems or network issues

```python
        else:
            # Check if in recovery mode
            cursor.execute("SELECT pg_is_in_recovery();")
            in_recovery = cursor.fetchone()[0]
            
            if not in_recovery:
                health_score -= 30  # Standby should be in recovery
```

- **Standby: Recovery mode check**:
  - **`pg_is_in_recovery()`**: Returns true if standby is in recovery (replicating)
  - **Not in recovery**: -30 points (standby should always be in recovery)
  - **Why needed**: If standby is not in recovery, it may have been promoted or misconfigured

```python
            # Check replication lag
            cursor.execute("""
                SELECT 
                    COALESCE(
                        pg_wal_lsn_diff(
                            pg_last_wal_receive_lsn(),
                            pg_last_wal_replay_lsn()
                        ), 0
                    ) as lag_bytes,
                    COALESCE(
                        EXTRACT(EPOCH FROM (
                            now() - pg_last_xact_replay_timestamp()
                        )), 0
                    ) as lag_seconds
                FROM pg_stat_wal_receiver;
            """)
            
            result = cursor.fetchone()
            if result:
                lag_bytes, lag_seconds = result
                if lag_bytes > 10485760:  # > 10MB
                    health_score -= 30
                elif lag_bytes > 1048576:  # > 1MB
                    health_score -= 10
                
                if lag_seconds > 30:  # > 30 seconds
                    health_score -= 20
                elif lag_seconds > 5:  # > 5 seconds
                    health_score -= 5
```

- **Standby: Lag checks**:
  - **Byte lag**: Same thresholds as primary (-30 for >10MB, -10 for >1MB)
  - **Time lag**: Additional time-based checks
    - **> 30 seconds**: -20 points (critical time lag)
    - **> 5 seconds**: -5 points (warning time lag)
  - **Why needed**: Time lag indicates processing delays, not just network issues

```python
        # Ensure health score is between 0 and 100
        health_score = max(0, min(100, health_score))
        pg_replication_health_score.labels(instance=instance).set(health_score)
        
        logger.debug(f"{instance} health score: {health_score}")
```

- **Bounds check**: Ensures score is between 0 and 100
- **Sets metric**: Exposes health score to Prometheus
- **Why needed**: Provides single metric for alerting (e.g., alert if score < 70)

### Metrics Collection Function

```python
def collect_metrics():
    """Collect all metrics from both primary and standby"""
    logger.info("Collecting replication metrics...")
    
    # Collect metrics from primary
    primary_conn = get_db_connection('primary')
    if primary_conn:
        get_replication_lag_metrics('primary', primary_conn)
        get_replication_connection_metrics('primary', primary_conn)
        get_wal_metrics('primary', primary_conn)
        get_replication_slot_metrics('primary', primary_conn)
        calculate_health_score('primary', primary_conn)
        primary_conn.close()
```

- **`def collect_metrics()`**: Main function that orchestrates all metric collection
- **Connects to primary**: Gets connection, collects all primary metrics, closes connection
- **Why needed**: Centralized collection function called periodically

```python
    # Collect metrics from standby
    standby_conn = get_db_connection('standby')
    if standby_conn:
        get_replication_lag_metrics('standby', standby_conn)
        get_wal_metrics('standby', standby_conn)
        calculate_health_score('standby', standby_conn)
        standby_conn.close()
```

- **Collects standby metrics**: Similar to primary, but fewer metrics (no connection metrics on standby)
- **Why needed**: Standby has different metrics available

```python
    # Collect cluster-wide metrics
    get_data_consistency_metrics()
    
    logger.info("Metrics collection completed")
```

- **Cluster metrics**: Consistency check requires both connections (handled internally)
- **Why needed**: Completes the collection cycle

### Main Function

```python
def main():
    """Main function"""
    port = int(os.getenv('EXPORTER_PORT', '9188'))
    
    logger.info(f"Starting PostgreSQL Replication Metrics Exporter on port {port}")
    
    # Start Prometheus metrics server
    start_http_server(port)
```

- **`def main()`**: Entry point for the script
- **`port = int(os.getenv('EXPORTER_PORT', '9188'))`**: Reads port from environment, defaults to 9188
- **`start_http_server(port)`**: Starts HTTP server that serves Prometheus metrics
  - **Why needed**: Prometheus scrapes metrics from this HTTP endpoint

```python
    # Collect metrics every 15 seconds
    while True:
        try:
            collect_metrics()
            time.sleep(15)
        except KeyboardInterrupt:
            logger.info("Exporter stopped by user")
            break
        except Exception as e:
            logger.error(f"Error in metrics collection: {e}")
            time.sleep(15)
```

- **Infinite loop**: Continuously collects metrics
- **`collect_metrics()`**: Calls collection function
- **`time.sleep(15)`**: Waits 15 seconds between collections
  - **Why needed**: Balances freshness with database load
- **`KeyboardInterrupt`**: Handles Ctrl+C gracefully
- **Exception handling**: Logs errors but continues running (resilient to temporary failures)
- **Why needed**: Ensures exporter keeps running even if one collection fails

```python
if __name__ == '__main__':
    main()
```

- **Script entry point**: Only runs main() if script is executed directly (not imported as module)
- **Why needed**: Allows script to be imported for testing without running main()

## How the Exporter Works

1. **Startup**: HTTP server starts on port 9188, begins serving metrics endpoint
2. **Collection Loop**: Every 15 seconds:
   - Connects to primary database
   - Collects lag, connections, WAL, slots, health score
   - Connects to standby database
   - Collects lag, WAL, health score
   - Performs consistency check (connects to both)
   - Updates all Prometheus metrics
3. **Metrics Exposure**: Prometheus scrapes `http://localhost:9188/metrics` to get current values
4. **Error Handling**: Logs errors but continues running (resilient design)

## Important Notes

- **Collection Interval**: 15 seconds - adjust based on monitoring needs and database load
- **Connection Management**: Opens and closes connections for each collection (not persistent)
- **Error Resilience**: Continues running even if one collection fails
- **Health Score**: Composite metric - check individual metrics for detailed diagnosis
- **Consistency Check**: Simple count comparison - doesn't verify data content
- **WAL Generation Rate**: Currently cumulative, not true rate (would need time-based calculation)

## Usage

### Run the Exporter
```bash
python3 pg-replication-exporter.py
```

### With Environment Variables
```bash
export PRIMARY_HOST=postgres-primary-lab
export STANDBY_HOST=postgres-standby-lab
export POSTGRES_PASSWORD=your_password
python3 pg-replication-exporter.py
```

### Access Metrics
```bash
curl http://localhost:9188/metrics
```

## Troubleshooting

- **Connection Errors**: Verify PostgreSQL instances are running and accessible
- **No Metrics**: Check that both primary and standby are reachable
- **High Lag**: Investigate network issues, standby performance, or WAL volume
- **Health Score Low**: Check individual metrics to identify specific issues
- **Import Errors**: Ensure all dependencies are installed (`pip install -r requirements.txt`)

