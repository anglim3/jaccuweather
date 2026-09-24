# Native iOS conversion (personal use)

Scaffold research for a **personal-use, native iOS** client of Jaccuweather. The Cloudflare Worker web app at [weather.janglim.cloud](https://weather.janglim.cloud) stays as-is under `public/` + `build.js`. Native work lives under `ios/`.

This is not an App Store product. The intended install path is Xcode → a single personal device, signed with a free Apple ID.

## Recommendation: SwiftUI (not React Native)

**Choose SwiftUI + URLSession.** Do not wrap the website. Do not use Capacitor, WKWebView-as-the-app, or React Native for this conversion.

### Why SwiftUI fits this repo

| Constraint | SwiftUI | React Native |
|---|---|---|
| Personal, one iPhone, no Android | First-class | Extra JS/native split for no extra platform |
| Not a website-in-a-shell | Real `View`s, Swift Charts, MapKit | Native screens possible, but Metro + a second UI toolkit |
| Reuse of this repo’s data logic | Worker/`public/app.js` are fetch + JSON + DOM. CORS is a **browser** problem; it disappears in-app. The glue is a few URLSession services, not a shared React tree. | Could extract pollen normalizers to JS, but `public/app.js` is tightly coupled to `getElementById` / `innerHTML`. RN would still rewrite the UI and still need Xcode. |
| Sideload with a free Apple ID | Open the `.xcodeproj`, pick Personal Team, Run | Xcode **plus** Node, Metro, CocoaPods/SPM, Hermes. More moving parts for a one-device app. |
| Maps / charts | MapKit + Swift Charts ship with iOS | Third-party maps/charts, extra native modules |
| Secrets | xcconfig / Info.plist / Keychain | `.env` + extra care they are not bundled into JS source maps |
| App Store / OTA | Irrelevant here | RN’s CodePush-style OTA is an App Store-oriented benefit, unused |

The only strong RN argument is “the owner only wants to write JavaScript.” The existing client is vanilla DOM JS, not a reusable module, so RN does not actually save the UI rewrite. Pollen normalization in `build.js` (~400 lines) is the only chunk worth sharing later; porting it to Swift is smaller than standing up RN.

**Decision:** SwiftUI app in `ios/`. Keep Worker pollen JS as the reference implementation; port helpers into `ios/Jaccuweather/Services/` as they are needed.

## How the web app talks to the world today

Verified in-tree (do not treat generated `src/index.js` as source of truth):

- **Forecast (live client):** `public/app.js` `fetchWeather()` calls **Open-Meteo ensemble** directly (`ensemble-api.open-meteo.com`), not `/api/forecast`. Ensemble members are averaged in `normalizeEnsembleWeatherData()`.
- **Geocoding search:** browser → `geocoding-api.open-meteo.com` directly.
- **Reverse geocode:** browser → BigDataCloud `reverse-geocode-client` directly.
- **Tides:** browser → NOAA `mdapi` + `datagetter` (never proxied).
- **Radar:** Ventusky iframe (`initializeVentuskyRadar()`). Lockdown **strips** `/ventusky-proxy`.
- **Pollen + AQI card:** browser → Worker `/api/pollen` (same-origin + per-IP rate limit, then Google → Tomorrow.io → Open-Meteo).
- **US alerts:** browser → Worker `/api/nws-points` then `/api/alerts/...` (User-Agent required by NWS).
- **Worker `/api/forecast`, `/api/geocoding`, `/api/reverse`, `/api/air-quality`, `/api/nws-wms`:** defined in `build.js` for CORS/caching; several are unused by the current client.

Native iOS does not need the Cloudflare edge. URLSession has no CORS. Caching, User-Agent, and pollen key handling move into the app (or a tiny optional local helper).

## Module map (Worker `/api` → native services)

| Web path / call | Upstream | Native type | Scaffold status |
|---|---|---|---|
| Ensemble forecast in `fetchWeather()` | `https://ensemble-api.open-meteo.com/v1/ensemble` | `WeatherService` | **Follow-up.** Ensemble averaging is non-trivial. Scaffold uses the **single-model forecast** API instead (same variables, `current` object, 14-day + 2 past days, °F / mph / inch). |
| `/api/forecast` | `https://api.open-meteo.com/v1/forecast` | `WeatherService` | **Live** in scaffold. Matches this Worker route; closer to a clean `Codable` model than ensemble members. |
| `/api/geocoding` | `https://geocoding-api.open-meteo.com/v1/search` | `GeocodingService.search` | **Live** |
| `/api/reverse` | `https://api.bigdatacloud.net/data/reverse-geocode-client` | `GeocodingService.reverse` | **Live** |
| `/api/air-quality` | `https://air-quality-api.open-meteo.com/v1/air-quality` | `PollenService` (Open-Meteo branch) | **Live** (AQI + pollen fallback) |
| `/api/pollen` | Google Pollen → Tomorrow.io → Open-Meteo | `PollenService` | Open-Meteo **live**. Google/Tomorrow **opt-in** via local secrets; cascade order preserved. Same-origin gate is N/A off-Worker. |
| `/api/nws-points` | `https://api.weather.gov/points/{lat},{lon}` | `AlertsService` | **Live** (US bounding box, NWS User-Agent) |
| `/api/alerts/...` | `https://api.weather.gov/alerts/...` | `AlertsService` | **Live** |
| `/api/nws-wms` | `https://opengeo.ncep.noaa.gov/geoserver/ows` | unused by the app | Historical Worker route. The iOS overlay does not call it. |
| NOAA tides (client) | `api.tidesandcurrents.noaa.gov` | `TideService` (not created yet) | **Stub later.** Same URLs as `public/app.js`. |
| Ventusky iframe | `https://www.ventusky.com/?p=lat;lon;7&l=rain` | website only | iOS radar does not link out or embed it. |
| Favorites IndexedDB / `weatherFavorites` | local | `FavoritesStore` | **UserDefaults JSON** (SwiftData later if needed) |
| Health scores | pure functions in `public/app.js` | `HealthScores` | **Ported** sinus 0–4 + allergy-from-pollen. Nice-weather index is a placeholder until daily averages are fully ported. |

Shared HTTP details live in `ios/Jaccuweather/Services/APIEndpoints.swift` so URLs stay in one place.

### What not to port from the Worker

- Pollen **same-origin 403** and **POLLEN_RATE_LIMIT** (20 / 60s / IP). Those protect billed keys on a **public** hostname. A personal app is one user; device-local throttling (`~1 request per location change`) is enough.
- `Access-Control-Allow-Origin` and the Ventusky HTML proxy (already stripped by lockdown).
- Edge caching (10 min forecast / 1 h geocoding). Use `URLCache` or a small in-memory TTL if chatter becomes an issue.
- Serving HTML/JS/icons. Native UI replaces that.

## Pollen / secrets (off same-origin)

Production Worker (`build.js` `handlePollenRequest` + `lockdown-worker.js`):

1. Same-origin gate, then `POLLEN_RATE_LIMIT`, then:
2. `GOOGLE_POLLEN_API_KEY` → Google `forecast:lookup` (5 days), normalize, **do not invent species from `TREE`** (category `TREE` → `tree_pollen` only; alder/birch/olive stay `null` unless Google reported those plants).
3. Else `TOMORROW_API_KEY` → Tomorrow.io grass/weed indexes scaled `index * 50`.
4. Else Open-Meteo air-quality pollen + US AQI.

### Chosen approach for the iOS app

**Direct vendor calls from the app. Keys only on the owner’s machine. Open-Meteo remains the no-key default.**

1. **Default / CI / clone:** no keys. `PollenService` uses Open-Meteo (`X-Pollen-Source` equivalent: `open-meteo`). Coarse categories, same as Worker Previews.
2. **Optional upgrade:** copy `ios/.env.example` → `ios/.env` (gitignored) **and/or** fill `ios/Jaccuweather/Config/Secrets.xcconfig` (gitignored if you replace it with a local-only file; the committed file is empty placeholders only).
3. **Xcode:** `Secrets.xcconfig` maps `GOOGLE_POLLEN_API_KEY` and `TOMORROW_API_KEY` into `Info.plist`. `Secrets.swift` reads them at runtime. Empty string → skip that vendor.
4. **Never** commit real keys. Never put keys in Swift source, README, or the research doc.
5. **Google:** create an iOS-restricted API key (bundle id `cloud.janglim.jaccuweather`) on a personal Google Cloud project. Billing may still be required by Maps Platform even at tiny quota — that is a Google account setting, not an Apple fee.
6. **Tomorrow.io:** query param `apikey`. Prefer a key used only on this device. Binary extraction is a theoretical risk; acceptable for a personal sideload. Do not reuse the production Worker secret if you want blast-radius isolation.
7. **Do not** stand up a new public proxy. A tiny `localhost` helper is optional later if a vendor blocks mobile IPs; it is not needed for Open-Meteo.

Null vs none: keep the product rule. Plants Google did not report stay `null`. Do not backfill alder/birch/olive from category `TREE`.

## Radar / map strategy

**Shipped:** the iOS radar tab uses RainViewer tiles on MapKit. See [native-ios-radar.md](native-ios-radar.md). The Ventusky rows below are the original scaffold notes. The website iframe is unchanged.

| Option | Fit | Tradeoff |
|---|---|---|
| **MapKit** (chosen default) | Native, works offline-ish for base map, no iframe, free Apple ID OK | No Ventusky-quality global radar by default |
| **NWS WMS tiles** on MapKit (`opengeo.ncep.noaa.gov`) | Closest to `/api/nws-wms`; no CORS in URLSession / `MKTileOverlay` | US only; WMS quirks (CRS, time dimension) already painful in the Worker |
| **RainViewer / similar tile API** | Easy `MKTileOverlay` | Third-party ToS / availability; not what the web app uses |
| **WKWebView → Ventusky URL** | Pixel-parity with the website | Still a web surface. Third-party UI, cookie/ToS, possible `window.open`, blank loads (already a known web issue). Acceptable as an **optional** sheet for personal use, not as the app shell. |
| Safari `Link` to Ventusky | Zero embed risk | Leaves the app |

**v1:** MapKit centered on the selected location + a button that opens Ventusky in-app (WKWebView) or in Safari. **v2:** NWS radar overlay for CONUS.

## Free Apple ID + Xcode sideload

No Apple Developer Program ($99) is required.

1. Install Xcode from the Mac App Store.
2. Signing & Capabilities → Team → **Add Apple ID** → Personal Team.
3. On the iPhone: enable **Developer Mode** (iOS 16+: Settings → Privacy & Security → Developer Mode).
4. Plug in the device (or use wireless debugging), pick it as the run destination, Run.
5. First launch: Settings → General → VPN & Device Management → trust the developer certificate.

### Limits that matter here

| Topic | Free Apple ID | Impact on this app |
|---|---|---|
| Certificate lifetime | **7 days**, then re-plug Xcode and Run again | Annoyance, not a blocker |
| Push (APNs) | No | Do not plan severe-weather push |
| CloudKit / iCloud KVS | No | Favorites stay on-device (`UserDefaults` / later files) |
| Associated Domains, Apple Pay, IAP | No | Unused |
| Background location / some background modes | Often unavailable or flaky | Request **When In Use** only |
| MapKit, Core Location, URLSession, Swift Charts, WebKit | Yes | Enough for weather, search, radar sheet |
| Devices / App IDs | Small caps (historically ~3 apps installed / limited App IDs) | Fine for one weather app |
| Capabilities that need entitlements | Avoid anything that requires a paid portal | Location When In Use is the only extra permission |

ATS: all current upstreams are HTTPS. No ATS exception.

## Feature coverage vs web app

| Feature | Native plan |
|---|---|
| Current conditions (temp, feels, humidity, wind, UV, pressure) | Scaffold **Now** tab, live Open-Meteo |
| 48h / 14-day lists | Scaffold **Forecast** tab (list; Charts placeholder) |
| Hourly/daily ApexCharts modals | Later: Swift Charts |
| Sunrise/sunset, moon | Later (SunCalc port or `Astronomy` / manual phase) |
| Sinus / allergy / nice-weather | Sinus + allergy in **Health** tab; nice-weather later |
| Pollen 5-day | Open-Meteo now; Google/Tomorrow when keys exist |
| Radar | RainViewer tiles on MapKit (see `docs/native-ios-radar.md`). Website stays Ventusky |
| NWS alerts | Live fetch, simple list |
| NOAA tides | Later |
| Search autocomplete | Live Open-Meteo geocoding sheet |
| Geolocation | Core Location When In Use |
| Favorites | On-device store, scaffold wired |
| Theme / glass UI | Dark glass-inspired SwiftUI, not a pixel clone |

## Project layout

```
ios/
  README.md                 # Open in Xcode, run on a device
  .env.example              # Empty pollen key placeholders
  scripts/verify-open-meteo.mjs
  Jaccuweather.xcodeproj/
  Jaccuweather/
    JaccuweatherApp.swift
    ContentView.swift       # Tabs: Now, Forecast, Health, Radar
    Services/               # Direct upstreams, no Cloudflare
    Views/
    Config/Secrets.xcconfig # Empty placeholders only
```

Web paths (`public/`, `build.js`, `lockdown-worker.js`, `src/index.js` generated) are unchanged.

## How to prove the data layer without a Mac

This Linux environment cannot compile the `.xcodeproj`. `ios/scripts/verify-open-meteo.mjs` hits **ensemble-api.open-meteo.com** (same URL as `fetchWeather()` / `WeatherService`) and runs `normalizeEnsembleWeatherData`.

```bash
node ios/scripts/verify-open-meteo.mjs
node --test tests/*.test.js
```

Feature close-out vs the live site: [`docs/native-ios-parity.md`](native-ios-parity.md). Sideload: [`ios/README.md`](../ios/README.md).

## Follow-up status (personal iOS, not merged)

Items below were the scaffold open questions. They are closed on `cursor/native-ios-personal-34dc` except the operational ones that cannot be closed in Linux CI.

1. **Ensemble vs forecast.** **DONE.** Native calls the ensemble API and runs the website `normalizeEnsembleWeatherData`.
2. **Google Pollen billing + iOS key restriction.** Documented. Blank `Secrets.xcconfig` → Open-Meteo. Owner must create a billing-capable, iOS-restricted key for species detail.
3. **NWS User-Agent.** **DONE** as editable `NWS_USER_AGENT` in `Secrets.xcconfig` (placeholder contact).
4. **Ventusky.** **DONE** as Safari link-out (preferred vs WKWebView/ToS). MapKit + NWS WMS overlay are in-app.
5. **Weekly re-sign.** Still a free Apple ID limit. Documented in `ios/README.md`.
6. **Meteocons.** **DONE.** Vendored under `ios/Jaccuweather/Resources/Icons/{weather,cards,alerts}`.
7. **Health-score parity.** **DONE.** Sinus, allergy, and nice-weather use the extracted website functions.
8. **No local backend.** Still true. Direct vendor calls from the device.
9. **No Xcode in this environment.** Still true. Owner confirms UI on a Mac + device with `open ios/Jaccuweather.xcodeproj`.

## References (in-repo)

- Worker routes: `README.md` “Worker routes”, `build.js` `/api/` branch, `handlePollenRequest`
- Client forecast / radar / alerts: `public/app.js` (`fetchWeather`, `fetchWeatherAlerts`, `fetchAirQuality`, `initializeVentuskyRadar`)
- Pollen null rule: `tests/pollen-null-handling.test.js`, `AGENTS.md` “Do not”
- Sideload: `ios/README.md`
