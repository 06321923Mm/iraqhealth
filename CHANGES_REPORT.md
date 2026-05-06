# CHANGES REPORT — Al-Madar Al-Tibbi (المدار الطبي)

Generated: 2026-05-06  
Last updated: 2026-05-06 (Phase 2 — Push notifications + Admin guard)

---

## ✅ Database Changes Executed

All migrations applied via `supabase db push --linked`.

| Migration | File | Status | Notes |
|---|---|---|---|
| Pending backlog | `20260505173000_doctors_profile_image_url.sql` | ✅ Applied | Adds `profile_image_url` column |
| Pending backlog | `20260505174500_clinic_profile_images_storage.sql` | ✅ Applied | Creates `clinic-profile-images` bucket |
| Step 1.1 | `20260506100000_doctors_verification_columns.sql` | ✅ Applied | Adds `is_verified`, `current_status`, `status_message`, `status_expires_at` to `doctors` |
| Step 1.2 | `20260506110000_verification_requests_table.sql` | ✅ Applied | Creates `verification_requests` table + trigger |
| Step 1.3 | `20260506120000_verification_rls_policies.sql` | ✅ Applied | RLS for `verification_requests` + doctors update guard |
| Step 1.4 | `20260506130000_verification_docs_storage.sql` | ✅ Applied | Creates private `verification-docs` storage bucket |
| Step 1.5 | `20260506140000_status_expiry_cron.sql` | ✅ Applied + **running** | pg_cron enabled; cron job active (`*/5 * * * *`) |
| Step 1.6 | `20260506200000_user_fcm_tokens.sql` | ✅ Applied | Creates `user_fcm_tokens` table for FCM push notification device tokens |

### Row count verification
- **Before:** 2,072 doctors
- **After:** 2,072 doctors ✅ (no data loss)
- New columns default: `is_verified = false`, `current_status = 'closed'`

---

## ✅ Files Created

### Phase 2 — Core Architecture
- `lib/core/config/app_endpoints.dart` — Centralized table/bucket/API URL constants
- `lib/core/services/base_service.dart` — Abstract Supabase service base class
- `lib/core/components/status_badge.dart` — Status badge widget (متاح/مشغول/مغلق)
- `lib/core/components/verification_badge.dart` — Verification checkmark badge
- `lib/core/components/loading_button.dart` — Button with loading state
- `lib/core/components/section_header.dart` — RTL-aware section header

### Phase 3 — Verification Feature
- `lib/features/verification/data/models/verification_request_model.dart` — Model + `VerificationStatus` enum
- `lib/features/verification/data/repositories/verification_repository.dart` — Upload, submit, stream methods
- `lib/features/verification/presentation/screens/submit_verification_screen.dart` — 3-document upload screen

### Phase 4 — My Clinic
- `lib/features/my_clinic/presentation/widgets/quick_status_widget.dart` — Real-time status toggle with expiry

### Phase 5 — Admin Dashboard
- `lib/features/admin/presentation/layouts/admin_layout.dart` — Sidebar layout (`AdminHubPage`) with `app_metadata.role` admin guard
- `lib/features/admin/presentation/screens/admin_dashboard_screen.dart` — Stats cards + recent requests
- `lib/features/admin/presentation/screens/verification_review_screen.dart` — Paginated review with approve/reject + FCM notifications
- `lib/features/admin/presentation/screens/clinics_management_screen.dart` — Server-paginated clinic table

### Phase 6 — Push Notifications
- `lib/services/fcm_token_service.dart` — Registers device FCM token to `user_fcm_tokens` on login
- `supabase/functions/send-notification/index.ts` — Edge Function: service-account JWT → OAuth2 → FCM HTTP v1 API

### Supabase Migrations
- `supabase/migrations/20260506100000_doctors_verification_columns.sql`
- `supabase/migrations/20260506110000_verification_requests_table.sql`
- `supabase/migrations/20260506120000_verification_rls_policies.sql`
- `supabase/migrations/20260506130000_verification_docs_storage.sql`
- `supabase/migrations/20260506140000_status_expiry_cron.sql`
- `supabase/migrations/20260506200000_user_fcm_tokens.sql`

---

## ✅ Files Modified

| File | Changes |
|---|---|
| `lib/doctor_dashboard/my_clinic_screen.dart` | Full rewrite — added 4 verification states (`verificationNotStarted`, `verificationPending`, `verificationRejected`). Existing claim + editing flows preserved. Switches to `AppEndpoints` constants. Integrates `QuickStatusWidget` in verified state. |
| `lib/main.dart` | Added `/admin/hub` route → `AdminHubPage`. Added `FcmTokenService.register()` in `initState`. |
| `.env.example` | Added `ADMIN_PASSWORD` and `SUPABASE_STORAGE_URL` placeholders. |

---

## ✅ Previously Manual Steps — Now Complete

| Step | Status |
|---|---|
| Enable pg_cron + schedule `expire-doctor-status` | ✅ Done — cron runs every 5 min |
| Set `app_metadata.role = "admin"` on admin user in Supabase Auth | ✅ Done |
| Add Firebase service account secrets to Edge Functions (`FIREBASE_PROJECT_ID`, `FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY`) | ✅ Done |
| Deploy `send-notification` Edge Function | ✅ Done — deployed to project `hygujebngiwemwujjcgm` |

## ⚠️ Remaining Manual Steps

### Storage check
Go to **Storage → Buckets** and confirm `verification-docs` is listed as **private**. The `clinic-profile-images` bucket should remain **public**.

### Access the Admin Hub
The new admin hub is at route `/admin/hub`. Navigate there via:
```dart
Navigator.of(context).pushNamed('/admin/hub');
```
Note: the existing `/admin` route (old dashboard) is **unchanged** and still functional.

---

### Environment Variables

Add to `.env` / `assets/env/flutter.env` and Codemagic/GitHub Actions secrets:

| Variable | Purpose |
|---|---|
| `ADMIN_PASSWORD` | Password gate for admin dashboard (compile-time `--dart-define`) |
| `SUPABASE_STORAGE_URL` | Optional override if storage URL differs from Supabase URL |

---

## 🧪 Testing Checklist

### Database
- [ ] Run `SELECT id, is_verified, current_status FROM doctors LIMIT 5;` — all should return `false`/`closed`
- [ ] Verify `verification_requests` table is empty (new)
- [ ] Verify `verification-docs` bucket exists and is private

### Verification Flow (Doctor)
- [ ] Doctor with claimed+approved clinic sees "توثيق الحساب" CTA in عيادتي
- [ ] Submit 3 document photos → request appears in `verification_requests`
- [ ] Doctor sees "قيد المراجعة" state after submission
- [ ] After admin approval: doctor sees full management hub
- [ ] After admin rejection: doctor sees rejection reason + resubmit button

### Quick Status (Doctor — Verified only)
- [ ] Toggle متاح/مشغول/مغلق → updates `doctors.current_status` immediately
- [ ] Set expiry to "ساعة واحدة" → `status_expires_at` is set ~1hr from now
- [ ] Set expiry to "نهاية اليوم" → `status_expires_at` is set to 23:59:59 UTC today
- [ ] StatusBadge appears in clinic card when doctor `is_verified = true`

### Admin Hub (`/admin/hub`)
- [ ] Sidebar shows on screens ≥ 800px wide; drawer on mobile
- [ ] Non-admin user sees "غير مصرّح بالدخول" access-denied screen
- [ ] Dashboard stats load (total doctors, pending verif, online now)
- [ ] Verification tab: filter by pending/approved/rejected works
- [ ] Clicking a row loads doctor info + signed document URLs
- [ ] Approve button sets `is_verified = true` on the doctor record + sends FCM notification
- [ ] Reject button shows notes dialog, stores `admin_notes` + sends FCM notification with reason
- [ ] Clinics table: pagination (20/page), governorate filter, verified filter
- [ ] Arabic search handles أ/ا/إ and ة/ه normalization

### Push Notifications
- [ ] Install and open app on Android/iOS → FCM token registered in `user_fcm_tokens`
- [ ] Admin approves request → doctor receives "تم قبول طلب التوثيق" notification
- [ ] Admin rejects request → doctor receives "بشأن طلب التوثيق" notification with reason

### Regression — Existing Features
- [ ] Home page loads and displays doctor list (Basra default)
- [ ] Search, filter by specialty/area still work
- [ ] Doctor card opens → phone, map, report all work
- [ ] Favorites (قائمة) tab still works
- [ ] Existing `/admin` route (old dashboard) still accessible
- [ ] Clinic claim workflow still works for new doctors

---

## ❗ Assumptions & Notes

| # | Item |
|---|---|
| 1 | **pg_cron**: Now enabled. Status auto-expiry cron job `expire-doctor-status` runs every 5 minutes. |
| 2 | **Admin guard**: `AdminHubPage` checks `user.appMetadata['role'] == 'admin'` from the Supabase JWT — no extra network call. Non-admin users see a lock screen. |
| 3 | **FCM notifications**: Wired. Approve → "تم قبول طلب التوثيق"; Reject → "بشأن طلب التوثيق" with admin notes. Both calls are non-fatal (`.ignore()`). |
| 4 | **`verification_requests.doctor_id` type**: The spec listed `REFERENCES doctors(id)` but `doctors.id` is an INTEGER. Corrected to `REFERENCES auth.users(id)` to match the RLS policy `auth.uid() = doctor_id`. |
| 5 | **RLS update guard**: Only `is_verified = true` doctors can UPDATE their own profile. Unverified doctors see the verification flow — intentional per spec. |
| 6 | **Admin hub navigation**: The new admin hub is at `/admin/hub`. It is not yet linked from the old `/admin` dashboard — add a navigation button there when ready. |
| 7 | **FCM token registration**: `FcmTokenService.register()` is called on home screen `initState`. Web is skipped (no VAPID key configured). macOS is treated as iOS. |
