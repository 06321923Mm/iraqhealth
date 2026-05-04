# Bulk geocode doctor addresses → Supabase

Writes **`lat`** and **`lng`** on `public.doctors` only (no Firebase / Firestore).

## Requirements

- Node.js 18+
- `GOOGLE_GEOCODING_API_KEY` (Geocoding API enabled)
- `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` (server-side only; never ship in the app)

## Setup

```bash
cd tools/geocode-doctors
npm install
```

## Run

```bash
set GOOGLE_GEOCODING_API_KEY=your_key
set SUPABASE_URL=https://....supabase.co
set SUPABASE_SERVICE_ROLE_KEY=your_service_role
npm run geocode
```

Optional:

```bash
node geocode.mjs --governorate=بغداد --delay-ms=300
```

Re-run even when `lat`/`lng` already exist:

```bash
node geocode.mjs --force
```

Addresses are geocoded with suffix **` Basra Iraq`** for regional accuracy.

Apply the SQL migration `20260501120000_doctors_location_supabase.sql` (and RPCs) on your Supabase project before relying on in-app location correction.
