const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..');

const TIDES_CITY_TYPES = [
  'temp', 'feelslike', 'niceweather', 'precip', 'wind', 'pressure',
  'snow', 'cloud', 'brightness', 'tides', 'moon'
];
const INLAND_CITY_TYPES = TIDES_CITY_TYPES.filter((t) => t !== 'tides');

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
  let js = fs.readFileSync(path.join(root, 'public', 'app.js'), 'utf8');
  const dir = path.join(root, 'patches');
  const early = fs.readdirSync(dir).filter((f) => /^app-0[1-7]\.patch$/.test(f)).sort();
  js = applyUnifiedDiff(js, early.map((f) => fs.readFileSync(path.join(dir, f), 'utf8')).join(''));
  js = applyUnifiedDiff(js, fs.readFileSync(path.join(dir, 'app-08.patch'), 'utf8'));
  js = applyUnifiedDiff(js, fs.readFileSync(path.join(dir, 'app-09.patch'), 'utf8'));
  js = applyUnifiedDiff(js, fs.readFileSync(path.join(dir, 'app-10.patch'), 'utf8'));
  return js;
}

function loadChartSeriesHelpers(js) {
  const start = js.indexOf('// ─── 14-day / hourly expanded-view chart series');
  assert.ok(start > -1, 'expected chart series helpers in app.js');
  const end = js.indexOf('function maybeRenderDailyChart', start);
  assert.ok(end > start, 'expected paintChartSelector before maybeRenderDailyChart');
  const sandbox = { console };
  vm.runInNewContext(`${js.slice(start, end)}; this.DEFAULT_CHART_SERIES = DEFAULT_CHART_SERIES; this.availableChartTypesFrom = availableChartTypesFrom; this.applyChartSeriesVisibility = applyChartSeriesVisibility; this.resolveDrawnChartSeries = resolveDrawnChartSeries; this.paintChartSelector = paintChartSelector;`, sandbox);
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

function mockCityContainers(types, hiddenTypes) {
  const hidden = new Set(hiddenTypes || []);
  return types.map((type) => mockContainer(type, hidden.has(type) ? 'true' : 'false'));
}

function fromVm(value) {
  return JSON.parse(JSON.stringify(value));
}

function simulateExpandedView(availableTypes) {
  const helpers = loadChartSeriesHelpers(fs.readFileSync(path.join(root, 'public', 'app.js'), 'utf8'));
  const hidden = TIDES_CITY_TYPES.filter((t) => !availableTypes.includes(t));
  const containers = mockCityContainers(TIDES_CITY_TYPES, hidden);
  return {
    firstOpen(reportedSelectValue) {
      // cloned <select> may report "all" even when Temperature looks selected
      return fromVm(helpers.paintChartSelector(containers, reportedSelectValue, true));
    },
    select(nextValue) {
      return fromVm(helpers.paintChartSelector(containers, nextValue, false));
    },
    visibleTypes() {
      return containers.filter((c) => c.style.display === 'block').map((c) => c.chartType);
    }
  };
}

test('tides city: first open of 14-day expanded view draws only temperature', () => {
  const view = simulateExpandedView(TIDES_CITY_TYPES);
  const drawn = view.firstOpen('all');
  assert.deepEqual(drawn, ['temp']);
  assert.deepEqual(view.visibleTypes(), ['temp']);
});

test('tides city: switch away then back to temperature draws only temperature', () => {
  const view = simulateExpandedView(TIDES_CITY_TYPES);
  view.firstOpen('all');
  const tidesDrawn = view.select('tides');
  assert.deepEqual(tidesDrawn, ['tides']);
  assert.deepEqual(view.visibleTypes(), ['tides']);
  const backToTemp = view.select('temp');
  assert.deepEqual(backToTemp, ['temp']);
  assert.deepEqual(view.visibleTypes(), ['temp']);
});

test('non-tides city: first open still defaults to temperature only', () => {
  const view = simulateExpandedView(INLAND_CITY_TYPES);
  const drawn = view.firstOpen('all');
  assert.deepEqual(drawn, ['temp']);
  assert.deepEqual(view.visibleTypes(), ['temp']);
  assert.equal(view.visibleTypes().includes('tides'), false);
});

test('tides stay available but are not drawn until that series is selected', () => {
  const helpers = loadChartSeriesHelpers(fs.readFileSync(path.join(root, 'public', 'app.js'), 'utf8'));
  const containers = mockCityContainers(TIDES_CITY_TYPES);
  assert.deepEqual(fromVm(helpers.availableChartTypesFrom(containers)), TIDES_CITY_TYPES);
  assert.deepEqual(fromVm(helpers.resolveDrawnChartSeries('temp', TIDES_CITY_TYPES)), ['temp']);
  assert.deepEqual(fromVm(helpers.resolveDrawnChartSeries('tides', TIDES_CITY_TYPES)), ['tides']);
  assert.equal(fromVm(helpers.resolveDrawnChartSeries('all', TIDES_CITY_TYPES)).includes('tides'), true);
});

test('first paint ignores a cloned select that still reports all', () => {
  const helpers = loadChartSeriesHelpers(fs.readFileSync(path.join(root, 'public', 'app.js'), 'utf8'));
  const containers = mockCityContainers(TIDES_CITY_TYPES);
  const drawn = fromVm(helpers.paintChartSelector(containers, 'all', true));
  assert.equal(helpers.DEFAULT_CHART_SERIES, 'temp');
  assert.deepEqual(drawn, ['temp']);
  const afterChange = fromVm(helpers.paintChartSelector(containers, 'wind', false));
  assert.deepEqual(afterChange, ['wind']);
});

test('openDailyModal no longer shows every chart container on first paint', () => {
  const js = fs.readFileSync(path.join(root, 'public', 'app.js'), 'utf8');
  assert.equal(js.includes('Show all chart containers so ApexCharts can measure width'), false);
  assert.equal(js.includes("applyChartSeriesVisibility(modal.querySelectorAll('.chart-container'), DEFAULT_CHART_SERIES)"), true);
  assert.equal(js.includes("maybeRenderDailyChart('temp')"), true);
  assert.equal(js.includes('dailyChart.temp.render()'), false);
  assert.equal(js.includes('paintChartSelector(chartContainers, newSelect.value, true)'), true);
  assert.match(js, /function updateChartVisibility\(\) \{[\s\S]*paintChartSelector\(chartContainers, selectedValue, false\)/);
});

test('patched worker JS keeps first-paint temperature default after app-08..10', () => {
  const js = patchedAppJs();
  const helpers = loadChartSeriesHelpers(js);
  const containers = mockCityContainers(TIDES_CITY_TYPES);
  assert.deepEqual(fromVm(helpers.paintChartSelector(containers, 'all', true)), ['temp']);
  assert.equal(js.includes('Show all chart containers so ApexCharts can measure width'), false);
  assert.equal(js.includes('function paintChartSelector'), true);
  assert.equal(js.includes('data.daily.sunrise[dayIndex]'), true);
});
