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
        pg_stat_get_bgwriter_stat_reset_time() AS stats_reset;

-- Pretty view
DROP VIEW IF EXISTS pgp_stat_bgwriter CASCADE;
CREATE OR REPLACE VIEW pgp_stat_bgwriter AS
    SELECT
        *
    FROM pgg_stat_bgwriter;

-- Rate oriented view
DROP VIEW IF EXISTS pgr_stat_bgwriter CASCADE;

CREATE OR REPLACE VIEW pgr_stat_bgwriter AS
	SELECT
		sample,
		runtime,
		-- TODO Convert timed/req to ratio then I can in theory re-derive the numbers without the originals.
		--Pretty version should only show the nice versions, so all % instead of counts?
		checkpoints_timed,checkpoints_req,
		-- TODO Need to catch 0 case
		round(seconds::numeric / 60 / (checkpoints_timed + checkpoints_req),3) AS minutes_to_checkpoint,
		round(8192 * buffers_checkpoint / (1024 * 1024 * seconds)::numeric,3)  AS checkpoint_mbps,
		round(8192 * buffers_clean / (1024 * 1024 * seconds)::numeric,3) AS clean_mbps,
		round(8192 * buffers_backend / (1024 * 1024 * seconds)::numeric,3) AS backend_mbps,
		round(8192 * (buffers_checkpoint + buffers_clean + buffers_backend) / (1024 * 1024 * seconds)::numeric,3) AS total_write_mbps,
		round(8192 * buffers_alloc / (1024 * 1024 * seconds)::numeric,3) AS alloc_mbps,
		-- TODO Include raw values or not in rate views?
		--buffers_alloc,
		--buffers_checkpoint,
		--buffers_clean,
		--buffers_backend,
		round((maxwritten_clean / seconds)::numeric,3) AS max_clean_per_sec,
		8192 * buffers_backend_fsync AS bytes_backend_fsync,
		round((1000 * checkpoint_write_time / (buffers_checkpoint + buffers_clean + buffers_backend))::numeric,3) AS avg_chkp_write_ms,
		round((1000 * checkpoint_sync_time / (buffers_checkpoint + buffers_clean + buffers_backend))::numeric,3) AS avg_chkp_sync_ms
	FROM
	(
	SELECT
	  current_timestamp AS sample,
	  current_timestamp - stats_reset AS runtime,
	  EXTRACT(EPOCH FROM current_timestamp) - extract(EPOCH FROM stats_reset) AS seconds,
	  b.*
	FROM
	  pg_stat_bgwriter b
	) bgw
	;

-- Next gen version based on pgg view
DROP VIEW IF EXISTS pgn_stat_bgwriter CASCADE;
CREATE OR REPLACE VIEW pgn_stat_bgwriter AS
	SELECT * FROM pgg_stat_bgwriter;

