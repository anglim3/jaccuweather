import test from 'node:test';
import assert from 'node:assert/strict';
import {
  authorizedVisitsKey,
  deviceTypeFromUa,
  handleVisitsRequest,
  isAssetPath,
  isBotRequest,
  isHtmlPageView,
  logVisit,
  parseVisitsRoute,
  rangeStartIso,
  scheduleVisitLog,
  shouldLogVisit,
  timingSafeEqual,
  visitRowFromRequest,
} from '../src/visits.js';

function headers(map = {}) {
  const normalized = Object.fromEntries(
    Object.entries(map).map(([k, v]) => [k.toLowerCase(), v]),
  );
  return {
    get(name) {
      return normalized[String(name).toLowerCase()] ?? null;
    },
  };
}

function makeRequest(url, { method = 'GET', headerMap = {}, cf } = {}) {
  return { method, headers: headers(headerMap), url, cf };
}

class MemoryD1 {
  constructor() {
    this.rows = [];
    this.failNext = false;
  }

  prepare(sql) {
    const db = this;
    const bound = (...params) => ({
          async run() {
            if (db.failNext) {
              db.failNext = false;
              throw new Error('d1 write failed');
            }
            if (/INSERT INTO visits/i.test(sql)) {
              db.rows.push({
                ts: params[0],
                path: params[1],
                city: params[2],
                region: params[3],
                region_code: params[4],
                country: params[5],
                postal_code: params[6],
                latitude: params[7],
                longitude: params[8],
                timezone: params[9],
                colo: params[10],
                device_type: params[11],
              });
            }
            return { success: true };
          },
          async all() {
            if (db.failNext) {
              db.failNext = false;
              throw new Error('d1 read failed');
            }
            let rows = db.rows;
            if (/WHERE ts >= \?/.test(sql)) {
              rows = rows.filter((row) => row.ts >= params[0]);
            }
            const groups = new Map();
            for (const row of rows) {
              const key = [row.city || '', row.region || '', row.region_code || '', row.country || ''].join('|');
              const existing = groups.get(key);
              const latCount = (existing?.latCount || 0) + (row.latitude == null ? 0 : 1);
              const lonCount = (existing?.lonCount || 0) + (row.longitude == null ? 0 : 1);
              groups.set(key, {
                city: row.city || '',
                region: row.region || '',
                region_code: row.region_code || '',
                country: row.country || '',
                count: (existing?.count || 0) + 1,
                last_seen: !existing || row.ts > existing.last_seen ? row.ts : existing.last_seen,
                latitude: row.latitude == null ? existing?.latitude ?? null : ((existing?.latitude || 0) * (existing?.latCount || 0) + row.latitude) / latCount,
                longitude: row.longitude == null ? existing?.longitude ?? null : ((existing?.longitude || 0) * (existing?.lonCount || 0) + row.longitude) / lonCount,
                latCount,
                lonCount,
              });
            }
            const results = [...groups.values()].sort((a, b) => b.count - a.count || (b.last_seen < a.last_seen ? -1 : 1));
            return { results };
          },
    });
    const unbound = bound();
    return {
      bind: bound,
      run: unbound.run,
      all: unbound.all,
    };
  }
}

test('isHtmlPageView logs app documents and other HTML navigations', () => {
  const home = new URL('https://example.com/');
  assert.equal(isHtmlPageView(makeRequest(home, { headerMap: { accept: '*/*' } }), home), true);
  assert.equal(
    isHtmlPageView(makeRequest(new URL('https://example.com/index.html')), new URL('https://example.com/index.html')),
    true,
  );
  const other = new URL('https://example.com/about');
  assert.equal(
    isHtmlPageView(makeRequest(other, { headerMap: { accept: 'text/html' } }), other),
    true,
  );
  assert.equal(
    isHtmlPageView(makeRequest(other, { headerMap: { 'sec-fetch-mode': 'navigate' } }), other),
    true,
  );
  assert.equal(isHtmlPageView(makeRequest(other, { headerMap: { accept: '*/*' } }), other), false);
});

test('isHtmlPageView skips assets, APIs, visits routes, and non-GET', () => {
  const cases = [
    'https://example.com/app.js',
    'https://example.com/favicon.svg',
    'https://example.com/apple-touch-icon.png',
    'https://example.com/icons/weather/clear-day.svg',
    'https://example.com/api/forecast?lat=1',
    'https://example.com/_visits',
    'https://example.com/_visits/secret',
    'https://example.com/_visits/secret/data',
  ];
  for (const href of cases) {
    const url = new URL(href);
    assert.equal(isHtmlPageView(makeRequest(url, { headerMap: { accept: 'text/html' } }), url), false, href);
  }
  const home = new URL('https://example.com/');
  assert.equal(isHtmlPageView(makeRequest(home, { method: 'POST', headerMap: { accept: 'text/html' } }), home), false);
  assert.equal(isHtmlPageView(makeRequest(home, { method: 'HEAD' }), home), false);
  assert.equal(isAssetPath('/icons/cards/barometer.svg'), true);
});

test('bot user agents and botManagement signals are skipped', () => {
  const home = new URL('https://example.com/');
  const botUa = makeRequest(home, { headerMap: { 'user-agent': 'Mozilla/5.0 (compatible; Googlebot/2.1)' } });
  assert.equal(isBotRequest(botUa), true);
  assert.equal(shouldLogVisit(botUa, home), false);

  const crawl = makeRequest(home, { headerMap: { 'user-agent': 'SomeCrawler/1.0' } });
  assert.equal(isBotRequest(crawl), true);

  const verified = makeRequest(home, {
    headerMap: { 'user-agent': 'Mozilla/5.0' },
    cf: { botManagement: { verifiedBot: true, score: 99 } },
  });
  assert.equal(isBotRequest(verified), true);
  assert.equal(shouldLogVisit(verified, home), false);

  const lowScore = makeRequest(home, {
    headerMap: { 'user-agent': 'Mozilla/5.0' },
    cf: { botManagement: { score: 15 } },
  });
  assert.equal(isBotRequest(lowScore), true);

  const human = makeRequest(home, {
    headerMap: { 'user-agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/120.0.0.0' },
    cf: { botManagement: { verifiedBot: false, score: 95 } },
  });
  assert.equal(isBotRequest(human), false);
  assert.equal(shouldLogVisit(human, home), true);
});

test('deviceTypeFromUa is coarse and visit rows omit IP and raw user agent', () => {
  assert.equal(deviceTypeFromUa('Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)'), 'mobile');
  assert.equal(deviceTypeFromUa('Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X)'), 'tablet');
  assert.equal(deviceTypeFromUa('Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0'), 'desktop');
  assert.equal(deviceTypeFromUa(''), null);

  const url = new URL('https://example.com/');
  const request = makeRequest(url, {
    headerMap: {
      'user-agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)',
      'cf-connecting-ip': '203.0.113.10',
    },
    cf: {
      city: 'Denver',
      region: 'Colorado',
      regionCode: 'CO',
      country: 'US',
      postalCode: '80202',
      latitude: '39.7392',
      longitude: '-104.9903',
      timezone: 'America/New_York',
      colo: 'DEN',
    },
  });
  const row = visitRowFromRequest(request, url, new Date('2026-11-22T22:00:00.000Z'));
  assert.equal(row.ts, '2026-11-22T22:00:00.000Z');
  assert.equal(row.path, '/');
  assert.equal(row.city, 'Denver');
  assert.equal(row.region, 'Colorado');
  assert.equal(row.region_code, 'CO');
  assert.equal(row.country, 'US');
  assert.equal(row.postal_code, '80202');
  assert.equal(row.latitude, 39.7392);
  assert.equal(row.longitude, -104.9903);
  assert.equal(row.timezone, 'America/New_York');
  assert.equal(row.colo, 'DEN');
  assert.equal(row.device_type, 'mobile');
  assert.equal(Object.prototype.hasOwnProperty.call(row, 'ip'), false);
  assert.equal(Object.prototype.hasOwnProperty.call(row, 'user_agent'), false);
  assert.equal(Object.prototype.hasOwnProperty.call(row, 'userAgent'), false);
  assert.equal(JSON.stringify(row).includes('203.0.113.10'), false);
  assert.equal(JSON.stringify(row).includes('iPhone'), false);
});

test('timingSafeEqual distinguishes keys without early string compare', async () => {
  assert.equal(await timingSafeEqual('alpha', 'alpha'), true);
  assert.equal(await timingSafeEqual('alpha', 'beta'), false);
  assert.equal(await timingSafeEqual('alpha', 'alph'), false);
  assert.equal(await authorizedVisitsKey('secret-key', 'secret-key'), true);
  assert.equal(await authorizedVisitsKey('nope', 'secret-key'), false);
  assert.equal(await authorizedVisitsKey('', 'secret-key'), false);
  assert.equal(await authorizedVisitsKey('secret-key', ''), false);
});

test('parseVisitsRoute accepts path and query keys', () => {
  const pathHtml = parseVisitsRoute(new URL('https://example.com/_visits/abc%2Fdef'));
  assert.equal(pathHtml.kind, 'html');
  assert.equal(pathHtml.key, 'abc/def');
  const pathJson = parseVisitsRoute(new URL('https://example.com/_visits/abc/data?range=24h'));
  assert.equal(pathJson.kind, 'json');
  assert.equal(pathJson.key, 'abc');
  const queryHtml = parseVisitsRoute(new URL('https://example.com/_visits?key=abc'));
  assert.equal(queryHtml.kind, 'html');
  assert.equal(queryHtml.key, 'abc');
  const queryJson = parseVisitsRoute(new URL('https://example.com/_visits/data?key=abc'));
  assert.equal(queryJson.kind, 'json');
  assert.equal(parseVisitsRoute(new URL('https://example.com/')), null);
});

test('rangeStartIso covers 24h, 7d, 30d, and all', () => {
  const now = new Date('2026-11-22T17:00:00.000Z');
  assert.equal(rangeStartIso('24h', now), '2026-11-21T17:00:00.000Z');
  assert.equal(rangeStartIso('7d', now), '2026-11-15T17:00:00.000Z');
  assert.equal(rangeStartIso('30d', now), '2026-10-23T17:00:00.000Z');
  assert.equal(rangeStartIso('all', now), null);
  assert.equal(rangeStartIso('nope', now), '2026-11-15T17:00:00.000Z');
});

test('logVisit writes city fields and local geo may be null', async () => {
  const db = new MemoryD1();
  const url = new URL('https://example.com/');
  const withGeo = makeRequest(url, {
    headerMap: { 'user-agent': 'Mozilla/5.0 (Macintosh)' },
    cf: { city: 'Austin', region: 'Texas', regionCode: 'TX', country: 'US', latitude: '30.27', longitude: '-97.74', colo: 'DFW' },
  });
  const logged = await logVisit(withGeo, { VISITS: db }, url, new Date('2026-11-22T18:00:00.000Z'));
  assert.equal(logged.logged, true);
  assert.equal(db.rows.length, 1);
  assert.equal(db.rows[0].city, 'Austin');
  assert.equal(db.rows[0].latitude, 30.27);

  const noGeo = makeRequest(url, { headerMap: { 'user-agent': 'Mozilla/5.0 (Macintosh)' } });
  await logVisit(noGeo, { VISITS: db }, url, new Date('2026-11-22T19:00:00.000Z'));
  assert.equal(db.rows[1].city, null);
  assert.equal(db.rows[1].latitude, null);
  assert.deepEqual(await logVisit(noGeo, {}, url), { logged: false, reason: 'unbound' });
});

test('private map is 404 without the right key and renders with the right key', async () => {
  const db = new MemoryD1();
  const env = { VISITS: db, VISITS_KEY: 'correct-key' };
  const wrongPath = await handleVisitsRequest(makeRequest('https://example.com/_visits/wrong-key'), env, new URL('https://example.com/_visits/wrong-key'));
  assert.equal(wrongPath.status, 404);
  assert.equal(wrongPath.headers.get('Cache-Control'), 'no-store');
  assert.equal(wrongPath.headers.get('X-Robots-Tag'), 'noindex, nofollow');

  const missing = await handleVisitsRequest(makeRequest('https://example.com/_visits'), env, new URL('https://example.com/_visits'));
  assert.equal(missing.status, 404);

  const html = await handleVisitsRequest(makeRequest('https://example.com/_visits/correct-key'), env, new URL('https://example.com/_visits/correct-key'));
  assert.equal(html.status, 200);
  assert.equal(html.headers.get('Content-Type').includes('text/html'), true);
  const body = await html.text();
  assert.match(body, /leaflet/i);
  assert.match(body, /noindex/);
  assert.equal(body.includes('correct-key'), false);

  const query = await handleVisitsRequest(
    makeRequest('https://example.com/_visits?key=correct-key'),
    env,
    new URL('https://example.com/_visits?key=correct-key'),
  );
  assert.equal(query.status, 200);
});

test('JSON endpoint aggregates counts and honors the range filter', async () => {
  const db = new MemoryD1();
  const env = { VISITS: db, VISITS_KEY: 'correct-key' };
  const url = new URL('https://example.com/');
  await logVisit(
    makeRequest(url, { cf: { city: 'Austin', region: 'Texas', country: 'US', latitude: '30.27', longitude: '-97.74' } }),
    env,
    url,
    new Date('2026-11-22T18:00:00.000Z'),
  );
  await logVisit(
    makeRequest(url, { cf: { city: 'Austin', region: 'Texas', country: 'US', latitude: '30.27', longitude: '-97.74' } }),
    env,
    url,
    new Date('2026-11-10T18:00:00.000Z'),
  );

  const week = await handleVisitsRequest(
    makeRequest('https://example.com/_visits/correct-key/data?range=7d'),
    env,
    new URL('https://example.com/_visits/correct-key/data?range=7d'),
  );
  assert.equal(week.status, 200);
  const weekJson = await week.json();
  assert.equal(weekJson.range, '7d');
  assert.equal(weekJson.total, 1);
  assert.equal(weekJson.cities[0].city, 'Austin');
  assert.equal(weekJson.cities[0].count, 1);

  const all = await handleVisitsRequest(
    makeRequest('https://example.com/_visits/data?key=correct-key&range=all'),
    env,
    new URL('https://example.com/_visits/data?key=correct-key&range=all'),
  );
  const allJson = await all.json();
  assert.equal(allJson.total, 2);
  assert.equal(allJson.cities[0].count, 2);
});

test('scheduleVisitLog uses waitUntil and logging failures do not throw', async () => {
  const url = new URL('https://example.com/');
  const request = makeRequest(url, { headerMap: { 'user-agent': 'Mozilla/5.0' } });
  const db = new MemoryD1();
  db.failNext = true;
  const pending = [];
  const ctx = { waitUntil(promise) { pending.push(promise); } };
  assert.equal(scheduleVisitLog(request, { VISITS: db }, ctx, url), true);
  assert.equal(pending.length, 1);
  await assert.doesNotReject(pending[0]);

  const skipped = scheduleVisitLog(
    makeRequest(url, { headerMap: { 'user-agent': 'compatible crawler' } }),
    { VISITS: db },
    ctx,
    url,
  );
  assert.equal(skipped, false);
  assert.equal(pending.length, 1);
});
