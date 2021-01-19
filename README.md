# pg_goggles

_pg\_goggles_ provides better annotated and summarized views into the database's cryptic internal counters.  These are intended for systems where access to the database port (typically 5432) is routine.

# Background

PostgreSQL comes with some basic built-in system metrics in its [src/backend/catalog/system_views.sql](https://github.com/postgres/postgres/blob/master/src/backend/catalog/system_views.sql) source code, what are usually called the _pg_stat*__ views.  Views are just memorized queries.  Those views summarize a variety of internal system counters in a way that's easy for the database to export.  Some of them are more exposed troubleshooting points than user facing reporting.  

By nature of core PostgreSQL's mandate not to ship management tools with GUI interfaces itself, the scope for these views is limited.  But there's nothing stopping someone from building better but still text system views.  Everyone who administers PostgreSQL systems have some of these views around, little report queries like "Least Used Index" and such.  Some of them live on the [wiki snippets](https://wiki.postgresql.org/wiki/Category:Snippets), others in the logic of tools like Nagios plug-ins.

There isn't a great route for contributing improved views from all our personal toolkits back into core.  It's a big project to grade the summary options, prove they are useful, and stand by their value.  _pg\_goggles_ is that project.

# Credits

The PostgreSQL benchmarking work that lead to this project was sponsored by a year long R&D effort within Crunchy Data Inc.
