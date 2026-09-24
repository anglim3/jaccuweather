# Native iOS vs weather.janglim.cloud

Personal-use SwiftUI app on `ios/`. Same upstreams as the website after lockdown (no Cloudflare Worker, no Ventusky HTML proxy). Logic that must match the site is extracted from `public/app.js` + `build.js` into `ios/Jaccuweather/Resources/Logic/jaccuweather-logic.js` and run in JavaScriptCore.

| Web feature | Native status |
|---|---|
| Open-Meteo ensemble (`icon_seamless,gfs_seamless,ecmwf_ifs025`) + `normalizeEnsembleWeatherData` | **DONE** — `WeatherService` + JS normalize (mean / medianFloor WMO / derived precip probability) |
| Current conditions (temp, feels, humidity, wind, UV, pressure trend, dew) | **DONE** — Now tab |
| Sunrise/sunset arc | **DONE** — half-ellipse matches the site SVG; dot uses location-local sunrise/sunset + `utc_offset_seconds` and ticks each minute (gold by day, moon when the sun is down) |
| Moon phase / rise / set in city TZ (`utc_offset_seconds` + SunCalc) | **DONE** — Now + Moon sheet |
| 48-hour forecast + UV/precip/wind/humidity/pressure charts | **DONE** — Forecast tab, Swift Charts; wind chart is speed + gust; pressure axis is inHg |
| 14-day forecast, WMO icons, **30% rain-icon downgrade** | **DONE** — `getWeatherIconFile(code, true, precipProbability)` |
| 14-day UV (`uv_index_max`) | **DONE** |
| Meteocons fill weather icons (SMIL in WKWebView wrappers) | **DONE** — `Resources/Icons/weather` |
| Static card-header Meteocons | **DONE** — `Resources/Icons/cards` |
| NWS alerts + Meteocons alarm icons | **DONE** — list plus detail sheet (severity, instruction, ends) |
| Sinus risk + methodology | **DONE** — same `calculateSinusRisk` |
| Allergy risk + methodology | **DONE** — same `calculateAllergyRisk` |
| Nice-weather index + methodology | **DONE** — same `getNiceWeatherBreakdown` |
| Pollen cascade Google → Tomorrow → Open-Meteo | **DONE** — blank keys skip to Open-Meteo |
| Google `TREE` → `tree_pollen` only (no species invention) | **DONE** — `normalizeGooglePollen` |
| Species rows (alder/birch/olive/mugwort/ragweed) | **DONE** — Now + Health |
| 5-day pollen forecast (daily max of hourly) | **DONE** |
| AQI (US AQI from Open-Meteo air-quality) | **DONE** — shown when Open-Meteo (or merged) current has `us_aqi` |
| NOAA tides (50 km / 20 m elevation, hilo + cosine interpolate) | **DONE** — Now list + Forecast tides chart |
| MapKit default map | **DONE** — Radar tab |
| NWS WMS radar overlay (`nexrad-n0q-wmst`, EPSG:3857) | **Broken upstream** — `LayerNotDefined` as of 2026-09-24. Replacement: [native-ios-radar.md](native-ios-radar.md) |
| Ventusky | Safari link-out is still in the radar tab. The radar plan removes it; do not add a WKWebView |
| City search (Open-Meteo geocoding) | **DONE** |
| Reverse geocode (BigDataCloud) | **DONE** |
| Device geolocation | **DONE** — When In Use |
| Favorites | **DONE** — on-device UserDefaults |
| Stale-tab refresh (15 min + 30s last-updated tick) | **DONE** — `shouldRefetchStaleForecast` on `scenePhase == .active` |
| Cloud low / mid / high | **DONE** — ensemble layers kept on hourly rows; 48h and 14-day charts are three line series (daily values are that day’s hourly average) |
| Wind direction + gusts | **DONE** — circular-mean direction and mean gusts; Now shows from-direction + gust; Forecast wind chips use an arrow opposite of FROM plus gust |
| Theme / glass UI | **DONE** — static deep-navy glass cards. The app forces dark appearance; there is no pale light skin or weather-sky background |
| 1024 app icon from `public/favicon.svg` | **DONE** |
| NWS User-Agent (editable) | **DONE** — Settings stores it in the Keychain; blank xcconfig uses a built-in identifier with no email |
| Pollen keys | **DONE** — Settings Keychain, else blank `Secrets.xcconfig`; empty keys stay on Open-Meteo |
| Now tab clear of the tab bar | **DONE** — scroll content sits above the floating tab bar |
| Favorites remove | **DONE** — swipe to remove in the location sheet |

## Honest leftovers (not code gaps vs the site)

| Item | Why it is not a merge blocker |
|---|---|
| Ventusky stays a Safari link | In-app iframe was intentionally not added. |
| Google/Tomorrow species detail | Needs the owner’s **billing-capable** Google Pollen key (iOS-restricted). Blank keys → Open-Meteo, which is correct. |
| NWS WMS empty outside CONUS | Same as the Worker tile layer. Use Ventusky Safari for global radar. |
| Ventusky is not an in-app iframe | Intentional: Safari link-out preferred vs WKWebView/ToS. |
| Free Apple ID re-sign every ~7 days | Personal Team limit. Not an app bug. |
| ApexCharts / MathJax / Leaflet | Replaced by Swift Charts + methodology copy + MapKit. Scoring is the same JS. |
| Worker pollen rate-limit / same-origin | N/A off-Worker. Personal app is one user. |
| Preview Worker Google pollen | Unrelated; production website still uses Worker secrets. Native does not. |

Web Worker under `public/` is unchanged. Native calls stay on public upstreams (30s timeout, 429 retry, short forecast/geocoding cache). Production Worker secrets are not in the app.
