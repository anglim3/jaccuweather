# Native iOS radar

The Radar tab draws **NOAA MRMS base reflectivity** on MapKit when the selected place is inside a NOAA mosaic: CONUS, Alaska, Hawaii, the Caribbean, or Guam. One WMS `GetMap` image covers the visible region. Play, pause, and the scrubber step those NOAA frames only.

Outside those five boxes the tab does not invent a radar picture from Open-Meteo points. The map stays on the place, a banner reads **Radar unavailable**, and the panel names the NOAA coverage. There is no second source, no play control, and no embedded web radar.

NOAA lives in `NOAARadarModel.swift` and `NOAARadarOverlay.swift`. The tab UI is `RadarView.swift`. The website’s Ventusky iframe is unchanged. The iOS app does not embed Ventusky and does not link out to it.

RainViewer is not part of this app. There is no catalog fetch, tile overlay, source control, or RainViewer credit.

## Why NOAA

The radar tab shows precipitation in space. NOAA MRMS is the United States picture: about a 2-minute cadence, public domain, no vendor key. It does not cover Europe, Asia, Africa, or South America, and it is a WMS `GetMap`, not an XYZ tile.

WeatherKit does not serve radar imagery, and it needs a paid Apple Developer Program membership. This app is a free-Apple-ID sideload. Open-Meteo precipitation values are point forecasts the app already shows; they are not a radar image, and the tab does not paint them as one.

## Comparison

| Source | Coverage | Frames | Key | What the app does |
|---|---|---|---|---|
| **NOAA opengeo MRMS WMS** | CONUS, Alaska, Hawaii, Caribbean, Guam. Five separate layers | ~60 stamps, ~2 min, ~2 h, per mosaic. Playback uses every other stamp (~4 min). `TIME=` verified | None | **Shipped.** The only radar imagery. One EPSG:3857 `GetMap` for the visible region, reloaded when the frame or the settled region changes. Credit “NOAA / NWS MRMS” links to the [NWS disclaimer](https://www.weather.gov/disclaimer). |
| **RainViewer Weather Maps API** | Global composite | Past tiles | None | **Not in the app.** No calls to `api.rainviewer.com` or `tilecache.rainviewer.com`. |
| **IEM tile cache** (`mesonet.agron.iastate.edu`) | US NEXRAD composite | Current plus short history | None | Not used. Courtesy GIS service; NOAA is the official mosaic. |
| **WeatherKit** | Global *points* where Apple has weather | No tiles | Paid Developer Program | No radar product. Skip. |
| **Open-Meteo precip points** | Global points | Hourly | None | Already on the forecast tab. Not drawn as radar. |
| **Ventusky iframe or WKWebView** | Global | Their UI | None | Website iframe only. Not in the iOS app. |

## What the Radar tab does

`NOAAMosaic.containing` picks the mosaic for the selected coordinate. Inside one, `NOAARadarCatalog.load()` fetches that layer’s WMS capabilities with the cache bypassed, about every 5 minutes while the tab is alive. It keeps every other time stamp, newest included, so play steps about 4 minutes. The scrubber opens on the latest frame. A refresh that arrives while you are on the latest frame stays on the latest; a frame you scrubbed to is kept when its stamp is still in the list.

The overlay is one `MKOverlay` (`NOAAImageOverlay`). Each frame or settled pan requests a single `GetMap` whose bbox is the visible `MKMapRect` converted to EPSG:3857 (easting, northing). Pixel size follows the map view, capped at 1024 on the long side. The previous image stays pinned to its map rect while a pan is in progress; `regionDidChange` reloads it. Play waits until that frame’s image settles (or 4 seconds) and holds the frame at least about 0.85 seconds. A failed request is retried once after a second, and only for a timeout, 429, or 5xx.

The bar under the map has play/pause, the scrubber, and the frame clock in the location’s `utc_offset_seconds`. The credit line is “NOAA / NWS MRMS”, linking to the NWS disclaimer. Outside all five boxes that bar is absent. The map shows **Radar unavailable**, and the panel states the coverage. There is no Ventusky control and no WKWebView.

The old `nexrad-n0q-wmst` request is gone. On 2026-09-24 that layer returned `LayerNotDefined`.

## NOAA MRMS

The running app calls these endpoints with `Secrets.nwsUserAgent`.

Directory (live): [opengeo.ncep.noaa.gov GeoServer layers](https://opengeo.ncep.noaa.gov/geoserver/www/). Composite products are MRMS. Each area has base reflectivity (`*_bref_qcd`), composite reflectivity (`*_cref_qcd`), echo tops (`*_neet_v18`), and precip type (`*_pcpn_typ`). The app requests **base reflectivity**. It is the near-surface field radar.weather.gov is built on.

| Area | GetCapabilities / GetMap endpoint | `LAYERS` | CRS:84 bounds (W, S, E, N) |
|---|---|---|---|
| CONUS | `https://opengeo.ncep.noaa.gov/geoserver/conus/conus_bref_qcd/ows` | `conus_bref_qcd` | −130, 20, −60, 55 |
| Alaska | `https://opengeo.ncep.noaa.gov/geoserver/alaska/alaska_bref_qcd/ows` | `alaska_bref_qcd` | −176, 50, −126, 72 |
| Hawaii | `https://opengeo.ncep.noaa.gov/geoserver/hawaii/hawaii_bref_qcd/ows` | `hawaii_bref_qcd` | −164, 15, −151, 26 |
| Caribbean | `https://opengeo.ncep.noaa.gov/geoserver/carib/carib_bref_qcd/ows` | `carib_bref_qcd` | −90, 10, −60, 25 |
| Guam | `https://opengeo.ncep.noaa.gov/geoserver/guam/guam_bref_qcd/ows` | `guam_bref_qcd` | 140, 9, 150, 18 |

Bounds are `EX_GeographicBoundingBox` from each layer’s capabilities on 2026-09-24. CONUS and the Caribbean overlap between 20–25°N and 90–60°W; CONUS wins inside the CONUS box (Miami stays CONUS, Puerto Rico falls through to Caribbean). The same preference applies where CONUS overlaps Alaska. Outside all five boxes, NOAA is not requested.

`GetMap` for the visible-region overlay:

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

- `conus_bref_qcd` and `conus:conus_bref_qcd` on EPSG:3857 both returned a 256×256 RGBA PNG with real echo. `conus_cref_qcd` did too.
- The same bbox with `TIME=2026-09-24T18:06:09.000Z` returned a different PNG, so the time parameter is honored.
- EPSG:4326 with longitude-first bbox returned a fully transparent PNG. WMS 1.3.0 axis order for 4326 is latitude, longitude. The overlay stays on EPSG:3857 (easting, northing).
- Alaska `GetMap` returned `image/png`.
- Each layer’s capabilities `Dimension name="time"` was a comma-separated list of 60 ISO-8601 stamps covering roughly the last two hours, `nearestValue="1"`, and a `default` attribute equal to the newest stamp. Pass stamps through unchanged (they include milliseconds).
- A latest-frame `GetMap` sent `Cache-Control: max-age=120`.
- Capabilities said `Fees: none` and `AccessConstraints: none`.

NWS data is public domain. The [disclaimer](https://www.weather.gov/disclaimer) asks you not to imply NWS endorsement and to respect refresh cycles. A personal phone polling every few minutes is in bounds. There is still no published per-tile quota; don’t tight-loop retries.

Forecast data on the other tabs is Open-Meteo under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Settings and the footers under Now, Forecast, and Health credit [Open-Meteo](https://open-meteo.com/) and note that ensemble values are averaged. That credit is separate from the radar image.

Single-site layers (`/geoserver/kdtw/ows` and the rest of the site list) are for one radar, not the national loop. Skip them.

## Left alone

- The Cloudflare Worker.
- `public/app.js` Ventusky.
- Pollen keys and `KeychainStore`. This source has no secret.
- The dead `nexrad-n0q-wmst` request. NOAA uses the `*_bref_qcd` mosaics above.

## Sources

- NOAA layer directory: https://opengeo.ncep.noaa.gov/geoserver/www/
- CONUS capabilities (names, time dimension, bounds): `https://opengeo.ncep.noaa.gov/geoserver/conus/ows?service=WMS&version=1.3.0&request=GetCapabilities`
- NWS disclaimer / public domain: https://www.weather.gov/disclaimer
- Open-Meteo licence (CC BY 4.0, link beside displayed data): https://open-meteo.com/en/licence
- IEM GIS radar terms (“as-is”, “thousands of simultaneous users”): https://mesonet.agron.iastate.edu/GIS/ridge.phtml
- WeatherKit product surface (conditions, hourly, daily, next-hour precip, alerts — no imagery): https://developer.apple.com/weatherkit/ and https://developer.apple.com/documentation/weatherkit/weather
- WeatherKit requires the Apple Developer Program: https://developer.apple.com/weatherkit/get-started/
