const test = require('node:test');
const assert = require('assert/strict');
const { execFileSync } = require('child_process');
const path = require('path');

const root = path.resolve(__dirname, '..');
const sources = [
  'ios/JaccuweatherWatch/WatchHourlyPlan.swift',
  'ios/JaccuweatherWatch/WatchPlacePlan.swift',
  'ios/JaccuweatherWatch/WatchPlaceLink.swift',
  'tests/watch-hourly-place-check.swift',
];

test('watch hours follow the place offset and the complication follows the shared place', () => {
  const binary = path.join('/tmp', 'watch-hourly-place-check');
  const sdk = execFileSync('xcrun', ['--sdk', 'macosx', '--show-sdk-path'], { encoding: 'utf8' }).trim();
  execFileSync('xcrun', ['swiftc', '-sdk', sdk, '-o', binary, ...sources], { cwd: root, stdio: 'pipe' });
  const output = execFileSync(binary, { encoding: 'utf8' });
  assert.match(output, /ok/);
});
