# health-check-server.sh - PostgreSQL Replication Health Check HTTP Server

This bash script provides an HTTP server that exposes health check endpoints for PostgreSQL replication. It monitors primary and standby availability, replication lag, and calculates health scores, returning JSON responses or Prometheus metrics.

## Overview

The health check server is a lightweight monitoring tool that:
1. Monitors primary and standby PostgreSQL instance availability
2. Calculates replication lag in bytes and seconds
3. Computes a health score (0-100) based on multiple factors
4. Exposes HTTP endpoints: `/health`, `/ready`, `/live`, `/metrics`
5. Can run as a persistent HTTP server or perform a single check
6. Returns appropriate HTTP status codes for orchestration tools (Kubernetes, Docker Swarm)

## Line-by-Line Explanation

### Script Header and Error Handling

```bash
#!/bin/bash
# PostgreSQL Replication Health Check Endpoint
# Returns HTTP status codes based on replication health

set -e
```

- **`#!/bin/bash`**: Shebang tells the system to use `/bin/bash` to execute this script
- **Comments**: Describe the script's purpose
- **`set -e`**: Script exits immediately if any command fails
  - **Why needed**: Ensures we don't proceed with incomplete or failed checks, providing accurate health status

### Configuration Variables

```bash
# Configuration
POSTGRES_USER=${POSTGRES_USER:-postgres}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-secure_password_123}
POSTGRES_DB=${POSTGRES_DB:-testdb}
PORT=${HEALTH_CHECK_PORT:-8080}
```

- **`POSTGRES_USER=${POSTGRES_USER:-postgres}`**: Sets database username
  - **`${POSTGRES_USER:-postgres}`**: Uses environment variable `POSTGRES_USER` if set, otherwise defaults to `postgres`
  - **Why needed**: Allows configuration via environment variables (Docker, Kubernetes) without code changes
- **`POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-secure_password_123}`**: Sets database password with default
  - **Why needed**: Password for database authentication
  - **Security Note**: In production, use secrets management instead of defaults
- **`POSTGRES_DB=${POSTGRES_DB:-testdb}`**: Sets database name with default
  - **Why needed**: Database to connect to for health checks
- **`PORT=${HEALTH_CHECK_PORT:-8080}`**: Sets HTTP server port with default 8080
  - **Why needed**: Port where health check server listens for HTTP requests

### Replication Lag Bytes Function

```bash
# Function to get replication lag in bytes
get_replication_lag_bytes() {
    local host=$1
    local port=$2
    
    PGPASSWORD=$POSTGRES_PASSWORD psql -h $host -p $port -U $POSTGRES_USER -d $POSTGRES_DB -t -c "
        SELECT COALESCE(
            pg_wal_lsn_diff(
                pg_current_wal_lsn(),
                pg_last_wal_replay_lsn()
            ), 0
        );
    " 2>/dev/null | tr -d ' ' || echo "0"
}
```

- **`get_replication_lag_bytes()`**: Function to calculate replication lag in bytes
- **`local host=$1`**: First parameter - PostgreSQL hostname
- **`local port=$2`**: Second parameter - PostgreSQL port
- **`PGPASSWORD=$POSTGRES_PASSWORD`**: Sets password environment variable for psql (avoids password prompt)
- **`psql -h $host -p $port`**: Connects to specified host and port
- **`-U $POSTGRES_USER`**: Uses specified username
- **`-d $POSTGRES_DB`**: Connects to specified database
- **`-t`**: Tuples-only mode (no headers, borders, or footers)
- **`-c "..."`**: Executes SQL command directly
- **SQL Query Explanation**:
  - **`pg_current_wal_lsn()`**: Current WAL position on the server
  - **`pg_last_wal_replay_lsn()`**: Last WAL position replayed (applied)
  - **`pg_wal_lsn_diff(...)`**: Calculates byte difference between two LSN positions
  - **`COALESCE(..., 0)`**: Returns 0 if result is NULL (no replication or error)
- **`2>/dev/null`**: Redirects stderr to /dev/null (suppresses error messages)
- **`| tr -d ' '`**: Removes spaces from output (cleans up formatting)
- **`|| echo "0"`**: If command fails, returns "0" as default
- **Why needed**: Measures how far behind the standby is in bytes (network + processing lag)

### Replication Lag Seconds Function

```bash
# Function to get replication lag in seconds
get_replication_lag_seconds() {
    local host=$1
    local port=$2
    
    PGPASSWORD=$POSTGRES_PASSWORD psql -h $host -p $port -U $POSTGRES_USER -d $POSTGRES_DB -t -c "
        SELECT COALESCE(
            EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())),
            0
        );
    " 2>/dev/null | tr -d ' ' || echo "0"
}
```

- **`get_replication_lag_seconds()`**: Function to calculate replication lag in time units
- **SQL Query Explanation**:
  - **`pg_last_xact_replay_timestamp()`**: Timestamp of last replayed transaction on standby
  - **`now() - pg_last_xact_replay_timestamp()`**: Time difference between now and last replay
  - **`EXTRACT(EPOCH FROM ...)`**: Converts time interval to seconds (numeric value)
  - **`COALESCE(..., 0)`**: Returns 0 if NULL (no transactions replayed yet)
- **Why needed**: Time-based lag is often more intuitive than byte-based lag for monitoring and alerting

### Service Availability Check Function

```bash
# Function to check if service is running
check_service() {
    local host=$1
    local port=$2
    
    nc -z $host $port 2>/dev/null
}
```

- **`check_service()`**: Function to check if a service is listening on a port
- **`local host=$1`**: Hostname or IP address
- **`local port=$2`**: Port number
- **`nc -z $host $port`**: Netcat command to check port connectivity
  - **`-z`**: Zero-I/O mode (just checks if connection is possible, doesn't send data)
  - **Why needed**: Fast way to check if PostgreSQL is accepting connections
- **`2>/dev/null`**: Suppresses error messages
- **Return value**: Returns 0 (success) if port is open, non-zero if closed
- **Why needed**: Determines if primary/standby instances are up before attempting database queries

### Health Status Calculation Function

```bash
# Function to get health status
get_health_status() {
    local primary_up=$(check_service "localhost" "5432" && echo "1" || echo "0")
    local standby_up=$(check_service "localhost" "5433" && echo "1" || echo "0")
```

- **`get_health_status()`**: Main function that calculates overall health status
- **`local primary_up=...`**: Checks if primary PostgreSQL is running
  - **`check_service "localhost" "5432"`**: Checks port 5432 (standard PostgreSQL port)
  - **`&& echo "1"`**: If check succeeds, outputs "1" (up)
  - **`|| echo "0"`**: If check fails, outputs "0" (down)
  - **Why needed**: Determines primary availability before attempting queries
- **`local standby_up=...`**: Similar check for standby on port 5433
  - **Why needed**: Determines standby availability

```bash
    local lag_bytes="0"
    local lag_seconds="0"
    
    if [ "$standby_up" = "1" ]; then
        lag_bytes=$(get_replication_lag_bytes "localhost" "5433")
        lag_seconds=$(get_replication_lag_seconds "localhost" "5433")
    fi
```

- **Initializes lag variables**: Sets defaults to "0"
- **Conditional lag calculation**: Only calculates lag if standby is up
  - **Why needed**: Avoids errors from attempting queries on down services
  - **Uses standby port 5433**: Gets lag from standby's perspective

```bash
    # Calculate health score
    local health_score=100
    
    if [ "$primary_up" = "0" ]; then
        health_score=$((health_score - 50))
    fi
    
    if [ "$standby_up" = "0" ]; then
        health_score=$((health_score - 30))
    fi
```

- **`health_score=100`**: Starts at 100 (perfect health)
- **Primary down**: Deducts 50 points (critical - no primary means no writes possible)
- **Standby down**: Deducts 30 points (important - no replication means no redundancy)
- **Why needed**: Provides single numeric health indicator for alerting

```bash
    if [ "$lag_bytes" -gt 10485760 ]; then  # > 10MB
        health_score=$((health_score - 30))
    elif [ "$lag_bytes" -gt 1048576 ]; then  # > 1MB
        health_score=$((health_score - 10))
    fi
```

- **Byte lag thresholds**:
  - **> 10MB (10485760 bytes)**: -30 points (critical lag)
  - **> 1MB (1048576 bytes)**: -10 points (warning lag)
- **`-gt`**: Greater than comparison (arithmetic comparison in bash)
- **Why needed**: High lag indicates replication problems or network issues

```bash
    if [ "$lag_seconds" -gt 30 ]; then
        health_score=$((health_score - 20))
    elif [ "$lag_seconds" -gt 5 ]; then
        health_score=$((health_score - 5))
    fi
```

- **Time lag thresholds**:
  - **> 30 seconds**: -20 points (critical time lag)
  - **> 5 seconds**: -5 points (warning time lag)
- **Why needed**: Time lag indicates processing delays, not just network issues

```bash
    # Ensure health score is between 0 and 100
    health_score=$((health_score < 0 ? 0 : health_score))
    health_score=$((health_score > 100 ? 100 : health_score))
    
    echo "$primary_up,$standby_up,$lag_bytes,$lag_seconds,$health_score"
}
```

- **Bounds checking**: Ensures score stays between 0 and 100
  - **`$((health_score < 0 ? 0 : health_score))`**: Ternary operator - if negative, use 0, else use value
  - **`$((health_score > 100 ? 100 : health_score))`**: If over 100, cap at 100
- **Returns comma-separated values**: Primary status, standby status, lag bytes, lag seconds, health score
- **Why needed**: Provides all health data in structured format for use by other functions

### JSON Response Generation Function

```bash
# Function to generate JSON response
generate_json_response() {
    local primary_up=$1
    local standby_up=$2
    local lag_bytes=$3
    local lag_seconds=$4
    local health_score=$5
    
    local status="healthy"
    local http_code=200
```

- **`generate_json_response()`**: Creates JSON-formatted health response
- **Parameters**: Receives all health data as function arguments
- **Initializes status**: Defaults to "healthy" with HTTP 200
- **Why needed**: Formats health data as JSON for API consumers

```bash
    if [ "$health_score" -lt 50 ]; then
        status="critical"
        http_code=503
    elif [ "$health_score" -lt 70 ]; then
        status="warning"
        http_code=200
    fi
```

- **Status determination**:
  - **Score < 50**: "critical" status, HTTP 503 (Service Unavailable)
  - **Score < 70**: "warning" status, HTTP 200 (OK but degraded)
  - **Score >= 70**: "healthy" status, HTTP 200
- **Why needed**: HTTP status codes allow orchestration tools to take action (e.g., restart containers)

```bash
    cat << EOF
{
  "status": "$status",
  "health_score": $health_score,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "primary": {
    "up": $([ "$primary_up" = "1" ] && echo "true" || echo "false"),
    "port": 5432
  },
  "standby": {
    "up": $([ "$standby_up" = "1" ] && echo "true" || echo "false"),
    "port": 5433
  },
  "replication": {
    "lag_bytes": $lag_bytes,
    "lag_seconds": $lag_seconds,
    "lag_mb": $(echo "scale=2; $lag_bytes/1024/1024" | bc)
  },
  "checks": {
    "primary_available": $([ "$primary_up" = "1" ] && echo "true" || echo "false"),
    "standby_available": $([ "$standby_up" = "1" ] && echo "true" || echo "false"),
    "replication_lag_acceptable": $([ "$lag_bytes" -lt 10485760 ] && echo "true" || echo "false"),
    "replication_time_acceptable": $([ "$lag_seconds" -lt 30 ] && echo "true" || echo "false")
  }
}
EOF
}
```

- **`cat << EOF`**: Here-document - outputs everything until `EOF` marker
- **JSON structure**:
  - **`status`**: Overall status string ("healthy", "warning", "critical")
  - **`health_score`**: Numeric score (0-100)
  - **`timestamp`**: ISO 8601 timestamp in UTC
    - **`date -u +%Y-%m-%dT%H:%M:%SZ`**: Formats current time as ISO 8601
  - **`primary`/`standby`**: Object with availability and port info
    - **`$([ "$primary_up" = "1" ] && echo "true" || echo "false")`**: Converts "1"/"0" to JSON boolean
  - **`replication`**: Object with lag metrics
    - **`lag_mb`**: Calculated using `bc` (basic calculator) for floating-point division
      - **`echo "scale=2; $lag_bytes/1024/1024" | bc`**: Divides bytes by 1024 twice, keeps 2 decimal places
  - **`checks`**: Object with boolean check results
    - **`replication_lag_acceptable`**: True if lag < 10MB
    - **`replication_time_acceptable`**: True if lag < 30 seconds
- **Why needed**: Provides structured, machine-readable health data for monitoring tools and dashboards

### HTTP Request Handler Function

```bash
# Function to handle HTTP requests
handle_request() {
    local method=$1
    local path=$2
    
    case "$path" in
        "/health")
```

- **`handle_request()`**: Routes HTTP requests to appropriate handlers
- **Parameters**: HTTP method and path
- **`case "$path" in`**: Bash case statement for path routing
- **Why needed**: Handles multiple endpoints with different responses

```bash
            local health_data=$(get_health_status)
            IFS=',' read -r primary_up standby_up lag_bytes lag_seconds health_score <<< "$health_data"
```

- **Gets health data**: Calls `get_health_status()` function
- **Parses CSV**: Uses `IFS=','` (Internal Field Separator) to split comma-separated values
- **`read -r ... <<< "$health_data"`**: Reads variables from string
  - **`-r`**: Raw mode (doesn't interpret backslashes)
- **Why needed**: Extracts individual values from comma-separated string

```bash
            local json_response=$(generate_json_response "$primary_up" "$standby_up" "$lag_bytes" "$lag_seconds" "$health_score")
            
            local status="healthy"
            local http_code=200
            
            if [ "$health_score" -lt 50 ]; then
                status="critical"
                http_code=503
            elif [ "$health_score" -lt 70 ]; then
                status="warning"
                http_code=200
            fi
            
            echo "HTTP/1.1 $http_code OK"
            echo "Content-Type: application/json"
            echo "Content-Length: ${#json_response}"
            echo "Cache-Control: no-cache"
            echo ""
            echo "$json_response"
            ;;
```

- **Generates JSON**: Calls `generate_json_response()` function
- **Determines HTTP status**: Same logic as in JSON generation (redundant but ensures consistency)
- **HTTP response headers**:
  - **`HTTP/1.1 $http_code OK`**: HTTP status line (e.g., "HTTP/1.1 200 OK" or "HTTP/1.1 503 OK")
  - **`Content-Type: application/json`**: Tells client response is JSON
  - **`Content-Length: ${#json_response}`**: Length of response body (required for HTTP)
    - **`${#json_response}`**: String length operator in bash
  - **`Cache-Control: no-cache`**: Prevents caching (ensures fresh health data)
  - **Empty line**: Separates headers from body (required by HTTP)
- **Outputs JSON body**: The actual JSON response
- **`;;`**: Ends case statement branch
- **Why needed**: Provides comprehensive health endpoint with proper HTTP formatting

```bash
        "/ready")
            local primary_up=$(check_service "localhost" "5432" && echo "1" || echo "0")
            local standby_up=$(check_service "localhost" "5433" && echo "1" || echo "0")
            
            if [ "$primary_up" = "1" ] && [ "$standby_up" = "1" ]; then
                echo "HTTP/1.1 200 OK"
                echo "Content-Type: text/plain"
                echo "Content-Length: 2"
                echo ""
                echo "OK"
            else
                echo "HTTP/1.1 503 Service Unavailable"
                echo "Content-Type: text/plain"
                echo "Content-Length: 13"
                echo ""
                echo "Not Ready"
            fi
            ;;
```

- **`/ready` endpoint**: Readiness check for orchestration tools
- **Checks both services**: Primary and standby must both be up
- **200 OK if ready**: Both services available
- **503 if not ready**: One or both services down
- **Simple text response**: "OK" or "Not Ready"
- **Why needed**: Kubernetes/Docker Swarm use this to determine if service is ready to receive traffic

```bash
        "/live")
            local primary_up=$(check_service "localhost" "5432" && echo "1" || echo "0")
            
            if [ "$primary_up" = "1" ]; then
                echo "HTTP/1.1 200 OK"
                echo "Content-Type: text/plain"
                echo "Content-Length: 2"
                echo ""
                echo "OK"
            else
                echo "HTTP/1.1 503 Service Unavailable"
                echo "Content-Type: text/plain"
                echo "Content-Length: 13"
                echo ""
                echo "Not Alive"
            fi
            ;;
```

- **`/live` endpoint**: Liveness check for orchestration tools
- **Checks only primary**: Primary must be up (standby optional for liveness)
- **200 OK if alive**: Primary is running
- **503 if not alive**: Primary is down
- **Why needed**: Kubernetes/Docker Swarm use this to determine if container should be restarted

```bash
        "/metrics")
            # Export Prometheus metrics
            local health_data=$(get_health_status)
            IFS=',' read -r primary_up standby_up lag_bytes lag_seconds health_score <<< "$health_data"
            
            local metrics="# HELP pg_replication_lag_bytes Replication lag in bytes
# TYPE pg_replication_lag_bytes gauge
pg_replication_lag_bytes $lag_bytes

# HELP pg_replication_lag_seconds Replication lag in seconds
# TYPE pg_replication_lag_seconds gauge
pg_replication_lag_seconds $lag_seconds

# HELP pg_primary_up Primary node availability
# TYPE pg_primary_up gauge
pg_primary_up $primary_up

# HELP pg_standby_up Standby node availability
# TYPE pg_standby_up gauge
pg_standby_up $standby_up

# HELP pg_replication_health_score Overall replication health score
# TYPE pg_replication_health_score gauge
pg_replication_health_score $health_score
"
            
            echo "HTTP/1.1 200 OK"
            echo "Content-Type: text/plain"
            echo "Content-Length: ${#metrics}"
            echo ""
            echo "$metrics"
            ;;
```

- **`/metrics` endpoint**: Prometheus-compatible metrics endpoint
- **Prometheus format**:
  - **`# HELP`**: Documentation for the metric
  - **`# TYPE`**: Metric type (gauge, counter, histogram)
  - **`metric_name value`**: Actual metric with value
- **Exposed metrics**:
  - **`pg_replication_lag_bytes`**: Lag in bytes
  - **`pg_replication_lag_seconds`**: Lag in seconds
  - **`pg_primary_up`**: Primary availability (1=up, 0=down)
  - **`pg_standby_up`**: Standby availability (1=up, 0=down)
  - **`pg_replication_health_score`**: Health score (0-100)
- **Why needed**: Allows Prometheus to scrape metrics for monitoring and alerting

```bash
        *)
            echo "HTTP/1.1 404 Not Found"
            echo "Content-Type: text/plain"
            echo "Content-Length: 9"
            echo ""
            echo "Not Found"
            ;;
    esac
}
```

- **Default case**: Handles unknown paths
- **404 Not Found**: Standard HTTP response for unknown endpoints
- **Why needed**: Proper HTTP error handling for invalid requests

### HTTP Server Startup Function

```bash
# Function to start HTTP server
start_server() {
    echo "Starting PostgreSQL Replication Health Check Server on port $PORT"
    echo "Available endpoints:"
    echo "  GET /health  - Comprehensive health check with JSON response"
    echo "  GET /ready   - Readiness check (both nodes must be up)"
    echo "  GET /live    - Liveness check (primary must be up)"
    echo "  GET /metrics - Prometheus metrics"
    echo ""
```

- **`start_server()`**: Main function that runs the HTTP server
- **Startup messages**: Informs user about available endpoints
- **Why needed**: Provides documentation and confirms server is starting

```bash
    # Simple HTTP server using netcat
    while true; do
        echo "Listening on port $PORT..."
        {
            # Read HTTP request
            read -r request_line
            read -r headers
```

- **Infinite loop**: Server runs continuously
- **`nc -l -p $PORT`**: Netcat listens on specified port
  - **`-l`**: Listen mode
  - **`-p $PORT`**: Port to listen on
- **`read -r request_line`**: Reads first line of HTTP request (e.g., "GET /health HTTP/1.1")
  - **`-r`**: Raw mode (doesn't interpret backslashes)
- **`read -r headers`**: Reads HTTP headers (simplified - only reads one line)
  - **Note**: Real HTTP servers read all headers, but this simplified version works for basic use
- **Why needed**: Creates a simple HTTP server without external dependencies

```bash
            # Parse request
            IFS=' ' read -r method path version <<< "$request_line"
            
            # Handle request
            handle_request "$method" "$path"
        } | nc -l -p $PORT
    done
}
```

- **Parses request line**: Splits "GET /health HTTP/1.1" into method, path, version
  - **`IFS=' '`**: Sets space as field separator
  - **`read -r method path version`**: Extracts three parts
- **Calls handler**: Routes to `handle_request()` function
- **Pipes to netcat**: Output from handler goes to netcat, which sends it to client
- **Why needed**: Simple HTTP server implementation using basic Unix tools

### Single Health Check Function

```bash
# Function to run single health check
run_health_check() {
    local health_data=$(get_health_status)
    IFS=',' read -r primary_up standby_up lag_bytes lag_seconds health_score <<< "$health_data"
    
    echo "Primary: $([ "$primary_up" = "1" ] && echo "UP" || echo "DOWN")"
    echo "Standby: $([ "$standby_up" = "1" ] && echo "UP" || echo "DOWN")"
    echo "Replication Lag: $lag_bytes bytes ($(echo "scale=2; $lag_bytes/1024/1024" | bc) MB)"
    echo "Replication Lag: $lag_seconds seconds"
    echo "Health Score: $health_score/100"
```

- **`run_health_check()`**: Performs single health check and prints results
- **Gets health data**: Same as HTTP endpoints
- **Formatted output**: Human-readable status messages
  - **Primary/Standby status**: "UP" or "DOWN"
  - **Lag in bytes and MB**: Both formats for readability
  - **Lag in seconds**: Time-based lag
  - **Health score**: Numeric score out of 100
- **Why needed**: Allows script to be used for one-time checks (useful for scripts, cron jobs)

```bash
    if [ "$health_score" -lt 50 ]; then
        echo "Status: CRITICAL"
        exit 1
    elif [ "$health_score" -lt 70 ]; then
        echo "Status: WARNING"
        exit 0
    else
        echo "Status: HEALTHY"
        exit 0
    fi
}
```

- **Exit codes based on health**:
  - **Score < 50**: CRITICAL, exit code 1 (failure)
  - **Score < 70**: WARNING, exit code 0 (success but degraded)
  - **Score >= 70**: HEALTHY, exit code 0 (success)
- **Why needed**: Allows script to be used in monitoring systems that check exit codes

### Main Execution Logic

```bash
# Main execution
case "${1:-server}" in
    "server")
        start_server
        ;;
    "check")
        run_health_check
        ;;
    *)
        echo "Usage: $0 {server|check}"
        echo ""
        echo "Commands:"
        echo "  server - Start HTTP health check server"
        echo "  check  - Run single health check and exit"
        exit 1
        ;;
esac
```

- **`case "${1:-server}" in`**: Checks first command-line argument
  - **`${1:-server}`**: Uses first argument if provided, defaults to "server"
- **`"server")`**: If argument is "server", start HTTP server
- **`"check")`**: If argument is "check", run single health check
- **Default case**: Shows usage message and exits with error
- **Why needed**: Allows script to operate in two modes - persistent server or one-time check

## How the Health Check Server Works

1. **Server Mode** (`./health-check-server.sh server`):
   - Starts HTTP server on port 8080 (or configured port)
   - Listens for HTTP requests using netcat
   - Routes requests to appropriate handlers based on path
   - Returns JSON, text, or Prometheus metrics based on endpoint

2. **Check Mode** (`./health-check-server.sh check`):
   - Performs single health check
   - Prints human-readable results
   - Exits with appropriate exit code (0=healthy, 1=critical)

3. **Health Calculation**:
   - Checks primary and standby availability (port connectivity)
   - Calculates replication lag (bytes and seconds) from standby
   - Computes health score based on availability and lag thresholds
   - Returns structured data (JSON or Prometheus format)

## Important Notes

- **Simple HTTP Server**: Uses netcat - not production-grade (no proper header parsing, connection handling)
- **Port Connectivity**: Uses `nc -z` for fast availability checks (doesn't verify PostgreSQL protocol)
- **Lag Calculation**: Queries standby database - requires standby to be accessible
- **Health Score**: Composite metric - check individual components for detailed diagnosis
- **Exit Codes**: Used by monitoring systems and orchestration tools
- **Dependencies**: Requires `psql`, `nc` (netcat), and `bc` (for calculations

## Usage Examples

### Start HTTP Server
```bash
./health-check-server.sh server
```

### Run Single Check
```bash
./health-check-server.sh check
```

### With Environment Variables
```bash
export POSTGRES_PASSWORD=your_password
export HEALTH_CHECK_PORT=9090
./health-check-server.sh server
```

### Access Endpoints
```bash
# Comprehensive health check
curl http://localhost:8080/health

# Readiness check
curl http://localhost:8080/ready

# Liveness check
curl http://localhost:8080/live

# Prometheus metrics
curl http://localhost:8080/metrics
```

### In Docker/Kubernetes
The `/ready` and `/live` endpoints are designed for orchestration tools:
- **Kubernetes**: Uses `/ready` for readiness probe, `/live` for liveness probe
- **Docker Swarm**: Can use these endpoints for health checks

## Troubleshooting

- **Connection Refused**: Verify PostgreSQL instances are running and ports are correct
- **Permission Denied**: Ensure script is executable (`chmod +x health-check-server.sh`)
- **Command Not Found**: Install required tools (`psql`, `nc`, `bc`)
- **Port Already in Use**: Change `HEALTH_CHECK_PORT` environment variable
- **No Lag Data**: Verify standby is accessible and replication is active
- **High Lag**: Investigate network issues, standby performance, or WAL volume

