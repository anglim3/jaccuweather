const test = require('node:test');
const assert = require('assert/strict');
const { execFileSync } = require('child_process');
const path = require('path');

const root = path.resolve(__dirname, '..');
const sources = [
  'ios/JaccuweatherWatch/WatchHourlyPlan.swift',
  'ios/JaccuweatherWatch/WatchDailyPlan.swift',
  'tests/watch-sun-check.swift',
];

test('watch sunrise and sunset stay on the place-local civil day', () => {
  const binary = path.join('/tmp', 'watch-sun-check');
  const sdk = execFileSync('xcrun', ['--sdk', 'macosx', '--show-sdk-path'], { encoding: 'utf8' }).trim();
  execFileSync('xcrun', ['swiftc', '-sdk', sdk, '-o', binary, ...sources], { cwd: root, stdio: 'pipe' });
  const output = execFileSync(binary, { encoding: 'utf8' });
  assert.match(output, /ok/);
});
