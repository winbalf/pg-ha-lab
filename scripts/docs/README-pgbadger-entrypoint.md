# pgbadger-entrypoint.sh - pgBadger Log Analysis Entrypoint

This shell script serves as the entrypoint for the pgBadger Docker container. It continuously monitors PostgreSQL log files and generates HTML analysis reports for both primary and standby nodes, making them available via a web interface.

## Overview

The pgBadger entrypoint script:
1. Ensures required directories exist for logs and reports
2. Installs and configures lighttpd web server to serve reports
3. Continuously monitors PostgreSQL log files for both primary and standby nodes
4. Generates HTML analysis reports using pgBadger when logs are available
5. Creates placeholder HTML pages when logs are not yet available
6. Updates reports every 5 minutes (300 seconds)
7. Runs indefinitely until the container is stopped

## Line-by-Line Explanation

### Script Header

```bash
#!/bin/sh
# pgBadger Entrypoint Script
```

- **`#!/bin/sh`**: Shebang tells the system to use `/bin/sh` (POSIX shell) to execute this script
  - **Why `/bin/sh`**: Lightweight and widely available, suitable for Alpine-based containers
  - **Why needed**: Ensures the script runs with the correct interpreter
- **`# pgBadger Entrypoint Script`**: Comment describing the script's purpose
  - **Why needed**: Documentation for developers reading the code

### Create PostgreSQL Log Directory

```bash
# Create directories if they don't exist
if [ ! -d /var/log/postgresql ]; then
  mkdir /var/log/postgresql
fi
```

- **`# Create directories if they don't exist`**: Comment explaining the purpose of this section
  - **Why needed**: Clarifies that we're ensuring directories exist before use
- **`if [ ! -d /var/log/postgresql ]; then`**: Conditional check for directory existence
  - **`[ ! -d /var/log/postgresql ]`**: Tests if `/var/log/postgresql` does NOT exist (`-d` checks for directory, `!` negates)
  - **Why needed**: Avoids errors when trying to access log files in a non-existent directory
- **`mkdir /var/log/postgresql`**: Creates the PostgreSQL log directory
  - **Why needed**: PostgreSQL containers write logs to this location, which is mounted as a volume
  - **Path**: `/var/log/postgresql` is the standard location for PostgreSQL log files
- **`fi`**: Closes the `if` statement
  - **Why needed**: Required syntax to complete the conditional block

### Create Web Report Directory

```bash
if [ ! -d /var/www/html ]; then
  mkdir /var/www/html
fi
```

- **`if [ ! -d /var/www/html ]; then`**: Checks if web directory exists
  - **Why needed**: pgBadger generates HTML reports that need to be served via web server
- **`mkdir /var/www/html`**: Creates the web root directory
  - **Why needed**: This is where pgBadger writes HTML reports and where the web server serves them from
  - **Path**: `/var/www/html` is the standard web root for Apache/Nginx in containers
- **`fi`**: Closes the `if` statement

### Install and Configure Web Server

```bash
# Install and start lighttpd web server
echo 'Installing and starting lighttpd web server...'
apk add --no-cache lighttpd > /dev/null 2>&1

# Create lighttpd config directory if it doesn't exist
mkdir -p /etc/lighttpd
mkdir -p /var/log/lighttpd

# Configure lighttpd to serve /var/www/html on port 80
cat > /etc/lighttpd/lighttpd.conf <<EOF
server.modules = ()
server.document-root = "/var/www/html"
server.port = 80
server.username = "nobody"
server.groupname = "nobody"
index-file.names = ("index.html", "primary-report.html", "standby-report.html")
dir-listing.activate = "enable"
EOF

# Start lighttpd in background
lighttpd -f /etc/lighttpd/lighttpd.conf -D &
echo 'Web server started on port 80'
```

- **`echo 'Installing and starting lighttpd web server...'`**: Status message indicating web server setup
  - **Why needed**: Provides feedback that the web server is being installed
- **`apk add --no-cache lighttpd > /dev/null 2>&1`**: Installs lighttpd web server
  - **`apk add`**: Alpine package manager command to install packages
  - **`--no-cache`**: Prevents caching package index (saves space in container)
  - **`lighttpd`**: Lightweight web server suitable for serving static HTML files
  - **`> /dev/null 2>&1`**: Suppresses output (redirects stdout and stderr to /dev/null)
  - **Why needed**: Automatically installs web server to serve pgBadger reports
  - **Why lighttpd**: Lightweight, fast, and perfect for serving static HTML reports
- **`mkdir -p /etc/lighttpd`**: Creates lighttpd configuration directory
  - **`-p`**: Creates parent directories if needed, no error if directory exists
  - **Why needed**: lighttpd requires a config directory for its configuration file
- **`mkdir -p /var/log/lighttpd`**: Creates lighttpd log directory
  - **Why needed**: lighttpd may write logs to this location
- **`cat > /etc/lighttpd/lighttpd.conf <<EOF`**: Creates lighttpd configuration file using heredoc
  - **`cat >`**: Writes content to file (overwrites if exists)
  - **`<<EOF`**: Heredoc syntax - everything until `EOF` is written to the file
  - **Why needed**: Configures lighttpd to serve reports from the correct directory
- **`server.modules = ()`**: Empty modules list (minimal configuration)
  - **Why needed**: For basic static file serving, no additional modules needed
- **`server.document-root = "/var/www/html"`**: Sets web root directory
  - **Why needed**: Tells lighttpd where to serve files from (where pgBadger writes reports)
- **`server.port = 80`**: Sets HTTP port to 80
  - **Why needed**: Standard HTTP port, mapped to host port 8081 in docker-compose
- **`server.username = "nobody"`**: Runs lighttpd as unprivileged user
  - **Why needed**: Security best practice - web server doesn't need root privileges
- **`server.groupname = "nobody"`**: Sets group to unprivileged group
  - **Why needed**: Security best practice
- **`index-file.names = ("index.html", "primary-report.html", "standby-report.html")`**: Sets index files
  - **Why needed**: Allows direct access to reports via root URL or specific report names
  - **User benefit**: Can access reports without specifying full filename
- **`dir-listing.activate = "enable"`**: Enables directory listing
  - **Why needed**: Allows browsing available reports if index files don't exist
  - **User benefit**: Can see all available reports in the directory
- **`EOF`**: Marks end of heredoc
  - **Why needed**: Closes the configuration file content
- **`lighttpd -f /etc/lighttpd/lighttpd.conf -D &`**: Starts lighttpd in background
  - **`-f /etc/lighttpd/lighttpd.conf`**: Specifies configuration file path
  - **`-D`**: Runs in foreground mode (but `&` puts it in background)
  - **`&`**: Runs process in background
  - **Why needed**: Starts web server so reports are accessible via HTTP
  - **Background execution**: Allows script to continue to log processing loop
- **`echo 'Web server started on port 80'`**: Confirmation message
  - **Why needed**: Provides feedback that web server is running

### Initial Status Message

```bash
echo 'pgBadger started, waiting for PostgreSQL logs...'
```

- **`echo 'pgBadger started, waiting for PostgreSQL logs...'`**: Prints startup message
  - **Why needed**: Provides feedback that the service has started and is waiting for log files to appear
  - **User benefit**: Helps users understand the service is running but waiting for data

### Main Processing Loop

```bash
while true; do
```

- **`while true`**: Creates an infinite loop that runs continuously
  - **Why needed**: Continuously monitors log files and regenerates reports as new logs arrive
  - **Exit condition**: Container must be stopped (no graceful exit in this script)

### Primary Log File Check

```bash
  if [ -f /var/log/postgresql/postgresql-primary.log ] && [ -s /var/log/postgresql/postgresql-primary.log ]; then
```

- **`if [ -f /var/log/postgresql/postgresql-primary.log ]`**: Checks if primary log file exists
  - **`[ -f ... ]`**: File test operator - returns true if file exists and is a regular file
  - **Why needed**: Avoids errors when trying to process non-existent files
- **`&&`**: Logical AND operator - both conditions must be true
  - **Why needed**: Ensures we only process files that both exist AND have content
- **`[ -s /var/log/postgresql/postgresql-primary.log ]`**: Checks if file has non-zero size
  - **`[ -s ... ]`**: File test operator - returns true if file exists and has size > 0
  - **Why needed**: Empty log files would generate empty reports - we skip processing them
- **`then`**: Begins the block executed when conditions are met

### Process Primary Logs

```bash
    echo 'Processing primary logs...'
    pgbadger -f stderr -o /var/www/html/primary-report.html /var/log/postgresql/postgresql-primary.log || true
```

- **`echo 'Processing primary logs...'`**: Status message indicating processing has started
  - **Why needed**: Provides feedback that pgBadger is working on the primary logs
- **`pgbadger`**: PostgreSQL log analyzer tool
  - **Why needed**: Parses PostgreSQL logs and generates comprehensive HTML reports
- **`-f stderr`**: Specifies log format as stderr (standard error output)
  - **Why needed**: PostgreSQL is configured to write logs to stderr, so we must tell pgBadger this format
  - **Alternative formats**: Could be `syslog`, `csvlog`, etc., but stderr is most common in containers
- **`-o /var/www/html/primary-report.html`**: Output file path for the HTML report
  - **`-o`**: Output file option
  - **Why needed**: Specifies where to write the generated report (web-accessible location)
- **`/var/log/postgresql/postgresql-primary.log`**: Input log file to analyze
  - **Why needed**: Source of log data to analyze
- **`|| true`**: Error suppression - if pgbadger fails, continue execution
  - **`||`**: Logical OR - executes right side if left side fails
  - **`true`**: Always succeeds (no-op command)
  - **Why needed**: Prevents script from exiting if pgBadger encounters errors (e.g., malformed log entries)
  - **Trade-off**: Errors are silently ignored, but script continues running

### Primary Log Placeholder

```bash
  else
    echo 'Primary log file not found or empty, creating placeholder...'
    echo '<html><body><h1>pgBadger - Primary Report</h1><p>No logs available yet. PostgreSQL logs will appear here once generated.</p><p>Last checked: ' $(date) '</p></body></html>' > /var/www/html/primary-report.html
  fi
```

- **`else`**: Executes when log file doesn't exist or is empty
  - **Why needed**: Handles the case where PostgreSQL hasn't generated logs yet
- **`echo 'Primary log file not found or empty, creating placeholder...'`**: Status message
  - **Why needed**: Informs that a placeholder is being created instead of a real report
- **`echo '<html>...' > /var/www/html/primary-report.html`**: Creates placeholder HTML file
  - **HTML structure**: Basic HTML with title and message
  - **`<h1>pgBadger - Primary Report</h1>`**: Page title identifying this as the primary report
  - **`<p>No logs available yet...`**: User-friendly message explaining why no report is available
  - **`$(date)`**: Command substitution - inserts current timestamp
  - **Why needed**: Shows when the placeholder was last checked/updated
  - **`> /var/www/html/primary-report.html`**: Redirects output to file (overwrites if exists)
  - **Why needed**: Ensures web server always has a file to serve, even when logs aren't available yet
- **`fi`**: Closes the primary log processing `if` statement

### Standby Log File Check

```bash
  if [ -f /var/log/postgresql/postgresql-standby.log ] && [ -s /var/log/postgresql/postgresql-standby.log ]; then
```

- **Same pattern as primary**: Checks if standby log file exists and has content
  - **Why needed**: Standby node writes to a different log file (`postgresql-standby.log`)
  - **Parallel processing**: Processes both primary and standby logs in each loop iteration

### Process Standby Logs

```bash
    echo 'Processing standby logs...'
    pgbadger -f stderr -o /var/www/html/standby-report.html /var/log/postgresql/postgresql-standby.log || true
```

- **Same pattern as primary**: Processes standby logs with identical pgBadger options
  - **`-o /var/www/html/standby-report.html`**: Different output file for standby report
  - **Why needed**: Keeps primary and standby reports separate for easy comparison
- **`|| true`**: Same error suppression as primary
  - **Why needed**: Prevents script failure if standby logs have issues

### Standby Log Placeholder

```bash
  else
    echo 'Standby log file not found or empty, creating placeholder...'
    echo '<html><body><h1>pgBadger - Standby Report</h1><p>No logs available yet. PostgreSQL logs will appear here once generated.</p><p>Last checked: ' $(date) '</p></body></html>' > /var/www/html/standby-report.html
  fi
```

- **Same pattern as primary placeholder**: Creates standby-specific placeholder
  - **Why needed**: Ensures standby report page is always available, even before logs exist
- **Different title**: "Standby Report" instead of "Primary Report"
  - **Why needed**: Users can distinguish between primary and standby reports

### Status Update and Sleep

```bash
  echo 'Reports updated at ' $(date)
  sleep 300
```

- **`echo 'Reports updated at ' $(date)`**: Prints timestamp of last update
  - **Why needed**: Provides feedback that processing cycle completed and when
  - **User benefit**: Helps users know reports are being refreshed
- **`sleep 300`**: Pauses execution for 300 seconds (5 minutes)
  - **Why needed**: Controls how frequently reports are regenerated
  - **Balance**: 5 minutes balances freshness with system load (pgBadger can be CPU-intensive)
  - **Consideration**: Longer sleep = less frequent updates but lower CPU usage

### Loop Closure

```bash
done
```

- **`done`**: Closes the `while true` loop
  - **Why needed**: Completes the infinite loop structure, causing the script to repeat after sleep

## Usage

The script is designed to run as a Docker container entrypoint with:
- pgBadger tool installed (via `dalibo/pgbadger` image)
- Volume mount: `/var/log/postgresql` (PostgreSQL logs from primary and standby)
- Volume mount: `/var/www/html` (web-accessible reports directory)
- lighttpd web server automatically installed and configured to serve files from `/var/www/html` on port 80

## File Structure

The script expects:
- **Input**: `/var/log/postgresql/postgresql-primary.log` and `/var/log/postgresql/postgresql-standby.log`
- **Output**: `/var/www/html/primary-report.html` and `/var/www/html/standby-report.html`

## Update Frequency

Reports are regenerated every **5 minutes (300 seconds)**. This means:
- New log entries may take up to 5 minutes to appear in reports
- System load is manageable (not constantly processing)
- Reports are reasonably fresh for monitoring purposes

## Error Handling

The script uses `|| true` to prevent failures:
- **Benefit**: Script continues running even if pgBadger encounters errors
- **Trade-off**: Errors are silently ignored (not logged or reported)
- **Use case**: Suitable for production where service continuity is more important than perfect reports

## Web Access

Once reports are generated, they are accessible via:
- Primary report: `http://container-ip:8081/primary-report.html`
- Standby report: `http://container-ip:8081/standby-report.html`

The container exposes port 80 (mapped to host port 8081) serving the `/var/www/html` directory.

## Testing Reports

A test script is available to verify that pgBadger reports are accessible and working correctly:

### Running the Test Script

```bash
# From the project root directory
./scripts/test-pgbadger-reports.sh
```

### What the Test Script Does

The `test-pgbadger-reports.sh` script performs comprehensive validation:

1. **Container Status Check**: Verifies that the `pgbadger-lab` container is running
   - Exits with error if container is not running
   - Provides command to start the container if needed

2. **HTTP Accessibility Test**: Tests if reports are accessible via HTTP
   - Checks primary report: `http://localhost:8081/primary-report.html`
   - Checks standby report: `http://localhost:8081/standby-report.html`
   - Verifies HTTP response codes (200 = success)
   - Displays report file sizes

3. **File Existence Check**: Verifies report files exist in the container
   - Checks `/var/www/html/primary-report.html`
   - Checks `/var/www/html/standby-report.html`
   - Displays file sizes from container filesystem

4. **Web Server Status Check**: Verifies lighttpd is running
   - Checks for lighttpd process
   - Also checks for httpd/nginx as fallback
   - Provides restart suggestion if web server is not running

5. **Summary Output**: Provides access URLs and troubleshooting tips
   - Localhost URLs for browser access
   - Network IP URLs for remote access
   - curl command examples for testing

### Example Test Output

```
==========================================
Testing pgBadger Reports Accessibility
==========================================

✓ Container 'pgbadger-lab' is running
Container IP: 172.18.0.7
Host port mapping: localhost:8081 -> container:80

Testing Primary Report...
URL: http://localhost:8081/primary-report.html
✓ Primary report is accessible (HTTP 200)
  Report size: 15234 bytes

Testing Standby Report...
URL: http://localhost:8081/standby-report.html
✓ Standby report is accessible (HTTP 200)
  Report size: 12890 bytes

Checking files in container...
✓ Primary report file exists (15234 bytes)
✓ Standby report file exists (12890 bytes)

Checking web server status...
✓ lighttpd web server is running

==========================================
Summary
==========================================

Access reports from your browser:
  Primary:  http://localhost:8081/primary-report.html
  Standby:  http://localhost:8081/standby-report.html

Or from another machine on your network:
  Primary:  http://YOUR_HOST_IP:8081/primary-report.html
  Standby:  http://YOUR_HOST_IP:8081/standby-report.html

To test with curl:
  curl http://localhost:8081/primary-report.html | head -20
  curl http://localhost:8081/standby-report.html | head -20
```

### Troubleshooting with the Test Script

The script provides helpful diagnostics for common issues:

- **Container not running**: Script exits with error and suggests: `docker-compose up -d pgbadger-lab`
- **HTTP 404 or 000**: Reports may not be generated yet (wait a few minutes for first generation)
- **Web server not running**: Suggests restarting the container: `docker-compose restart pgbadger-lab`
- **Files don't exist**: Indicates pgBadger hasn't processed logs yet or logs are empty

### When to Use the Test Script

Use the test script:
- After starting the pgBadger container for the first time
- When reports are not accessible in your browser
- To verify web server is running correctly
- To check if reports have been generated
- For troubleshooting report accessibility issues
- As part of automated testing/validation

The script is safe to run multiple times and provides real-time status of the pgBadger setup.

