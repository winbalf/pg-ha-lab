-- PostgreSQL Extensions Initialization Script
-- This script sets up monitoring and performance extensions

-- Enable pg_stat_statements for query performance monitoring
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Enable pg_buffercache for buffer cache monitoring
CREATE EXTENSION IF NOT EXISTS pg_buffercache;

-- Enable pg_prewarm for buffer warming
CREATE EXTENSION IF NOT EXISTS pg_prewarm;

-- Enable pg_trgm for text search
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Enable btree_gin for GIN indexes on btree data types
CREATE EXTENSION IF NOT EXISTS btree_gin;

-- Enable btree_gist for GiST indexes on btree data types
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- Create a test table for demonstrating replication and monitoring
CREATE TABLE IF NOT EXISTS test_data (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    data JSONB
);

-- Create indexes for performance testing
CREATE INDEX IF NOT EXISTS idx_test_data_name ON test_data USING gin (name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_test_data_email ON test_data (email);
CREATE INDEX IF NOT EXISTS idx_test_data_created_at ON test_data (created_at);
CREATE INDEX IF NOT EXISTS idx_test_data_data ON test_data USING gin (data);

-- Insert sample data for testing
INSERT INTO test_data (name, email, data) VALUES
    ('John Doe', 'john.doe@example.com', '{"department": "Engineering", "level": "Senior"}'),
    ('Jane Smith', 'jane.smith@example.com', '{"department": "Marketing", "level": "Manager"}'),
    ('Bob Johnson', 'bob.johnson@example.com', '{"department": "Sales", "level": "Junior"}'),
    ('Alice Brown', 'alice.brown@example.com', '{"department": "Engineering", "level": "Lead"}'),
    ('Charlie Wilson', 'charlie.wilson@example.com', '{"department": "HR", "level": "Director"}')
ON CONFLICT (email) DO NOTHING;

-- Create a function to generate load for testing
CREATE OR REPLACE FUNCTION generate_test_load(iterations INTEGER DEFAULT 1000)
RETURNS VOID AS $$
DECLARE
    i INTEGER;
    random_name VARCHAR(100);
    random_email VARCHAR(255);
    random_data JSONB;
BEGIN
    FOR i IN 1..iterations LOOP
        random_name := 'User_' || i || '_' || (random() * 1000)::INTEGER;
        random_email := 'user' || i || '@test' || (random() * 100)::INTEGER || '.com';
        random_data := jsonb_build_object(
            'department', CASE (random() * 4)::INTEGER
                WHEN 0 THEN 'Engineering'
                WHEN 1 THEN 'Marketing'
                WHEN 2 THEN 'Sales'
                ELSE 'HR'
            END,
            'level', CASE (random() * 3)::INTEGER
                WHEN 0 THEN 'Junior'
                WHEN 1 THEN 'Senior'
                ELSE 'Lead'
            END,
            'score', (random() * 100)::INTEGER
        );
        
        INSERT INTO test_data (name, email, data) 
        VALUES (random_name, random_email, random_data);
        
        -- Update some existing records
        IF i % 10 = 0 THEN
            UPDATE test_data 
            SET updated_at = CURRENT_TIMESTAMP,
                data = data || jsonb_build_object('last_updated', CURRENT_TIMESTAMP)
            WHERE id = (random() * (SELECT COUNT(*) FROM test_data))::INTEGER + 1;
        END IF;
        
        -- Delete some records occasionally
        IF i % 50 = 0 THEN
            DELETE FROM test_data 
            WHERE id = (random() * (SELECT COUNT(*) FROM test_data))::INTEGER + 1;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Create a view for monitoring replication lag
CREATE OR REPLACE VIEW replication_status AS
SELECT 
    client_addr,
    application_name,
    state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    write_lag,
    flush_lag,
    replay_lag,
    sync_priority,
    sync_state
FROM pg_stat_replication;

-- Create a view for monitoring database activity
CREATE OR REPLACE VIEW database_activity AS
SELECT 
    datname,
    numbackends,
    xact_commit,
    xact_rollback,
    blks_read,
    blks_hit,
    tup_returned,
    tup_fetched,
    tup_inserted,
    tup_updated,
    tup_deleted,
    conflicts,
    temp_files,
    temp_bytes,
    deadlocks,
    blk_read_time,
    blk_write_time,
    stats_reset
FROM pg_stat_database 
WHERE datname = current_database();

-- Grant necessary permissions
GRANT SELECT ON replication_status TO postgres;
GRANT SELECT ON database_activity TO postgres;
GRANT EXECUTE ON FUNCTION generate_test_load(INTEGER) TO postgres;
