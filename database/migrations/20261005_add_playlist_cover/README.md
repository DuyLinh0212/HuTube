# Add playlist cover URL

Adds nullable `public.playlists.cover_url`, used by playlist summaries and
playlist detail responses. The EF migration is
`20261005100000_PlaylistCover` in the Infrastructure project.

The reported Neon error (`42703: column p.cover_url does not exist`) confirms
the API schema is behind the current model. Apply `up.sql` in the intended
Neon branch's SQL Editor, or deploy the API migration runner with
`dotnet HuTube.Api.dll --migrate`. The SQL uses `IF NOT EXISTS`, so either
order is safe if the column has already been added.

Verify the selected database and schema before applying:

```sql
SELECT current_database(), current_schema();
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'playlists'
  AND column_name = 'cover_url';
SELECT "MigrationId"
FROM public."__EFMigrationsHistory"
WHERE "MigrationId" = '20261005100000_PlaylistCover';
```

After deployment, verify both playlist list and detail endpoints. If the SQL
was applied manually, leave migration history to EF: the next `--migrate` run
will detect the column, skip its idempotent `ADD COLUMN`, and record the EF
migration. No down script is provided because dropping the column would erase
uploaded playlist cover references.
