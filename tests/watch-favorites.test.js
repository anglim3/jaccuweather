const test = require('node:test');
const assert = require('assert/strict');
const { execFileSync } = require('child_process');
const path = require('path');

const root = path.resolve(__dirname, '..');
const sources = [
  'ios/Jaccuweather/Models/LocationModels.swift',
  'ios/Shared/WatchFavoritesPayload.swift',
  'ios/JaccuweatherWatch/WatchPlacePlan.swift',
  'tests/watch-favorites-check.swift',
];

test('watch favorites payload dedupes coordinates and an explicit place stays selected', () => {
  const binary = path.join('/tmp', 'watch-favorites-check');
  const sdk = execFileSync('xcrun', ['--sdk', 'macosx', '--show-sdk-path'], { encoding: 'utf8' }).trim();
  execFileSync('xcrun', ['swiftc', '-sdk', sdk, '-o', binary, ...sources], { cwd: root, stdio: 'pipe' });
  const output = execFileSync(binary, { encoding: 'utf8' });
  assert.match(output, /ok/);
});
