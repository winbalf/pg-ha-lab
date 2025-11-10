#!/bin/sh
# pgBadger Entrypoint Script

# Create directories if they don't exist
if [ ! -d /var/log/postgresql ]; then
  mkdir /var/log/postgresql
fi

if [ ! -d /var/www/html ]; then
  mkdir /var/www/html
fi

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

echo 'pgBadger started, waiting for PostgreSQL logs...'

while true; do
  if [ -f /var/log/postgresql/postgresql-primary.log ] && [ -s /var/log/postgresql/postgresql-primary.log ]; then
    echo 'Processing primary logs...'
    pgbadger -f stderr -o /var/www/html/primary-report.html /var/log/postgresql/postgresql-primary.log || true
  else
    echo 'Primary log file not found or empty, creating placeholder...'
    echo '<html><body><h1>pgBadger - Primary Report</h1><p>No logs available yet. PostgreSQL logs will appear here once generated.</p><p>Last checked: ' $(date) '</p></body></html>' > /var/www/html/primary-report.html
  fi
  
  if [ -f /var/log/postgresql/postgresql-standby.log ] && [ -s /var/log/postgresql/postgresql-standby.log ]; then
    echo 'Processing standby logs...'
    pgbadger -f stderr -o /var/www/html/standby-report.html /var/log/postgresql/postgresql-standby.log || true
  else
    echo 'Standby log file not found or empty, creating placeholder...'
    echo '<html><body><h1>pgBadger - Standby Report</h1><p>No logs available yet. PostgreSQL logs will appear here once generated.</p><p>Last checked: ' $(date) '</p></body></html>' > /var/www/html/standby-report.html
  fi
  
  echo 'Reports updated at ' $(date)
  sleep 300
done

