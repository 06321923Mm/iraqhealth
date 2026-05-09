# Troubleshooting — المدار الطبي

## Error: "تعذر تحميل هيكل قاعدة البيانات"

### Symptom
On app startup or when opening the "اقتراح تعديل" sheet, the app displays
**"تعذر تحميل هيكل قاعدة البيانات"** and the report form is blank or disabled.

### Root Cause
`EditSuggestionSchemaService.loadBundle()` calls the Supabase RPC function
`app_edit_suggestion_schema_bundle()` using the anonymous key.  This RPC
introspects `information_schema` to discover the `reports` table structure.

The call can fail for any of these reasons:

| Reason | Indicator |
|--------|-----------|
| RLS policy blocks `information_schema` access | 403 Forbidden in network log |
| RPC function not yet deployed (migration missing) | 404 / function not found |
| Network is unavailable on startup | SocketException / timeout |
| Supabase project in maintenance | 503 |

### Fix Applied (2026-05-09)

`EditSuggestionSchemaService._fetch()` now falls back gracefully:

1. Calls RPC `app_edit_suggestion_schema_bundle()`.
2. **If RPC fails** → tries a lightweight `SELECT id FROM reports LIMIT 1`.
3. **If table query succeeds** → returns a hardcoded `buildFallbackBundle()` from
   `lib/core/services/schema_fallback.dart`.  The bundle contains all known
   columns as of migration `20260510`.
4. **If even the table query fails** → returns `ok: false`, which disables the
   edit-suggestion form gracefully (no crash).

### Manual Actions Required

⚠️ **MANUAL ACTION REQUIRED** — Apply migration `20260510_specializations_ca*.sql`
and ensure the RPC `app_edit_suggestion_schema_bundle` is deployed to your
Supabase project:

```sql
-- Verify in Supabase SQL editor:
SELECT app_edit_suggestion_schema_bundle();
```

If this returns an error, re-run the migration or recreate the function.

### Keeping the Fallback Bundle in Sync

When you add new columns to `reports` or `doctors`, update
`lib/core/services/schema_fallback.dart` to include them so offline / RPC-down
users still get the correct form fields.
