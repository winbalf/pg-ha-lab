# Dockerfile.replication-exporter - PostgreSQL Replication Metrics Exporter Container

This Dockerfile builds a containerized Python application that exports PostgreSQL replication metrics in Prometheus format. The exporter connects to both primary and standby PostgreSQL instances to collect comprehensive replication health metrics.

## Overview

The replication exporter is a monitoring tool that:
1. Connects to primary and standby PostgreSQL instances
2. Collects replication lag, connection status, WAL metrics, and health scores
3. Exposes metrics via HTTP endpoint on port 9188 in Prometheus format
4. Runs as a non-root user for security
5. Includes health checks for container orchestration

## Line-by-Line Explanation

### Base Image Selection

```dockerfile
FROM python:3.11-slim
```

- **`FROM python:3.11-slim`**: Uses the official Python 3.11 slim image as the base
  - **`python:3.11`**: Provides Python 3.11 runtime and pip package manager
  - **`slim`**: Minimal variant that excludes many system packages, resulting in a smaller image size (~45MB vs ~300MB for full image)
  - **Why needed**: The exporter is a Python application, so we need Python runtime. The slim variant reduces image size and attack surface.

### System Dependencies Installation

```dockerfile
# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*
```

- **`# Install system dependencies`**: Comment explaining the purpose of this section
- **`RUN apt-get update`**: Updates the package list from Debian repositories (required before installing packages)
- **`apt-get install -y`**: Installs packages with `-y` flag to auto-confirm installation (needed for non-interactive Docker builds)
- **`gcc`**: GNU Compiler Collection - C compiler needed to build Python packages with C extensions
  - **Why needed**: `psycopg2` (PostgreSQL adapter for Python) requires compilation of C extensions
- **`libpq-dev`**: PostgreSQL client library development files
  - **Why needed**: Provides header files and libraries needed to compile `psycopg2` against PostgreSQL client libraries
- **`&& rm -rf /var/lib/apt/lists/*`**: Removes package list cache after installation
  - **Why needed**: Reduces image size by removing unnecessary files (saves ~20-30MB). This is a Docker best practice for multi-stage builds and smaller images.

### Working Directory Setup

```dockerfile
# Set working directory
WORKDIR /app
```

- **`WORKDIR /app`**: Sets `/app` as the working directory for all subsequent commands
  - **Why needed**: All file operations (COPY, RUN) will be relative to `/app`. This keeps the container organized and makes paths simpler.

### Python Dependencies Installation

```dockerfile
# Copy requirements and install Python dependencies
COPY scripts/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
```

- **`COPY scripts/requirements.txt .`**: Copies the requirements file from the build context into the container
  - **`scripts/requirements.txt`**: Source path relative to Docker build context (usually project root)
  - **`.`**: Destination is current working directory (`/app` due to WORKDIR)
  - **Why needed**: We need the requirements file to know which Python packages to install
- **`RUN pip install --no-cache-dir -r requirements.txt`**: Installs Python packages listed in requirements.txt
  - **`--no-cache-dir`**: Prevents pip from storing downloaded packages in cache
  - **Why needed**: Reduces image size by not storing package cache (saves ~50-100MB). Packages are already installed, so cache isn't needed at runtime.
  - **`-r requirements.txt`**: Reads package list from the requirements file
  - **Why needed**: Ensures all dependencies (like `psycopg2`, `prometheus_client`) are installed before the application runs

### Application Code Copy

```dockerfile
# Copy the exporter script
COPY scripts/pg-replication-exporter.py .
```

- **`COPY scripts/pg-replication-exporter.py .`**: Copies the Python exporter script into the container
  - **`scripts/pg-replication-exporter.py`**: Source path in build context
  - **`.`**: Destination is `/app/pg-replication-exporter.py` (due to WORKDIR)
  - **Why needed**: The application code must be in the container to run. This is the main exporter script that collects and exposes metrics.

### User Creation and Security

```dockerfile
# Create non-root user
RUN useradd -m -u 1000 exporter && chown -R exporter:exporter /app
USER exporter
```

- **`RUN useradd -m -u 1000 exporter`**: Creates a new system user
  - **`useradd`**: Linux command to create a new user
  - **`-m`**: Creates the user's home directory (`/home/exporter`)
  - **`-u 1000`**: Sets user ID to 1000 (common convention for first non-root user)
  - **`exporter`**: Username for the new user
  - **Why needed**: Running as root is a security risk. If the container is compromised, an attacker would have root access.
- **`chown -R exporter:exporter /app`**: Changes ownership of `/app` directory to the exporter user
  - **`-R`**: Recursive - applies to all files and subdirectories
  - **`exporter:exporter`**: Sets both user and group to `exporter`
  - **Why needed**: The exporter user needs read/execute permissions on the application files to run the script
- **`USER exporter`**: Switches to the exporter user for all subsequent commands
  - **Why needed**: Ensures the container runs as non-root. This is a Docker security best practice.

### Port Exposure

```dockerfile
# Expose port
EXPOSE 9188
```

- **`EXPOSE 9188`**: Documents that the container listens on port 9188
  - **Why needed**: 
    - Documentation for developers/operators
    - Allows Docker to map this port when using `-P` flag
    - Required for health checks and port mapping
  - **Note**: This doesn't actually publish the port - you still need `-p 9188:9188` or `docker-compose` port mapping

### Environment Variables

```dockerfile
# Set environment variables
ENV EXPORTER_PORT=9188
ENV PRIMARY_HOST=postgres-primary-lab
ENV PRIMARY_PORT=5432
ENV STANDBY_HOST=postgres-standby-lab
ENV STANDBY_PORT=5432
ENV POSTGRES_DB=testdb
ENV POSTGRES_USER=postgres
ENV POSTGRES_PASSWORD=secure_password_123
```

- **`ENV EXPORTER_PORT=9188`**: Sets the HTTP port where metrics are exposed
  - **Why needed**: The Python script reads this via `os.getenv('EXPORTER_PORT', '9188')` to start the HTTP server
- **`ENV PRIMARY_HOST=postgres-primary-lab`**: Hostname of the primary PostgreSQL instance
  - **Why needed**: The exporter connects to this host to collect primary-side replication metrics
  - **Note**: This should match the service name in docker-compose or the actual hostname
- **`ENV PRIMARY_PORT=5432`**: Port of the primary PostgreSQL instance
  - **Why needed**: Standard PostgreSQL port for connecting to the primary
- **`ENV STANDBY_HOST=postgres-standby-lab`**: Hostname of the standby PostgreSQL instance
  - **Why needed**: The exporter connects to this host to collect standby-side replication metrics
- **`ENV STANDBY_PORT=5432`**: Port of the standby PostgreSQL instance
  - **Why needed**: Port for connecting to the standby (may differ if using port mapping)
- **`ENV POSTGRES_DB=testdb`**: Database name to connect to
  - **Why needed**: The exporter connects to this database to run queries
- **`ENV POSTGRES_USER=postgres`**: Database username for authentication
  - **Why needed**: Credentials for connecting to both primary and standby instances
- **`ENV POSTGRES_PASSWORD=secure_password_123`**: Database password for authentication
  - **Why needed**: Password for database connections
  - **Security Note**: In production, use secrets management (Docker secrets, environment files, or secret managers) instead of hardcoding passwords

### Health Check Configuration

```dockerfile
# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import requests; requests.get('http://localhost:9188/metrics')" || exit 1
```

- **`HEALTHCHECK`**: Docker instruction that defines how to check container health
  - **Why needed**: Allows Docker and orchestration tools (Kubernetes, Docker Swarm) to automatically detect unhealthy containers and restart them
- **`--interval=30s`**: Time between health checks (30 seconds)
  - **Why needed**: Balances between quick failure detection and not overloading the system
- **`--timeout=10s`**: Maximum time allowed for health check to complete
  - **Why needed**: If the check takes longer than 10 seconds, it's considered failed
- **`--start-period=5s`**: Grace period after container starts before health checks begin
  - **Why needed**: Gives the application time to start up (Python server needs a few seconds to initialize)
- **`--retries=3`**: Number of consecutive failures before marking container as unhealthy
  - **Why needed**: Prevents false positives from transient network issues or temporary load spikes
- **`CMD python -c "import requests; requests.get('http://localhost:9188/metrics')" || exit 1`**: Health check command
  - **`python -c`**: Executes Python code directly from command line
  - **`import requests`**: Imports the requests library (should be in requirements.txt)
  - **`requests.get('http://localhost:9188/metrics')`**: Makes HTTP GET request to metrics endpoint
    - **Why needed**: If the exporter is running correctly, it should respond to HTTP requests on port 9188
  - **`|| exit 1`**: If the request fails, exit with error code 1
    - **Why needed**: Docker interprets exit code 1 as unhealthy. Exit code 0 means healthy.

### Container Entry Point

```dockerfile
# Run the exporter
CMD ["python", "pg-replication-exporter.py"]
```

- **`CMD ["python", "pg-replication-exporter.py"]`**: Default command to run when container starts
  - **`CMD`**: Docker instruction for the default command (can be overridden at runtime)
  - **`["python", "pg-replication-exporter.py"]`: Exec form (JSON array) - recommended format
    - **Why needed**: Exec form doesn't invoke a shell, so signals (like SIGTERM) are properly handled
  - **`python`**: Python interpreter to execute the script
  - **`pg-replication-exporter.py`**: The exporter script (located in `/app` due to WORKDIR)
  - **Why needed**: This starts the Prometheus metrics HTTP server and begins collecting metrics

## How the Container Works

1. **Build Time**: 
   - Base image provides Python runtime
   - System dependencies (gcc, libpq-dev) installed for compiling psycopg2
   - Python packages installed from requirements.txt
   - Application code copied into container
   - Non-root user created and ownership set
   - Environment variables set with default values

2. **Runtime**:
   - Container starts and runs as `exporter` user
   - Python script reads environment variables for database connection details
   - HTTP server starts on port 9188
   - Every 15 seconds, script connects to primary and standby databases
   - Metrics are collected and exposed at `http://localhost:9188/metrics`
   - Health check runs every 30 seconds to verify the HTTP server is responding

## Important Notes

- **Security**: The container runs as non-root user (`exporter`) for better security
- **Environment Variables**: Can be overridden at runtime using `-e` flag or docker-compose environment section
- **Health Check**: Requires `requests` library in requirements.txt (or the health check will fail)
- **Network**: Container must be on the same Docker network as PostgreSQL containers to resolve hostnames
- **Port Mapping**: Use `-p 9188:9188` or docker-compose port mapping to access metrics from host
- **Secrets**: In production, use Docker secrets or environment variable files instead of hardcoded passwords

## Usage Examples

### Build the Image
```bash
docker build -f scripts/Dockerfile.replication-exporter -t pg-replication-exporter .
```

### Run the Container
```bash
docker run -d \
  --name replication-exporter \
  --network pg-ha-lab_default \
  -e PRIMARY_HOST=postgres-primary-lab \
  -e STANDBY_HOST=postgres-standby-lab \
  -e POSTGRES_PASSWORD=your_password \
  -p 9188:9188 \
  pg-replication-exporter
```

### Access Metrics
```bash
curl http://localhost:9188/metrics
```

## Troubleshooting

- **Connection Errors**: Verify PostgreSQL containers are running and on the same network
- **Health Check Fails**: Ensure `requests` library is in requirements.txt
- **Permission Denied**: Verify user `exporter` owns `/app` directory
- **Port Already in Use**: Change `EXPORTER_PORT` or use different host port mapping
- **Import Errors**: Check that all dependencies in requirements.txt are installed correctly

