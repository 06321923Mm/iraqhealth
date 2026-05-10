-- Security alignment with Flutter admin gate (AdminHubPage + /admin route):
-- The client reads JWT **app_metadata** (`auth.users.raw_app_meta_data`) via
-- `SupabaseUser.appMetadata['role']`, not **user_metadata**, because standard
-- Supabase client updates to user metadata can be performed by the signed-in user.
--
-- Action items (outside this migration, in Supabase Dashboard or an Auth Hook):
-- 1. Assign `role: "admin"` under App Metadata for administrator accounts.
-- 2. Avoid relying on User Metadata alone for privilege escalation checks.

DO $$
BEGIN
  NULL;
END $$;
