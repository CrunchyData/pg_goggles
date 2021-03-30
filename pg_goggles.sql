-- The redundant DROP/CREATE statements here are to make cutting and pasting
-- sections of this easier when testing.

-- Buffers are 8192 bytes.
-- Page size is adjustable at compile time, and some commercial distributions (EDB, others) did 16K block PG releases at one point.

-- All "rates" are labeled in bytes/MiB per second or event/second unless otherwise labeled.
-- Some rates go through PG pretty print.

-- Goggles enhanced view
DROP VIEW IF EXISTS pgg_stat_bgwriter CASCADE;
CREATE OR REPLACE VIEW pgg_stat_bgwriter AS
    SELECT
        pg_stat_get_bgwriter_timed_checkpoints() AS checkpoints_timed,
        pg_stat_get_bgwriter_requested_checkpoints() AS checkpoints_req,
        pg_stat_get_checkpoint_write_time() AS checkpoint_write_time,
        pg_stat_get_checkpoint_sync_time() AS checkpoint_sync_time,
        pg_stat_get_bgwriter_buf_written_checkpoints() * 8192 AS bytes_checkpoint,
        pg_stat_get_bgwriter_buf_written_clean() * 8192 AS bytes_clean,
        pg_stat_get_bgwriter_maxwritten_clean() AS maxwritten_clean,
        pg_stat_get_buf_written_backend() * 8192 AS bytes_backend,
        pg_stat_get_buf_fsync_backend() * 8192 AS bytes_backend_fsync,
        pg_stat_get_buf_alloc() * 8192 AS bytes_alloc,
        pg_stat_get_bgwriter_stat_reset_time() AS stats_reset,
		-- Would like to eliminate this one but unclear how.
		-- Is this encapsulation failure a clue all counters should pass through goggles?
        -- Need to diagram count/sum relations and cover all of them.
		pg_stat_get_bgwriter_buf_written_checkpoints() AS writes_checkpoint
		;

-- Byte rate oriented view
-- TODO Include raw values or not in rate views?
DROP VIEW IF EXISTS pgb_stat_bgwriter CASCADE;
CREATE OR REPLACE VIEW pgb_stat_bgwriter AS
    WITH bgw AS (
        SELECT
            current_timestamp AS sample,
            current_timestamp - stats_reset AS runtime,
            (EXTRACT(EPOCH FROM current_timestamp) - extract(EPOCH FROM stats_reset))::numeric AS seconds,
            b.*
        FROM
            pg_stat_bgwriter b
    )
    SELECT
        sample,
        runtime,
        CASE WHEN (checkpoints_timed + checkpoints_req) > 0
            THEN ROUND((100 * checkpoints_timed / (checkpoints_timed + checkpoints_req))::numeric,3)
            ELSE 0 END AS checkpoint_timed_pct,
        CASE WHEN (checkpoints_timed + checkpoints_req) > 0
            THEN ROUND(seconds / 60 / (checkpoints_timed + checkpoints_req),3)
            ELSE 0 END AS minutes_to_checkpoint,
        ROUND(8192 * buffers_alloc      / seconds,3) AS alloc_rate_byte,
        ROUND(8192 * (buffers_checkpoint + buffers_clean + buffers_backend) / seconds,3) AS write_rate_byte,
        ROUND(8192 * buffers_checkpoint / seconds,3) AS checkpoint_rate_byte,
        ROUND(8192 * buffers_clean      / seconds,3) AS clean_rate_byte,
        ROUND(8192 * buffers_backend    / seconds,3) AS backend_rate_byte,
        checkpoint_write_time,
        checkpoint_sync_time,
        CASE WHEN (buffers_checkpoint) > 0
            THEN ROUND(checkpoint_write_time::numeric / buffers_checkpoint,3)
            ELSE 0 END AS checkpoint_write_avg,
        CASE WHEN (buffers_checkpoint) > 0
            THEN ROUND(checkpoint_sync_time::numeric  / buffers_checkpoint,3)
            ELSE 0 END AS checkpoint_sync_avg,
        ROUND(maxwritten_clean / seconds,3) AS max_clean_rate,
        8192 * buffers_backend_fsync AS bytes_backend_fsync
    FROM bgw
    ;

-- Rate oriented view.  Recommended units.
-- TODO Might rewrite this to be based on byte version.
DROP VIEW IF EXISTS pgr_stat_bgwriter CASCADE;
CREATE OR REPLACE VIEW pgr_stat_bgwriter AS
    WITH bgw AS (
        SELECT
            current_timestamp AS sample,
            current_timestamp - stats_reset AS runtime,
            (EXTRACT(EPOCH FROM current_timestamp) - extract(EPOCH FROM stats_reset))::numeric AS seconds,
            b.*
        FROM
            pg_stat_bgwriter b
    )
    SELECT
        sample,
        runtime,
        checkpoints_timed,checkpoints_req,
        CASE WHEN (checkpoints_timed + checkpoints_req) > 0
            THEN ROUND((100 * checkpoints_timed / (checkpoints_timed + checkpoints_req))::numeric,3)
            ELSE 0 END AS checkpoint_timed_pct,
        CASE WHEN (checkpoints_timed + checkpoints_req) > 0
            THEN ROUND(seconds / 60 / (checkpoints_timed + checkpoints_req),3)
            ELSE 0 END AS minutes_to_checkpoint,
        ROUND(8192 * buffers_alloc      / (1024 * 1024 * seconds),3) AS alloc_rate_mib,
        ROUND(8192 * (buffers_checkpoint + buffers_clean + buffers_backend) / (1024 * 1024 * seconds),3) AS total_write_rate_mib,
        ROUND(8192 * buffers_checkpoint / (1024 * 1024 * seconds),3) AS checkpoint_rate_mib,
        ROUND(8192 * buffers_clean      / (1024 * 1024 * seconds),3) AS clean_rate_mib,
        ROUND(8192 * buffers_backend    / (1024 * 1024 * seconds),3) AS backend_rate_mib,
        CASE WHEN buffers_checkpoint > 0
            THEN ROUND((1000 * checkpoint_write_time / buffers_checkpoint)::numeric,3)
            ELSE 0 END AS avg_chkp_write_ms,
        CASE WHEN buffers_checkpoint > 0
            THEN ROUND((1000 * checkpoint_sync_time  / buffers_checkpoint)::numeric,3)
            ELSE 0 END AS avg_chkp_sync_ms,
        ROUND(maxwritten_clean / seconds,3) AS max_clean_rate,
        8192 * buffers_backend_fsync AS bytes_backend_fsync
    FROM bgw
    ;

-- Pretty view TBD.
-- Boring for bgwriter, but very useful for relation level data
DROP VIEW IF EXISTS pgp_stat_bgwriter CASCADE;
CREATE OR REPLACE VIEW pgp_stat_bgwriter AS
    SELECT
        *
    FROM pgr_stat_bgwriter;

-- Testing
-- SELECT * FROM pgg_stat_bgwriter;
-- SELECT * FROM pgb_stat_bgwriter;
-- SELECT * FROM pgr_stat_bgwriter;
-- SELECT * FROM pgp_stat_bgwriter;

--
-- Database
--
DROP VIEW IF EXISTS pgg_stat_database CASCADE;
CREATE OR REPLACE VIEW pgg_stat_database AS
    SELECT
            D.oid AS datid,
            D.datname AS datname,
                CASE
                    WHEN (D.oid = (0)::oid) THEN 0
                    ELSE pg_stat_get_db_numbackends(D.oid)
                END AS numbackends,
            pg_stat_get_db_xact_commit(D.oid) AS xact_commit,
            pg_stat_get_db_xact_rollback(D.oid) AS xact_rollback,
            current_setting('block_size')::numeric * 
                (pg_stat_get_db_blocks_fetched(D.oid) -
                    pg_stat_get_db_blocks_hit(D.oid)) AS bytes_read,
            current_setting('block_size')::numeric * 
                (pg_stat_get_db_blocks_hit(D.oid)) AS bytes_hit,
            pg_stat_get_db_tuples_returned(D.oid) AS tup_returned,
            pg_stat_get_db_tuples_fetched(D.oid) AS tup_fetched,
            pg_stat_get_db_tuples_inserted(D.oid) AS tup_inserted,
            pg_stat_get_db_tuples_updated(D.oid) AS tup_updated,
            pg_stat_get_db_tuples_deleted(D.oid) AS tup_deleted,
            pg_stat_get_db_conflict_all(D.oid) AS conflicts,
            pg_stat_get_db_temp_files(D.oid) AS temp_files,
            pg_stat_get_db_temp_bytes(D.oid) AS temp_bytes,
            pg_stat_get_db_deadlocks(D.oid) AS deadlocks,
            pg_stat_get_db_checksum_failures(D.oid) AS checksum_failures,
            pg_stat_get_db_checksum_last_failure(D.oid) AS checksum_last_failure,
            pg_stat_get_db_blk_read_time(D.oid) AS blk_read_time,
            pg_stat_get_db_blk_write_time(D.oid) AS blk_write_time,
            pg_stat_get_db_stat_reset_time(D.oid) AS stats_reset
    FROM (
        SELECT 0 AS oid, NULL::name AS datname
        UNION ALL
        SELECT oid, datname FROM pg_database
    ) D;

-- Byte rate oriented view.  Only includes current database.
DROP VIEW IF EXISTS pgb_stat_database CASCADE;
CREATE OR REPLACE VIEW pgb_stat_database AS
    WITH db AS (
        SELECT
            current_timestamp AS sample,
            current_timestamp - stats_reset AS runtime,
            (EXTRACT(EPOCH FROM current_timestamp) - extract(EPOCH FROM stats_reset))::numeric AS seconds,
            d.*
        FROM
            pg_stat_database d
        WHERE
            datname=current_database()
    )
    SELECT
        sample,
        runtime,
        datid, datname, 
        xact_commit, xact_rollback,
        xact_commit   / seconds AS xact_commit_rate,
        xact_rollback / seconds AS xact_rollback_rate,
        -- TODO replace these with block_size in WITH?
        current_setting('block_size')::numeric * blks_hit AS hit_bytes,
        current_setting('block_size')::numeric * blks_read AS read_bytes,
        current_setting('block_size')::numeric * blks_hit / seconds AS hit_rate_bytes,
        current_setting('block_size')::numeric * blks_read / seconds AS read_rate_bytes,
        tup_returned, tup_fetched, tup_inserted,  tup_updated, tup_deleted,
        tup_returned  / seconds AS tup_returned_rate,
        tup_fetched   / seconds AS tup_fetched_rate,
        tup_inserted  / seconds AS tup_inserted_rate,
        tup_updated   / seconds AS tup_updated_rate,
        tup_deleted   / seconds AS tup_deleted_rate,
        temp_files    / seconds AS temp_rate_files,
        temp_bytes    / seconds AS temp_rate_bytes,
        CASE WHEN temp_files > 0
            THEN temp_bytes / temp_files
            ELSE 0 END AS temp_file_avg,
        blk_read_time,
        -- TODO Is there a denominator for blk_write_time that's effectively blks_write?
        blk_write_time,
        CASE WHEN (blk_read_time + blk_write_time) > 0
            THEN 100 * blk_read_time / (blk_read_time + blk_write_time)
            ELSE 0 END AS blk_read_pct,
        CASE WHEN blks_read > 0
            THEN blk_read_time / blks_read
            ELSE 0 END AS blk_read_avg,
        conflicts,
        deadlocks,
        conflicts     / seconds AS conflicts_rate,
        deadlocks     / seconds AS deadlocks_rate,
        checksum_failures,
        checksum_last_failure,
        stats_reset
    FROM db;

-- Build rate view from bytes.  Too much logic in pgb view to write this starting with system view.
-- TODO Add some sort of read/write percentages to the tuple data.
DROP VIEW IF EXISTS pgr_stat_database CASCADE;
CREATE OR REPLACE VIEW pgr_stat_database AS
    SELECT
      sample,
      runtime,
      ROUND(tup_returned_rate,3) AS tup_returned_rate,
      ROUND(tup_fetched_rate,3) AS tup_fetched_rate,
      ROUND(tup_inserted_rate,3) AS tup_inserted_rate,
      ROUND(tup_updated_rate,3) AS tup_updated_rate,
      ROUND(tup_deleted_rate,3) AS tup_deleted_rate,
      temp_file_avg,
      ROUND(temp_rate_bytes / (1024*1024),3) AS temp_rate_mib,
      ROUND(hit_rate_bytes / (1024*1024),3) AS hit_rate_mib,
      ROUND(read_rate_bytes / (1024*1024),3) AS read_rate_mib,
      ROUND(blk_read_pct::numeric,3) AS blk_read_pct,
      ROUND(1000 * blk_read_avg::numeric,3) AS blk_read_avg_ms,
      ROUND(blk_read_time::numeric,3) AS blk_read_time,
      ROUND(blk_write_time::numeric,3) AS blk_write_time,
      ROUND(xact_commit_rate,3) AS xact_commit_rate,
      ROUND(xact_rollback_rate,3) AS xact_rollback_rate
    FROM pgb_stat_database;

DROP VIEW IF EXISTS pgp_stat_database CASCADE;
CREATE OR REPLACE VIEW pgp_stat_database AS
    SELECT * FROM pgb_stat_database;

-- Testing
-- SELECT * FROM pgg_stat_database;
-- SELECT * FROM pgb_stat_database;
-- SELECT * FROM pgr_stat_database;
-- SELECT * FROM pgp_stat_database;

DROP VIEW IF EXISTS pgg_statio_all_tables;
CREATE OR REPLACE VIEW pgg_statio_all_tables AS
    SELECT
            C.oid AS relid,
            N.nspname AS schemaname,
            C.relname AS relname,
            current_setting('block_size')::numeric * (pg_stat_get_blocks_fetched(C.oid) -
                    pg_stat_get_blocks_hit(C.oid)) AS heap_bytes_read,
            current_setting('block_size')::numeric * pg_stat_get_blocks_hit(C.oid) AS heap_bytes_hit,
            current_setting('block_size')::numeric * (sum(pg_stat_get_blocks_fetched(I.indexrelid) -
                    pg_stat_get_blocks_hit(I.indexrelid))::bigint) AS idx_bytes_read,
            current_setting('block_size')::numeric * (sum(pg_stat_get_blocks_hit(I.indexrelid))::bigint) AS idx_bytes_hit,
            current_setting('block_size')::numeric * (pg_stat_get_blocks_fetched(T.oid) -
                    pg_stat_get_blocks_hit(T.oid)) AS toast_bytes_read,
            current_setting('block_size')::numeric * pg_stat_get_blocks_hit(T.oid) AS toast_bytes_hit,
            current_setting('block_size')::numeric * (pg_stat_get_blocks_fetched(X.indexrelid) -
                    pg_stat_get_blocks_hit(X.indexrelid)) AS tidx_bytes_read,
            current_setting('block_size')::numeric * pg_stat_get_blocks_hit(X.indexrelid) AS tidx_bytes_hit
            -- TODO Cache hit stats
    FROM pg_class C LEFT JOIN
            pg_index I ON C.oid = I.indrelid LEFT JOIN
            pg_class T ON C.reltoastrelid = T.oid LEFT JOIN
            pg_index X ON T.oid = X.indrelid
            LEFT JOIN pg_namespace N ON (N.oid = C.relnamespace)
    WHERE   C.relkind IN ('r', 't', 'm') -- AND
            -- TOOO schemaname isn't working as hoped here, need to replace.
--            N.schemaname NOT IN ('pg_catalog', 'information_schema') AND
--            N.schemaname !~ '^pg_toast'
    GROUP BY C.oid, N.nspname, C.relname, T.oid, X.indexrelid;

DROP VIEW IF EXISTS pgg_settings;
CREATE OR REPLACE VIEW pgg_settings AS
    SELECT
        name,
        current_setting(name) AS setting,
        CASE
            WHEN unit='B' THEN setting::numeric
            WHEN unit='8kB' THEN setting::numeric * 8192
            WHEN unit='kB' THEN setting::numeric * 1024
            WHEN unit='MB' THEN setting::numeric * 1024 * 1024
            WHEN unit='s' THEN setting::numeric
            WHEN unit='ms' THEN round(setting::numeric / 1000,3)
            WHEN unit='min' THEN setting::numeric * 60
            WHEN unit IS NULL AND vartype='integer' THEN setting::numeric
            WHEN unit IS NULL AND vartype='real' THEN setting::numeric
            END AS numeric_value,
        CASE
            WHEN unit IN ('B','8kB','kB','MB') THEN 'bytes'
            WHEN unit IN ('s','ms','min') THEN 'seconds'
            WHEN unit IN ('integer,real') THEN 'numeric'
            END AS units
    FROM pg_settings
    ORDER BY unit,name;

-- Nothing to add so far in basic Goggles view, just pass these through
DROP VIEW IF EXISTS pgg_stat_sys_tables;
CREATE OR REPLACE VIEW pgg_stat_sys_tables AS
    SELECT * FROM pg_stat_sys_tables;

DROP VIEW IF EXISTS pgg_stat_user_tables;
CREATE OR REPLACE VIEW pgg_stat_user_tables AS
    SELECT * FROM pg_stat_user_tables;

DROP VIEW IF EXISTS pgg_stat_all_tables;
CREATE OR REPLACE VIEW pgg_stat_all_tables AS
    SELECT * FROM pg_stat_all_tables;

DROP VIEW IF EXISTS pg_stat_block;
CREATE OR REPLACE VIEW pg_stat_block AS
    SELECT
      pg_catalog.pg_get_userbyid(c.relowner) as "Owner",
      n.nspname as "Schema",
      c.relname as "Name",
      CASE c.relkind WHEN 'r' THEN 'table' WHEN 'v' THEN 'view'
        WHEN 'm' THEN 'materialized view' WHEN 'i' THEN 'index'
        WHEN 'S' THEN 'sequence' WHEN 's' THEN 'special'
        WHEN 'f' THEN 'foreign table' WHEN 'p' THEN 'partitioned table'
        WHEN 'I' THEN 'partitioned index' END as "Type",
      c2.relname AS idxrel,
      pg_relation_size(C.oid) AS rel_bytes,
      pg_size_pretty(pg_relation_size(C.oid)) AS rel_bytes_pretty,
      pg_stat_get_numscans(C2.oid) AS idx_scan,
      pg_stat_get_tuples_returned(C2.oid) AS idx_tup_read,
      pg_stat_get_tuples_fetched(C2.oid) AS idx_tup_fetch,
      (pg_stat_get_blocks_fetched(C.oid) -
          pg_stat_get_blocks_hit(C.oid)) *
          current_setting('block_size')::numeric AS heap_bytes_read,
      pg_stat_get_blocks_hit(C.oid) *
          current_setting('block_size')::numeric AS heap_bytes_hit,
      (pg_stat_get_blocks_fetched(T.oid) -
          pg_stat_get_blocks_hit(T.oid)) *
          current_setting('block_size')::numeric AS toast_blks_read,
      pg_stat_get_blocks_hit(T.oid) *
          current_setting('block_size')::numeric AS toast_blks_hit
    -- TODO Toast index?
    FROM pg_catalog.pg_class c
         LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
         LEFT JOIN pg_catalog.pg_index i ON i.indexrelid = c.oid
         LEFT JOIN pg_catalog.pg_class c2 ON i.indrelid = c2.oid
         LEFT JOIN pg_class T ON C.reltoastrelid = T.oid
    WHERE c.relkind IN ('r','p','i','m','S','f','')
          AND n.nspname <> 'pg_catalog'
          AND n.nspname <> 'information_schema'
          AND n.nspname !~ '^pg_toast'
      AND pg_catalog.pg_table_is_visible(c.oid)
      AND pg_relation_size(C.oid) > 16384
    ORDER BY c.relkind,n.nspname,c.relname;

DROP VIEW IF EXISTS pgb_stat_block;
CREATE OR REPLACE VIEW pgb_stat_block AS
    WITH db AS (
        SELECT
            current_timestamp AS sample,
            current_timestamp - stats_reset AS runtime,
            (EXTRACT(EPOCH FROM current_timestamp) - extract(EPOCH FROM stats_reset))::numeric AS seconds,
            d.*
        FROM
            pg_stat_database d
        WHERE
            datname=current_database()
    )
    SELECT
      pg_catalog.pg_get_userbyid(c.relowner) as "Owner",
      n.nspname as "Schema",
      c.relname as "Name",
      CASE c.relkind WHEN 'r' THEN 'table' WHEN 'v' THEN 'view'
        WHEN 'm' THEN 'materialized view' WHEN 'i' THEN 'index'
        WHEN 'S' THEN 'sequence' WHEN 's' THEN 'special'
        WHEN 'f' THEN 'foreign table' WHEN 'p' THEN 'partitioned table'
        WHEN 'I' THEN 'partitioned index' END as "Type",
      c2.relname AS idxrel,
      pg_relation_size(C.oid) AS rel_bytes,
      pg_size_pretty(pg_relation_size(C.oid)) AS rel_bytes_pretty,
      pg_stat_get_numscans(C2.oid) / seconds AS idx_scan_rate,
      pg_stat_get_tuples_returned(C2.oid) / seconds AS idx_tup_read_rate,
      pg_stat_get_tuples_fetched(C2.oid) / seconds AS idx_tup_fetch_rate,
      (pg_stat_get_blocks_fetched(C.oid) - pg_stat_get_blocks_hit(C.oid)) *
          current_setting('block_size')::numeric / seconds AS heap_bytes_read_rate,
      pg_stat_get_blocks_hit(C.oid) *
          current_setting('block_size')::numeric / seconds AS heap_bytes_hit_rate,
      pg_stat_get_blocks_hit(T.oid) *
          current_setting('block_size')::numeric / seconds AS toast_blks_hit_rate
    -- TODO Toast index?
    FROM db, pg_catalog.pg_class c
         LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
         LEFT JOIN pg_catalog.pg_index i ON i.indexrelid = c.oid
         LEFT JOIN pg_catalog.pg_class c2 ON i.indrelid = c2.oid
         LEFT JOIN pg_class T ON C.reltoastrelid = T.oid
    WHERE c.relkind IN ('r','p','i','m','S','f','')
          AND n.nspname <> 'pg_catalog'
          AND n.nspname <> 'information_schema'
          AND n.nspname !~ '^pg_toast'
      AND pg_catalog.pg_table_is_visible(c.oid)
      AND pg_relation_size(C.oid) > 16384
    ORDER BY c.relkind,n.nspname,c.relname;

-- TODO Should break down returned/feched etc more like original view components.  Not permanently, just to help prove the MiB code looks right and the () are in the right place.
-- TODO Find less long run-on description for previous TODO

-- Goggles provide time interval and convert to bytes
DROP VIEW IF EXISTS pgg_stat_statements;
CREATE OR REPLACE VIEW pgg_stat_statements AS
    WITH db AS (
        SELECT
            current_timestamp AS sample,
            current_timestamp - stats_reset AS runtime,
            (EXTRACT(EPOCH FROM current_timestamp) - extract(EPOCH FROM stats_reset))::numeric AS seconds,
            p.setting::integer AS bs
        FROM
            pg_stat_database d, pg_settings p
        WHERE
            d.datname=current_database() AND
            p.name='block_size'
    )
    SELECT
        --Version for pg_stat_database version
        --pg_stat_get_db_stat_reset_time(db.datid) AS reset,
        queryid,
        db.seconds,
        -- TODO Is there a way to cap the column width at 60 but allow vertical multi-line?
        substr(query,0,60) AS query,
        calls,
        rows,
        ROUND(total_exec_time::numeric / (1000.0*60*60),2) as "total_hrs",
        plans,total_plan_time,min_plan_time,max_plan_time,mean_plan_time,stddev_plan_time,
        total_exec_time,min_exec_time,max_exec_time,mean_exec_time,stddev_exec_time,
        shared_blks_hit     * bs AS shared_hit_bytes,  -- Or just shared_hit? and assume bytes?
        shared_blks_read    * bs AS shared_read_bytes,
        shared_blks_dirtied * bs AS shared_dirtied_bytes,
        shared_blks_written * bs AS shared_written_bytes,
        local_blks_hit      * bs AS local_hit_bytes,
        local_blks_read     * bs AS local_read_bytes,
        local_blks_dirtied  * bs AS local_dirtied_bytes,
        local_blks_written  * bs AS local_written_bytes,
        temp_blks_read      * bs AS temp_bytes_read,
        temp_blks_written   * bs AS temp_bytes_written,
        -- TODO Scale these by read/write total, so avg latency per read/write
        blk_read_time,blk_write_time,
        wal_records,wal_fpi,wal_bytes
    FROM db,pg_stat_statements
    ORDER BY total_exec_time DESC;

-- Byte rate
DROP VIEW IF EXISTS pgb_stat_statements;
CREATE OR REPLACE VIEW pgb_stat_statements AS
    WITH db AS (
        SELECT
            current_timestamp AS sample,
            current_timestamp - stats_reset AS runtime,
            (EXTRACT(EPOCH FROM current_timestamp) - extract(EPOCH FROM stats_reset))::numeric AS seconds,
            p.setting::integer AS bs
        FROM
            pg_stat_database d, pg_settings p
        WHERE
            d.datname=current_database() AND
            p.name='block_size'
    )
    SELECT
        --Version for pg_stat_database version
        --pg_stat_get_db_stat_reset_time(db.datid) AS reset,
        queryid,
        db.seconds,
        -- TODO Is there a way to cap the column width at 60 but allow vertical multi-line?
        substr(query,0,60) AS query,
        calls,
        rows,
        ROUND(total_exec_time::numeric / (1000.0*60*60),2) as "total_hrs",
        plans,total_plan_time,min_plan_time,max_plan_time,mean_plan_time,stddev_plan_time,
        total_exec_time,min_exec_time,max_exec_time,mean_exec_time,stddev_exec_time,
        ROUND(shared_blks_hit     * bs / seconds) AS shared_hit_rate,
        ROUND(shared_blks_read    * bs / seconds) AS shared_read_rate,
        ROUND(shared_blks_dirtied * bs / seconds) AS shared_dirtied_rate,
        ROUND(shared_blks_written * bs / seconds) AS shared_written_rate,
        ROUND(local_blks_hit      * bs / seconds) AS local_hit_rate,
        ROUND(local_blks_read     * bs / seconds) AS local_read_rate,
        ROUND(local_blks_dirtied  * bs / seconds) AS local_dirtied_rate,
        ROUND(local_blks_written  * bs / seconds) AS local_written_rate,
        ROUND(temp_blks_read      * bs / seconds) AS temp_read_rate,
        ROUND(temp_blks_written   * bs / seconds) AS temp_written_rate,
        -- TODO Scale these by read/write total, so avg latency per read/write
        blk_read_time,blk_write_time,
        wal_records,wal_fpi,wal_bytes
    FROM db,pg_stat_statements
    ORDER BY total_exec_time DESC;

DROP VIEW IF EXISTS pgp_stat_statements;
-- TODO Need pretty print version

CREATE OR REPLACE VIEW pgp_stat_statements AS
    WITH db AS (
        SELECT
            current_timestamp AS sample,
            current_timestamp - stats_reset AS runtime,
            (EXTRACT(EPOCH FROM current_timestamp) - extract(EPOCH FROM stats_reset))::numeric AS seconds,
            p.setting::integer AS bs
        FROM
            pg_stat_database d, pg_settings p
        WHERE
            d.datname=current_database() AND
            p.name='block_size'
    )
    SELECT
        --Version for pg_stat_database version
        --pg_stat_get_db_stat_reset_time(db.datid) AS reset,
        queryid,
        db.seconds,
        -- TODO Is there a way to cap the column width at 60 but allow vertical multi-line?
        substr(query,0,60) AS query,
        calls,
        rows,
        ROUND(total_exec_time::numeric / (1000.0*60*60),2) as "total_hrs",
        plans,total_plan_time,min_plan_time,max_plan_time,mean_plan_time,stddev_plan_time,
        total_exec_time,min_exec_time,max_exec_time,mean_exec_time,stddev_exec_time,
        pg_size_pretty(ROUND(shared_blks_hit     * bs / seconds)::int8) AS shared_hit_rate,
        pg_size_pretty(ROUND(shared_blks_read    * bs / seconds)::int8) AS shared_read_rate,
        pg_size_pretty(ROUND(shared_blks_dirtied * bs / seconds)::int8) AS shared_dirtied_rate,
        pg_size_pretty(ROUND(shared_blks_written * bs / seconds)::int8) AS shared_written_rate,
        pg_size_pretty(ROUND(local_blks_hit      * bs / seconds)::int8) AS local_hit_rate,
        pg_size_pretty(ROUND(local_blks_read     * bs / seconds)::int8) AS local_read_rate,
        pg_size_pretty(ROUND(local_blks_dirtied  * bs / seconds)::int8) AS local_dirtied_rate,
        pg_size_pretty(ROUND(local_blks_written  * bs / seconds)::int8) AS local_written_rate,
        pg_size_pretty(ROUND(temp_blks_read      * bs / seconds)::int8) AS temp_read_rate,
        pg_size_pretty(ROUND(temp_blks_written   * bs / seconds)::int8) AS temp_written_rate,
        -- TODO Scale these by read/write total, so avg latency per read/write
        blk_read_time,blk_write_time,
        wal_records,wal_fpi,wal_bytes
    FROM db,pg_stat_statements
    ORDER BY total_exec_time DESC;
