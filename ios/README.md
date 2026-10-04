# Jaccuweather iOS (personal)

Native SwiftUI client for a **single iPhone**, signed with a **free Apple ID / Personal Team**. Direct public APIs — no Cloudflare Worker in the loop. The website under `public/` is unchanged.

Parity vs [weather.janglim.cloud](https://weather.janglim.cloud): [`docs/native-ios-parity.md`](../docs/native-ios-parity.md). Research notes: [`docs/native-ios-research.md`](../docs/native-ios-research.md).

Do **not** submit this to the App Store. Do **not** merge to `main` as part of this conversion. Do **not** deploy the Worker from this branch unless you mean to.

## Open in Xcode tonight (Mac + free Apple ID)

1. Install [Xcode](https://developer.apple.com/xcode/) from the Mac App Store (15+; iOS 17 deployment target).
2. Clone/pull this branch (`cursor/native-ios-personal-34dc`) and open **only** the project file:

   ```bash
   open ios/Jaccuweather.xcodeproj
   ```

   Do not open the repo root as an Xcode project.
3. Select the **Jaccuweather** target → **Signing & Capabilities**:
   - **Team:** Add an Account… with a free Apple ID → **Personal Team**
   - **Bundle ID:** `cloud.janglim.jaccuweather` (change the last segment if Xcode says it is taken)
   - Leave **Automatically manage signing** on
4. On the iPhone: **Settings → Privacy & Security → Developer Mode** (iOS 16+), reboot if asked.
5. Plug in the phone (or wireless debugging), pick it as the Run destination, press **⌘R**.
6. First launch: **Settings → General → VPN & Device Management** → trust the developer certificate, then open the app again.

### Copy Bundle Resources (Logic / Icons at app root)

Source files stay on disk at `Jaccuweather/Resources/Logic` and `Jaccuweather/Resources/Icons`. In the Xcode project those are **two folder references** (`name = Logic`, `path = Resources/Logic` and the same for Icons) in Copy Bundle Resources.

The built `.app` must contain `Logic/` and `Icons/` at the **bundle root**, next to the executable and `Assets.car`. Do not add a folder reference named `Resources` — a top-level `Resources/` directory inside an iOS `.app` makes `codesign` fail (`bundle format unrecognized, invalid, or unsuitable`) on current SDKs. `LogicEngine` and `SVGIconView` look up both `Logic/` / `Icons/` and the `Resources/…` fallbacks.

If you regenerate the project, use `node ios/scripts/generate-xcodeproj.js` (it emits the flattened folder refs, the `JaccuweatherWidgets` extension, and the `JaccuweatherWatch` app). Do not point Copy Bundle Resources at the parent `Resources` directory.

### 7-day re-sign (free Apple ID)

Personal Team provisioning **expires about every 7 days**. The app icon goes black / “integrity could not be verified.” Fix: reconnect the phone, open the same `.xcodeproj`, **⌘R** again. No paid Apple Developer Program is required. Push / CloudKit are unavailable; this app does not need them.

### Simulator

Pick any iPhone simulator and Run. **Features → Location → Custom Location** if you want a city other than the in-app default (Seattle).

### Home Screen and Lock Screen widgets

`JaccuweatherWidgets` shows current conditions on the Home Screen (small and medium) and the Lock Screen (circular, rectangular, and inline). It reloads about every 20 minutes. Home Screen widgets use the website Horizon background — navy gradient, cyan, gold, and indigo glows — plus glass chips and a serif place name. Lock Screen accessories use that same hierarchy, and the Horizon fill when the system draws a widget background.

**Paid Apple Developer team.** The app and the extension share the App Group `group.cloud.janglim.jaccuweather`. After a forecast refresh, the app writes the active place and current conditions there. A snapshot newer than about 40 minutes is what the widget shows when the widget has no chosen place, or when that snapshot is the chosen place. A chosen place that differs from the snapshot is loaded from Open-Meteo, so changing the place inside the app does not replace a widget that was set to another city. When the snapshot is that same place and it is older than about 40 minutes, the extension refreshes it from Open-Meteo.

**Free Apple ID / Personal Team.** App Groups cannot be provisioned, so the shared container is missing and the snapshot is never written. Touch and hold the widget, tap **Edit Widget**, and search for a city or enter latitude and longitude (for example `47.61, -122.33`). The extension loads that place from `api.open-meteo.com/v1/forecast`. The same Open-Meteo path is used when a snapshot exists but belongs to a different place, and when the matching snapshot is stale.

Install the app, then:

1. Home Screen: long-press, tap **+**, search **Jaccuweather**, and add the small or medium widget.
2. If the widget says to choose a place, touch and hold it, tap **Edit Widget**, and search for a city or enter coordinates.
3. Lock Screen: long-press, tap **Customize**, and add the circular or rectangular Jaccuweather accessory. It uses the same place.

### Control Center

iOS 18 and later. The same widget extension provides an **Open Jaccuweather** control. Add it from Control Center’s control gallery (open Control Center, touch and hold, then add a control, and search Jaccuweather). Tapping it runs an app intent that opens the Now tab for the place the app already has loaded. The URL `jaccuweather://now` selects that same tab.

When the App Group snapshot is readable, the control label shows that temperature. A free Personal Team cannot provision the App Group, so the container is missing, the label stays **Open**, and the control still launches Now. No extra entitlement is required for that fallback.

### Apple Watch

`JaccuweatherWatch` is a watchOS companion in the same Xcode project. The glance shows the place, temperature, a feels-like line when the rounded apparent temperature differs from that temperature by at least 2°F (otherwise the condition), and an SF Symbol for the WMO code, on the Horizon navy field with a glass symbol chip. Apparent temperature uses a fresh phone snapshot’s `feelsLikeF` when the iPhone already has one for that place. Otherwise the watch fills it from Open-Meteo `current.apparent_temperature` in Fahrenheit, or the nearest hour’s `apparent_temperature` when current omits it. VoiceOver speaks the feels-like line only while it is on screen. Under that header, today's sunrise and sunset sit with one short metric: the wind when the forecast has a speed or gust, otherwise the UV index. Gusts stay in VoiceOver. A 40mm face puts that metric on the sun line. A 45mm face and larger keep the sun line and place the metric on its own line underneath.

After each successful forecast refresh, the iPhone sends that reading with WatchConnectivity (`updateApplicationContext`). The Watch shows it while it is under about 40 minutes old. If the phone is unreachable, the context is empty, or the reading is older than that, the Watch requests `api.open-meteo.com/v1/forecast` for the last coordinates it stored. A first launch with no stored place uses Seattle (`47.6062, -122.3321`).

UV is Open-Meteo `uv_index`, rounded like the iPhone Now tab. VoiceOver adds the same Low, Moderate, High, Very high, and Extreme bands, and still speaks the wind gust when Open-Meteo `wind_gusts_10m` is present. The visible wind is `wind_speed_10m` and `wind_direction_10m` in miles per hour (`windspeed_unit=mph`). A fresh phone snapshot carries optional `uvIndex`, `windSpeedMph`, `windDirectionDegrees`, and `windGustMph` inside the WatchConnectivity `snapshot` JSON. When any of those fields is missing, or the phone reading is older than about 40 minutes, the watch fills the gap from the same Open-Meteo forecast. Circular, rectangular, inline, and corner complications stay temperature and condition.

The glance also shows the next eight place-local hours: temperature, precipitation probability, and a rain or snow cue. Open-Meteo `timezone=auto` stamps are wall clocks. The hour that contains “now” is chosen with `utc_offset_seconds`, the same way the iPhone Now and Forecast tabs pick the current hour, so the labels stay on the place’s clock. Tapping an hour opens a short sheet for that place-local hour. The title is 12-hour time, such as 3 PM, never a 24-hour clock. The sheet shows the WMO symbol and short condition, the temperature, the chance of precipitation, and a rain or snow amount when that hour has at least 0.01 inch. Feels-like, wind, humidity, and UV appear only when that hour’s forecast already includes them. Close returns to the glance. The strip itself stays the hour, temperature, and precipitation cue. Those fields come from the same Open-Meteo hourly forecast the watch already requests (`apparent_temperature`, `relative_humidity_2m`, `precipitation`, `rain`, `snowfall`, `wind_speed_10m`, `uv_index`, `is_day`), in inches and miles per hour. A Debug launch can open the first hour with `-watchHourDetail 1`.

The sun clocks are Open-Meteo daily `sunrise` and `sunset` (`timezone=auto`), printed in 12-hour place-local time, for example ↑ 7:12 AM · ↓ 6:51 PM. AM and PM follow the locale, including where the locale prefers 24-hour time. A phone snapshot newer than about 40 minutes that already includes `sunriseISO` and `sunsetISO` is shown as-is. When either stamp is missing, or that reading is older, the watch fills the line from the same Open-Meteo forecast it uses for the hours. Shorter watches, including the 40mm, use tighter type and share the sun line with the wind or UV metric so the header and both strips stay fully on screen. A 45mm face and larger keep the roomier sizes and a separate metric line.

Under the hours, the glance shows the next seven place-local days: weekday, a WMO SF Symbol, and the high and low. Each row is that civil day’s midnight in `utc_offset_seconds`, the same rule as the iPhone’s today row, so a watch set to another zone does not start on the wrong day. When fewer than seven days remain, the strip shows the days that are left. On a larger face the hour and day columns widen so the card ends on a whole column. Tapping a day opens a short sheet for that place-local day: weekday and date, the WMO symbol and short condition, high and low, precipitation probability, a rain or snow amount when that day’s total is at least 0.01 inch, and UV max when the forecast includes it. Close returns to the glance. The strip itself stays weekday, symbol, high, and low. Those amounts and the UV max come from the same Open-Meteo daily forecast the watch already requests (`rain_sum`, `snowfall_sum`, `precipitation_probability_max`, `uv_index_max`, inches). A Debug launch can open the first day with `-watchDayDetail 1`.

If the iPhone’s WatchConnectivity payload includes an active NWS summary (`alertTitle`, `alertSeverity`, and `alertCount`), the glance adds a compact badge for that title. Tap the badge for a short sheet with that severity, title, and count (for example “2 alerts”). When the phone also sends optional text it already has for the alert — `alertHeadline`, `alertEvent`, `alertInstruction`, and `alertEnds` — the sheet shows the lines that are present. `alertEnds` is the phone’s existing “Ends …” or “Expires …” line, with a 12-hour clock. A missing required field stays quiet, and the Watch does not request alerts itself. There is no push and no App Group. A Debug launch can seed a Juneau sample with `-name Juneau -lat 58.3019 -lon -134.4197 -watchAlertSample 1` when no phone payload is present. Add `-watchAlertDetail 1` to open the sheet.

The same context includes `favorites`, a JSON array of `{name, latitude, longitude}` in the saved favorite order. Names are the favorite display names. Rows are deduped with the same coordinate id as the iPhone list, and the array stops at 12. The glance’s Places button lists the city on screen plus those favorites. Picking one writes that place to `watch-place.json` with `explicit` set, reloads the complication, and shows the phone reading when it is still fresh for that place. Otherwise the watch requests Open-Meteo. A later phone city does not replace an explicit pick. A Debug launch can seed Portland, Denver, and Juneau with `-watchFavoritesSample 1`, and open the list with `-watchPlaces 1`, when the phone sent no favorites.

Personal Team provisioning cannot create App Groups, and the watch targets do not add one. The Watch app writes the last place to `watch-place.json` in its documents directory and in the complication extension’s documents directory, which sit next to each other. The complication reads that file and loads Open-Meteo for those coordinates, instead of staying on Seattle after the glance has another city. Tapping a complication opens the Watch app with `jaccuweather://place`, which shows that city’s glance. Circular, rectangular, inline, and corner slots share that place and that link. The inline slot is the temperature and a short condition. The corner slot shows the temperature, with the condition as an SF Symbol and a short label.

Open the `JaccuweatherWatch` scheme and pick a watchOS Simulator to run the glance. Install the iPhone app as well when you want the phone's current place to mirror across. A simulator launch can pin a city with `-name Juneau -lat 58.3019 -lon -134.4197`. Adding `-complicationGallery 1` shows the circular, rectangular, inline, and corner slots for that place.

Signing stays Automatic. The committed project leaves `DEVELOPMENT_TEAM` empty — pick your Personal Team locally in Xcode. Do not commit a team id.

### Optional pollen keys (never commit)

Without keys, pollen uses **Open-Meteo** (same fallback as the Worker when secrets are missing). That path must keep working with blank `Secrets.xcconfig`.

```bash
cp ios/.env.example ios/.env                          # gitignored; notes only
cp ios/Jaccuweather/Config/Secrets.xcconfig.example \
   ios/Jaccuweather/Config/Secrets.xcconfig           # already present empty
# edit Secrets.xcconfig locally — never git add real values
```

Xcode still injects `GOOGLE_POLLEN_API_KEY`, `TOMORROW_API_KEY`, and `NWS_USER_AGENT` from `Secrets.xcconfig` into `Info.plist` when those values are set. The app reads the Keychain first (Settings gear on every tab). A blank key skips that vendor. A blank NWS User-Agent uses `Jaccuweather/1.0 (personal iOS; https://github.com/anglim3/jaccuweather)`.

**Google Pollen (species detail):** create a key on a personal Google Cloud project with **Pollen API** enabled. Maps Platform Pollen is **billing-capable** even at tiny quota — that is a Google account setting, not an Apple fee. Restrict the key to **iOS apps** + bundle id `cloud.janglim.jaccuweather`. Do not reuse the production Worker key if you want blast-radius isolation. Category `TREE` fills `tree_pollen` only; alder/birch/olive stay `null` unless Google `plantInfo` reported those plants.

**Tomorrow.io:** optional second pollen vendor (`apikey` query param). Used only if Google is blank or returns nothing usable.

**NWS User-Agent:** open Settings in the app and enter a contact string NWS can use. Do not put a personal email in git. The committed `Secrets.xcconfig` leaves `NWS_USER_AGENT` empty.

## What the app calls

| Data | Upstream |
|---|---|
| Forecast | `ensemble-api.open-meteo.com` (same models + `normalizeEnsembleWeatherData` as the website) |
| Search | `geocoding-api.open-meteo.com` |
| Reverse | BigDataCloud `reverse-geocode-client` |
| Pollen / AQI | Google Pollen → Tomorrow.io → Open-Meteo air-quality |
| US alerts | `api.weather.gov` (User-Agent required) |
| US 48h snow | `api.weather.gov` points → `forecastGridData` `snowfallAmount` (same User-Agent as alerts) |
| Radar | NOAA MRMS base reflectivity on MapKit inside CONUS, Alaska, Hawaii, the Caribbean, and Guam. Outside those mosaics the Radar tab shows an unavailable state. See [`docs/native-ios-radar.md`](../docs/native-ios-radar.md) |
| Tides | NOAA `mdapi` + `datagetter` (coastal: ≤50 km + elevation ≤20 m) |
| Widgets | Fresh App Group snapshot when it is the widget's place, or when the widget has no chosen place. Otherwise the chosen place, from `api.open-meteo.com/v1/forecast` (current, a short hourly window, daily high/low), including when the container is missing. Search uses `geocoding-api.open-meteo.com` |
| Apple Watch | Phone forecast via WatchConnectivity when that reading is under about 40 minutes old and it is the place on screen. Otherwise `api.open-meteo.com/v1/forecast` for the last saved place (Seattle until one exists). The snapshot JSON may include `sunriseISO`, `sunsetISO`, `uvIndex`, `windSpeedMph`, `windDirectionDegrees`, and `windGustMph`. Missing sun stamps and atmosphere values are filled from that same Open-Meteo call. A fresh phone `feelsLikeF` is the apparent temperature; otherwise current `apparent_temperature`, or the nearest hour when current omits it. The glance shows that line only when the rounded values differ by at least 2°F. The context also carries `favorites` (name, latitude, longitude; coordinate-deduped; at most 12). Places on the glance switches among the current city and those favorites, stores the pick in `watch-place.json`, and reloads the complication. The glance adds today’s 12-hour place-local sunrise and sunset under the temperature, plus one wind or UV metric (wind when present, otherwise UV; gusts stay in VoiceOver). It also shows the next eight place-local hours (temperature, precipitation probability, rain or snow) and the next seven place-local days (weekday, WMO symbol, high and low). Tapping a day opens that place-local day’s weekday and date, condition, high and low, precipitation probability, rain or snow amount when at least 0.01 inch is in the forecast, and UV max when it is present. Tapping an hour opens that place-local hour in 12-hour time, with the WMO symbol and short condition, temperature, precipitation probability, rain or snow when at least 0.01 inch, and feels-like, wind, humidity, or UV when the hourly forecast includes them. Close returns to the glance. An NWS badge appears only when the phone payload includes title, severity, and count for the city on screen. Tapping it opens a short sheet and Close returns to the glance. Optional `alertHeadline`, `alertEvent`, `alertInstruction`, and `alertEnds` are shown when the phone sent them. Circular, rectangular, inline, and corner complications stay temperature and condition, read the place the glance published, without an App Group entitlement, and a tap opens that glance |

Shared scoring, icons, ensemble averaging, moon times, and pollen normalize run in **JavaScriptCore** from `Resources/Logic/jaccuweather-logic.js` (generated by `node ios/scripts/extract-logic.js` from `public/app.js` + `build.js`). Re-run that script if you change the website logic.

## Prove the ensemble URL without Xcode

From the repo root (Linux/macOS, Node 18+):

```bash
node ios/scripts/verify-open-meteo.mjs
# optional: LAT=40.7128 LON=-74.0060 node ios/scripts/verify-open-meteo.mjs
```

This hits **ensemble-api.open-meteo.com** (not the single-model forecast API) and runs `normalizeEnsembleWeatherData`.

Web tests (must stay green):

```bash
node --test tests/*.test.js
```

## Requirements

- macOS + Xcode 15+
- Free Apple ID
- Network to Open-Meteo, BigDataCloud, api.weather.gov, NOAA, and (optional) Google/Tomorrow
