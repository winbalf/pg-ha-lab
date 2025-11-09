#!/bin/bash
# PostgreSQL Replication Health Check Endpoint
# Returns HTTP status codes based on replication health

set -e

# Configuration
POSTGRES_USER=${POSTGRES_USER:-postgres}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-secure_password_123}
POSTGRES_DB=${POSTGRES_DB:-testdb}
PORT=${HEALTH_CHECK_PORT:-8080}

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

# Function to check if service is running
check_service() {
    local host=$1
    local port=$2
    
    nc -z $host $port 2>/dev/null
}

# Function to get health status
get_health_status() {
    local primary_up=$(check_service "localhost" "5432" && echo "1" || echo "0")
    local standby_up=$(check_service "localhost" "5433" && echo "1" || echo "0")
    
    local lag_bytes="0"
    local lag_seconds="0"
    
    if [ "$standby_up" = "1" ]; then
        lag_bytes=$(get_replication_lag_bytes "localhost" "5433")
        lag_seconds=$(get_replication_lag_seconds "localhost" "5433")
    fi
    
    # Calculate health score
    local health_score=100
    
    if [ "$primary_up" = "0" ]; then
        health_score=$((health_score - 50))
    fi
    
    if [ "$standby_up" = "0" ]; then
        health_score=$((health_score - 30))
    fi
    
    if [ "$lag_bytes" -gt 10485760 ]; then  # > 10MB
        health_score=$((health_score - 30))
    elif [ "$lag_bytes" -gt 1048576 ]; then  # > 1MB
        health_score=$((health_score - 10))
    fi
    
    if [ "$lag_seconds" -gt 30 ]; then
        health_score=$((health_score - 20))
    elif [ "$lag_seconds" -gt 5 ]; then
        health_score=$((health_score - 5))
    fi
    
    # Ensure health score is between 0 and 100
    health_score=$((health_score < 0 ? 0 : health_score))
    health_score=$((health_score > 100 ? 100 : health_score))
    
    echo "$primary_up,$standby_up,$lag_bytes,$lag_seconds,$health_score"
}

# Function to generate JSON response
generate_json_response() {
    local primary_up=$1
    local standby_up=$2
    local lag_bytes=$3
    local lag_seconds=$4
    local health_score=$5
    
    local status="healthy"
    local http_code=200
    
    if [ "$health_score" -lt 50 ]; then
        status="critical"
        http_code=503
    elif [ "$health_score" -lt 70 ]; then
        status="warning"
        http_code=200
    fi
    
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

# Function to handle HTTP requests
handle_request() {
    local method=$1
    local path=$2
    
    case "$path" in
        "/health")
            local health_data=$(get_health_status)
            IFS=',' read -r primary_up standby_up lag_bytes lag_seconds health_score <<< "$health_data"
            
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
        *)
            echo "HTTP/1.1 404 Not Found"
            echo "Content-Type: text/plain"
            echo "Content-Length: 9"
            echo ""
            echo "Not Found"
            ;;
    esac
}

# Function to start HTTP server
start_server() {
    echo "Starting PostgreSQL Replication Health Check Server on port $PORT"
    echo "Available endpoints:"
    echo "  GET /health  - Comprehensive health check with JSON response"
    echo "  GET /ready   - Readiness check (both nodes must be up)"
    echo "  GET /live    - Liveness check (primary must be up)"
    echo "  GET /metrics - Prometheus metrics"
    echo ""
    
    # Simple HTTP server using netcat
    while true; do
        echo "Listening on port $PORT..."
        {
            # Read HTTP request
            read -r request_line
            read -r headers
            
            # Parse request
            IFS=' ' read -r method path version <<< "$request_line"
            
            # Handle request
            handle_request "$method" "$path"
        } | nc -l -p $PORT
    done
}

# Function to run single health check
run_health_check() {
    local health_data=$(get_health_status)
    IFS=',' read -r primary_up standby_up lag_bytes lag_seconds health_score <<< "$health_data"
    
    echo "Primary: $([ "$primary_up" = "1" ] && echo "UP" || echo "DOWN")"
    echo "Standby: $([ "$standby_up" = "1" ] && echo "UP" || echo "DOWN")"
    echo "Replication Lag: $lag_bytes bytes ($(echo "scale=2; $lag_bytes/1024/1024" | bc) MB)"
    echo "Replication Lag: $lag_seconds seconds"
    echo "Health Score: $health_score/100"
    
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
