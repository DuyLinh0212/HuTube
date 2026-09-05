-- Development operator utility: psql -v email=verified@example.com -f grant-local-admin.sql
-- Creates admin access for an already verified active account; never creates passwords.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO hutube.admin_accounts(user_id, status)
SELECT user_id, 'active'
FROM hutube.users
WHERE email = :'email'::citext AND status = 'active' AND email_verified_at IS NOT NULL AND deleted_at IS NULL
ON CONFLICT (user_id) DO UPDATE SET status = 'active', disabled_at = NULL;
COMMIT;
SELECT u.email, a.status
FROM hutube.admin_accounts a JOIN hutube.users u ON u.user_id = a.user_id
WHERE u.email = :'email'::citext;
