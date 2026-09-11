const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..');
const appJs = fs.readFileSync(path.join(root, 'public', 'app.js'), 'utf8');

const SECTION_MARKER = '// ─── Stale-refresh after tab sleep (issue #10) ─────────────────────────────';

function loadStaleRefreshSection(options = {}) {
  const at = appJs.indexOf(SECTION_MARKER);
  assert.ok(at > -1, 'stale-refresh section exists in public/app.js');
  const section = appJs.slice(at);

  const listeners = { document: [], window: [] };
  const intervals = [];
  const labelEl = { textContent: '' };
  const fetchCalls = [];
  let fetchBehavior = options.fetchBehavior || 'resolve';

  const sandbox = {
    console,
    currentLat: options.lat !== undefined ? options.lat : 51.5,
    currentLon: options.lon !== undefined ? options.lon : -0.12,
    document: {
      hidden: false,
      getElementById: (id) => (id === 'lastUpdated' ? labelEl : null),
      addEventListener: (type, fn) => listeners.document.push({ type, fn }),
    },
    window: {
      addEventListener: (type, fn) => listeners.window.push({ type, fn }),
    },
    setInterval: (fn, ms) => {
      intervals.push({ fn, ms });
      return intervals.length;
    },
    fetchWeather: options.fetchImpl || (async (lat, lon) => {
      fetchCalls.push({ lat, lon });
      if (fetchBehavior === 'reject') throw new Error('network down');
    }),
  };
  vm.createContext(sandbox);
  vm.runInContext(`${section}; this.__staleRefresh = {
    formatLastUpdatedBetween,
    shouldRefetchStaleForecast,
    recordWeatherFetchTime,
    updateLastUpdatedLabel,
    handleStaleRefreshVisible,
    STALE_REFETCH_AFTER_MS,
    LAST_UPDATED_TICK_MS,
  };`, sandbox);
  return { ...sandbox.__staleRefresh, listeners, intervals, labelEl, fetchCalls, setFetchBehavior: (b) => { fetchBehavior = b; } };
}

test('stale refetch threshold is 15 minutes and retick interval is 30s', () => {
  const mod = loadStaleRefreshSection();
  assert.equal(mod.STALE_REFETCH_AFTER_MS, 15 * 60 * 1000);
  assert.equal(mod.LAST_UPDATED_TICK_MS, 30 * 1000);
  assert.ok(mod.LAST_UPDATED_TICK_MS >= 30 * 1000 && mod.LAST_UPDATED_TICK_MS <= 60 * 1000);
});

test('formatLastUpdatedBetween renders the relative label from a stored timestamp', () => {
  const mod = loadStaleRefreshSection();
  const now = Date.UTC(2026, 8, 11, 12, 0, 0);
  assert.equal(mod.formatLastUpdatedBetween(now, now), 'just now');
  assert.equal(mod.formatLastUpdatedBetween(now, now - 30 * 1000), 'just now');
  assert.equal(mod.formatLastUpdatedBetween(now, now - 60 * 1000), '1 minute ago');
  assert.equal(mod.formatLastUpdatedBetween(now, now - 2 * 60 * 1000), '2 minutes ago');
  assert.equal(mod.formatLastUpdatedBetween(now, now - 59 * 60 * 1000), '59 minutes ago');
  assert.equal(mod.formatLastUpdatedBetween(now, now - 60 * 60 * 1000), '1 hour ago');
  assert.equal(mod.formatLastUpdatedBetween(now, now - 3 * 60 * 60 * 1000), '3 hours ago');
  assert.equal(mod.formatLastUpdatedBetween(now, now + 60 * 1000), 'just now');
  assert.equal(mod.formatLastUpdatedBetween(now, NaN), 'just now');
});

test('formatLastUpdatedBetween matches formatLastUpdated wording', () => {
  const source = appJs;
  const start = source.indexOf('function formatLastUpdated(date)');
  const end = source.indexOf('function displayPressure(data)');
  assert.ok(start > -1 && end > start, 'expected formatLastUpdated in app.js');
  const sandbox = { Date };
  vm.runInNewContext(
    `${source.slice(start, end)};
     this.formatLastUpdated = formatLastUpdated;`,
    sandbox
  );
  const mod = loadStaleRefreshSection();
  const RealDate = Date;
  const nowMs = Date.UTC(2026, 8, 11, 12, 0, 0);
  // Pin the clock inside the legacy helper so both render from the same "now".
  sandbox.Date = class extends RealDate {
    constructor(...args) {
      super(...(args.length ? args : [nowMs]));
    }
    static now() {
      return nowMs;
    }
  };
  vm.runInNewContext('this.renderLegacy = (ms) => formatLastUpdated(new Date(ms));', sandbox);
  for (const offsetMs of [0, 30 * 1000, 60 * 1000, 14 * 60 * 1000, 60 * 60 * 1000, 5 * 60 * 60 * 1000]) {
    assert.equal(mod.formatLastUpdatedBetween(nowMs, nowMs - offsetMs), sandbox.renderLegacy(nowMs - offsetMs));
  }
});

test('shouldRefetchStaleForecast only fires beyond the threshold', () => {
  const mod = loadStaleRefreshSection();
  const now = 1_000_000_000;
  const fifteen = 15 * 60 * 1000;
  assert.equal(mod.shouldRefetchStaleForecast(now, 0), false);
  assert.equal(mod.shouldRefetchStaleForecast(now, NaN), false);
  assert.equal(mod.shouldRefetchStaleForecast(now, now - 2 * 60 * 1000), false);
  assert.equal(mod.shouldRefetchStaleForecast(now, now - 14 * 60 * 1000), false);
  assert.equal(mod.shouldRefetchStaleForecast(now, now - fifteen), true);
  assert.equal(mod.shouldRefetchStaleForecast(now, now - 3 * 60 * 60 * 1000), true);
});

test('displayWeather records the fetch time and paints the label from it', () => {
  assert.match(appJs, /recordWeatherFetchTime\(Date\.now\(\)\);\s*updateLastUpdatedLabel\(\);/);
  assert.equal(appJs.includes('`Updated ${formatLastUpdated(new Date())}`'), false);
});

test('retick timer and wake listeners are wired without unconditional refetch', () => {
  const mod = loadStaleRefreshSection();
  assert.deepEqual(mod.listeners.document.map((l) => l.type), ['visibilitychange']);
  assert.deepEqual(mod.listeners.window.map((l) => l.type), ['pageshow']);
  assert.equal(mod.intervals.length, 1);
  assert.equal(mod.intervals[0].ms, 30 * 1000);
  assert.match(appJs, /document\.addEventListener\('visibilitychange'/);
  assert.match(appJs, /window\.addEventListener\('pageshow', handleStaleRefreshVisible\)/);
  assert.match(appJs, /if \(!shouldRefetchStaleForecast\(Date\.now\(\), lastWeatherFetchTimeMs\)\) return;/);
});

test('becoming visible reticks and refetches only when stale', async () => {
  const mod = loadStaleRefreshSection();
  const fifteen = 15 * 60 * 1000;

  // Fresh data: retick only, no refetch.
  mod.recordWeatherFetchTime(Date.now() - 2 * 60 * 1000);
  mod.listeners.window[0].fn();
  assert.equal(mod.fetchCalls.length, 0);
  assert.match(mod.labelEl.textContent, /^Updated 2 minutes ago$/);

  // Stale data: retick plus exactly one refetch for the current location.
  mod.recordWeatherFetchTime(Date.now() - 20 * 60 * 1000);
  mod.listeners.window[0].fn();
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(mod.fetchCalls.length, 1);
  assert.deepEqual([mod.fetchCalls[0].lat, mod.fetchCalls[0].lon], [51.5, -0.12]);
  assert.match(mod.labelEl.textContent, /^Updated 20 minutes ago$/);

  // No recorded fetch yet: never touch the label, never fetch.
  const fresh = loadStaleRefreshSection();
  fresh.listeners.window[0].fn();
  assert.equal(fresh.fetchCalls.length, 0);
  assert.equal(fresh.labelEl.textContent, '');
});

test('automatic refetch never overlaps an in-flight fetchWeather call', async () => {
  const fetchCalls = [];
  let releaseFetch;
  const fetchGate = new Promise((resolve) => { releaseFetch = resolve; });
  const mod = loadStaleRefreshSection({
    fetchImpl: async (lat, lon) => {
      fetchCalls.push({ lat, lon });
      await fetchGate;
    },
  });
  mod.recordWeatherFetchTime(Date.now() - 60 * 60 * 1000);

  // First visible event kicks off a fetch that stays pending...
  mod.listeners.window[0].fn();
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(fetchCalls.length, 1);

  // ...so a second visible event mid-flight must retick but not refetch.
  mod.listeners.window[0].fn();
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(fetchCalls.length, 1);
  assert.match(mod.labelEl.textContent, /^Updated 1 hour ago$/);

  releaseFetch();
  await new Promise((resolve) => setImmediate(resolve));

  // Once the in-flight fetch settles, a later visible event may refetch again.
  mod.listeners.window[0].fn();
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(fetchCalls.length, 2);
});
