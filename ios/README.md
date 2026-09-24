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

If you regenerate the project, use `node ios/scripts/generate-xcodeproj.js` (it emits the flattened folder refs). Do not point Copy Bundle Resources at the parent `Resources` directory.

### 7-day re-sign (free Apple ID)

Personal Team provisioning **expires about every 7 days**. The app icon goes black / “integrity could not be verified.” Fix: reconnect the phone, open the same `.xcodeproj`, **⌘R** again. No paid Apple Developer Program is required. Push / CloudKit are unavailable; this app does not need them.

### Simulator

Pick any iPhone simulator and Run. **Features → Location → Custom Location** if you want a city other than the in-app default (Seattle).

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
| Radar overlay | NWS WMS `opengeo.ncep.noaa.gov` `nexrad-n0q-wmst` on MapKit |
| Global radar | Safari → `https://www.ventusky.com/?p=lat;lon;7&l=rain` |
| Tides | NOAA `mdapi` + `datagetter` (coastal: ≤50 km + elevation ≤20 m) |

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
