# Jaccuweather

A weather app that runs as a single [Cloudflare Worker](https://workers.cloudflare.com/). It uses vanilla JavaScript with no framework, renders everything client-side, and calls free public APIs. The Worker embeds the HTML and JavaScript and proxies external APIs so the browser avoids CORS errors.

**Demo:** [weather.janglim.cloud](https://weather.janglim.cloud)

## What you get

- Current conditions: temperature, feels-like, humidity, wind, UV, pressure trend, AQI
- Sunrise and sunset arc (sun marker along the path by day, moon after dark)
- Moon phase detail modal
- 48-hour forecast with Conditions, Precipitation, and Wind toggle
- 14-day forecast with week separators
- Detail modals with ApexCharts for hourly and daily views
- Health scores: sinus risk, allergy risk, nice-weather index (each with a methodology modal)
- Pollen levels and 5-day pollen forecast
- Ventusky radar centered on the selected location
- NWS alerts for US locations
- NOAA tides on coastal locations
- City search with autocomplete, geolocation, and local favorites

Core weather works without API keys. Optional keys improve pollen coverage.

## Requirements

- [Node.js](https://nodejs.org/) 16 or higher
- npm
- A [Cloudflare](https://dash.cloudflare.com/) account (the free tier is enough)
- [Wrangler](https://developers.cloudflare.com/workers/wrangler/) (installed via `npm install`)

## Quick start

```bash
git clone https://github.com/janglimTARS/jaccuweather.git
cd jaccuweather
npm install
```

### Configure Cloudflare

1. Open `wrangler.toml` and set your own `account_id`. You can also remove the line and let Wrangler use your default account after login.
2. Log in once:

```bash
npx wrangler login
```

### Run locally

```bash
npm run dev
```

Open the URL Wrangler prints (default `http://127.0.0.1:8787`).

If port 8787 is busy:

```bash
npm run build
npx wrangler dev --ip 127.0.0.1 --port 8793
```

Edit files under `public/`. Then rebuild and restart `npm run dev` so `src/index.js` is regenerated. Do not edit `src/index.js` by hand. The build step overwrites it.

### Deploy

```bash
npm run deploy
```

This builds and deploys the Worker named `weather-app` from `wrangler.toml`. After deploy, attach a custom domain in the Cloudflare dashboard if you want one.

Optional: set the account ID for that command only:

```bash
CLOUDFLARE_ACCOUNT_ID=your_account_id npm run deploy
```

## Optional secrets

Pollen works without secrets via Open-Meteo. For better coverage, add Worker secrets:

| Secret | Required | Purpose |
|--------|----------|---------|
| `GOOGLE_POLLEN_API_KEY` | No | Primary pollen source (Google Pollen API) |
| `TOMORROW_API_KEY` | No | Secondary pollen fallback |

```bash
npx wrangler secret put GOOGLE_POLLEN_API_KEY
npx wrangler secret put TOMORROW_API_KEY
```

Local `wrangler dev` does not load remote secrets by default. To test with production secrets:

```bash
npx wrangler dev --remote --ip 127.0.0.1 --port 8789
```

## Project layout

```
jaccuweather/
├── public/
│   ├── index.html      # UI and CSS (edit this)
│   ├── app.js          # Frontend logic (edit this)
│   └── favicon.svg
├── src/
│   └── index.js        # Generated Worker. Do not edit.
├── build.js            # Embeds public/* and defines API proxy routes
├── convert-favicon.js  # SVG to PNG for Apple touch icon (uses sharp)
├── wrangler.toml
└── package.json
```

| Script | Description |
|--------|-------------|
| `npm run build` | Generate `src/index.js` from `public/*` |
| `npm run dev` | Build and start the local Worker dev server |
| `npm run deploy` | Build and deploy to Cloudflare |

Syntax check before shipping:

```bash
node --check public/app.js && node --check build.js && npm run build && node --check src/index.js
```

## How it works

1. `build.js` inlines `public/index.html`, `public/app.js`, and assets into a single Worker file.
2. The Worker serves the app and proxies `/api/*` routes and Ventusky with caching where useful.
3. The browser fetches weather data from the Worker, then renders the UI, charts, radar, and health metrics client-side.
4. Favorites live in IndexedDB with a localStorage fallback. Theme preference is stored in the browser only.

### Worker routes

| Route | Upstream |
|-------|----------|
| `/`, `/app.js`, favicons | Embedded static assets |
| `/api/forecast` | Open-Meteo forecast |
| `/api/geocoding` | Open-Meteo geocoding |
| `/api/reverse` | BigDataCloud reverse geocode |
| `/api/air-quality` | Open-Meteo air quality and pollen |
| `/api/pollen` | Google Pollen, then Tomorrow.io, then Open-Meteo |
| `/api/alerts` | NWS alerts (US only) |
| `/api/nws-points` | NWS points |
| `/api/nws-wms` | NWS radar WMS tiles |
| `/ventusky-proxy/*` | Ventusky (iframe-safe proxy) |

### UI notes for theming

- Fonts: DM Sans for UI text, Lora for location titles
- Accent color: soft sky blue. Sun marker is gold.
- Layout: glass cards over a full-page background, max width 920px
- Theme toggle: dark mode keeps a static deep-blue background. Light mode applies weather-based gradients (sunny, cloudy, rain, storm, snow, fog, clear night).
- Sun arc: SVG path in the hero card. The marker position follows location-local sunrise and sunset times.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Changes in `public/` do not appear | Run `npm run build` and restart `wrangler dev` |
| `sharp` missing on build | Optional. Favicon PNG conversion warns and continues. `npm install` should install it as a devDependency. |
| Pollen always empty | Coverage varies by location. Optional Google or Tomorrow secrets help. Without them Open-Meteo is used. |
| Radar blank or navigates away | Keep the Ventusky proxy route. It removes frame-busting scripts. |
| NWS alerts fail | US locations only. The Worker must send a User-Agent header (already set in `build.js`). |
| Wrong account on deploy | Set `account_id` in `wrangler.toml` or pass `CLOUDFLARE_ACCOUNT_ID`. |

## Credits

| Role | Source |
|------|--------|
| Forecast, geocoding, air quality | [Open-Meteo](https://open-meteo.com/) |
| Pollen | Google Pollen API, Tomorrow.io, Open-Meteo |
| Maps | [Ventusky](https://www.ventusky.com/) |
| Alerts and radar tiles | [NWS](https://www.weather.gov/) |
| Tides | [NOAA](https://tidesandcurrents.noaa.gov/) |
| Moon times | [SunCalc.js](https://github.com/mourner/suncalc) |
| Charts | [ApexCharts](https://apexcharts.com/) |
| Math in methodology modals | [MathJax](https://www.mathjax.org/) |
| Icons | [Font Awesome](https://fontawesome.com/) |
| CSS utilities | [Tailwind CSS](https://tailwindcss.com/) |
| Reverse geocode | [BigDataCloud](https://www.bigdatacloud.com/) |
| Fonts | [DM Sans](https://fonts.google.com/specimen/DM+Sans), [Lora](https://fonts.google.com/specimen/Lora) |

## License

MIT

## Author

Jack Anglim