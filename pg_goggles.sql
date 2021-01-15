-- The redundant DROP/CREATE statements here are to make cutting and pasting
-- sections of this easier when testing.

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
        *
    FROM pgg_stat_bgwriter;
