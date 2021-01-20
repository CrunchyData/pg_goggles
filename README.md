# pg_goggle
_pg\_goggles_ provides better annotated and summarized views into the database's cryptic internal counters.  These are intended for systems where access to the database port (typically 5432) is routine.

# Usage

The goggles views use a single letter code after the "pg" to select which type of view:

* G - pgg_stat:  Goggles view, basic.  Pages and buffers are decoded into bytes.  Highly useful catalog data is added.
* B - pgb_stat:  Byte rate.  Rates are bytes per second or event/second unless otherwise labeled.  Times are in seconds.  Suitable for further machine parsing and processing.
* R - pgr_stat:  Rate re-scaled to suggested units.  This may use MB/s for some values and times in milliseconds for others.
* P - pgp_stat:  Pretty print.  Use pg_size_pretty() to help scale large values.

# Example

Byte rate:

    gis=# \x
    Expanded display is on.
    gis=# select * from pgb_stat_bgwriter;
    -[ RECORD 1 ]---------+------------------------------
    sample                | 2021-01-20 04:14:37.272058-05
    runtime               | 09:21:35.39257
    checkpoint_timed_pct  | 63.000
    minutes_to_checkpoint | 51.054
    alloc_byte_rate       | 22117176.395
    write_byte_rate       | 69419953.093
    checkpoint_byte_rate  | 3226021.125
    clean_byte_rate       | 17072286.486
    backend_byte_rate     | 49121645.482
    checkpoint_write_time | 9243341
    checkpoint_sync_time  | 21670
    checkpoint_write_avg  | 0.697
    checkpoint_sync_avg   | 0.002
    max_clean_rate        | 0.995
    bytes_backend_fsync   | 0

Rate version with MB/ms:

    gis=# select * from pgr_stat_bgwriter;
    -[ RECORD 1 ]---------+------------------------------
    sample                | 2021-01-20 04:17:52.251859-05
    runtime               | 09:24:50.372371
    checkpoints_timed     | 7
    checkpoints_req       | 5
    checkpoint_timed_pct  | 58.000
    minutes_to_checkpoint | 47.070
    alloc_mbps            | 21.121
    checkpoint_mbps       | 3.280
    clean_mbps            | 16.259
    backend_mbps          | 47.653
    total_write_mbps      | 67.192
    max_clean_rate        | 0.990
    bytes_backend_fsync   | 0
    avg_chkp_write_ms     | 649.621
    avg_chkp_sync_ms      | 1.523

# Background

PostgreSQL comes with some basic built-in system metrics in its [src/backend/catalog/system_views.sql](https://github.com/postgres/postgres/blob/master/src/backend/catalog/system_views.sql) source code, what are usually called the _pg_stat*__ views.  Views are just memorized queries.  Those views summarize a variety of internal system counters in a way that's easy for the database to export.  Some of them are more exposed troubleshooting points than user facing reporting.  

By nature of core PostgreSQL's mandate not to ship management tools with GUI interfaces itself, the scope for these views is limited.  But there's nothing stopping someone from building better but still text system views.  Everyone who administers PostgreSQL systems have some of these views around, little report queries like "Least Used Index" and such.  Some of them live on the [wiki snippets](https://wiki.postgresql.org/wiki/Category:Snippets), others in the logic of tools like Nagios plug-ins.

There isn't a great route for contributing improved views from all our personal toolkits back into core.  It's a big project to grade the summary options, prove they are useful, and stand by their value.  _pg\_goggles_ is that project.

# Credits

The PostgreSQL benchmarking work that lead to this project was sponsored by a year long R&D effort within Crunchy Data Inc.
