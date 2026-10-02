const test = require('node:test');
const assert = require('assert/strict');
const { execFileSync } = require('child_process');
const path = require('path');

const root = path.resolve(__dirname, '..');
const sources = [
  'ios/JaccuweatherWatch/WatchHourlyPlan.swift',
  'tests/watch-hour-detail-check.swift',
];

test('watch hour detail uses 12-hour time, precip amounts, and extras only when present', () => {
  const binary = path.join('/tmp', 'watch-hour-detail-check');
  const sdk = execFileSync('xcrun', ['--sdk', 'macosx', '--show-sdk-path'], { encoding: 'utf8' }).trim();
  execFileSync('xcrun', ['swiftc', '-sdk', sdk, '-o', binary, ...sources], { cwd: root, stdio: 'pipe' });
  const output = execFileSync(binary, { encoding: 'utf8' });
  assert.match(output, /ok/);
});
