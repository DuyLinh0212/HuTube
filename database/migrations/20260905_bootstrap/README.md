# PostgreSQL bootstrap baseline

Source: the supplied `database/HuTube.sql` from outside this repository. `up.sql` preserves that file verbatim, including system seed data and the complete schema for subsequent sprints. Only the authentication projection is implemented in S4-01/02.

The EF `202609050001_Bootstrap` migration embeds the same SQL, with outer BEGIN/COMMIT removed so EF controls the transaction, and `SET LOCAL search_path` so pooled connections do not retain session state. Apply using `dotnet HuTube.Api.dll --migrate` or the documented local setup script. Reapplying through EF is a no-op recorded in `__EFMigrationsHistory`.

Take a `pg_dump` backup before applying to an existing database. Existing tables are not rebuilt; a database with a divergent historical schema must be reviewed and upgraded with a separate migration. Do not treat CREATE TABLE IF NOT EXISTS as schema reconciliation.

Rollback: bootstrap creates the full shared business schema, so automated Down intentionally refuses to destroy it. Restore the pre-migration backup. For a new disposable test database, drop that isolated database only. Subsequent migrations must carry their own rollback strategy. The EF model snapshot tracks the auth projection, while this baseline owns the remaining schema until later features map it.
