const test = require('node:test');
const assert = require('assert/strict');
const { execFileSync } = require('child_process');
const path = require('path');

const root = path.resolve(__dirname, '..');
const sources = [
  'ios/Shared/WatchAtmosphere.swift',
  'ios/JaccuweatherWatch/WatchHourlyPlan.swift',
  'ios/JaccuweatherWatch/WatchDailyPlan.swift',
  'ios/JaccuweatherWatch/WatchSpoken.swift',
  'tests/watch-spoken-check.swift',
];

test('watch spoken labels use words for degrees, chance, UV, and AQI', () => {
  const binary = path.join('/tmp', 'watch-spoken-check');
  const sdk = execFileSync('xcrun', ['--sdk', 'macosx', '--show-sdk-path'], { encoding: 'utf8' }).trim();
  execFileSync('xcrun', ['swiftc', '-sdk', sdk, '-o', binary, ...sources], { cwd: root, stdio: 'pipe' });
  const output = execFileSync(binary, { encoding: 'utf8' });
  assert.match(output, /ok/);
});
