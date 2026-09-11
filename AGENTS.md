# AGENTS.md — Guide for Coding Agents

## Overview

Weather app deployed as a **single Cloudflare Worker**. Vanilla JavaScript, no
framework; everything renders client-side. The Worker embeds the HTML/JS and
proxies external APIs so the browser avoids CORS errors.

**Demo:** [weather.janglim.cloud](https://weather.janglim.cloud)

Features: current conditions (temp, feels-like, humidity, wind, UV, pressure
trend, AQI), sunrise/sunset arc, moon-phase details, 48-hour forecast,
14-day forecast, ApexCharts detail modals, health scores (sinus risk, allergy
risk, nice-weather index, each with a methodology modal), pollen levels plus
5-day pollen forecast, Ventusky radar centered on the location, NWS alerts
for US locations, NOAA tides for coastal locations, city search with
autocomplete, geolocation, and local favorites.

## Stack

- Runtime/build: Cloudflare Workers + Wrangler (`^4.54.0`), Node.js 16+.
- Frontend: vanilla ES6+ JS, Tailwind CSS (CDN), ApexCharts 4.7.0 (charts —
  **not** Chart.js), SunCalc (moon times), MathJax (methodology modals),
  Font Awesome (icons), Leaflet + leaflet.wms (NWS radar tiles).
- Data: Open-Meteo (forecast, geocoding, air quality), BigDataCloud (reverse
  geocode), Google Pollen API (primary pollen, optional secret), Tomorrow.io
  (pollen fallback, optional secret), NWS (alerts, points, radar WMS), NOAA
  (tides, fetched client-side), Ventusky (radar iframe, direct URL).
- Core weather works with no keys. Pollen falls back to Open-Meteo without
  secrets.

## Source of truth

Edit `public/index.html` and `public/app.js` (plus `public/favicon.svg` and
other `public/` assets). **`src/index.js` is generated — never hand-edit it.**
The build overwrites it. `README.md` + code are truth; this file replaces the
removed `CLAUDE.md`, which was stale.

## Build

```bash
npm install        # first time only
npm run build      # node build.js && node lockdown-worker.js
```

1. `build.js` converts the favicon (warns and continues if `sharp` is
   missing), then inlines `public/index.html`, `public/app.js`, and icons
   into `src/index.js`, including the `/api/*` proxy handlers.
2. `lockdown-worker.js` post-processes `src/index.js`: it applies
   `patches/app-01.patch` … `patches/app-10.patch` to the embedded JS and
   `patches/index.html.patch` to the embedded HTML, enforces the pollen
   same-origin gate + per-IP rate limit (`POLLEN_RATE_LIMIT` in
   `wrangler.toml`), strips the Ventusky HTML proxy, and **fails closed**
   (throws, failing the build) if any expected security/client patch did not
   land. A successful build prints the `lockdown-worker: ...` line.

Because patches apply with exact context matching, **any change to
`public/app.js` line content/ordering can break patch hunk offsets** — run
`npm run build` after editing and fix/rebase the affected patch if lockdown
reports a hunk mismatch.

## Dev / deploy

| Script            | Action                              |
|-------------------|-------------------------------------|
| `npm run dev`     | Build + start local Worker (`wrangler dev`) |
| `npm run deploy`  | Build + deploy Worker (`weather-app` per `wrangler.toml`) |

After editing `public/`, rebuild and restart `wrangler dev`; changes do not
hot-reload. If the default port is busy, run `npm run build` then
`npx wrangler dev --ip 127.0.0.1 --port <free-port>`.

Optional pollen secrets (Worker secrets, not in repo):

```bash
npx wrangler secret put GOOGLE_POLLEN_API_KEY
npx wrangler secret put TOMORROW_API_KEY
```

Local `wrangler dev` does not load remote secrets; use
`npx wrangler dev --remote ...` to test with production secrets.

## Architecture

- `build.js` output serves embedded assets (`/`, `/app.js`, `/favicon.svg`,
  `/apple-touch-icon.png`) and proxies `/api/*` with caching (forecast
  10 min, geocoding 1 h), 30 s timeout, and retry-with-backoff on 429s from
  Open-Meteo.
- Worker `/api/*` routes (defined in `build.js`): `forecast` → Open-Meteo;
  `geocoding` → Open-Meteo geocoding; `reverse` → BigDataCloud;
  `air-quality` → Open-Meteo air quality; `pollen` → Google, then
  Tomorrow.io, then Open-Meteo; `alerts` and `nws-points` → NWS (with
  `User-Agent` header, US only); `nws-wms` → NWS radar tiles with CORS
  headers and transparent-PNG fallback on errors.
- `/ventusky-proxy/*` exists in `build.js` output but **lockdown strips it**:
  the deployed worker has no Ventusky HTML proxy. The client embeds Ventusky
  directly (`https://www.ventusky.com/?p=<lat>;<lon>;7&l=rain`) via
  `initializeVentuskyRadar()` in `public/app.js`.
- Tides are fetched client-side from NOAA (`api.tidesandcurrents.noaa.gov`),
  not through the Worker.
- Favorites: IndexedDB (`WeatherAppDB`, `favorites` store) with localStorage
  (`weatherFavorites`) fallback and auto-migration. Theme preference is
  browser-only.

## Lockdown / security invariants

- `/api/pollen` is same-origin gated (non-same-origin → 403) and per-IP
  rate-limited (20 req / 60 s per `CF-Connecting-IP`, missing IP → 403)
  **before** `handlePollenRequest`, which can call billed Google/Tomorrow
  APIs. Do not weaken, reorder, or bypass these gates.
- Lockdown removes `Access-Control-Allow-Origin: *` from the shared
  `jsonResponse` helper. Do not add it back and do not add new `*` CORS
  headers on JSON responses. Do not reintroduce `/ventusky-proxy`.
- If you touch `public/app.js`, rebase `patches/app-*.patch` hunk offsets so
  `npm run build` still applies cleanly.

## Tests

Node tests exist under `tests/` (built on `node:test` + `vm`, no extra
dependencies). Run:

```bash
node --test tests/*.test.js
```

| File | Covers |
|------|--------|
| `pollen-null-handling.test.js` | Google/Tomorrow pollen normalization, null-vs-none display metadata |
| `pollen-rate-limit.test.js` | Per-IP pollen limiter behavior in `lockdown-worker.js` |
| `precip-timing.test.js` | Precipitation start timezone handling |
| `daily-modal-sun.test.js` | Daily modal sunrise/sunset day indexing |
| `daily-modal-chart-default.test.js` | 14-day chart first-paint temperature default |
| `daily-modal-details.test.js` | Per-day details under the 14-day chart |
| `moon-times.test.js` | Moonrise/moonset in location timezone |

Manual check: `npm run dev`, open the printed URL, exercise search,
geolocation, favorites, hourly/daily modals, health tiles, radar, and mobile
viewport via DevTools. Syntax check before shipping:

```bash
node --check public/app.js && node --check build.js && npm run build && node --check src/index.js
```

## Common tasks

- **Add a weather metric**: check Open-Meteo params, extend the forecast URL
  in `fetchWeather()` (`public/app.js`), add the element in `index.html`,
  render it in the display path.
- **Change a proxy route**: edit the `/api/` block in `build.js`
  (not `src/index.js`), then `npm run build`. Never add billed upstreams
  outside the pollen same-origin + rate-limit gates.
- **Add a health tile**: follow `calculateSinusRisk`/`calculateAllergyRisk`
  in `public/app.js`, add the tile in `index.html`, add a methodology modal
  if the score needs explaining.
- **Radar**: Ventusky iframe URL lives in `initializeVentuskyRadar()`; NWS
  tile proxy is the `nws-wms` branch in `build.js`. Keep the direct-Ventusky
  approach — do not restore the stripped HTML proxy.

## Conventions

Vanilla ES6+ (arrow functions, template literals, async/await), no
TypeScript, no framework. camelCase functions/variables (`fetchWeather`,
`currentLat`) and DOM ids (`hourlyForecast`). Direct DOM manipulation
(`getElementById`, `innerHTML`). Tailwind utilities plus custom
`.card`/`.skeleton`/`.modal` classes in the `<style>` block in `index.html`.

## Do not

- Hand-edit `src/index.js` (generated; overwritten every build).
- Weaken the pollen same-origin gate or rate limit, or call billed pollen
  APIs from a new ungated route.
- Reintroduce `/ventusky-proxy` or `Access-Control-Allow-Origin: *` on JSON.
- Invent species pollen from the Google `TREE` category: plants Google did
  not report stay `null` (intended product rule — an open PR moves
  category-level `TREE` data onto `tree_pollen` only; until it merges, main
  still backfills alder/birch/olive from `TREE`, so write new code against
  the null rule).
