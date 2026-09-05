# PostgreSQL bootstrap baseline

Source: the supplied `database/HuTube.sql` from outside this repository. `up.sql` preserves the corrected lean schema with exactly 42 base tables. S4-01/02 adds authentication columns and role seeds through the follow-up `AuthCompatibility` migration; it does not add auth tables.

The EF `202609050001_Bootstrap` migration embeds the same SQL, with outer BEGIN/COMMIT removed so EF controls the transaction. Apply using `dotnet HuTube.Api.dll --migrate` or the documented local setup script. Reapplying through EF is a no-op recorded in `__EFMigrationsHistory`.

Take a `pg_dump` backup before applying to an existing database. Existing tables are not rebuilt; a database with a divergent historical schema must be reviewed and upgraded with a separate migration. Do not treat CREATE TABLE IF NOT EXISTS as schema reconciliation.

Rollback: bootstrap creates the full shared business schema, so automated Down intentionally refuses to destroy it. Restore the pre-migration backup. For a new disposable test database, drop that isolated database only. Subsequent migrations must carry their own rollback strategy. The EF model snapshot tracks the auth projection, while this baseline owns the remaining schema until later features map it.
