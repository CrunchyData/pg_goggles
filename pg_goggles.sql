-- The redundant DROP/CREATE statements here are to make cutting and pasting
-- sections of this easier when testing.

-- Buffers are 8192 bytes.
-- Page size is adjustable at compile time, and some commercial distributions (EDB, others) did 16K block PG releases at one point.

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
            THEN round((100 * checkpoints_timed / (checkpoints_timed + checkpoints_req))::numeric,3)
            ELSE 0 END AS checkpoint_timed_pct,
        CASE WHEN (checkpoints_timed + checkpoints_req) > 0
            THEN round(seconds / 60 / (checkpoints_timed + checkpoints_req),3)
            ELSE 0 END AS minutes_to_checkpoint,
        8192 * buffers_alloc      / seconds AS alloc_bps,
        8192 * buffers_checkpoint / seconds AS checkpoint_bps,
        8192 * buffers_clean      / seconds AS clean_bps,
        8192 * buffers_backend    / seconds AS backend_bps,
        (buffers_checkpoint + buffers_clean + buffers_backend) / seconds AS total_write_bps,
        maxwritten_clean / seconds AS max_clean_per_sec,
        8192 * buffers_backend_fsync AS bytes_backend_fsync,
        checkpoint_write_time / buffers_checkpoint AS avg_chkp_write_s,
        checkpoint_sync_time  / buffers_checkpoint AS avg_chkp_sync_s
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
        round(maxwritten_clean / seconds,3) AS max_clean_per_sec,
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

