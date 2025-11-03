# setup-primary.sh - Primary Server Replication Configuration

This script configures the **primary PostgreSQL server** to enable streaming replication. It must run **before** the standby server can connect and replicate data.

## Overview

The primary server acts as the main database that accepts write operations. This script prepares it to:
1. Accept replication connections from standby servers
2. Stream Write-Ahead Log (WAL) data to standby servers
3. Create replication slots for reliable replication

## Line-by-Line Explanation

### Script Header and Error Handling

```bash
#!/bin/bash
set -e
```

- **Line 1**: Shebang tells the system to use `/bin/bash` to execute this script
- **Line 2**: `set -e` means the script will **immediately exit** if any command fails. This ensures we don't proceed with incomplete configuration

### Section 1: Database Setup - Creating Replication User

```bash
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
```

- **`-v ON_ERROR_STOP=1`**: If any SQL command fails, stop immediately (similar to `set -e` but for SQL)
- **`--username "$POSTGRES_USER"`**: Connects as the database owner (usually `postgres`)
- **`--dbname "$POSTGRES_DB"`**: Connects to the target database (usually `testdb`)
- **`<<-EOSQL`**: Here-document syntax - all SQL between `<<-EOSQL` and `EOSQL` is executed as one transaction

#### Creating the Replication User

```sql
CREATE USER $POSTGRES_REPLICATION_USER REPLICATION LOGIN PASSWORD '$POSTGRES_REPLICATION_PASSWORD';
```

- **`CREATE USER`**: Creates a new database user
- **`REPLICATION`**: This is a **critical privilege** - only users with this attribute can connect for replication
- **`LOGIN`**: Allows the user to connect to the database
- **`PASSWORD`**: Sets authentication password (default: `replicator_password_123`)
- **Why needed**: The standby server will use this user to connect and pull WAL data

#### Granting Permissions

```sql
GRANT CONNECT ON DATABASE $POSTGRES_DB TO $POSTGRES_REPLICATION_USER;
GRANT USAGE ON SCHEMA public TO $POSTGRES_REPLICATION_USER;
```

- **`GRANT CONNECT`**: Allows the replication user to connect to the database (needed for `pg_basebackup`)
- **`GRANT USAGE ON SCHEMA public`**: Allows the user to access the public schema (needed for some replication operations)
- **Why needed**: Even replication users need basic database access permissions

### Section 2: PostgreSQL System Configuration for Replication

This section configures PostgreSQL's internal settings using `ALTER SYSTEM`, which modifies `postgresql.auto.conf`:

```sql
ALTER SYSTEM SET wal_level = replica;
```

- **`wal_level`**: Controls how much information is written to WAL files
  - `minimal`: Only writes enough for crash recovery (NOT enough for replication)
  - **`replica`**: Writes enough information for replication AND crash recovery (required for standby)
  - `logical`: Same as `replica` plus logical decoding information
- **Why needed**: Standby servers read WAL data to replicate changes. Without `replica` level, replication won't work.

```sql
ALTER SYSTEM SET max_wal_senders = 10;
```

- **`max_wal_senders`**: Maximum number of simultaneous replication connections
- **Default**: Usually `0` (replication disabled)
- **Why needed**: Sets how many standby servers can connect simultaneously. Set to `10` to allow multiple standbys.

```sql
ALTER SYSTEM SET max_replication_slots = 10;
```

- **`max_replication_slots`**: Maximum number of replication slots
- **Replication slots**: Prevent the primary from deleting WAL files that a standby hasn't received yet
- **Why needed**: Without replication slots, if a standby falls behind, the primary might delete old WAL files the standby needs, breaking replication

```sql
ALTER SYSTEM SET hot_standby = on;
```

- **`hot_standby`**: Allows the **standby** server to accept read-only queries while replicating
- **Why needed**: Without this, standbys can replicate but won't accept connections. With it, standbys can serve read queries (useful for read scaling)

```sql
ALTER SYSTEM SET archive_mode = on;
ALTER SYSTEM SET archive_command = 'test ! -f /var/lib/postgresql/archive/%f && cp %p /var/lib/postgresql/archive/%f';
```

- **`archive_mode = on`**: Enables WAL archiving (saving WAL files to a backup location)
- **`archive_command`**: Command to copy WAL files to archive directory
  - `%p`: Path to the WAL file being archived
  - `%f`: Filename only (without path)
  - **Logic**: Only copies if file doesn't already exist (prevents overwrites)
- **Why needed**: Archives provide a safety net - if replication fails, you can recover from archived WAL files

```sql
SELECT pg_reload_conf();
```

- **`pg_reload_conf()`**: Reloads PostgreSQL configuration without restarting the server
- **Note**: Some settings (like `wal_level`) require a **full restart**, not just a reload
- **Why needed**: Applies the configuration changes immediately (for settings that can be reloaded)

### Section 3: Network Configuration - pg_hba.conf

PostgreSQL uses `pg_hba.conf` (host-based authentication) to control who can connect and how:

```bash
sed -i 's/host all all all scram-sha-256/host    all             all             0.0.0.0\/0                trust/' /var/lib/postgresql/data/pg_hba.conf
```

- **`sed -i`**: In-place file editing
- **What it does**: Replaces `scram-sha-256` authentication with `trust` for all connections
  - `scram-sha-256`: Secure password-based authentication
  - **`trust`**: No password required (NOT SECURE, but convenient for lab environments)
- **Pattern**: `host all all 0.0.0.0/0 trust` means "allow all hosts, all databases, all users, no password"
- **Why needed**: Simplifies lab setup (production should use `scram-sha-256`)

```bash
if ! grep -q "host.*replication.*all.*0.0.0.0/0" /var/lib/postgresql/data/pg_hba.conf; then
    echo "host    replication     all             0.0.0.0/0                trust" >> /var/lib/postgresql/data/pg_hba.conf
fi
```

- **`grep -q`**: Quietly checks if pattern exists (returns true if found)
- **What it does**: Adds a replication-specific entry to `pg_hba.conf` if one doesn't exist
- **`host replication all 0.0.0.0/0 trust`**: Allows replication connections from any host with no password
- **Why needed**: Even if we have a replication user, PostgreSQL won't allow replication connections unless explicitly allowed in `pg_hba.conf`

### Section 4: Archive Directory Setup

```bash
mkdir -p /var/lib/postgresql/archive
```

- **`mkdir -p`**: Creates directory, including any parent directories if needed (`-p` prevents errors if it already exists)
- **Why needed**: The `archive_command` we configured earlier copies files here. This directory must exist or archiving will fail

### Completion Message

```bash
echo "Primary server replication setup completed"
```

Confirms successful completion of the setup process.

## How This Enables Replication

1. **Replication User Created**: Standby can authenticate and connect
2. **WAL Level Set**: PostgreSQL writes enough WAL data for replication
3. **Max WAL Senders Set**: Primary accepts replication connections
4. **Replication Slots Enabled**: Prevents WAL deletion that would break replication
5. **Network Access Configured**: Standby can connect from remote host
6. **Archiving Enabled**: Safety net for WAL recovery

## What Happens Next

After this script completes:
1. The primary server is ready to accept replication connections
2. The standby server can run `pg_basebackup` to create an initial copy
3. The standby can then stream WAL changes in real-time

## Important Notes

- **`wal_level = replica` requires a server restart** to take effect (not just `pg_reload_conf()`)
- In Docker, this typically happens when the container restarts
- **`trust` authentication is insecure** - only use in lab/development environments
- Production systems should use `scram-sha-256` authentication and SSL/TLS

## Troubleshooting

If replication fails after this script:
- Check that `wal_level = replica` in `postgresql.auto.conf`
- Verify replication user exists: `SELECT * FROM pg_user WHERE usename = 'replicator';`
- Check `pg_hba.conf` has replication entry: `cat /var/lib/postgresql/data/pg_hba.conf | grep replication`

