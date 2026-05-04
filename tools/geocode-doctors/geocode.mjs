/**
 * Bulk-geocode doctor addresses and write latitude/longitude on public.doctors.
 *
 * Env:
 *   GOOGLE_GEOCODING_API_KEY
 *   SUPABASE_URL
 *   SUPABASE_SERVICE_ROLE_KEY
 *
 * Options:
 *   --delay-ms=250
 *   --governorate=البصرة
 */

import { createClient } from "@supabase/supabase-js";

const GEO_SUFFIX = " Basra Iraq";

const args = Object.fromEntries(
  process.argv.slice(2).map((a) => {
    const [k, ...rest] = a.replace(/^--/, "").split("=");
    return [k, rest.length ? rest.join("=") : true];
  }),
);

const delayMs = Math.max(0, Number(args["delay-ms"] ?? 250));
const governorate = args.governorate ?? "البصرة";

const geocodeKey = process.env.GOOGLE_GEOCODING_API_KEY;
const supabaseUrl = process.env.SUPABASE_URL;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!geocodeKey || !supabaseUrl || !serviceKey) {
  console.error(
    "Need GOOGLE_GEOCODING_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY",
  );
  process.exit(1);
}

const supabase = createClient(supabaseUrl, serviceKey);

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

async function geocodeAddress(address) {
  const q = `${String(address).trim()}${GEO_SUFFIX}`;
  const url = new URL("https://maps.googleapis.com/maps/api/geocode/json");
  url.searchParams.set("address", q);
  url.searchParams.set("key", geocodeKey);
  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`HTTP ${res.status}`);
  }
  const data = await res.json();
  if (data.status !== "OK" || !data.results?.length) {
    return {
      ok: false,
      status: data.status,
      lat: null,
      lng: null,
      query: q,
    };
  }
  const loc = data.results[0].geometry.location;
  return {
    ok: true,
    status: data.status,
    lat: loc.lat,
    lng: loc.lng,
    query: q,
    formatted: data.results[0].formatted_address,
  };
}

async function fetchDoctors() {
  const pageSize = 1000;
  const rows = [];
  let from = 0;
  for (;;) {
    const { data, error } = await supabase
      .from("doctors")
      .select("id,name,spec,addr,gove,latitude,longitude")
      .eq("gove", governorate)
      .order("id", { ascending: true })
      .range(from, from + pageSize - 1);
    if (error) {
      throw error;
    }
    if (!data?.length) {
      break;
    }
    rows.push(...data);
    if (data.length < pageSize) {
      break;
    }
    from += pageSize;
  }
  return rows;
}

async function main() {
  const rows = await fetchDoctors();
  console.log(`Supabase: ${rows.length} doctors (gove=${governorate})`);
  let ok = 0;
  let skipped = 0;
  let failed = 0;

  for (const row of rows) {
    const id = row.id;
    const name = row.name ?? "";
    const addr = (row.addr ?? "").trim();
    if (!addr) {
      console.warn(`[skip empty address] id=${id} name=${name}`);
      skipped++;
      await sleep(delayMs);
      continue;
    }
    if (
      typeof row.latitude === "number" &&
      typeof row.longitude === "number" &&
      !args.force
    ) {
      console.log(`[skip has coords] id=${id}`);
      skipped++;
      await sleep(delayMs);
      continue;
    }

    try {
      const g = await geocodeAddress(addr);
      console.log(
        `[geocode] id=${id} name=${name} ok=${g.ok} status=${g.status} lat=${g.lat} lng=${g.lng}`,
      );
      if (!g.ok) {
        console.warn(`[no result] id=${id} name=${name} query=${g.query} api=${g.status}`);
        failed++;
      } else {
        const { error } = await supabase
          .from("doctors")
          .update({
            latitude: g.lat,
            longitude: g.lng,
          })
          .eq("id", id);
        if (error) {
          console.error(`[supabase update] id=${id}`, error);
          failed++;
        } else {
          ok++;
        }
      }
    } catch (e) {
      console.error(`[error] id=${id} name=${name}`, e);
      failed++;
    }
    await sleep(delayMs);
  }
  console.log(`Done. updated=${ok} skipped=${skipped} failed=${failed}`);
}

if (process.argv.includes("--force")) {
  args.force = true;
}

await main();
process.exit(0);
