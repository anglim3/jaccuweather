const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..');

function loadBuildFunctions() {
  const source = fs.readFileSync(path.join(root, 'build.js'), 'utf8');
  const start = source.indexOf('function hasNumericValue');
  const end = source.indexOf('async function fetchTomorrowPollen');
  assert.ok(start > -1 && end > start, 'expected pollen helpers in build.js');
  const sandbox = { console, POLLEN_HOURLY_PARAMS: 'alder_pollen,birch_pollen,grass_pollen,mugwort_pollen,olive_pollen,ragweed_pollen' };
  vm.runInNewContext(
    `${source.slice(start, end)};
     this.normalizeGooglePollen = normalizeGooglePollen;
     this.normalizeTomorrowPollen = normalizeTomorrowPollen;
     this.hasAnyUsablePollen = hasAnyUsablePollen;`,
    sandbox
  );
  return sandbox;
}

test('Google WEED/RAGWEED entries present without indexInfo are marked as none-display metadata without fake numeric pollen', () => {
  const { normalizeGooglePollen } = loadBuildFunctions();
  const normalized = normalizeGooglePollen({
    dailyInfo: [{
      date: { year: 2026, month: 6, day: 1 },
      pollenTypeInfo: [
        { code: 'GRASS', indexInfo: { value: 4 } },
        { code: 'WEED' }
      ],
      plantInfo: [
        { code: 'RAGWEED' }
      ]
    }]
  });

  assert.equal(normalized.current.grass_pollen, 200);
  assert.equal(normalized.current.weed_pollen, null);
  assert.equal(normalized.current.ragweed_pollen, null);
  assert.equal(normalized.current.mugwort_pollen, null);
  assert.deepEqual(JSON.parse(JSON.stringify(normalized.pollen_null_display_as_none.current)), {
    weed_pollen: true,
    ragweed_pollen: true
  });
  assert.deepEqual(JSON.parse(JSON.stringify(normalized.pollen_null_display_as_none.hourly[0])), {
    weed_pollen: true,
    ragweed_pollen: true
  });
});

test('Google categories absent from provider remain unavailable rather than none', () => {
  const { normalizeGooglePollen } = loadBuildFunctions();
  const normalized = normalizeGooglePollen({
    dailyInfo: [{
      date: { year: 2026, month: 6, day: 1 },
      pollenTypeInfo: [{ code: 'GRASS', indexInfo: { value: 4 } }],
      plantInfo: []
    }]
  });

  assert.equal(normalized.current.weed_pollen, null);
  assert.equal(normalized.current.ragweed_pollen, null);
  assert.equal(normalized.pollen_null_display_as_none.current.weed_pollen, undefined);
  assert.equal(normalized.pollen_null_display_as_none.current.ragweed_pollen, undefined);
});

test('Google WEED category populates hourly.weed_pollen so the 5-day forecast matches today', () => {
  const { normalizeGooglePollen } = loadBuildFunctions();
  const normalized = normalizeGooglePollen({
    dailyInfo: [
      {
        date: { year: 2026, month: 6, day: 1 },
        pollenTypeInfo: [
          { code: 'GRASS', indexInfo: { value: 2 } },
          { code: 'WEED', indexInfo: { value: 3 } }
        ],
        plantInfo: []
      },
      {
        date: { year: 2026, month: 6, day: 2 },
        pollenTypeInfo: [{ code: 'WEED', indexInfo: { value: 4 } }],
        plantInfo: []
      }
    ]
  });

  assert.equal(normalized.current.weed_pollen, 150);
  assert.equal(normalized.hourly.weed_pollen.length, 2);
  assert.deepEqual(JSON.parse(JSON.stringify(normalized.hourly.weed_pollen)), [150, 200]);
  assert.deepEqual(JSON.parse(JSON.stringify(normalized.hourly.grass_pollen)), [100, null]);
});

test('Tomorrow empty timelines payload is not treated as usable pollen', () => {
  const { normalizeTomorrowPollen, hasAnyUsablePollen } = loadBuildFunctions();
  const normalized = normalizeTomorrowPollen({
    data: { timelines: [{ intervals: [{ startTime: '2026-06-01T00:00:00Z', values: {} }] }] }
  });

  assert.equal(normalized.current.grass_pollen, null);
  assert.equal(normalized.current.weed_pollen, null);
  assert.equal(hasAnyUsablePollen(normalized), false);
  assert.deepEqual(JSON.parse(JSON.stringify(normalized.hourly.weed_pollen)), [null]);
});

test('Tomorrow grass/weed indexes populate hourly series including weed_pollen', () => {
  const { normalizeTomorrowPollen, hasAnyUsablePollen } = loadBuildFunctions();
  const normalized = normalizeTomorrowPollen({
    data: {
      timelines: [{
        intervals: [{
          startTime: '2026-06-01T00:00:00Z',
          values: { grassIndex: 2, weedIndex: 3 }
        }]
      }]
    }
  });

  assert.equal(normalized.current.grass_pollen, 100);
  assert.equal(normalized.current.weed_pollen, 150);
  assert.equal(hasAnyUsablePollen(normalized), true);
  assert.deepEqual(JSON.parse(JSON.stringify(normalized.hourly.grass_pollen)), [100]);
  assert.deepEqual(JSON.parse(JSON.stringify(normalized.hourly.weed_pollen)), [150]);
});

test('Tomorrow and handler paths require usable pollen before returning a 200', () => {
  const source = fs.readFileSync(path.join(root, 'build.js'), 'utf8');
  assert.match(source, /if \(!hasAnyUsablePollen\(timelinesData\)\) \{\s*return null;/);
  assert.match(source, /if \(tomorrowData\?\.current && hasAnyUsablePollen\(tomorrowData\)\)/);
});

test('pollen section appears after weather radar in page order', () => {
  const html = fs.readFileSync(path.join(root, 'public', 'index.html'), 'utf8');
  const radarIndex = html.indexOf('<!-- Weather Radar -->');
  const pollenIndex = html.indexOf('<!-- Pollen Forecast -->');
  assert.ok(radarIndex > -1, 'weather radar section exists');
  assert.ok(pollenIndex > -1, 'pollen forecast section exists');
  assert.ok(pollenIndex > radarIndex, 'pollen section should be after weather radar');
});
