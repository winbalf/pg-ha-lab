# setup-standby.sh - Standby Server Replication Setup

This script configures the **standby PostgreSQL server** to connect to the primary and start replicating data. It creates an initial base backup and configures the standby to stream WAL changes continuously.

## Overview

The standby server maintains a copy of the primary database and stays synchronized by:
1. Taking an initial base backup from the primary
2. Configuring itself to connect to the primary
3. Streaming WAL (Write-Ahead Log) changes from the primary in real-time
4. Applying those changes to keep its data synchronized

## Line-by-Line Explanation

### Script Header and Error Handling

```bash
#!/bin/bash
set -e
```

- **Line 1**: Shebang tells the system to use `/bin/bash` to execute this script
- **Line 2**: `set -e` ensures the script exits immediately if any command fails. Critical for replication setup - we don't want a partially configured standby.

### Section 1: Wait for Primary Server

```bash
echo "Starting standby setup..."

until pg_isready -h postgres-primary-lab -p 5432 -U postgres; do
    echo 'Waiting for primary to be ready...'
    sleep 2
done

echo 'Primary is ready, creating standby from primary...'
```

- **`pg_isready`**: PostgreSQL utility that checks if a server is accepting connections
- **`-h postgres-primary-lab`**: Hostname of the primary server (Docker service name)
- **`-p 5432`**: PostgreSQL default port
- **`-U postgres`**: Connect as the `postgres` user
- **`until ... do ... done`**: Loop that keeps checking until the primary is ready
- **`sleep 2`**: Wait 2 seconds between checks (prevents excessive connection attempts)
- **Why needed**: The standby **must wait** for the primary to be fully initialized before creating a base backup. Without this, `pg_basebackup` will fail.

### Section 2: Clean Up Existing Data

```bash
# Clean up any existing data
rm -rf /var/lib/postgresql/data/*
```

- **`rm -rf`**: Recursively removes all files and directories
- **`/var/lib/postgresql/data/`**: PostgreSQL's data directory (where all database files live)
- **Why needed**: If this script runs multiple times (container restart), we need a clean slate. Old data would conflict with the new base backup.

### Section 3: Create Base Backup from Primary

```bash
# Create base backup
echo "Creating base backup..."
PGPASSWORD=$POSTGRES_REPLICATION_PASSWORD pg_basebackup \
    -h postgres-primary-lab \
    -D /var/lib/postgresql/data \
    -U $POSTGRES_REPLICATION_USER \
    -v -P -R
```

This is the **core replication initialization step**. Let's break it down:

#### Command Breakdown

- **`PGPASSWORD=$POSTGRES_REPLICATION_PASSWORD`**: Sets the password for the replication user (used by `pg_basebackup` for authentication)

- **`pg_basebackup`**: PostgreSQL utility that creates a physical copy of the primary database
  - **Physical backup**: Copies actual database files, not logical SQL dumps
  - **Consistent snapshot**: Ensures the backup is from a single point in time

- **`-h postgres-primary-lab`**: Connect to the primary server (Docker service name resolves to primary's IP)

- **`-D /var/lib/postgresql/data`**: **Destination directory** - where to copy the database files

- **`-U $POSTGRES_REPLICATION_USER`**: Connect as the replication user (created in `setup-primary.sh`)

- **`-v`**: Verbose output (shows progress)

- **`-P`**: Show progress (displays percentage and transfer rate during backup)

- **`-R`**: **CRITICAL FLAG** - "Write recovery configuration"
  - Creates `postgresql.auto.conf` with `primary_conninfo`
  - Creates `standby.signal` file (tells PostgreSQL to start in standby mode)
  - Automatically configures the standby to connect to the primary

#### What Happens During Base Backup

1. `pg_basebackup` connects to the primary using the replication user
2. It starts streaming all database files (data, indexes, configuration)
3. While copying, it also captures WAL files being written on the primary
4. Once complete, the standby has a point-in-time copy of the primary
5. The `-R` flag automatically configures it to stream future changes

**Why needed**: The standby needs an initial copy of all data. After this, it only needs to stream incremental WAL changes (much faster).

### Section 4: Additional Standby Configuration

```bash
# Configure standby settings
echo "Configuring standby settings..."

# Add replication settings to postgresql.conf
cat >> /var/lib/postgresql/data/postgresql.conf << EOF

# Standby configuration
primary_conninfo = 'host=postgres-primary-lab port=5432 user=$POSTGRES_REPLICATION_USER password=$POSTGRES_REPLICATION_PASSWORD'
EOF
```

- **`cat >>`**: Appends text to a file
- **`postgresql.conf`**: PostgreSQL's main configuration file
- **`primary_conninfo`**: Connection string for the standby to reach the primary
  - Contains: host, port, username, password
  - Used automatically when PostgreSQL starts in standby mode
- **Why needed**: Even though `-R` creates this, we're being explicit to ensure it's correct. This tells the standby: "when you start, connect here to get WAL updates"

### Section 5: Standby Signal File

```bash
# Create standby signal file
touch /var/lib/postgresql/data/standby.signal
```

- **`standby.signal`**: **Magic file** that tells PostgreSQL to start in standby mode
- **Empty file**: The file can be empty - its **existence** is what matters
- **When PostgreSQL starts**:
  - If `standby.signal` exists → start as standby (read-only, streaming replication)
  - If it doesn't exist → start as regular primary server
- **Why needed**: Without this file, PostgreSQL would start as a normal primary server, not a standby. This file is automatically created by `pg_basebackup -R`, but we ensure it exists.

### Section 6: Authentication Configuration (pg_hba.conf)

```bash
# Configure pg_hba.conf for replication
# Ensure pg_hba.conf exists and has proper format
if [ ! -f /var/lib/postgresql/data/pg_hba.conf ]; then
    echo "Creating pg_hba.conf"
    cat > /var/lib/postgresql/data/pg_hba.conf << 'EOF'
# PostgreSQL Client Authentication Configuration File
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             all                                     trust
host    all             all             127.0.0.1/32            trust
host    all             all             ::1/128                 trust
host    replication     all             0.0.0.0/0                trust
host    all             all             0.0.0.0/0                trust
EOF
else
    echo "host all all 0.0.0.0/0 trust" >> /var/lib/postgresql/data/pg_hba.conf
    echo "host replication all 0.0.0.0/0 trust" >> /var/lib/postgresql/data/pg_hba.conf
fi
```

This section ensures authentication is configured on the standby:

- **`if [ ! -f ... ]`**: Check if `pg_hba.conf` doesn't exist
- **If missing**: Create a new file with standard authentication rules
  - `local all all trust`: Local connections (socket) - no password
  - `host all all 127.0.0.1/32 trust`: Localhost connections - no password
  - `host replication all 0.0.0.0/0 trust`: Replication connections from anywhere - no password
  - `host all all 0.0.0.0/0 trust`: All other connections - no password
- **If exists**: Append replication and general access rules
- **Why needed**: Even though the standby is read-only, it needs `pg_hba.conf` configured so:
  - The base backup process can complete
  - Future queries can connect to the standby (for read scaling)
  - Monitoring tools can connect

### Section 7: Start PostgreSQL in Standby Mode

```bash
echo "Starting standby server..."
# Start PostgreSQL in standby mode using the standard entrypoint
exec docker-entrypoint.sh postgres -D /var/lib/postgresql/data
```

- **`exec`**: Replaces the current shell process with the PostgreSQL process
  - Important: The script process becomes the PostgreSQL server process
  - When PostgreSQL stops, the container stops
- **`docker-entrypoint.sh`**: Docker's standard PostgreSQL entrypoint script
  - Handles initialization, user creation, and starting PostgreSQL
- **`postgres -D /var/lib/postgresql/data`**: Start PostgreSQL with this data directory
- **Why needed**: 
  - PostgreSQL reads `standby.signal` and starts in standby mode
  - Reads `primary_conninfo` and connects to the primary
  - Begins streaming WAL changes automatically

## How Standby Replication Works After This Script

Once PostgreSQL starts with `standby.signal` present:

1. **PostgreSQL reads `standby.signal`** → "I'm a standby, start in read-only mode"
2. **Reads `primary_conninfo`** → "Connect to `postgres-primary-lab` as replicator user"
3. **Connects to primary** → Authenticates using replication user
4. **Requests WAL stream** → "Send me all WAL changes from now on"
5. **Primary streams WAL** → Continuously sends write-ahead log entries
6. **Standby applies WAL** → Replays changes to keep data synchronized
7. **Standby stays current** → Usually only seconds behind primary

## The Replication Flow

```
Primary Server                    Standby Server
    │                                  │
    │  1. Base Backup Request          │
    │<─────────────────────────────────┤
    │                                  │
    │  2. Stream All Files             │
    │─────────────────────────────────>│
    │                                  │
    │  3. Initial Copy Complete        │
    │                                  │
    │  4. WAL Streaming Request        │
    │<─────────────────────────────────┤
    │                                  │
    │  5. Continuous WAL Stream        │
    │─────────────────────────────────>│
    │─────────────────────────────────>│
    │─────────────────────────────────>│
    │     (forever...)                 │
```

## Key Files Created/Modified

1. **`/var/lib/postgresql/data/standby.signal`**: Tells PostgreSQL to start as standby
2. **`/var/lib/postgresql/data/postgresql.auto.conf`**: Contains `primary_conninfo` (created by `-R`)
3. **`/var/lib/postgresql/data/pg_hba.conf`**: Authentication rules
4. **`/var/lib/postgresql/data/*`**: All database files copied from primary

## Important Notes

- **The standby starts automatically** - once this script completes, PostgreSQL begins replicating
- **Base backup can take time** - depends on database size (usually seconds to minutes)
- **Standby is read-only** - writes will fail (use for read queries only)
- **Replication lag**: Standby is usually 0-2 seconds behind primary (depends on network and load)

## Troubleshooting

If standby doesn't replicate:
- **Check primary is ready**: `docker exec postgres-primary-lab pg_isready`
- **Check base backup logs**: Look for `pg_basebackup` errors in container logs
- **Verify `standby.signal` exists**: `docker exec postgres-standby-lab ls -la /var/lib/postgresql/data/standby.signal`
- **Check `primary_conninfo`**: `docker exec postgres-standby-lab cat /var/lib/postgresql/data/postgresql.auto.conf`
- **Verify network connectivity**: `docker exec postgres-standby-lab ping postgres-primary-lab`

## What Makes This Work

The combination of:
1. **`standby.signal`** → Tells PostgreSQL "you're a standby"
2. **`primary_conninfo`** → Tells it "connect here for WAL updates"
3. **Base backup** → Gives it the initial data copy
4. **Replication user** → Allows authentication with primary

All of these work together to create a continuously synchronized standby database.

