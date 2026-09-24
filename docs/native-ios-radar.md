# Native iOS radar

Research note for the personal SwiftUI app on `ios/0.1`. Probed live on **2026-09-24**. No app code in this change.

**Build RainViewer past-radar tiles on the existing MapKit overlay.** One `MKTileOverlay`, worldwide, no API key, with a time scrubber over the last two hours.

That is tile images drawn by MapKit. It is the same kind of overlay as today’s `NWSRadarOverlay`, with an XYZ URL instead of a WMS `GetMap`. Leave the website’s Ventusky iframe alone; this note is only the iOS radar tab.

If a third-party tile host is unacceptable, build the NOAA section at the bottom instead and accept US mosaics only. Do not implement both in the first pass.

## Why this one

The radar tab is how this app shows precipitation in space, including places outside the United States. RainViewer is the option that is global, free for personal use, keyless, and already shaped like `MKTileOverlay`.

Verified on 2026-09-24:

- `https://api.rainviewer.com/public/weather-maps.json` returned 13 past frames spanning 120 minutes at a 10-minute step. `radar.nowcast` was `[]`. `satellite.infrared` was `[]`.
- Tiles from the latest frame were real PNGs with precipitation painted in the US, Europe, Japan, and Australia.
- Response headers were `Cache-Control: max-age=172800` and `X-RateLimit-Limit: 500` / `X-RateLimit-Window: 60` (burst limit 300). Their transition page still says 100 requests per IP per minute as of 2026-01-01. Budget for 100.
- Color-scheme ids `0` through `8` returned byte-identical PNGs (Universal Blue only). `1_0` (smoothed) differed from `0_0`. The snow flag did not (`1_0` matched `1_1`).
- Zoom 8 and zoom 9 of the same geographic tile were the **same 1,370-byte PNG**. The documented maximum zoom is 7. Requesting a higher z does not overzoom; it repeats one placeholder. The app has to crop.

NOAA MRMS is the stronger *United States* picture (about a 2-minute cadence, 1 km, public domain, no vendor). It does not cover Europe, Asia, Africa, or South America, and it is a WMS `GetMap`, not an XYZ tile. The recipe is complete below so it can be built without another research pass. It is the fallback, not the default.

WeatherKit does not serve radar imagery, and it needs a paid Apple Developer Program membership. This app is a free-Apple-ID sideload. Open-Meteo precipitation values are point forecasts the app already shows; they are not a radar image.

## Comparison

| Source | Coverage | Frames | Key | What you would actually ship |
|---|---|---|---|---|
| **RainViewer Weather Maps API** | Global composite (1,200+ radars claimed; US/EU/JP/AU tiles verified) | Past 2 h, 13 frames, 10 min. Nowcast and satellite arrays were empty | None | **Build this.** `MKTileOverlay` + scrubber. Personal/educational terms. Credit with a link. |
| **NOAA opengeo MRMS WMS** | CONUS, Alaska, Hawaii, Caribbean, Guam. Five separate layers | ~60 stamps, ~2 min, ~2 h, per mosaic. `TIME=` verified | None | Best no-third-party US radar. Keep the current Web Mercator math; change the layer. Full recipe below. |
| **IEM tile cache** (`mesonet.agron.iastate.edu`) | US NEXRAD composite (CONUS/AK/HI/PR/GU) | Current, plus `m05m`…`m55m` (5 min steps). Current and `-m20m` tiles returned PNG | None | Courtesy GIS service. Their page says it is as-is and asks apps not to put thousands of users on it. A single phone is inside that, and it is still a worse fit than NOAA (official) or RainViewer (global, published app API). |
| **WeatherKit** | Global *points* where Apple has weather | Minute precip for the next hour in some regions. No tiles | Paid Developer Program + WeatherKit entitlement, 500k calls/month included | No radar product in the API. Skip. |
| **Open-Meteo / WeatherKit precip points** | Global points | Hourly (and, for WeatherKit, next-hour minutes) | Open-Meteo: none | Already on the forecast tab. A grid of points is a different product. Do not draw a fake radar from it. |
| **OpenWeatherMap weather maps** | Global tiles | Precipitation layer, short history on paid plans | API key; each tile spends quota | Free daily call caps are too small for an interactive map (a pan is dozens of tiles). Skip. |
| **Ventusky iframe, WKWebView, or Safari link** | Global | Their UI | None | Out of scope for this app. The radar tab should stop offering the Safari link when the overlay ships. Do not put Ventusky back on the Worker. |

## What the app does today

`NWSRadarOverlay` requests `APIEndpoints.nwsWms` (`https://opengeo.ncep.noaa.gov/geoserver/ows`) with `LAYERS=nexrad-n0q-wmst`, WMS 1.3.0, `CRS=EPSG:3857`, 256×256 transparent PNG. The Web Mercator bbox math in `url(forTilePath:)` is the standard XYZ → EPSG:3857 conversion.

That layer name is gone. The same request returned HTTP 200 `text/xml` with `ServiceException code="LayerNotDefined"`: `Could not find layer nexrad-n0q-wmst`. MapKit then paints nothing.

`RadarView` also shows a Safari link to Ventusky. `initializeVentuskyRadar()` on the website is unchanged by this note.

`RadarMapView.updateUIView` calls `setRegion` on every SwiftUI update. A scrubber will retrigger that and yank the map back to the city. Recenter only when `model.coordinate` changes.

The Xcode target lists Swift files one by one in `ios/Jaccuweather.xcodeproj/project.pbxproj`. Rewriting `NWSRadarOverlay.swift` avoids a project edit. A new file has to be added to the file reference, the Services group, and the Sources build phase.

Deployment target is iOS 17. SwiftUI `Map` still has no raster-tile overlay. Keep `RadarMapView` as an `MKMapView` inside `UIViewRepresentable`.

## Build steps

### 1. Frame list

`GET https://api.rainviewer.com/public/weather-maps.json`

Use `host` and each `radar.past[]` entry. Do not invent the tile host or the path. On 2026-09-24 `host` was `https://tilecache.rainviewer.com` and `path` looked like `/v2/radar/<opaque id>`, not `/v2/radar/<unix time>`.

```json
{
  "host": "https://tilecache.rainviewer.com",
  "radar": {
    "past": [ { "time": 1790280000, "path": "/v2/radar/e0fed87cd374" } ],
    "nowcast": []
  }
}
```

`time` is the frame’s unix timestamp (UTC) for the label. Refresh this JSON about every 5 minutes while the Radar tab is visible. Ignore `nowcast` and `satellite` until they are non-empty; both were empty arrays.

Add the URL on `APIEndpoints`. Decode with a small `Codable` next to the overlay. No key, so nothing goes in `Secrets` or the Keychain.

### 2. Tile URL

```
{host}{path}/256/{z}/{x}/{y}/2/1_0.png
```

| Piece | Value |
|---|---|
| `{host}{path}` | From the JSON frame you are showing |
| `256` | Pixel size. 512 is allowed; stay on 256 so a loop costs fewer bytes |
| `{z}/{x}/{y}` | Standard XYZ, y origin north. Same scheme MapKit uses |
| `2` | Color scheme. Every id currently returns Universal Blue; `2` matches RainViewer’s own example |
| `1_0` | Smoothed (`1`), snow ramp off (`0`). Snow on/off was the same image |

Example that returned a PNG: `https://tilecache.rainviewer.com/v2/radar/e0fed87cd374/256/2/1/1/2/1_1.png`.

### 3. Overlay class

Rewrite `ios/Jaccuweather/Services/NWSRadarOverlay.swift`.

- Subclass `MKTileOverlay`. `canReplaceMapContent = false`. `tileSize = 256×256`. `minimumZ = 2`. Set `maximumZ` high enough to pinch in (16 is enough) **and clamp fetches to z = 7** in `loadTile(at:result:)`.
- Store `framePathPrefix` (`host + path`). The coordinator keeps one overlay instance.
- On scrub or play, change the prefix and call `MKTileOverlayRenderer.reloadData()`. One overlay. Thirteen overlays at once will blow the rate limit.
- Implement `loadTile` with a dedicated `URLSession` whose `URLCache` is about 20 MB memory / 50 MB disk. RainViewer’s `max-age=172800` then makes the second pass through the loop free. `MKTileOverlay`’s built-in loader is the wrong place once you need cropping and that cache.
- z ≤ 7: download the URL above.
- z > 7: let `dz = z - 7`, `scale = 1 << dz`, fetch z=7 tile `(x / scale, y / scale)`, crop

  `CGRect(x: (x % scale) * (256 / scale), y: (y % scale) * (256 / scale), width: 256 / scale, height: 256 / scale)`

  and scale that crop back to 256×256 PNG bytes. XYZ y grows south, and PNG y grows down, so the modulo row is already the top-left origin. A transparent ancestor stays transparent.

Renderer alpha around `0.7` matches the current NWS renderer.

### 4. Radar tab UI

Edit `ios/Jaccuweather/Views/RadarView.swift`.

- Remove the Ventusky caption and the `Link` to `APIEndpoints.ventusky`. Delete `ventusky(latitude:longitude:)` once nothing calls it.
- Under the map: play/pause, a slider over `radar.past`, and the frame time in the location’s zone (the frame timestamp is UTC).
- Open on the latest frame (last array element).
- Play steps one frame at a time, on the order of 0.7–1.0 s, and only advances when that frame’s visible tiles have arrived or failed. RainViewer’s Leaflet sample uses 500 ms; at that pace a fresh city view (about 10–20 tiles) times 13 frames is ~130–260 requests and will pass the published 100/minute cap on a cold cache. The second loop should be cache hits.
- Attribution, always visible on this screen, as a link: [RainViewer](https://www.rainviewer.com/). Their terms ask for that link. Wording like “Radar from RainViewer” is enough. No separate legend is required; the ramp is Universal Blue.
- Recenter the map when the selected place changes, not when the frame changes.

### 5. Leave these alone

- The Cloudflare Worker. Do not add `/api/rainviewer`. The public site is not “personal or educational use,” and lockdown should not grow a new proxy.
- `public/app.js` Ventusky. Website radar is a separate decision.
- Pollen keys and `KeychainStore`. This source has no secret.
- NOAA `GetMap` code, unless you switch to the fallback below. Don’t leave the dead `nexrad-n0q-wmst` request running next to a working overlay.

## NOAA fallback (US mosaics, no third party)

Use this instead of RainViewer when the requirement is “official NWS radar only.”

Directory (live): [opengeo.ncep.noaa.gov GeoServer layers](https://opengeo.ncep.noaa.gov/geoserver/www/). Composite products are MRMS. Each area has base reflectivity (`*_bref_qcd`), composite reflectivity (`*_cref_qcd`), echo tops (`*_neet_v18`), and precip type (`*_pcpn_typ`). Ship **base reflectivity**. It is the near-surface field radar.weather.gov is built on. Composite reflectivity shows more echo aloft; it is a one-string swap if you want the busier picture.

| Area | GetCapabilities / GetMap endpoint | `LAYERS` | CRS:84 bounds (W, S, E, N) |
|---|---|---|---|
| CONUS | `https://opengeo.ncep.noaa.gov/geoserver/conus/conus_bref_qcd/ows` | `conus_bref_qcd` | −130, 20, −60, 55 |
| Alaska | `https://opengeo.ncep.noaa.gov/geoserver/alaska/alaska_bref_qcd/ows` | `alaska_bref_qcd` | −176, 50, −126, 72 |
| Hawaii | `https://opengeo.ncep.noaa.gov/geoserver/hawaii/hawaii_bref_qcd/ows` | `hawaii_bref_qcd` | −164, 15, −151, 26 |
| Caribbean | `https://opengeo.ncep.noaa.gov/geoserver/carib/carib_bref_qcd/ows` | `carib_bref_qcd` | −90, 10, −60, 25 |
| Guam | `https://opengeo.ncep.noaa.gov/geoserver/guam/guam_bref_qcd/ows` | `guam_bref_qcd` | 140, 9, 150, 18 |

Bounds are `EX_GeographicBoundingBox` from each layer’s capabilities on 2026-09-24. Pick the mosaic that contains the coordinate. CONUS and the Caribbean overlap between 20–25°N and 90–60°W; prefer CONUS inside the CONUS box (Miami stays CONUS, Puerto Rico falls through to Caribbean). Outside all five boxes, show the map with no overlay and a one-line “US radar only” caption.

`GetMap` (this is the current overlay with the layer fixed):

```
SERVICE=WMS
VERSION=1.3.0
REQUEST=GetMap
LAYERS=conus_bref_qcd
STYLES=
CRS=EPSG:3857
BBOX={minX},{minY},{maxX},{maxY}
WIDTH=256
HEIGHT=256
FORMAT=image/png
TRANSPARENT=TRUE
TIME={stamp-from-capabilities}   # omit for the latest default
```

Verified:

- `conus_bref_qcd` and `conus:conus_bref_qcd` on EPSG:3857 both returned a 256×256 RGBA PNG with real echo (about 3.5% non-transparent pixels on a central-US z=4 tile). `conus_cref_qcd` did too (about 4.6%).
- The same bbox with `TIME=2026-09-24T18:06:09.000Z` returned a different PNG, so the time parameter is honored.
- EPSG:4326 with longitude-first bbox returned a fully transparent PNG. WMS 1.3.0 axis order for 4326 is latitude, longitude. Stay on EPSG:3857 and the math already in `NWSRadarOverlay`.
- Alaska `GetMap` returned `image/png`.
- Each layer’s capabilities `Dimension name="time"` was a comma-separated list of 60 ISO-8601 stamps covering roughly the last two hours, `nearestValue="1"`, and a `default` attribute equal to the newest stamp. Pass stamps through unchanged (they include milliseconds).
- A latest-frame `GetMap` sent `Cache-Control: max-age=120`.
- Capabilities said `Fees: none` and `AccessConstraints: none`.
- Legend PNG (optional under the slider): `REQUEST=GetLegendGraphic&LAYER=conus_bref_qcd&FORMAT=image/png` on the CONUS endpoint. It returned `image/png`.

Refresh the capabilities document when the tab opens and about every 5 minutes. Sixty stamps is a long slider; stepping every other stamp (~4 minutes) is a reasonable default play rate. Send `Secrets.nwsUserAgent` on these requests. NWS data is public domain; credit “NOAA / NWS MRMS” in the caption anyway, and show the frame time. Their [disclaimer](https://www.weather.gov/disclaimer) asks you not to imply NWS endorsement and to respect refresh cycles. A personal phone polling every few minutes is in bounds. There is still no published per-tile quota; don’t tight-loop retries.

Single-site layers (`/geoserver/kdtw/ows` and the rest of the site list) are for one radar, not the national loop. Skip them.

## Sources

- RainViewer terms and API index: https://www.rainviewer.com/api.html
- Weather Maps API (JSON shape, tile template, 2 h / 10 min, zoom discussion): https://www.rainviewer.com/api/weather-maps-api.html
- What they removed on 2026-01-01 (nowcast, satellite, extra color schemes, zoom cap, the 100/min line): https://www.rainviewer.com/api/transition-faq.html
- NOAA layer directory: https://opengeo.ncep.noaa.gov/geoserver/www/
- CONUS capabilities (names, time dimension, bounds): `https://opengeo.ncep.noaa.gov/geoserver/conus/ows?service=WMS&version=1.3.0&request=GetCapabilities`
- NWS disclaimer / public domain: https://www.weather.gov/disclaimer
- IEM GIS radar terms (“as-is”, “thousands of simultaneous users”): https://mesonet.agron.iastate.edu/GIS/ridge.phtml
- IEM tile layer names (`nexrad-n0q`, `nexrad-n0q-mXXm`): https://mesonet.agron.iastate.edu/ogc/
- `MKTileOverlay` / `loadTile(at:result:)`: https://developer.apple.com/documentation/mapkit/mktileoverlay
- WeatherKit product surface (conditions, hourly, daily, next-hour precip, alerts — no imagery): https://developer.apple.com/weatherkit/ and https://developer.apple.com/documentation/weatherkit/weather
- WeatherKit requires the Apple Developer Program: https://developer.apple.com/weatherkit/get-started/
