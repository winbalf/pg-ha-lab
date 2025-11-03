# init-extensions.sql - Database Extensions and Monitoring Setup

This script sets up monitoring extensions, test data, and utility functions on the **primary database**. These changes are automatically replicated to the standby server, providing the same capabilities on both nodes.

## Overview

This script doesn't directly configure replication, but it enhances both primary and standby servers with:
1. **Monitoring extensions** for performance analysis
2. **Test data** for validating replication
3. **Utility functions** for generating load and testing
4. **Monitoring views** for replication status and database activity

Since PostgreSQL replicates **all data and schema changes**, everything created here automatically appears on the standby.

## Section-by-Section Explanation

### Section 1: Monitoring Extensions

Extensions are PostgreSQL add-ons that provide additional functionality:

```sql
-- Enable pg_stat_statements for query performance monitoring
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

- **`pg_stat_statements`**: Tracks execution statistics for all SQL statements
  - Shows: query execution time, number of calls, rows affected
  - Useful for: Identifying slow queries, finding frequently executed queries
- **`IF NOT EXISTS`**: Only creates if it doesn't already exist (safe to run multiple times)
- **Why needed**: Monitor query performance and identify bottlenecks

```sql
-- Enable pg_buffercache for buffer cache monitoring
CREATE EXTENSION IF NOT EXISTS pg_buffercache;
```

- **`pg_buffercache`**: Shows what data is currently in PostgreSQL's shared buffer cache
  - Buffer cache: Memory where frequently accessed data is stored (faster than disk)
- **Why needed**: Understand memory usage patterns, see what data is "hot" (frequently accessed)

```sql
-- Enable pg_prewarm for buffer warming
CREATE EXTENSION IF NOT EXISTS pg_prewarm;
```

- **`pg_prewarm`**: Allows pre-loading data into the buffer cache
  - After a restart, cache is empty (slow queries until it fills)
  - Prewarm can load important tables/indexes into cache immediately
- **Why needed**: Improve performance after server restarts

```sql
-- Enable pg_trgm for text search
CREATE EXTENSION IF NOT EXISTS pg_trgm;
```

- **`pg_trgm`**: Provides trigram-based text search and similarity matching
  - Trigrams: Groups of 3 consecutive characters from text
  - Enables fuzzy text search (find "John" even if you search "Jon")
- **Why needed**: Enables advanced text search capabilities (used in the test table indexes)

```sql
-- Enable btree_gin for GIN indexes on btree data types
CREATE EXTENSION IF NOT EXISTS btree_gin;

-- Enable btree_gist for GiST indexes on btree data types
CREATE EXTENSION IF NOT EXISTS btree_gist;
```

- **`btree_gin`** and **`btree_gist`**: Allow creating GIN/GiST indexes on standard data types (normally only for specialized types)
  - GIN: Generalized Inverted Index (excellent for arrays, JSONB, full-text search)
  - GiST: Generalized Search Tree (useful for geometric data, ranges, full-text search)
- **Why needed**: Enables more flexible indexing strategies (combining different index types)

### Section 2: Test Table Creation

```sql
-- Create a test table for demonstrating replication and monitoring
CREATE TABLE IF NOT EXISTS test_data (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    data JSONB
);
```

This table serves as **proof that replication is working**:

- **`id SERIAL PRIMARY KEY`**: Auto-incrementing integer primary key
  - Primary key ensures uniqueness and enables fast lookups
- **`name VARCHAR(100) NOT NULL`**: Person's name (required field, max 100 characters)
- **`email VARCHAR(255) UNIQUE`**: Email address (must be unique across all rows)
  - Unique constraint: PostgreSQL enforces no duplicate emails
- **`created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP`**: Automatically set when row is created
- **`updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP`**: Tracks last modification time
- **`data JSONB`**: Flexible JSON data column
  - JSONB: Binary JSON format (faster queries than regular JSON)
  - Can store arbitrary structured data

**Why this table?**
- Simple enough to understand
- Complex enough to demonstrate replication (JSONB, constraints, defaults)
- Useful for testing: Insert on primary, verify it appears on standby

### Section 3: Index Creation for Performance Testing

```sql
-- Create indexes for performance testing
CREATE INDEX IF NOT EXISTS idx_test_data_name ON test_data USING gin (name gin_trgm_ops);
```

- **`USING gin`**: Creates a GIN (Generalized Inverted Index)
- **`name gin_trgm_ops`**: Uses trigram operator class
- **Why**: Enables fast fuzzy text search on names (find "John" even if searching "Jon")

```sql
CREATE INDEX IF NOT EXISTS idx_test_data_email ON test_data (email);
```

- **Standard B-tree index** on email (default index type)
- **Why**: Fast lookups by email address (used by UNIQUE constraint too)

```sql
CREATE INDEX IF NOT EXISTS idx_test_data_created_at ON test_data (created_at);
```

- **B-tree index** on timestamp
- **Why**: Fast queries filtering or sorting by creation date

```sql
CREATE INDEX IF NOT EXISTS idx_test_data_data ON test_data USING gin (data);
```

- **GIN index** on JSONB column
- **Why**: Enables fast queries on JSONB data (e.g., `WHERE data->>'department' = 'Engineering'`)

### Section 4: Sample Data Insertion

```sql
-- Insert sample data for testing
INSERT INTO test_data (name, email, data) VALUES
    ('John Doe', 'john.doe@example.com', '{"department": "Engineering", "level": "Senior"}'),
    ('Jane Smith', 'jane.smith@example.com', '{"department": "Marketing", "level": "Manager"}'),
    ('Bob Johnson', 'bob.johnson@example.com', '{"department": "Sales", "level": "Junior"}'),
    ('Alice Brown', 'alice.brown@example.com', '{"department": "Engineering", "level": "Lead"}'),
    ('Charlie Wilson', 'charlie.wilson@example.com', '{"department": "HR", "level": "Director"}')
ON CONFLICT (email) DO NOTHING;
```

- **Inserts 5 sample rows** with realistic data
- **`ON CONFLICT (email) DO NOTHING`**: If email already exists, don't insert (safe to run multiple times)
- **Why needed**: 
  - Provides data to query immediately
  - Proves replication works (insert appears on standby automatically)
  - Demonstrates JSONB usage

### Section 5: Load Generation Function

```sql
-- Create a function to generate load for testing
CREATE OR REPLACE FUNCTION generate_test_load(iterations INTEGER DEFAULT 1000)
RETURNS VOID AS $$
DECLARE
    i INTEGER;
    random_name VARCHAR(100);
    random_email VARCHAR(255);
    random_data JSONB;
BEGIN
```

This function generates test load to stress-test replication:

- **`CREATE OR REPLACE FUNCTION`**: Creates or updates the function
- **`generate_test_load(iterations INTEGER DEFAULT 1000)`**: Function name and parameter
  - `iterations`: How many records to create (default: 1000)
- **`RETURNS VOID`**: Function doesn't return a value
- **`$$ ... $$`**: Dollar-quoting for function body (allows using quotes easily)
- **`DECLARE`**: Variables used in the function

```sql
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
```

- **`FOR i IN 1..iterations LOOP`**: Loop from 1 to `iterations`
- **Generates random data**:
  - Name: "User_1_123", "User_2_456", etc.
  - Email: "user1@test45.com", etc.
  - JSONB: Random department, level, and score

```sql
        INSERT INTO test_data (name, email, data) 
        VALUES (random_name, random_email, random_data);
```

- **Inserts the generated row**

```sql
        -- Update some existing records
        IF i % 10 = 0 THEN
            UPDATE test_data 
            SET updated_at = CURRENT_TIMESTAMP,
                data = data || jsonb_build_object('last_updated', CURRENT_TIMESTAMP)
            WHERE id = (random() * (SELECT COUNT(*) FROM test_data))::INTEGER + 1;
        END IF;
```

- **Every 10th iteration**: Updates a random existing row
- **`||`**: JSONB concatenation operator (merges JSON objects)
- **Why**: Simulates real-world load (mix of inserts and updates)

```sql
        -- Delete some records occasionally
        IF i % 50 = 0 THEN
            DELETE FROM test_data 
            WHERE id = (random() * (SELECT COUNT(*) FROM test_data))::INTEGER + 1;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
```

- **Every 50th iteration**: Deletes a random row
- **Why**: Tests that DELETE operations also replicate correctly
- **`LANGUAGE plpgsql`**: Function is written in PL/pgSQL (PostgreSQL's procedural language)

**Usage**: `SELECT generate_test_load(1000);` - Creates 1000 rows, updates ~100, deletes ~20

### Section 6: Replication Status Monitoring View

```sql
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
```

This view provides **easy access to replication status**:

- **`CREATE OR REPLACE VIEW`**: Creates a simplified view of `pg_stat_replication` system view
- **Fields explained**:
  - **`client_addr`**: IP address of the standby server
  - **`application_name`**: Connection name (usually "walreceiver")
  - **`state`**: Replication state (usually "streaming")
  - **`sent_lsn`**: Last WAL location sent by primary
  - **`write_lsn`**: Last WAL location written to standby's disk
  - **`flush_lsn`**: Last WAL location flushed to standby's disk
  - **`replay_lsn`**: Last WAL location replayed (applied) on standby
  - **`write_lag`**: Delay between primary sending and standby writing
  - **`flush_lag`**: Delay between primary sending and standby flushing
  - **`replay_lag`**: **Most important** - Delay between primary and standby applying changes (this is replication lag)
  - **`sync_priority`** and **`sync_state`**: Synchronous replication settings (we use async)

**Usage**: `SELECT * FROM replication_status;` - Quick overview of replication health

### Section 7: Database Activity Monitoring View

```sql
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
```

This view shows **database-level statistics**:

- **Fields explained**:
  - **`datname`**: Database name
  - **`numbackends`**: Number of active connections
  - **`xact_commit`**: Number of committed transactions
  - **`xact_rollback`**: Number of rolled back transactions
  - **`blks_read`**: Disk blocks read from disk
  - **`blks_hit`**: Disk blocks read from cache (cache hits)
  - **`tup_returned`**: Rows returned by queries
  - **`tup_fetched`**: Rows fetched by queries
  - **`tup_inserted/updated/deleted`**: Rows modified
  - **`conflicts`**: Query conflicts (important on standby - happens when queries conflict with replication)
  - **`temp_files`**: Temporary files created (indicates disk sorting/spilling)
  - **`deadlocks`**: Number of deadlocks detected
  - **`blk_read_time/blk_write_time`**: Time spent reading/writing (in milliseconds)

**Usage**: `SELECT * FROM database_activity;` - Monitor overall database health

### Section 8: Permission Grants

```sql
-- Grant necessary permissions
GRANT SELECT ON replication_status TO postgres;
GRANT SELECT ON database_activity TO postgres;
GRANT EXECUTE ON FUNCTION generate_test_load(INTEGER) TO postgres;
```

- **Grants access** to the views and function
- **`postgres` user**: The database owner (already has permissions, but explicit is better)

## How This Relates to Replication

### Automatic Replication

**Everything in this script replicates automatically**:

1. **Extensions**: When you `CREATE EXTENSION` on primary, it replicates to standby
   - Note: Extensions must be available on both servers (they are, since we use the same Docker image)

2. **Tables and Data**: All `CREATE TABLE` and `INSERT` statements replicate
   - Insert on primary → appears on standby within seconds

3. **Functions and Views**: Schema objects replicate too
   - The `generate_test_load()` function is available on standby
   - The monitoring views work on standby (with standby-specific data)

4. **Indexes**: Index creation replicates
   - Standby builds indexes too (useful for read queries)

### Testing Replication with This Script

1. **Run `init-extensions.sql`** on primary (happens automatically during setup)
2. **Connect to standby** and verify:
   ```sql
   SELECT * FROM test_data;  -- Should show the 5 sample rows
   SELECT * FROM replication_status;  -- Shows replication info
   ```
3. **Generate load on primary**:
   ```sql
   SELECT generate_test_load(100);
   ```
4. **Check standby** - new rows appear automatically!

### Monitoring Replication Health

Use the views to monitor replication:

```sql
-- On primary: See replication status
SELECT * FROM replication_status;

-- On standby: See database activity (including conflicts from replication)
SELECT * FROM database_activity;
```

**Key metric**: `replay_lag` in `replication_status`
- Low (seconds): Healthy replication
- High (minutes): Standby is falling behind (check network, primary load)

## Important Notes

- **Run only on primary**: Changes replicate automatically to standby
- **Extensions require superuser**: The `postgres` user has superuser privileges
- **Safe to run multiple times**: `IF NOT EXISTS` and `ON CONFLICT` prevent errors
- **Standby can use these too**: All functions and views work on standby (great for read scaling)

## Troubleshooting

If extensions don't appear on standby:
- **Check replication is active**: `SELECT * FROM pg_stat_replication;` on primary
- **Check standby logs**: Look for errors applying WAL
- **Verify extensions exist on standby**: `SELECT * FROM pg_extension;` on standby

If test data doesn't appear on standby:
- **Wait a few seconds**: Replication lag is usually 1-2 seconds
- **Check replication status**: Use `replication_status` view to see lag
- **Verify primary has data**: `SELECT COUNT(*) FROM test_data;` on primary

