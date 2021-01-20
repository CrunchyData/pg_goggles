-- The redundant DROP/CREATE statements here are to make cutting and pasting
-- sections of this easier when testing.

-- Buffers are 8192 bytes.
-- Page size is adjustable at compile time, and some commercial distributions (EDB, others) did 16K block PG releases at one point.

-- All "rates" are bytes per second or event/second unless otherwise labeled.
-- Some rates go through PG pretty print

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
        ROUND(8192 * buffers_alloc      / seconds,3) AS alloc_byte_rate,
        ROUND(8192 * (buffers_checkpoint + buffers_clean + buffers_backend) / seconds,3) AS total_write_byte_rate,
        ROUND(8192 * buffers_checkpoint / seconds,3) AS checkpoint_byte_rate,
        ROUND(8192 * buffers_clean      / seconds,3) AS clean_byte_rate,
        ROUND(8192 * buffers_backend    / seconds,3) AS backend_byte_rate,
        checkpoint_write_time,
        checkpoint_sync_time,
        ROUND(1000 * checkpoint_write_time::numeric / buffers_checkpoint,3) AS checkpoint_write_avg_ms,
        ROUND(1000 * checkpoint_sync_time::numeric  / buffers_checkpoint,3) AS checkpoint_sync_avg_ms,
        ROUND(maxwritten_clean / seconds,3) AS max_clean_rate,
        8192 * buffers_backend_fsync AS bytes_backend_fsync
    FROM bgw
    ;

-- Rate oriented view.  Recommended units with MB/s.
-- TODO Rewrite this to be based on byte version?
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
            THEN round((100 * checkpoints_timed / (checkpoints_timed + checkpoints_req))::numeric,3)
            ELSE 0 END AS checkpoint_timed_pct,
        CASE WHEN (checkpoints_timed + checkpoints_req) > 0
            THEN round(seconds / 60 / (checkpoints_timed + checkpoints_req),3)
            ELSE 0 END AS minutes_to_checkpoint,
        round(8192 * buffers_alloc      / (1024 * 1024 * seconds),3) AS alloc_mbps,
        round(8192 * buffers_checkpoint / (1024 * 1024 * seconds),3) AS checkpoint_mbps,
        round(8192 * buffers_clean      / (1024 * 1024 * seconds),3) AS clean_mbps,
        round(8192 * buffers_backend    / (1024 * 1024 * seconds),3) AS backend_mbps,
        round(8192 * (buffers_checkpoint + buffers_clean + buffers_backend) / (1024 * 1024 * seconds),3) AS total_write_mbps,
        round(maxwritten_clean / seconds,3) AS max_clean_rate,
        8192 * buffers_backend_fsync AS bytes_backend_fsync,
        round((1000 * checkpoint_write_time / buffers_checkpoint)::numeric,3) AS avg_chkp_write_ms,
        round((1000 * checkpoint_sync_time  / buffers_checkpoint)::numeric,3) AS avg_chkp_sync_ms
    FROM bgw
    ;

-- Pretty view.
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

-- Byte rate oriented view
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
        current_setting('block_size')::numeric * blks_read AS bytes_read,
        current_setting('block_size')::numeric * blks_read / seconds AS bytes_read_rate,
        current_setting('block_size')::numeric * blks_hit AS bytes_hit,
        current_setting('block_size')::numeric * blks_hit / seconds AS bytes_hit_rate,
        tup_returned, tup_fetched, tup_inserted,  tup_updated, tup_deleted,
        tup_returned  / seconds AS tup_returned_rate,
        tup_fetched   / seconds AS tup_fetched_rate,
        tup_inserted  / seconds AS tup_inserted_rate,
        tup_updated   / seconds AS tup_updated_rate,
        tup_deleted   / seconds AS tup_deleted_rate,
        temp_files    / seconds AS temp_files_rate,
        temp_bytes    / seconds AS temp_bytes_rate,
        CASE WHEN (temp_files) > 0
            THEN temp_bytes / temp_files
            ELSE 0 END AS temp_avg_file,
        CASE WHEN (blk_read_time + blk_write_time) > 0
            THEN 100 * blk_read_time / (blk_read_time + blk_write_time)
            ELSE 0 END AS blk_read_to_write_pct,
        CASE WHEN (blks_read) > 0
            THEN 1000 * blk_read_time / blks_read 
            ELSE 0 END AS avg_blk_read_time_ms,
        blk_read_time
        -- TODO Is there a better denominator for this one?
        blk_write_time,
        conflicts,
        deadlocks,
        conflicts     / seconds AS conflicts_rate,
        deadlocks     / seconds AS deadlocks_rate,
        checksum_failures,
        checksum_last_failure,
        stats_reset
    FROM db;

-- SELECT * from pgg_stat_database;
-- SELECT * from pgb_stat_database;
