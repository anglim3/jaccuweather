// City-level HTML page-view logging and the private visits map.
// Never store IP addresses or the full User-Agent.

const BOT_UA_RE =
  /bot|crawl|spider|slurp|preview|headless|monitor|wget|curl|python-requests|httpie|scrapy|facebookexternalhit|pingdom|uptimerobot|statuscake|embedly|slackbot|discordbot|telegram|whatsapp|applebot|googlebot|bingbot|yandex|baidu|semrush|ahrefs|mj12|dotbot|gptbot|chatgpt|claudebot|perplexity|bytespider|ia_archiver|petalbot|duckduckbot|twitterbot|linkedinbot|pinterest|okhttp|go-http-client|libwww-perl|phantom|selenium|puppeteer|playwright/i;

const ASSET_EXT_RE =
  /\.(?:js|mjs|cjs|css|map|png|jpe?g|gif|svg|ico|webp|avif|woff2?|ttf|eot|json|xml|txt|webmanifest|mp4|webm|wasm|pdf)$/i;

const ASSET_PREFIXES = ['/icons/', '/assets/', '/static/'];

const VISITS_PREFIX = '/_visits';
const BOT_SCORE_THRESHOLD = 30;
const RANGES = {
  '24h': 24 * 60 * 60 * 1000,
  '7d': 7 * 24 * 60 * 60 * 1000,
  '30d': 30 * 24 * 60 * 60 * 1000,
};
const DEFAULT_RANGE = '7d';

const PRIVATE_HEADERS = {
  'Cache-Control': 'no-store',
  'X-Robots-Tag': 'noindex, nofollow',
  'Referrer-Policy': 'no-referrer',
};

function normalizePath(pathname) {
  if (!pathname) return '/';
  if (pathname !== '/' && pathname.endsWith('/')) return pathname.slice(0, -1);
  return pathname;
}

function emptyToNull(value) {
  if (value === undefined || value === null) return null;
  const text = String(value).trim();
  return text ? text : null;
}

function parseCoord(value) {
  if (value === undefined || value === null || value === '') return null;
  const n = typeof value === 'number' ? value : Number.parseFloat(String(value));
  return Number.isFinite(n) ? n : null;
}

function deviceTypeFromUa(ua) {
  if (!ua) return null;
  const s = String(ua).toLowerCase();
  if (/ipad|tablet|playbook|silk/.test(s) || (/android/.test(s) && !/mobile/.test(s))) {
    return 'tablet';
  }
  if (/mobi|iphone|ipod|android|webos|blackberry|opera mini|iemobile/.test(s)) {
    return 'mobile';
  }
  return 'desktop';
}

function isBotUserAgent(ua) {
  if (!ua) return false;
  return BOT_UA_RE.test(String(ua));
}

function isBotRequest(request) {
  const ua = request.headers?.get?.('user-agent') || '';
  if (isBotUserAgent(ua)) return true;
  const bot = request.cf?.botManagement;
  if (!bot || typeof bot !== 'object') return false;
  if (bot.verifiedBot === true) return true;
  if (typeof bot.score === 'number' && bot.score < BOT_SCORE_THRESHOLD) return true;
  return false;
}

function isAssetPath(pathname) {
  const path = normalizePath(pathname);
  if (ASSET_EXT_RE.test(path)) return true;
  return ASSET_PREFIXES.some((prefix) => path.startsWith(prefix));
}

function isVisitsPath(pathname) {
  const path = normalizePath(pathname);
  return path === VISITS_PREFIX || path.startsWith(`${VISITS_PREFIX}/`);
}

function isHtmlPageView(request, url) {
  const method = (request.method || 'GET').toUpperCase();
  if (method !== 'GET') return false;
  const path = normalizePath(url.pathname);
  if (path.startsWith('/api/') || path === '/api') return false;
  if (isVisitsPath(path)) return false;
  if (isAssetPath(path)) return false;

  const accept = request.headers?.get?.('accept') || '';
  const mode = (request.headers?.get?.('sec-fetch-mode') || '').toLowerCase();
  const dest = (request.headers?.get?.('sec-fetch-dest') || '').toLowerCase();
  const isDocument = accept.includes('text/html') || mode === 'navigate' || dest === 'document';
  const isAppDocument = path === '/' || path === '/index.html';
  return isDocument || isAppDocument;
}

function shouldLogVisit(request, url) {
  return isHtmlPageView(request, url) && !isBotRequest(request);
}

function visitRowFromRequest(request, url, now = new Date()) {
  const cf = request.cf || {};
  const ua = request.headers?.get?.('user-agent') || '';
  return {
    ts: now.toISOString(),
    path: normalizePath(url.pathname),
    city: emptyToNull(cf.city),
    region: emptyToNull(cf.region),
    region_code: emptyToNull(cf.regionCode),
    country: emptyToNull(cf.country),
    postal_code: emptyToNull(cf.postalCode),
    latitude: parseCoord(cf.latitude),
    longitude: parseCoord(cf.longitude),
    timezone: emptyToNull(cf.timezone),
    colo: emptyToNull(cf.colo),
    device_type: deviceTypeFromUa(ua),
  };
}

async function timingSafeEqual(a, b) {
  const left = typeof a === 'string' ? a : '';
  const right = typeof b === 'string' ? b : '';
  const enc = new TextEncoder();
  const cryptoKey = await crypto.subtle.importKey(
    'raw',
    enc.encode('visits-key-compare'),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const [leftSig, rightSig] = await Promise.all([
    crypto.subtle.sign('HMAC', cryptoKey, enc.encode(left)),
    crypto.subtle.sign('HMAC', cryptoKey, enc.encode(right)),
  ]);
  const leftBytes = new Uint8Array(leftSig);
  const rightBytes = new Uint8Array(rightSig);
  if (leftBytes.length !== rightBytes.length) return false;
  let mismatch = 0;
  for (let i = 0; i < leftBytes.length; i++) {
    mismatch |= leftBytes[i] ^ rightBytes[i];
  }
  return mismatch === 0;
}

function parseVisitsRoute(url) {
  const path = normalizePath(url.pathname);
  if (path !== VISITS_PREFIX && !path.startsWith(`${VISITS_PREFIX}/`)) return null;

  if (path === VISITS_PREFIX) {
    return { key: url.searchParams.get('key') || '', kind: 'html' };
  }
  if (path === `${VISITS_PREFIX}/data`) {
    return { key: url.searchParams.get('key') || '', kind: 'json' };
  }

  const parts = path.slice(`${VISITS_PREFIX}/`.length).split('/').filter(Boolean);
  if (parts.length === 1) {
    try {
      return { key: decodeURIComponent(parts[0]), kind: 'html' };
    } catch {
      return { key: '', kind: 'unknown' };
    }
  }
  if (parts.length === 2 && parts[1] === 'data') {
    try {
      return { key: decodeURIComponent(parts[0]), kind: 'json' };
    } catch {
      return { key: '', kind: 'unknown' };
    }
  }
  return { key: '', kind: 'unknown' };
}

function normalizeRange(value) {
  const range = String(value || DEFAULT_RANGE).toLowerCase();
  if (range === 'all' || range in RANGES) return range;
  return DEFAULT_RANGE;
}

function rangeStartIso(range, now = new Date()) {
  const normalized = normalizeRange(range);
  if (normalized === 'all') return null;
  return new Date(now.getTime() - RANGES[normalized]).toISOString();
}

async function authorizedVisitsKey(candidate, secret) {
  if (!secret) return false;
  if (!candidate) {
    await timingSafeEqual(secret, '');
    return false;
  }
  return timingSafeEqual(candidate, secret);
}

function notFound() {
  return new Response('Not Found', {
    status: 404,
    headers: { 'Content-Type': 'text/plain;charset=UTF-8', ...PRIVATE_HEADERS },
  });
}

async function logVisit(request, env, url, now = new Date()) {
  const db = env?.VISITS;
  if (!db) return { logged: false, reason: 'unbound' };
  const row = visitRowFromRequest(request, url, now);
  await db
    .prepare(
      `INSERT INTO visits (
        ts, path, city, region, region_code, country, postal_code,
        latitude, longitude, timezone, colo, device_type
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    )
    .bind(
      row.ts,
      row.path,
      row.city,
      row.region,
      row.region_code,
      row.country,
      row.postal_code,
      row.latitude,
      row.longitude,
      row.timezone,
      row.colo,
      row.device_type,
    )
    .run();
  return { logged: true, row };
}

function scheduleVisitLog(request, env, ctx, url) {
  if (!shouldLogVisit(request, url)) return false;
  ctx.waitUntil(
    logVisit(request, env, url).catch((error) => {
      console.error('visit log failed:', error && error.message ? error.message : error);
    }),
  );
  return true;
}

async function loadVisitSummary(db, range, now = new Date()) {
  const normalized = normalizeRange(range);
  const start = rangeStartIso(normalized, now);
  const sql = `SELECT
      COALESCE(city, '') AS city,
      COALESCE(region, '') AS region,
      COALESCE(region_code, '') AS region_code,
      COALESCE(country, '') AS country,
      COUNT(*) AS count,
      MAX(ts) AS last_seen,
      AVG(latitude) AS latitude,
      AVG(longitude) AS longitude
    FROM visits
    ${start ? 'WHERE ts >= ?' : ''}
    GROUP BY 1, 2, 3, 4
    ORDER BY count DESC, last_seen DESC`;
  const stmt = start ? db.prepare(sql).bind(start) : db.prepare(sql);
  const result = await stmt.all();
  const cities = (result.results || result.rows || []).map((row) => ({
    city: row.city || null,
    region: row.region || null,
    region_code: row.region_code || null,
    country: row.country || null,
    count: Number(row.count) || 0,
    last_seen: row.last_seen || null,
    latitude: parseCoord(row.latitude),
    longitude: parseCoord(row.longitude),
  }));
  const total = cities.reduce((sum, row) => sum + row.count, 0);
  return {
    range: normalized,
    since: start,
    generated_at: now.toISOString(),
    total,
    cities,
  };
}

function visitsMapHtml() {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="robots" content="noindex, nofollow">
  <title>Visit map</title>
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
  <link rel="stylesheet" href="https://unpkg.com/leaflet.markercluster@1.5.3/dist/MarkerCluster.css">
  <link rel="stylesheet" href="https://unpkg.com/leaflet.markercluster@1.5.3/dist/MarkerCluster.Default.css">
  <style>
    :root {
      --bg: #0d2137;
      --bg-2: #1a3a5c;
      --text: #ffffff;
      --muted: rgba(255,255,255,0.72);
      --faint: rgba(255,255,255,0.48);
      --line: rgba(255,255,255,0.18);
      --accent: #7dd3fc;
      font-family: "DM Sans", system-ui, sans-serif;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      background: linear-gradient(180deg, var(--bg-2), var(--bg));
      color: var(--text);
    }
    header {
      display: flex;
      flex-wrap: wrap;
      gap: 12px 20px;
      align-items: center;
      justify-content: space-between;
      padding: 16px 20px;
      border-bottom: 1px solid var(--line);
    }
    h1 { font-size: 1.15rem; margin: 0; font-weight: 600; }
    .meta { color: var(--muted); font-size: 0.9rem; }
    .filters { display: flex; gap: 8px; flex-wrap: wrap; }
    .filters button {
      background: rgba(255,255,255,0.08);
      color: var(--text);
      border: 1px solid var(--line);
      border-radius: 999px;
      padding: 6px 12px;
      cursor: pointer;
    }
    .filters button[aria-pressed="true"] {
      background: rgba(125,211,252,0.2);
      border-color: var(--accent);
    }
    #map { height: min(62vh, 640px); width: 100%; background: #0a1a2b; }
    .table-wrap { padding: 16px 20px 32px; overflow-x: auto; }
    table { width: 100%; border-collapse: collapse; font-size: 0.95rem; }
    th, td { text-align: left; padding: 8px 10px; border-bottom: 1px solid var(--line); }
    th { color: var(--faint); font-weight: 500; }
    .empty, .error { padding: 20px; color: var(--muted); }
    .error { color: #fca5a5; }
  </style>
</head>
<body>
  <header>
    <div>
      <h1>Visit map</h1>
      <div class="meta" id="summary">Loading…</div>
    </div>
    <div class="filters" role="group" aria-label="Time range">
      <button type="button" data-range="24h">24 hours</button>
      <button type="button" data-range="7d" aria-pressed="true">7 days</button>
      <button type="button" data-range="30d">30 days</button>
      <button type="button" data-range="all">All</button>
    </div>
  </header>
  <div id="map"></div>
  <div class="table-wrap">
    <table>
      <thead>
        <tr>
          <th>City</th>
          <th>Region</th>
          <th>Country</th>
          <th>Visits</th>
          <th>Last seen</th>
        </tr>
      </thead>
      <tbody id="rows">
        <tr><td class="empty" colspan="5">Loading…</td></tr>
      </tbody>
    </table>
  </div>
  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
  <script src="https://unpkg.com/leaflet.markercluster@1.5.3/dist/leaflet.markercluster.js"></script>
  <script>
    const map = L.map('map', { scrollWheelZoom: true }).setView([20, 0], 2);
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '&copy; OpenStreetMap contributors',
      maxZoom: 18,
    }).addTo(map);
    const clusters = L.markerClusterGroup();
    map.addLayer(clusters);

    function dataEndpoint(range) {
      const url = new URL(location.href);
      const path = url.pathname.replace(/\\/+$/, '') || '/';
      if (path === '/_visits') url.pathname = '/_visits/data';
      else if (!path.endsWith('/data')) url.pathname = path + '/data';
      url.searchParams.set('range', range);
      return url.toString();
    }

    function label(value) {
      return value ? value : 'Unknown';
    }

    function formatTime(iso) {
      if (!iso) return '—';
      const date = new Date(iso);
      if (Number.isNaN(date.getTime())) return iso;
      return date.toLocaleString(undefined, {
        year: 'numeric', month: 'short', day: 'numeric',
        hour: 'numeric', minute: '2-digit', hour12: true,
      });
    }

    function setActive(range) {
      document.querySelectorAll('.filters button').forEach((button) => {
        button.setAttribute('aria-pressed', button.dataset.range === range ? 'true' : 'false');
      });
    }

    async function load(range) {
      setActive(range);
      const summary = document.getElementById('summary');
      const body = document.getElementById('rows');
      summary.textContent = 'Loading…';
      try {
        const response = await fetch(dataEndpoint(range), { cache: 'no-store' });
        if (!response.ok) throw new Error('Unable to load visits');
        const data = await response.json();
        summary.textContent = (data.total || 0) + ' visit' + (data.total === 1 ? '' : 's') +
          ' across ' + (data.cities || []).length + ' ' + ((data.cities || []).length === 1 ? 'place' : 'places');
        clusters.clearLayers();
        const points = [];
        (data.cities || []).forEach((row) => {
          if (row.latitude == null || row.longitude == null) return;
          const marker = L.marker([row.latitude, row.longitude]);
          marker.bindPopup(
            '<strong>' + label(row.city) + '</strong><br>' +
            label(row.region) + (row.country ? ', ' + row.country : '') + '<br>' +
            row.count + ' visit' + (row.count === 1 ? '' : 's') + '<br>Last seen ' + formatTime(row.last_seen)
          );
          clusters.addLayer(marker);
          points.push([row.latitude, row.longitude]);
        });
        if (points.length) map.fitBounds(points, { padding: [24, 24], maxZoom: 8 });
        else map.setView([20, 0], 2);
        if (!(data.cities || []).length) {
          body.innerHTML = '<tr><td class="empty" colspan="5">No visits in this range.</td></tr>';
          return;
        }
        body.innerHTML = data.cities.map((row) =>
          '<tr><td>' + label(row.city) + '</td><td>' + label(row.region) +
          '</td><td>' + label(row.country) + '</td><td>' + row.count +
          '</td><td>' + formatTime(row.last_seen) + '</td></tr>'
        ).join('');
      } catch (error) {
        summary.textContent = 'Unable to load visits';
        body.innerHTML = '<tr><td class="error" colspan="5">' + (error && error.message ? error.message : 'Error') + '</td></tr>';
      }
    }

    document.querySelectorAll('.filters button').forEach((button) => {
      button.addEventListener('click', () => load(button.dataset.range));
    });
    const initial = new URL(location.href).searchParams.get('range') || '7d';
    load(initial);
  </script>
</body>
</html>`;
}

async function handleVisitsRequest(request, env, url) {
  const route = parseVisitsRoute(url);
  if (!route) return null;
  const method = (request.method || 'GET').toUpperCase();
  if (method !== 'GET' && method !== 'HEAD') return notFound();
  const allowed = await authorizedVisitsKey(route.key, env?.VISITS_KEY);
  if (!allowed || route.kind === 'unknown') return notFound();

  if (route.kind === 'html') {
    return new Response(visitsMapHtml(), {
      status: 200,
      headers: {
        'Content-Type': 'text/html;charset=UTF-8',
        ...PRIVATE_HEADERS,
      },
    });
  }

  if (!env?.VISITS) {
    return new Response(JSON.stringify({ error: true, reason: 'Visit storage is not configured' }), {
      status: 503,
      headers: { 'Content-Type': 'application/json;charset=UTF-8', ...PRIVATE_HEADERS },
    });
  }

  try {
    const payload = await loadVisitSummary(env.VISITS, url.searchParams.get('range'));
    return new Response(JSON.stringify(payload), {
      status: 200,
      headers: { 'Content-Type': 'application/json;charset=UTF-8', ...PRIVATE_HEADERS },
    });
  } catch (error) {
    console.error('visit summary failed:', error && error.message ? error.message : error);
    return new Response(JSON.stringify({ error: true, reason: 'Visit data is unavailable' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json;charset=UTF-8', ...PRIVATE_HEADERS },
    });
  }
}

export {
  authorizedVisitsKey,
  deviceTypeFromUa,
  handleVisitsRequest,
  isAssetPath,
  isBotRequest,
  isBotUserAgent,
  isHtmlPageView,
  logVisit,
  normalizeRange,
  parseVisitsRoute,
  rangeStartIso,
  scheduleVisitLog,
  shouldLogVisit,
  timingSafeEqual,
  visitRowFromRequest,
};
