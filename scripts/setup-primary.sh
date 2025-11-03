#!/bin/bash
set -e

# Setup replication user and permissions
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Create replication user
    CREATE USER $POSTGRES_REPLICATION_USER REPLICATION LOGIN PASSWORD '$POSTGRES_REPLICATION_PASSWORD';
    
    -- Grant necessary permissions
    GRANT CONNECT ON DATABASE $POSTGRES_DB TO $POSTGRES_REPLICATION_USER;
    GRANT USAGE ON SCHEMA public TO $POSTGRES_REPLICATION_USER;
    
    -- Configure streaming replication
    ALTER SYSTEM SET wal_level = replica;
    ALTER SYSTEM SET max_wal_senders = 10;
    ALTER SYSTEM SET max_replication_slots = 10;
    ALTER SYSTEM SET hot_standby = on;
    ALTER SYSTEM SET archive_mode = on;
    ALTER SYSTEM SET archive_command = 'test ! -f /var/lib/postgresql/archive/%f && cp %p /var/lib/postgresql/archive/%f';
    
    -- Reload configuration
    SELECT pg_reload_conf();
EOSQL

# Configure pg_hba.conf for replication
# Replace scram-sha-256 with trust for external connections
sed -i 's/host all all all scram-sha-256/host    all             all             0.0.0.0\/0                trust/' /var/lib/postgresql/data/pg_hba.conf

# Add replication entries if not present
if ! grep -q "host.*replication.*all.*0.0.0.0/0" /var/lib/postgresql/data/pg_hba.conf; then
    echo "host    replication     all             0.0.0.0/0                trust" >> /var/lib/postgresql/data/pg_hba.conf
fi

# Create archive directory
mkdir -p /var/lib/postgresql/archive

echo "Primary server replication setup completed"
