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

function loadFirstPaintHelpers(js) {
  const start = js.indexOf('// ─── 14-day / hourly expanded-view chart series');
  assert.ok(start > -1, 'expected chart series helpers in app.js');
  const end = js.indexOf('function maybeRenderDailyChart', start);
  assert.ok(end > start, 'expected helpers before maybeRenderDailyChart');
  const sandbox = { console };
  vm.runInNewContext(`${js.slice(start, end)};
    this.DEFAULT_CHART_SERIES = DEFAULT_CHART_SERIES;
    this.availableChartTypesFrom = availableChartTypesFrom;
    this.applyChartSeriesVisibility = applyChartSeriesVisibility;
    this.resolveDrawnChartSeries = resolveDrawnChartSeries;
    this.paintChartSelector = paintChartSelector;
    this.paintExpandedViewFirstPaint = paintExpandedViewFirstPaint;
    this.ensureDailyDetailsVisible = ensureDailyDetailsVisible;
    this.populateDailyDetailItems = populateDailyDetailItems;
    this.isDetailsStrip = isDetailsStrip;
    this.tideAnnotationPoints = tideAnnotationPoints;`, sandbox);
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

function mockDetailsContainer(display) {
  const children = [];
  return {
    id: 'dailyDetails',
    dataset: { featureHidden: 'false' },
    style: { display: display || '' },
    children,
    get childElementCount() { return children.length; },
    getAttribute(name) {
      if (name === 'data-details-strip') return 'true';
      if (name === 'data-chart-type') return null;
      return null;
    },
    appendChild(item) {
      children.push(item);
      return item;
    }
  };
}

function fromVm(value) {
  return JSON.parse(JSON.stringify(value));
}

function firstOpenExpandedView(availableTypes) {
  const helpers = loadFirstPaintHelpers(fs.readFileSync(path.join(root, 'public', 'app.js'), 'utf8'));
  const hidden = TIDES_CITY_TYPES.filter((t) => !availableTypes.includes(t));
  const charts = mockCityContainers(TIDES_CITY_TYPES, hidden);
  const details = mockDetailsContainer();
  // Include the details strip in the visibility pass — this is the leak PR 13
  // introduced when a broader NodeList or missing data-chart-type hid #dailyDetails.
  const containers = charts.concat([details]);
  const drawn = fromVm(helpers.paintExpandedViewFirstPaint(containers));
  assert.equal(typeof helpers.populateDailyDetailItems, 'function', 'populate-details path must exist');
  helpers.populateDailyDetailItems(details, { className: 'forecast-chip', day: 'one' });
  helpers.populateDailyDetailItems(details, { className: 'forecast-chip', day: 'two' });
  return {
    drawn,
    visibleTypes: charts.filter((c) => c.style.display === 'block').map((c) => c.chartType),
    details
  };
}

test('tides city: first open of 14-day view is temperature-only AND per-day details render', () => {
  const view = firstOpenExpandedView(TIDES_CITY_TYPES);
  assert.deepEqual(view.drawn, ['temp']);
  assert.deepEqual(view.visibleTypes, ['temp']);
  assert.notEqual(view.details.style.display, 'none');
  assert.equal(view.details.dataset.featureHidden, 'false');
  assert.equal(view.details.childElementCount, 2);
  assert.equal(view.details.children[0].className, 'forecast-chip');
});

test('inland city: first open of 14-day view is temperature-only AND per-day details render', () => {
  const view = firstOpenExpandedView(INLAND_CITY_TYPES);
  assert.deepEqual(view.drawn, ['temp']);
  assert.deepEqual(view.visibleTypes, ['temp']);
  assert.equal(view.visibleTypes.includes('tides'), false);
  assert.notEqual(view.details.style.display, 'none');
  assert.equal(view.details.dataset.featureHidden, 'false');
  assert.equal(view.details.childElementCount, 2);
});

test('applyChartSeriesVisibility never hides the details strip even if it is in the NodeList', () => {
  const helpers = loadFirstPaintHelpers(fs.readFileSync(path.join(root, 'public', 'app.js'), 'utf8'));
  const details = mockDetailsContainer('none');
  details.dataset.featureHidden = 'true';
  const containers = mockCityContainers(TIDES_CITY_TYPES).concat([details]);
  fromVm(helpers.applyChartSeriesVisibility(containers, 'temp'));
  assert.notEqual(details.style.display, 'none');
  assert.equal(details.dataset.featureHidden, 'false');
  assert.equal(helpers.isDetailsStrip(details), true);
});

test('openDailyModal still runs the populate-details path after first-paint chart filter', () => {
  const js = fs.readFileSync(path.join(root, 'public', 'app.js'), 'utf8');
  const html = fs.readFileSync(path.join(root, 'public', 'index.html'), 'utf8');
  assert.equal(js.includes('// Populate detailed daily items'), true);
  assert.equal(js.includes('populateDailyDetailItems(detailsContainer, detailItem)'), true);
  assert.equal(js.includes("document.getElementById('dailySnowChart').parentElement"), false);
  assert.equal(js.includes('if (snowChartContainer) snowChartContainer.dataset.featureHidden'), true);
  assert.match(html, /id="dailyDetails"[^>]*data-details-strip="true"/);
  assert.equal(html.includes('id="dailyDetails" class="space-y-3">'), false);
});

function keyedDailyTideAnnotations() {
  // Same shape openDailyModal builds: keyed object, not an array.
  const dailyTideAnnotations = {};
  [
    { index: 2, value: 4.2, text: 'H' },
    { index: 5, value: 0.4, text: 'L' }
  ].forEach((point) => {
    dailyTideAnnotations[`dailyTideLabel_${point.index}_${point.text}`] = {
      x: point.index,
      y: point.value,
      borderColor: 'transparent',
      label: { text: point.text, position: 'top' }
    };
  });
  return dailyTideAnnotations;
}

function mockApexChartsRequiringArrayPoints() {
  const calls = [];
  function ApexCharts(_el, opts) {
    const points = opts && opts.annotations && opts.annotations.points;
    if (!Array.isArray(points)) {
      throw new Error('ApexCharts 4.7 annotations.points must be an array');
    }
    calls.push(points);
    this.render = () => {};
  }
  return { ApexCharts, calls };
}

test('tides city first open: keyed dailyTideAnnotations become an array and details still populate', () => {
  const js = fs.readFileSync(path.join(root, 'public', 'app.js'), 'utf8');
  assert.equal(js.includes('annotations: { points: Object.values(dailyTideAnnotations) }'), true);
  assert.equal(js.includes('annotations: { points: Object.values(tideAnnotations) }'), true);
  assert.equal(js.includes('annotations: { points: dailyTideAnnotations }'), false);
  assert.equal(js.includes('annotations: { points: tideAnnotations }'), false);

  const helpers = loadFirstPaintHelpers(js);
  const keyed = keyedDailyTideAnnotations();
  assert.equal(Array.isArray(keyed), false);
  assert.equal(typeof keyed, 'object');

  const { ApexCharts, calls } = mockApexChartsRequiringArrayPoints();
  const details = mockDetailsContainer();
  const charts = mockCityContainers(TIDES_CITY_TYPES);
  let threwBeforePopulate = false;

  try {
    const drawn = fromVm(helpers.paintExpandedViewFirstPaint(charts.concat([details])));
    assert.deepEqual(drawn, ['temp']);
    // openDailyModal still constructs the tides series when NOAA data exists,
    // even though first paint only renders temperature.
    const points = helpers.tideAnnotationPoints(keyed);
    new ApexCharts({ id: 'dailyTidesChart' }, { annotations: { points } });
    helpers.populateDailyDetailItems(details, { className: 'forecast-chip', day: 'tide-city' });
    assert.deepEqual(drawn, ['temp']);
  } catch (err) {
    threwBeforePopulate = true;
    throw err;
  }

  assert.equal(threwBeforePopulate, false);
  assert.equal(calls.length, 1);
  assert.equal(Array.isArray(calls[0]), true);
  assert.deepEqual(fromVm(calls[0]), fromVm(Object.values(keyed)));
  assert.notEqual(details.style.display, 'none');
  assert.equal(details.childElementCount, 1);
});

test('passing the keyed annotations object to ApexCharts still throws (documents the tides-city bug)', () => {
  const keyed = keyedDailyTideAnnotations();
  const { ApexCharts } = mockApexChartsRequiringArrayPoints();
  assert.throws(
    () => new ApexCharts({ id: 'dailyTidesChart' }, { annotations: { points: keyed } }),
    /annotations\.points must be an array/
  );
});

test('patched worker JS keeps temp-only first paint and still populates daily details', () => {
  const js = patchedAppJs();
  const viewTypes = TIDES_CITY_TYPES;
  const helpers = loadFirstPaintHelpers(js);
  const charts = mockCityContainers(viewTypes);
  const details = mockDetailsContainer();
  const drawn = fromVm(helpers.paintExpandedViewFirstPaint(charts.concat([details])));
  helpers.populateDailyDetailItems(details, { className: 'forecast-chip' });
  assert.deepEqual(drawn, ['temp']);
  assert.notEqual(details.style.display, 'none');
  assert.equal(details.childElementCount, 1);
  assert.equal(js.includes('Populate detailed daily items'), true);
  assert.equal(js.includes('populateDailyDetailItems(detailsContainer, detailItem)'), true);
  assert.equal(js.includes('function paintChartSelector'), true);
  assert.equal(js.includes('data.daily.sunrise[dayIndex]'), true);
  assert.equal(js.includes('annotations: { points: Object.values(dailyTideAnnotations) }'), true);
  assert.equal(js.includes('annotations: { points: Object.values(tideAnnotations) }'), true);
});
