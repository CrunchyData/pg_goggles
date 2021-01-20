# pg_goggle
_pg\_goggles_ provides better annotated and summarized views into the database's cryptic internal counters.  These are intended for systems where access to the database port (typically 5432) is routine.

# Usage

The goggles views use a single letter code after the "pg" to select which type of view:

* G - `pgg_stat`:  `Goggles` view, basic.  Pages and buffers are decoded into bytes.  Highly useful catalog data is added.  Fields are renamed with minimal changes, so that the pgg version of the view can be swapped in for scripts using the regular one with minimal changes.
* B - `pgb_stat`:  `Byte` rate.  Rates are bytes per second or event/second unless otherwise labeled.  Times are in seconds.  The formatting for some fields is reordered to make byte/MiB units at the end.  Suitable for further machine parsing and processing.
* R - `pgr_stat`:  `Rate` scaled to suggested units for administrator use.  This may use megabytes/second (MB/s) for some values and times in milliseconds for others.
* P - `pgp_stat`:  `Pretty` print of rate view.  Uses _pg\_size\_pretty()__ to help scale large values.  This view is not easily machine readable; use the _pgr_ version for that instead.

# Examples

Byte rate:

    gis=# \x
    Expanded display is on.
    gis=# select * from pgb_stat_bgwriter;
    -[ RECORD 1 ]---------+-----------------------------
    sample                | 2021-01-20 12:36:49.26753-05
    runtime               | 17:43:47.388042
    checkpoint_timed_pct  | 61.000
    minutes_to_checkpoint | 50.657
    alloc_rate_byte       | 28719189.526
    write_rate_byte       | 63922255.075
    checkpoint_rate_byte  | 2433497.822
    clean_rate_byte       | 26045930.044
    backend_rate_byte     | 35442827.209
    checkpoint_write_time | 16321469
    checkpoint_sync_time  | 55841
    checkpoint_write_avg  | 0.861
    checkpoint_sync_avg   | 0.003
    max_clean_rate        | 1.466
    bytes_backend_fsync   | 0

Rate version with mega/milli prefix scaling to put units in the right range for human review.  _mib\_rate_ is a 1024-based megabyte per second (MiB/s) value:

    gis=# select * from pgr_stat_bgwriter;
    -[ RECORD 1 ]---------+------------------------------
    sample                | 2021-01-20 12:37:33.320723-05
    runtime               | 17:44:31.441235
    checkpoints_timed     | 13
    checkpoints_req       | 8
    checkpoint_timed_pct  | 61.000
    minutes_to_checkpoint | 50.692
    alloc_rate_mib        | 27.370
    total_write_rate_mib  | 60.919
    checkpoint_rate_mib   | 2.319
    clean_rate_mib        | 24.822
    backend_rate_mib      | 33.778
    avg_chkp_write_ms     | 860.818
    avg_chkp_sync_ms      | 2.945
    max_clean_rate        | 1.465
    bytes_backend_fsync   | 0

# Background

PostgreSQL comes with some basic built-in system metrics in its [src/backend/catalog/system_views.sql](https://github.com/postgres/postgres/blob/master/src/backend/catalog/system_views.sql) source code, what are usually called the _pg_stat*__ views.  Views are just memorized queries.  Those views summarize a variety of internal system counters in a way that's easy for the database to export.  Some of them are more exposed troubleshooting points than user facing reporting.  

By nature of core PostgreSQL's mandate not to ship management tools with GUI interfaces itself, the scope for these views is limited.  But there's nothing stopping someone from building better but still text system views.  Everyone who administers PostgreSQL systems have some of these views around, little report queries like ["Least Used Index"](https://wiki.postgresql.org/wiki/Index_Maintenance) and such.  Some of them live on the [wiki snippets](https://wiki.postgresql.org/wiki/Category:Snippets), others in the logic of tools like the [check_postgres](https://bucardo.org/check_postgres/) Nagios plug-in.

PostgreSQL has a whole list of [https://wiki.postgresql.org/wiki/Monitoring](monitoring projects).  There isn't a great route for them to contribute improved views from all those toolkits back into core.  It's a big project to grade the summary options, prove they are useful, and stand by their value.  _pg\_goggles_ is that project.

# Scope

Completed views:

* pg_stat_bgwriter, pg_stat_database.

Planned future additions:

* pg_tables, pg_stat_all_tables, pg_statio_all_tables:  Convert to byte units.
* pg_indexes, pg_stat_all_indexes, pg_statio_all_indexes:  Conbert to byte units.
* pg_relations:  Combined table+index view.
* pg_settings:  Numeric values should be easier to lookup.
* pg_locks:  Include the standard recursive lock nagivator.
* pg_stat_activity:  Might improve on waiting information.

# Credits

The PostgreSQL benchmarking work that lead to this project was sponsored by a year long R&D effort within Crunchy Data led by Greg Smith.