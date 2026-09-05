-- Development operator utility: psql -v email=verified@example.com -f grant-local-admin.sql
-- Grants the admin role to an already verified active account; never creates passwords.
\set ON_ERROR_STOP on
BEGIN;
UPDATE public.users AS u
SET role_id = r.role_id, status = 'active', updated_at = NOW()
FROM public.roles AS r
WHERE r.code = 'admin'
  AND r.status = 'active'
  AND u.email = :'email'::citext
  AND u.status = 'active'
  AND u.email_verified_at IS NOT NULL
  AND u.deleted_at IS NULL;
COMMIT;
SELECT u.email, u.status, r.code AS role
FROM public.users AS u
JOIN public.roles AS r ON r.role_id = u.role_id
WHERE u.email = :'email'::citext;
