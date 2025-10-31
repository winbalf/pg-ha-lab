# PostgreSQL High Availability Lab

[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-14-blue.svg)](https://www.postgresql.org/)
[![Docker](https://img.shields.io/badge/Docker-Compose-blue.svg)](https://docs.docker.com/compose/)

[PostgreSQL 14](https://www.postgresql.org/) + [Docker Compose](https://docs.docker.com/compose/) lab environment to experiment with high availability concepts. It brings up two PostgreSQL nodes: a primary and a standby container on a dedicated bridge network.

Important: replication and failover orchestration are not pre-configured. This lab provides a clean base to practice setting up physical streaming replication and manual failover.

### Contents
- **Primary**: `postgres-primary-lab` (port host 35432 → container 5432)
- **Standby**: `postgres-standby-lab` (port host 45433 → container 5432)
- **Volumes**: data dirs for primary/standby and a shared logs volume

### Prerequisites
- Docker and Docker Compose installed
- ~1 GB free disk space for images and data volumes

### Quick start
Bring the lab up:
```bash
docker compose -f docker-compose.yml -p pg-ha up -d
```

Verify containers and health:
```bash
docker compose -f docker-compose.yml -p pg-ha ps
```

Tear down (including volumes):
```bash
docker compose -f docker-compose.yml -p pg-ha down --volumes
```

### Configuration
Environment variables (with defaults) used by both nodes:
- `POSTGRES_DB` = `testdb`
- `POSTGRES_USER` = `postgres`
- `POSTGRES_PASSWORD` = `secure_password_123`

You can override these by exporting them in your shell or by creating a `.env` file in the project root. Example `.env`:
```bash
POSTGRES_DB=labdb
POSTGRES_USER=labuser
POSTGRES_PASSWORD=supersecret
```

Ports exposed on the host:
- Primary: `localhost:35432`
- Standby: `localhost:45433`

Data and logs persist in Docker volumes:
- Primary data: `postgres_primary_lab_data`
- Standby data: `postgres_standby_lab_data`
- Logs: `postgres_lab_logs` (mounted at `/var/log/postgresql` in both containers)

### Connect
Using `psql` from your host (if installed):
```bash
# Primary
psql "host=127.0.0.1 port=35432 dbname=${POSTGRES_DB:-testdb} user=${POSTGRES_USER:-postgres} password=${POSTGRES_PASSWORD:-secure_password_123} sslmode=disable"

# Standby (not replicated by default)
psql "host=127.0.0.1 port=45433 dbname=${POSTGRES_DB:-testdb} user=${POSTGRES_USER:-postgres} password=${POSTGRES_PASSWORD:-secure_password_123} sslmode=disable"
```

Or from inside the container:
```bash
docker exec -it postgres-primary-lab psql -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-testdb}
```


### Security
This is a lab environment. Do not reuse the sample credentials in production and do not expose these ports on untrusted networks.
