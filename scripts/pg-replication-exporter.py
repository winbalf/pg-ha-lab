#!/usr/bin/env python3
"""
Custom PostgreSQL Replication Metrics Exporter
Provides additional replication-specific metrics for Prometheus
"""

import os
import sys
import time
import psycopg2
import psycopg2.extras
from prometheus_client import start_http_server, Gauge, Counter, Histogram
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Prometheus metrics
pg_replication_lag_bytes = Gauge('pg_replication_lag_bytes', 'Replication lag in bytes', ['instance'])
pg_replication_lag_seconds = Gauge('pg_replication_lag_seconds', 'Replication lag in seconds', ['instance'])
pg_replication_lag_mb = Gauge('pg_replication_lag_mb', 'Replication lag in megabytes', ['instance'])
pg_replication_connections = Gauge('pg_replication_connections', 'Number of replication connections', ['instance'])
pg_replication_sync_state = Gauge('pg_replication_sync_state', 'Replication sync state (0=async, 1=sync)', ['instance', 'client_addr'])
pg_wal_senders = Gauge('pg_wal_senders', 'Number of WAL senders', ['instance'])
pg_wal_receivers = Gauge('pg_wal_receivers', 'Number of WAL receivers', ['instance'])
pg_wal_generation_rate = Gauge('pg_wal_generation_rate', 'WAL generation rate in bytes per second', ['instance'])
pg_replication_slots_total = Gauge('pg_replication_slots_total', 'Total number of replication slots', ['instance'])
pg_replication_slots_active = Gauge('pg_replication_slots_active', 'Number of active replication slots', ['instance'])
pg_replication_slots_inactive = Gauge('pg_replication_slots_inactive', 'Number of inactive replication slots', ['instance'])
pg_replication_health_score = Gauge('pg_replication_health_score', 'Overall replication health score (0-100)', ['instance'])
pg_data_consistency_check = Gauge('pg_data_consistency_check', 'Data consistency check result (1=consistent, 0=inconsistent)', ['instance'])

# Database connection configuration
DB_CONFIG = {
    'primary': {
        'host': os.getenv('PRIMARY_HOST', 'localhost'),
        'port': os.getenv('PRIMARY_PORT', '5432'),
        'database': os.getenv('POSTGRES_DB', 'testdb'),
        'user': os.getenv('POSTGRES_USER', 'postgres'),
        'password': os.getenv('POSTGRES_PASSWORD', 'secure_password_123')
    },
    'standby': {
        'host': os.getenv('STANDBY_HOST', 'localhost'),
        'port': os.getenv('STANDBY_PORT', '5433'),
        'database': os.getenv('POSTGRES_DB', 'testdb'),
        'user': os.getenv('POSTGRES_USER', 'postgres'),
        'password': os.getenv('POSTGRES_PASSWORD', 'secure_password_123')
    }
}

def get_db_connection(instance):
    """Get database connection for specified instance"""
    config = DB_CONFIG[instance]
    try:
        conn = psycopg2.connect(
            host=config['host'],
            port=config['port'],
            database=config['database'],
            user=config['user'],
            password=config['password']
        )
        return conn
    except psycopg2.Error as e:
        logger.error(f"Failed to connect to {instance}: {e}")
        return None

def get_replication_lag_metrics(instance, conn):
    """Get replication lag metrics"""
    try:
        cursor = conn.cursor()
        
        if instance == 'primary':
            # Get lag from primary perspective
            cursor.execute("""
                SELECT 
                    COALESCE(
                        pg_wal_lsn_diff(
                            pg_current_wal_lsn(),
                            MIN(replay_lsn)
                        ), 0
                    ) as lag_bytes,
                    COALESCE(
                        EXTRACT(EPOCH FROM (
                            now() - MIN(pg_last_xact_replay_timestamp())
                        )), 0
                    ) as lag_seconds
                FROM pg_stat_replication;
            """)
        else:
            # Get lag from standby perspective
            cursor.execute("""
                SELECT 
                    COALESCE(
                        pg_wal_lsn_diff(
                            pg_last_wal_receive_lsn(),
                            pg_last_wal_replay_lsn()
                        ), 0
                    ) as lag_bytes,
                    COALESCE(
                        EXTRACT(EPOCH FROM (
                            now() - pg_last_xact_replay_timestamp()
                        )), 0
                    ) as lag_seconds;
            """)
        
        result = cursor.fetchone()
        if result:
            lag_bytes, lag_seconds = result
            lag_mb = lag_bytes / (1024 * 1024)
            
            pg_replication_lag_bytes.labels(instance=instance).set(lag_bytes)
            pg_replication_lag_seconds.labels(instance=instance).set(lag_seconds)
            pg_replication_lag_mb.labels(instance=instance).set(lag_mb)
            
            logger.debug(f"{instance} replication lag: {lag_bytes} bytes, {lag_seconds} seconds")
        
        cursor.close()
        
    except psycopg2.Error as e:
        logger.error(f"Failed to get replication lag metrics for {instance}: {e}")

def get_replication_connection_metrics(instance, conn):
    """Get replication connection metrics"""
    try:
        cursor = conn.cursor()
        
        if instance == 'primary':
            # Count replication connections from primary
            cursor.execute("""
                SELECT 
                    COUNT(*) as connection_count,
                    COUNT(*) FILTER (WHERE sync_state = 'sync') as sync_count
                FROM pg_stat_replication;
            """)
            
            result = cursor.fetchone()
            if result:
                total_connections, sync_connections = result
                pg_replication_connections.labels(instance=instance).set(total_connections)
                
                # Set sync state (1 if any sync connections, 0 otherwise)
                sync_state = 1 if sync_connections > 0 else 0
                pg_replication_sync_state.labels(instance=instance, client_addr='all').set(sync_state)
            
            # Get individual sync states
            cursor.execute("""
                SELECT 
                    client_addr,
                    CASE WHEN sync_state = 'sync' THEN 1 ELSE 0 END as sync_state
                FROM pg_stat_replication;
            """)
            
            for row in cursor.fetchall():
                client_addr, sync_state = row
                pg_replication_sync_state.labels(instance=instance, client_addr=str(client_addr)).set(sync_state)
        
        cursor.close()
        
    except psycopg2.Error as e:
        logger.error(f"Failed to get replication connection metrics for {instance}: {e}")

def get_wal_metrics(instance, conn):
    """Get WAL-related metrics"""
    try:
        cursor = conn.cursor()
        
        if instance == 'primary':
            # WAL senders count
            cursor.execute("SELECT COUNT(*) FROM pg_stat_replication;")
            wal_senders = cursor.fetchone()[0]
            pg_wal_senders.labels(instance=instance).set(wal_senders)
            
            # WAL generation rate (simplified)
            cursor.execute("""
                SELECT 
                    pg_wal_lsn_diff(
                        pg_current_wal_lsn(),
                        '0/0'
                    ) as total_wal_bytes;
            """)
            total_wal_bytes = cursor.fetchone()[0]
            pg_wal_generation_rate.labels(instance=instance).set(total_wal_bytes)
            
        else:
            # WAL receivers count
            cursor.execute("SELECT COUNT(*) FROM pg_stat_wal_receiver;")
            wal_receivers = cursor.fetchone()[0]
            pg_wal_receivers.labels(instance=instance).set(wal_receivers)
        
        cursor.close()
        
    except psycopg2.Error as e:
        logger.error(f"Failed to get WAL metrics for {instance}: {e}")

def get_replication_slot_metrics(instance, conn):
    """Get replication slot metrics"""
    try:
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT 
                COUNT(*) as total_slots,
                COUNT(*) FILTER (WHERE active = true) as active_slots,
                COUNT(*) FILTER (WHERE active = false) as inactive_slots
            FROM pg_replication_slots;
        """)
        
        result = cursor.fetchone()
        if result:
            total_slots, active_slots, inactive_slots = result
            pg_replication_slots_total.labels(instance=instance).set(total_slots)
            pg_replication_slots_active.labels(instance=instance).set(active_slots)
            pg_replication_slots_inactive.labels(instance=instance).set(inactive_slots)
        
        cursor.close()
        
    except psycopg2.Error as e:
        logger.error(f"Failed to get replication slot metrics for {instance}: {e}")

def get_data_consistency_metrics():
    """Get data consistency metrics by comparing record counts"""
    try:
        primary_conn = get_db_connection('primary')
        standby_conn = get_db_connection('standby')
        
        if not primary_conn or not standby_conn:
            return
        
        primary_cursor = primary_conn.cursor()
        standby_cursor = standby_conn.cursor()
        
        # Get record counts from both instances
        primary_cursor.execute("SELECT COUNT(*) FROM test_data;")
        primary_count = primary_cursor.fetchone()[0]
        
        standby_cursor.execute("SELECT COUNT(*) FROM test_data;")
        standby_count = standby_cursor.fetchone()[0]
        
        # Set consistency metric (1 if consistent, 0 if not)
        consistency = 1 if primary_count == standby_count else 0
        pg_data_consistency_check.labels(instance='cluster').set(consistency)
        
        logger.debug(f"Data consistency check: Primary={primary_count}, Standby={standby_count}, Consistent={consistency}")
        
        primary_cursor.close()
        standby_cursor.close()
        primary_conn.close()
        standby_conn.close()
        
    except psycopg2.Error as e:
        logger.error(f"Failed to get data consistency metrics: {e}")

def calculate_health_score(instance, conn):
    """Calculate overall replication health score"""
    try:
        cursor = conn.cursor()
        health_score = 100
        
        if instance == 'primary':
            # Check replication connections
            cursor.execute("SELECT COUNT(*) FROM pg_stat_replication;")
            replication_count = cursor.fetchone()[0]
            
            if replication_count == 0:
                health_score -= 50  # No replication connections
            elif replication_count < 1:
                health_score -= 20  # Less than expected connections
            
            # Check replication lag
            cursor.execute("""
                SELECT 
                    COALESCE(
                        pg_wal_lsn_diff(
                            pg_current_wal_lsn(),
                            MIN(replay_lsn)
                        ), 0
                    ) as lag_bytes
                FROM pg_stat_replication;
            """)
            
            result = cursor.fetchone()
            if result:
                lag_bytes = result[0]
                if lag_bytes > 10485760:  # > 10MB
                    health_score -= 30
                elif lag_bytes > 1048576:  # > 1MB
                    health_score -= 10
        
        else:
            # Check if in recovery mode
            cursor.execute("SELECT pg_is_in_recovery();")
            in_recovery = cursor.fetchone()[0]
            
            if not in_recovery:
                health_score -= 30  # Standby should be in recovery
            
            # Check replication lag
            cursor.execute("""
                SELECT 
                    COALESCE(
                        pg_wal_lsn_diff(
                            pg_last_wal_receive_lsn(),
                            pg_last_wal_replay_lsn()
                        ), 0
                    ) as lag_bytes,
                    COALESCE(
                        EXTRACT(EPOCH FROM (
                            now() - pg_last_xact_replay_timestamp()
                        )), 0
                    ) as lag_seconds
                FROM pg_stat_wal_receiver;
            """)
            
            result = cursor.fetchone()
            if result:
                lag_bytes, lag_seconds = result
                if lag_bytes > 10485760:  # > 10MB
                    health_score -= 30
                elif lag_bytes > 1048576:  # > 1MB
                    health_score -= 10
                
                if lag_seconds > 30:  # > 30 seconds
                    health_score -= 20
                elif lag_seconds > 5:  # > 5 seconds
                    health_score -= 5
        
        # Ensure health score is between 0 and 100
        health_score = max(0, min(100, health_score))
        pg_replication_health_score.labels(instance=instance).set(health_score)
        
        logger.debug(f"{instance} health score: {health_score}")
        
        cursor.close()
        
    except psycopg2.Error as e:
        logger.error(f"Failed to calculate health score for {instance}: {e}")

def collect_metrics():
    """Collect all metrics from both primary and standby"""
    logger.info("Collecting replication metrics...")
    
    # Collect metrics from primary
    primary_conn = get_db_connection('primary')
    if primary_conn:
        get_replication_lag_metrics('primary', primary_conn)
        get_replication_connection_metrics('primary', primary_conn)
        get_wal_metrics('primary', primary_conn)
        get_replication_slot_metrics('primary', primary_conn)
        calculate_health_score('primary', primary_conn)
        primary_conn.close()
    
    # Collect metrics from standby
    standby_conn = get_db_connection('standby')
    if standby_conn:
        get_replication_lag_metrics('standby', standby_conn)
        get_wal_metrics('standby', standby_conn)
        calculate_health_score('standby', standby_conn)
        standby_conn.close()
    
    # Collect cluster-wide metrics
    get_data_consistency_metrics()
    
    logger.info("Metrics collection completed")

def main():
    """Main function"""
    port = int(os.getenv('EXPORTER_PORT', '9188'))
    
    logger.info(f"Starting PostgreSQL Replication Metrics Exporter on port {port}")
    
    # Start Prometheus metrics server
    start_http_server(port)
    
    # Collect metrics every 15 seconds
    while True:
        try:
            collect_metrics()
            time.sleep(15)
        except KeyboardInterrupt:
            logger.info("Exporter stopped by user")
            break
        except Exception as e:
            logger.error(f"Error in metrics collection: {e}")
            time.sleep(15)

if __name__ == '__main__':
    main()
