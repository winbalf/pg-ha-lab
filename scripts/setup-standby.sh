#!/bin/bash
set -e

echo "Starting standby setup..."

# Wait for primary to be ready
until pg_isready -h postgres-primary-lab -p 5432 -U postgres; do
    echo 'Waiting for primary to be ready...'
    sleep 2
done

echo 'Primary is ready, creating standby from primary...'

# Clean up any existing data
rm -rf /var/lib/postgresql/data/*

# Create base backup
echo "Creating base backup..."
PGPASSWORD=$POSTGRES_REPLICATION_PASSWORD pg_basebackup \
    -h postgres-primary-lab \
    -D /var/lib/postgresql/data \
    -U $POSTGRES_REPLICATION_USER \
    -v -P -R

echo "Base backup completed"

# Configure standby settings
echo "Configuring standby settings..."

# Add replication settings to postgresql.conf
cat >> /var/lib/postgresql/data/postgresql.conf << EOF

# Standby configuration
primary_conninfo = 'host=postgres-primary-lab port=5432 user=$POSTGRES_REPLICATION_USER password=$POSTGRES_REPLICATION_PASSWORD'
EOF

# Create standby signal file
touch /var/lib/postgresql/data/standby.signal

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

echo "Starting standby server..."
# Start PostgreSQL in standby mode using the standard entrypoint
exec docker-entrypoint.sh postgres -D /var/lib/postgresql/data