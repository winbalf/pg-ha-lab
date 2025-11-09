# PostgreSQL High Availability Lab

[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-14-blue.svg)](https://www.postgresql.org/)
[![Docker](https://img.shields.io/badge/Docker-Compose-blue.svg)](https://docs.docker.com/compose/)

[PostgreSQL 14](https://www.postgresql.org/) + [Docker Compose](https://docs.docker.com/compose/) lab environment to experiment with high availability concepts. This setup automatically configures **physical streaming replication** between a primary and standby PostgreSQL instance, providing a ready-to-use HA environment for testing and learning.

## Features

- **Automatic replication setup**: Primary and standby nodes are automatically configured for streaming replication
- **Monitoring extensions**: Pre-configured with `pg_stat_statements`, `pg_buffercache`, and other useful extensions
- **Prometheus metrics**: Two exporters included for comprehensive monitoring (standard PostgreSQL metrics and custom replication metrics)
- **Health check server**: HTTP-based health check server with JSON and Prometheus endpoints for replication monitoring
- **Test data**: Sample data and test functions included for replication validation
- **Enhanced logging**: Comprehensive logging configuration for both primary and standby nodes
- **Health checks**: Built-in health checks ensure nodes are ready before connections

## Contents

- **Primary**: `postgres-primary-lab` (port host `35432` → container `5432`)
- **Standby**: `postgres-standby-lab` (port host `45433` → container `5432`)
- **PostgreSQL Exporter**: `pg-exporter-lab` (Prometheus metrics on port `9187`)
- **Replication Exporter**: `pg-replication-exporter-lab` (Custom replication metrics on port `9188`)
- **Health Check Server**: `health-check-server-lab` (HTTP health endpoints on port `8080`)
- **Network**: `pgnet-lab` (bridge network for inter-container communication)
- **Volumes**: Separate data directories for primary/standby and a shared logs volume

## Prerequisites

- Docker and Docker Compose installed
- ~1 GB free disk space for images and data volumes
- Ports `35432`, `45433`, `9187`, `9188`, and `8080` available on your host

## Quick Start

Bring the lab up:
```bash
docker-compose -f docker-compose.yml -p pg-ha up -d
```

The setup process includes:
1. Primary node initialization with replication configuration
2. Automatic base backup creation for standby
3. Standby node configuration and startup

Verify containers and health:
```bash
docker-compose -f docker-compose.yml -p pg-ha ps
```

Wait for both containers to show `healthy` status before connecting.

Tear down (including volumes):
```bash
docker-compose -f docker-compose.yml -p pg-ha down --volumes
```

## Configuration

### Environment Variables

**Database configuration** (with defaults):
- `POSTGRES_DB` = `testdb`
- `POSTGRES_USER` = `postgres`
- `POSTGRES_PASSWORD` = `secure_password_123`

**Replication configuration** (with defaults):
- `POSTGRES_REPLICATION_USER` = `replicator`
- `POSTGRES_REPLICATION_PASSWORD` = `replicator_password_123`

You can override these by exporting them in your shell or by creating a `.env` file in the project root:

```bash
POSTGRES_DB=labdb
POSTGRES_USER=labuser
POSTGRES_PASSWORD=supersecret
POSTGRES_REPLICATION_USER=repl_user
POSTGRES_REPLICATION_PASSWORD=repl_secret
```

### Ports

- **Primary**: `localhost:35432`
- **Standby**: `localhost:45433`
- **PostgreSQL Exporter**: `localhost:9187` (Prometheus metrics endpoint)
- **Replication Exporter**: `localhost:9188` (Custom replication metrics endpoint)
- **Health Check Server**: `localhost:8080` (HTTP health check endpoints)

### Volumes

- `postgres_primary_lab_data`: Primary node data directory
- `postgres_standby_lab_data`: Standby node data directory
- `postgres_lab_logs`: Shared logs volume (mounted at `/var/log/postgresql` in both containers)

### Setup Scripts

The project includes initialization scripts that run automatically:

- **`scripts/setup-primary.sh`**: Configures primary for replication (WAL level, replication slots, replication user)
- **`scripts/setup-standby.sh`**: Creates base backup from primary and configures standby
- **`scripts/init-extensions.sql`**: Sets up monitoring extensions, test data, and useful views

## Connect

### Using psql from your host

```bash
# Primary (read-write)
psql "host=127.0.0.1 port=35432 dbname=${POSTGRES_DB:-testdb} user=${POSTGRES_USER:-postgres} password=${POSTGRES_PASSWORD:-secure_password_123} sslmode=disable"

# Standby (read-only, replicating from primary)
psql "host=127.0.0.1 port=45433 dbname=${POSTGRES_DB:-testdb} user=${POSTGRES_USER:-postgres} password=${POSTGRES_PASSWORD:-secure_password_123} sslmode=disable"
```

### From inside containers

```bash
# Primary
docker exec -it postgres-primary-lab psql -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-testdb}

# Standby
docker exec -it postgres-standby-lab psql -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-testdb}
```

## Verify Replication

### Check replication status on primary

```bash
docker exec -it postgres-primary-lab psql -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-testdb} -c "SELECT * FROM replication_status;"
```

Or use the built-in view:
```sql
SELECT * FROM pg_stat_replication;
```

### Test data replication

1. **Insert data on primary**:
```bash
docker exec -it postgres-primary-lab psql -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-testdb} -c "INSERT INTO test_data (name, email, data) VALUES ('Test User', 'test@example.com', '{\"test\": true}');"
```

2. **Query from standby** (should see the new row):
```bash
docker exec -it postgres-standby-lab psql -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-testdb} -c "SELECT * FROM test_data WHERE name = 'Test User';"
```

### Check replication lag

On the primary:
```sql
SELECT 
    application_name,
    state,
    sync_state,
    replay_lag,
    write_lag,
    flush_lag
FROM pg_stat_replication;
```

## Pre-installed Extensions & Features

The setup includes:

- **`pg_stat_statements`**: Query performance monitoring
- **`pg_buffercache`**: Buffer cache statistics
- **`pg_prewarm`**: Buffer warming utilities
- **`pg_trgm`**: Trigram text search
- **`btree_gin`** and **`btree_gist`**: Advanced indexing support

### Test Data

A `test_data` table is pre-populated with sample records. You can generate additional test load:

```sql
SELECT generate_test_load(1000);  -- Generate 1000 test records
```

### Monitoring Views

- **`replication_status`**: Replication connection details
- **`database_activity`**: Database statistics and activity metrics

## Logs and Monitoring

### Container Logs

```bash
# Primary logs
docker logs postgres-primary-lab

# Standby logs
docker logs postgres-standby-lab

# PostgreSQL Exporter logs
docker logs pg-exporter-lab

# Replication Exporter logs
docker logs pg-replication-exporter-lab

# Health Check Server logs
docker logs health-check-server-lab

# Follow logs in real-time
docker logs -f postgres-primary-lab
```

### PostgreSQL Logs

Detailed PostgreSQL logs are available in both containers at `/var/log/postgresql/`:
- Primary: `postgresql-primary.log`
- Standby: `postgresql-standby.log`

The logging configuration includes:
- All SQL statements (`log_statement=all`)
- Connection/disconnection events
- Checkpoints
- Lock waits
- Temporary file usage

### Prometheus Metrics

The lab includes two Prometheus exporters for comprehensive monitoring:

#### PostgreSQL Exporter (`pg-exporter-lab`)

Standard PostgreSQL metrics exporter (port `9187`):
```bash
# View metrics
curl http://localhost:9187/metrics
```

Provides standard PostgreSQL metrics including:
- Database connections and activity
- Query performance statistics
- Table and index statistics
- Connection pool metrics

#### Replication Exporter (`pg-replication-exporter-lab`)

Custom replication-specific metrics exporter (port `9188`):
```bash
# View replication metrics
curl http://localhost:9188/metrics
```

Provides specialized replication metrics including:
- Replication lag (bytes, seconds, megabytes)
- Replication connection status
- WAL sender/receiver counts
- Replication slot status
- Replication health score
- Data consistency checks

Both exporters are automatically configured to connect to the primary database and provide metrics in Prometheus format.

### Health Checks

PostgreSQL containers use `pg_isready` health checks:
- Interval: 10 seconds
- Timeout: 5 seconds
- Retries: 5

The replication exporter includes its own health check that verifies the metrics endpoint is responding.

### Health Check Server

The lab includes a dedicated HTTP health check server (`health-check-server-lab`) that provides comprehensive replication health monitoring:

#### Endpoints

- **`GET /health`**: Comprehensive health check with JSON response
  - Returns health score (0-100), node availability, replication lag, and status
  - HTTP 200 for healthy/warning, HTTP 503 for critical
  
- **`GET /ready`**: Readiness check for orchestration tools
  - Returns HTTP 200 if both primary and standby are available
  - Returns HTTP 503 if either node is down
  
- **`GET /live`**: Liveness check for orchestration tools
  - Returns HTTP 200 if primary is available
  - Returns HTTP 503 if primary is down
  
- **`GET /metrics`**: Prometheus-compatible metrics endpoint
  - Exposes replication lag, node availability, and health score as Prometheus metrics

#### Usage Examples

```bash
# Comprehensive health check
curl http://localhost:8080/health

# Readiness check (for Kubernetes/Docker Swarm)
curl http://localhost:8080/ready

# Liveness check (for Kubernetes/Docker Swarm)
curl http://localhost:8080/live

# Prometheus metrics
curl http://localhost:8080/metrics
```

#### Health Score Calculation

The health check server calculates a health score (0-100) based on:
- Primary availability (-50 points if down)
- Standby availability (-30 points if down)
- Replication lag in bytes (-10 to -30 points based on threshold)
- Replication lag in seconds (-5 to -20 points based on threshold)

Status levels:
- **Healthy**: Score ≥ 70 (HTTP 200)
- **Warning**: Score 50-69 (HTTP 200)
- **Critical**: Score < 50 (HTTP 503)

For detailed documentation, see `scripts/docs/README-health-check-server.md`.

## Troubleshooting

### Containers won't start

- **Check port availability**: Ensure ports `35432`, `45433`, `9187`, `9188`, and `8080` are not in use
- **Check Docker resources**: Ensure Docker has sufficient resources allocated
- **View logs**: Check container logs for initialization errors
- **Check exporter builds**: The replication exporter needs to be built - ensure Docker can build images

### Replication not working

- **Verify primary is healthy**: `docker-compose -f docker-compose.yml -p pg-ha ps`
- **Check primary logs**: Look for replication setup errors
- **Check standby logs**: Verify base backup completed successfully
- **Verify network connectivity**: Ensure containers can communicate on `pgnet-lab`
- **Check exporter connectivity**: Verify exporters can connect to PostgreSQL instances

### Connection issues

- **Authentication failures**: Ensure `POSTGRES_PASSWORD` matches what was used during initialization
- **Port conflicts**: Modify port mappings in `docker-compose.yml` if needed
- **Container not ready**: Wait for health checks to pass before connecting

### Standby appears empty

If the standby doesn't show data:
1. Ensure the standby completed initialization (check logs)
2. Verify replication is active: `SELECT * FROM pg_stat_replication;` on primary
3. Check for replication lag (standby may still be catching up)

## Manual Failover (Exercise)

To practice manual failover:

1. **Stop the primary**:
```bash
docker stop postgres-primary-lab
```

2. **Promote standby to primary** (on standby):
```bash
docker exec -it postgres-standby-lab pg_ctl promote -D /var/lib/postgresql/data
```

3. **Update application connections** to point to the new primary (port `45433`)

4. **Reconfigure old primary as new standby** (requires re-initialization)

## Clean Up

Remove all containers, networks, and volumes:
```bash
docker-compose -f docker-compose.yml -p pg-ha down --volumes
```

Remove only containers (preserve data):
```bash
docker-compose -f docker-compose.yml -p pg-ha down
```

## Security

⚠️ **This is a lab environment for testing and learning purposes.**

- **Do NOT** reuse the default credentials in production
- **Do NOT** expose these ports on untrusted networks
- The setup uses `trust` authentication for simplicity in the lab environment
- For production use, configure proper authentication (`scram-sha-256`) and SSL/TLS

## License

This project is provided as-is for educational and testing purposes.
