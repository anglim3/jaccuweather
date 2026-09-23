# Jaccuweather iOS (personal)

Native SwiftUI client. Direct public APIs — no Cloudflare Worker in the loop. The website under `public/` is unchanged.

Research, stack choice, pollen secrets, and radar notes: [`docs/native-ios-research.md`](../docs/native-ios-research.md).

## What is here

- **Now** — current conditions from Open-Meteo (live)
- **Forecast** — next hours + 14-day list from the same payload
- **Health** — Open-Meteo AQI/pollen (live), sinus/allergy helpers, optional Google/Tomorrow if keys are set locally
- **Radar** — MapKit around the selected point, optional Ventusky WKWebView
- Search (Open-Meteo geocoding), reverse geocode (BigDataCloud), US NWS alerts, on-device favorites

## Open in Xcode (Mac)

1. Install [Xcode](https://developer.apple.com/xcode/) from the Mac App Store.
2. Open `ios/Jaccuweather.xcodeproj` (not the repo root).
3. Signing & Capabilities on the **Jaccuweather** target:
   - Team: **Add an Account…** with a free Apple ID → Personal Team
   - Bundle ID: `cloud.janglim.jaccuweather` (change if Xcode says it is taken)
4. Destination: your iPhone. On the phone, enable **Developer Mode** (iOS 16+: Settings → Privacy & Security).
5. Run (⌘R). Trust the developer certificate on the device the first time: Settings → General → VPN & Device Management.

The placeholder App Icon is the 180×180 apple-touch PNG. Xcode may warn until a 1024×1024 marketing icon is dropped into `Assets.xcassets/AppIcon.appiconset`.

Free Apple ID signing expires about **every 7 days**. Reconnect the phone and Run again. No paid Apple Developer Program is required. Push / CloudKit are unavailable; this app does not need them.

### Simulator

Pick an iPhone simulator and Run. Location: Features → Location → Custom Location, or allow the in-app permission.

## Pollen keys (optional)

Without keys, pollen/AQI use **Open-Meteo** (same fallback as the Worker when secrets are missing).

```bash
cp ios/.env.example ios/.env
cp ios/Jaccuweather/Config/Secrets.xcconfig.example ios/Jaccuweather/Config/Secrets.xcconfig
# edit locally — never commit real values
```

The committed `Secrets.xcconfig` is empty placeholders. Xcode injects those build settings into Info.plist; `Secrets.swift` reads them. Leave blank to skip Google and Tomorrow.

Do not copy production Worker secrets into git. Restrict a Google key to this iOS bundle id if you create one.

## Prove the weather URL without Xcode

From the repo root (Linux/macOS, Node 18+):

```bash
node ios/scripts/verify-open-meteo.mjs
# optional: LAT=40.7128 LON=-74.0060 node ios/scripts/verify-open-meteo.mjs
```

This hits the same Open-Meteo forecast URL as `WeatherService`.

## Requirements

- macOS + Xcode 15+ (iOS 17 deployment target)
- Apple ID (free)
- Network to Open-Meteo, BigDataCloud, and (US) api.weather.gov
