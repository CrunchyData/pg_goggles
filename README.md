# Introduction

_pg\_goggles_ provides better annotated and summarized views into the PostgreSQL database's cryptic internal counters.  These are intended for systems where access to the database port (typically 5432) is routine, whether that be for a ``psql`` client, a development language driver, or or opening communication with a monitoring server.  The views should supplement a full long-term metrics monitoring solution rather than replace it.

# Installation

_pg\_goggles_ can be installed by just running the software's SQL code against one database:

    # psql -d gis -x -f pg_goggles.sql # Expand flag on command line
    # SELECT * FROM pgb_stat_database;

Output from the PG Goggles approach has a lot of columns.  That's why the "-x" flag was used above to list columns across lines rather than horizontal space.  You can also swap that option around with the "\x" psql command:

    # psql -d gis -f pg_goggles.sql # Add expand flag as an option later
    gis=# \x                        # Now
    Expanded display is on.
    x
# Usage

The goggles views use a single letter code after the "pg" to select which type of view:

* *G* - `pgg_stat`:  `Goggles` basic view.  Pages and buffers are decoded into bytes.  Highly useful catalog data is added.  Fields are renamed with minimal changes, so that the pgg version of the view can be swapped in for scripts using the regular one with minimal changes.
* *B* - `pgb_stat`:  `Byte` rate.  Rates are bytes per second or event/second unless otherwise labeled.  Times are in seconds.  The formatting for some fields is reordered to make byte/MiB units at the end.  Suitable for further machine parsing and processing.
* *R* - `pgr_stat`:  `Rate` scaled to suggested units for administrator use.  This may use megabytes/second (MB/s) for some values and times in milliseconds for others.
* *P* - `pgp_stat`:  `Pretty` print of rate view.  Uses _pg\_size\_pretty()_ to help scale large values.  This view is not easily machine readable; use the _pgr_ version for that instead.

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

Rate version with mega/milli prefix scaling to put units in the right range for human review.  _rate\_mib_ is a 1024-based megabyte per second (MiB/s) value:

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

Allocation is when the database initializes a new buffer to hold 8K of data.   The write total here considers only the writes listed below it:  checkpoints, the background cleaner, and client backends writing dirty data themselves.  Other sources of database writes include temporary files (accounted at the database level), the write-ahead log (probably worth its own Goggles view), and low volume metadata like the Commit Log (_pg\_clog_ directory).

# Background

PostgreSQL comes with some basic built-in system metrics in its [src/backend/catalog/system_views.sql](https://github.com/postgres/postgres/blob/master/src/backend/catalog/system_views.sql) source code, what are usually called the _pg_stat*__ views.  Views are just memorized queries.  Those views summarize a variety of internal system counters in a way that's easy for the database to export.  Some of them are more exposed troubleshooting points than user facing reporting.  

By nature of core PostgreSQL's mandate not to ship management tools with GUI interfaces itself, the scope for these views is limited.  But there's nothing stopping someone from building better but still text system views.  Everyone who administers PostgreSQL systems have some of these views around, little report queries like ["Least Used Index"](https://wiki.postgresql.org/wiki/Index_Maintenance) and such.  Some of them live on the [wiki snippets](https://wiki.postgresql.org/wiki/Category:Snippets), others in the logic of tools like the [check_postgres](https://bucardo.org/check_postgres/) Nagios plug-in.

PostgreSQL has a whole list of [monitoring projects](https://wiki.postgresql.org/wiki/Monitoring).  There isn't a great route for them to contribute improved views from all these toolkits back into core.  It's a big project to grade the summary options, prove they are useful, and stand by their value.  _pg\_goggles_ is that project.

# Scope

Completed views:

* _pg\_stat\_bgwriter_, _pg\_stat\_database_.

Targets for near future development:

* _pg\_stat\_statements_:   Switch to bytes/MiB and provide a rate version.
* _pg\_tables_, _pg\_stat\_all\_tables_, _pg\_statio\_all\_tables_:  Convert to byte units, rate versions.
* _pg\_indexes_, _pg\_stat\_all\_indexes_, _pg\_statio\_all\_indexes_:  Conbert to byte units.
* _pg\_settings_:  Numeric values should be easier to lookup.
* _pg\_locks_:  Include the standard recursive lock nagivator.
* _pg\_stat\_activity_:  Might improve on waiting information.

Future views:
* _pg\_stat\_relations_:  Combined table and index view.

Eventually _pg\_goggles_ may expand to where it's packaged in an extension or some other form for easier testing and use.

# Credits

The PostgreSQL benchmarking work that lead to this project was sponsored by a year long R&D effort within Crunchy Data led by Greg Smith.

The name was inspired by the yearning of [The Goggles Do Nothing](https://knowyourmeme.com/memes/the-goggles-do-nothing) crossed with the optimism of ["Rose Coloured Glasses"](https://www.youtube.com/watch?v=Gp8knr8Ho-4), from the band Animal Logic's second album.