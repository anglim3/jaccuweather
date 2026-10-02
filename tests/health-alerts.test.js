const test = require('node:test');
const assert = require('assert/strict');
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const logicPath = path.join(root, 'ios/Jaccuweather/Resources/Logic/jaccuweather-logic.js');
const alertsPath = path.join(root, 'ios/Jaccuweather/Services/AlertsService.swift');

test('health and alert display helpers', () => {
  const binary = path.join('/tmp', 'health-alerts-check');
  const sdk = execFileSync('xcrun', ['--sdk', 'macosx', '--show-sdk-path'], { encoding: 'utf8' }).trim();
  execFileSync('xcrun', [
    'swiftc',
    '-sdk', sdk,
    '-o', binary,
    path.join(root, 'ios/Jaccuweather/Models/JSONMap.swift'),
    path.join(root, 'ios/Jaccuweather/Models/PollenModels.swift'),
    path.join(root, 'ios/Jaccuweather/Models/AlertModels.swift'),
    path.join(root, 'tests/health-alerts-check.swift')
  ], { cwd: root, stdio: 'pipe' });
  const output = execFileSync(binary, { encoding: 'utf8' });
  assert.match(output, /ok/);
});

test('5-day pollen keeps zeros and does not call a missing count None', () => {
  const logic = require(logicPath);
  const days = logic.buildPollenForecastDays({
    hourly: {
      time: ['2026-10-02T00:00', '2026-10-02T01:00', '2026-10-03T00:00'],
      grass_pollen: [0, 40, null],
      alder_pollen: [null, null, 90],
      birch_pollen: [null, null, null],
      olive_pollen: [null, null, null],
      weed_pollen: [null, null, null]
    },
    pollen_null_display_as_none: {
      hourly: [{ weed_pollen: true }, { weed_pollen: true }, {}]
    }
  });
  assert.equal(days.length, 2);
  assert.equal(days[0].grass, 40);
  assert.equal(days[0].grassLabel, 'Moderate');
  assert.equal(days[0].treeLabel, 'n/a');
  assert.equal(days[0].weedLabel, 'None');
  assert.equal(days[1].tree, 90);
  assert.equal(days[1].treeLabel, 'High');
  assert.equal(days[1].weedLabel, 'n/a');
  assert.equal(days[1].emoji, '😷');

  const empty = logic.buildPollenForecastDays({
    hourly: {
      time: ['2026-10-02T00:00'],
      grass_pollen: [null],
      alder_pollen: [null]
    }
  });
  assert.equal(empty[0].grassLabel, 'n/a');
  assert.equal(empty[0].treeLabel, 'n/a');
  assert.equal(empty[0].emoji, '🌿');
  assert.deepEqual(logic.buildPollenForecastDays({ hourly: {} }), []);
});

test('alert loading does not skip places outside the lower 48', () => {
  const source = fs.readFileSync(alertsPath, 'utf8');
  const loadStart = source.indexOf('func load(');
  const loadEnd = source.indexOf('private', loadStart);
  const load = source.slice(loadStart, loadEnd === -1 ? source.length : loadEnd);
  assert.doesNotMatch(load, /isLikelyUS/);
  assert.match(load, /badStatus\(404/);
  assert.match(source, /case failed/);
});
