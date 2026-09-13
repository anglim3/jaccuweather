const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..');

function appJs() {
  return fs.readFileSync(path.join(root, 'public', 'app.js'), 'utf8');
}

function loadPatchApplier() {
  const source = fs.readFileSync(path.join(root, 'lockdown-worker.js'), 'utf8');
  const start = source.indexOf('function parseHunks');
  const end = source.indexOf('function extractJsonStringConst');
  const sandbox = { console };
  vm.runInNewContext(`${source.slice(start, end)}; this.applyUnifiedDiff = applyUnifiedDiff;`, sandbox);
  return sandbox.applyUnifiedDiff;
}

function patchedAppJs() {
  const applyUnifiedDiff = loadPatchApplier();
  let js = appJs();
  const dir = path.join(root, 'patches');
  const early = fs.readdirSync(dir).filter((f) => /^app-0[1-7]\.patch$/.test(f)).sort();
  js = applyUnifiedDiff(js, early.map((f) => fs.readFileSync(path.join(dir, f), 'utf8')).join(''));
  js = applyUnifiedDiff(js, fs.readFileSync(path.join(dir, 'app-08.patch'), 'utf8'));
  js = applyUnifiedDiff(js, fs.readFileSync(path.join(dir, 'app-09.patch'), 'utf8'));
  js = applyUnifiedDiff(js, fs.readFileSync(path.join(dir, 'app-10.patch'), 'utf8'));
  return js;
}

// Extract a top-level `function name(...) {...}` by brace matching.
function extractFunction(js, name) {
  const marker = `function ${name}(`;
  const start = js.indexOf(marker);
  assert.ok(start > -1, `expected function ${name} in app.js`);
  const brace = js.indexOf('{', start);
  let depth = 0;
  for (let i = brace; i < js.length; i++) {
    if (js[i] === '{') depth += 1;
    else if (js[i] === '}') {
      depth -= 1;
      if (depth === 0) return js.slice(start, i + 1);
    }
  }
  throw new Error(`unbalanced braces in ${name}`);
}

function loadUvHelpers(js) {
  const names = [
    'averageEnsembleValues',
    'modeEnsembleValue',
    'medianEnsembleValue',
    'medianFloorEnsembleValue',
    'summarizeDailyFromHourly',
    'uvCategoryLabel',
    'uvColorForValue',
    'maxHourlyUvForDateString'
  ];
  const sandbox = { console };
  const src = names.map((n) => extractFunction(js, n)).join('\n');
  vm.runInNewContext(`${src};
    this.summarizeDailyFromHourly = summarizeDailyFromHourly;
    this.uvCategoryLabel = uvCategoryLabel;
    this.uvColorForValue = uvColorForValue;
    this.maxHourlyUvForDateString = maxHourlyUvForDateString;`, sandbox);
  return sandbox;
}

function loadChartSeriesHelpers(js) {
  const start = js.indexOf('// ─── 14-day / hourly expanded-view chart series');
  assert.ok(start > -1, 'expected chart series helpers in app.js');
  const end = js.indexOf('function maybeRenderDailyChart', start);
  assert.ok(end > start, 'expected paintChartSelector before maybeRenderDailyChart');
  const sandbox = { console };
  vm.runInNewContext(`${js.slice(start, end)}; this.DEFAULT_CHART_SERIES = DEFAULT_CHART_SERIES; this.DAILY_CHART_TYPE_BY_KEY = DAILY_CHART_TYPE_BY_KEY; this.paintChartSelector = paintChartSelector; this.resolveDrawnChartSeries = resolveDrawnChartSeries; this.availableChartTypesFrom = availableChartTypesFrom;`, sandbox);
  return sandbox;
}

function mockContainer(type, featureHidden) {
  return {
    chartType: type,
    dataset: { featureHidden: featureHidden || 'false' },
    style: { display: '' },
    getAttribute(name) {
      return name === 'data-chart-type' ? type : null;
    }
  };
}

function fromVm(value) {
  return JSON.parse(JSON.stringify(value));
}

test('fetchWeather requests hourly uv_index and daily uv_index_max', () => {
  const js = appJs();
  const urlMatch = js.match(/ensemble-api\.open-meteo\.com\/v1\/ensemble\?[^`]+/);
  assert.ok(urlMatch, 'expected ensemble request URL in fetchWeather');
  const url = urlMatch[0];
  assert.match(url, /hourly=[^`]*uv_index/);
  assert.match(url, /daily=[^`]*uv_index_max/);
});

test('daily normalization carries uv_index_max with 1-decimal rounding and units', () => {
  const js = appJs();
  assert.match(js, /\{\s*source:\s*'uv_index_max',\s*target:\s*'uv_index_max'/);
  assert.match(js, /uv_index_max:\s*\{\s*decimals:\s*1\s*\}/);
  assert.ok(js.includes("'uv_index_max'"), 'expected uv_index_max in missingDailyFields');
  assert.ok(js.includes('normalized.daily_units.uv_index_max'), 'expected daily units fallback');
});

test('hourly modal builds a UV series from hourly uv_index', () => {
  const js = appJs();
  assert.ok(js.includes('const uv = [];'), 'expected hourly uv array');
  assert.ok(js.includes('hourlyChart.uv = new ApexCharts'), 'expected hourly UV chart');
  assert.ok(js.includes("document.getElementById('hourlyUvChart')"), 'expected hourly UV chart element');
  assert.ok(js.includes('hourlyChart.uv.render()'), 'expected hourly UV chart render');
  assert.ok(js.includes("series: [{ name: 'UV index', data: uv }]"), 'expected UV series label');
});

test('daily modal builds a UV series from daily uv_index_max with lazy render', () => {
  const js = appJs();
  assert.ok(js.includes('const dailyUv = [];'), 'expected daily UV array');
  assert.ok(js.includes('dailyChart.uv = new ApexCharts'), 'expected daily UV chart');
  assert.ok(js.includes("document.getElementById('dailyUvChart')"), 'expected daily UV chart element');
  assert.ok(js.includes("maybeRenderDailyChart('uv')"), 'expected lazy daily UV render');
  assert.ok(js.includes("series: [{ name: 'UV index', data: dailyUv }]"), 'expected UV series label');
  assert.ok(js.includes('data.daily.uv_index_max'), 'expected daily uv_index_max read');
});

test('daily chart key map exposes uv as a first-class series', () => {
  const helpers = loadChartSeriesHelpers(appJs());
  assert.equal(fromVm(helpers.DAILY_CHART_TYPE_BY_KEY.uv), 'uv');
});

test('index.html offers UV in both selectors with matching chart containers', () => {
  const html = fs.readFileSync(path.join(root, 'public', 'index.html'), 'utf8');
  assert.match(html, /id="hourlyChartSelect"[\s\S]*?value="uv">UV index/);
  assert.match(html, /id="dailyChartSelect"[\s\S]*?value="uv">UV index/);
  assert.ok(html.includes('data-chart-type="uv"'), 'expected uv chart containers');
  assert.ok(html.includes('id="hourlyUvChart"'), 'expected hourly UV chart element');
  assert.ok(html.includes('id="dailyUvChart"'), 'expected daily UV chart element');
});

test('WHO bands label boundary values', () => {
  const h = loadUvHelpers(appJs());
  assert.equal(h.uvCategoryLabel(0), 'Low');
  assert.equal(h.uvCategoryLabel(2.9), 'Low');
  assert.equal(h.uvCategoryLabel(3), 'Moderate');
  assert.equal(h.uvCategoryLabel(5.4), 'Moderate');
  assert.equal(h.uvCategoryLabel(6), 'High');
  assert.equal(h.uvCategoryLabel(7.9), 'High');
  assert.equal(h.uvCategoryLabel(8), 'Very high');
  assert.equal(h.uvCategoryLabel(10.9), 'Very high');
  assert.equal(h.uvCategoryLabel(11), 'Extreme');
  assert.equal(h.uvCategoryLabel(14), 'Extreme');
  assert.equal(h.uvCategoryLabel(null), 'Low');
});

test('UV point colors change at the same band edges', () => {
  const h = loadUvHelpers(appJs());
  assert.equal(h.uvColorForValue(1), 'rgb(34, 197, 94)');
  assert.equal(h.uvColorForValue(4), 'rgb(250, 204, 21)');
  assert.equal(h.uvColorForValue(6.5), 'rgb(251, 146, 60)');
  assert.equal(h.uvColorForValue(9), 'rgb(239, 68, 68)');
  assert.equal(h.uvColorForValue(12), 'rgb(168, 85, 247)');
});

test('daily UV max derives from hourly values when daily is missing', () => {
  const h = loadUvHelpers(appJs());
  const hourly = {
    time: ['2026-09-14T00:00', '2026-09-14T12:00', '2026-09-14T23:00', '2026-09-15T12:00'],
    uv_index: [0, 5.55, 0.2, 8.1]
  };
  assert.equal(h.maxHourlyUvForDateString(hourly, '2026-09-14'), 5.6);
  assert.equal(h.maxHourlyUvForDateString(hourly, '2026-09-15'), 8.1);
  assert.equal(h.maxHourlyUvForDateString(hourly, '2026-09-16'), null);
  assert.equal(h.maxHourlyUvForDateString({ time: [], uv_index: [] }, '2026-09-14'), null);
});

test('summarizeDailyFromHourly takes the daily max of hourly uv_index', () => {
  const h = loadUvHelpers(appJs());
  const hourly = {
    time: ['2026-09-14T00:00', '2026-09-14T06:00', '2026-09-14T12:00', '2026-09-15T12:00'],
    weather_code: [1, 1, 2, 3],
    temperature_2m: [60, 62, 75, 70],
    apparent_temperature: [60, 62, 75, 70],
    precipitation: [0, 0, 0, 0],
    wind_speed_10m: [5, 6, 7, 8],
    precipitation_probability: [0, 0, 10, 20],
    snowfall: [0, 0, 0, 0],
    uv_index: [0, 1.2, 6.44, 3.3]
  };
  const daily = h.summarizeDailyFromHourly(hourly, ['2026-09-14', '2026-09-15']);
  assert.deepEqual(fromVm(daily.uv_index_max), [6.44, 3.3]);
});

test('selector can switch to UV and first paint still defaults to temperature', () => {
  const helpers = loadChartSeriesHelpers(appJs());
  const types = ['temp', 'precip', 'wind', 'uv', 'humidity', 'pressure', 'snow', 'cloud', 'brightness'];
  const containers = types.map((t) => mockContainer(t));
  assert.deepEqual(fromVm(helpers.paintChartSelector(containers, 'all', true)), ['temp']);
  assert.deepEqual(fromVm(helpers.paintChartSelector(containers, 'uv', false)), ['uv']);
  assert.deepEqual(fromVm(helpers.resolveDrawnChartSeries('uv', types)), ['uv']);
});

test('patched worker JS keeps UV wiring after lockdown patches', () => {
  const js = patchedAppJs();
  const helpers = loadChartSeriesHelpers(js);
  assert.equal(fromVm(helpers.DAILY_CHART_TYPE_BY_KEY.uv), 'uv');
  assert.ok(js.includes('hourlyChart.uv = new ApexCharts'), 'expected hourly UV chart after patches');
  assert.ok(js.includes('dailyChart.uv = new ApexCharts'), 'expected daily UV chart after patches');
  assert.ok(js.includes('uv_index_max'), 'expected uv_index_max after patches');
  const start = js.indexOf('function uvCategoryLabel');
  assert.ok(start > -1, 'expected UV helpers after patches');
  const helpersEnd = js.indexOf('// ─── 14-day / hourly expanded-view chart series', start);
  assert.ok(helpersEnd > start, 'expected UV helpers before chart series section');
  const sandbox = { console };
  vm.runInNewContext(`${js.slice(start, helpersEnd)}; this.uvCategoryLabel = uvCategoryLabel;`, sandbox);
  assert.equal(sandbox.uvCategoryLabel(7), 'High');
});
