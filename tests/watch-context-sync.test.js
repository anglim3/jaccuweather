const test = require('node:test');
const assert = require('assert/strict');
const { execFileSync } = require('child_process');
const path = require('path');

const root = path.resolve(__dirname, '..');
const sources = [
  'ios/Shared/WatchFavoritesPayload.swift',
  'ios/Shared/WatchContextSync.swift',
  'tests/watch-context-sync-check.swift',
];

test('watch context sync dedupes identical payloads and resends when the session becomes ready', () => {
  const binary = path.join('/tmp', 'watch-context-sync-check');
  const sdk = execFileSync('xcrun', ['--sdk', 'macosx', '--show-sdk-path'], { encoding: 'utf8' }).trim();
  execFileSync('xcrun', ['swiftc', '-sdk', sdk, '-o', binary, ...sources], { cwd: root, stdio: 'pipe' });
  const output = execFileSync(binary, { encoding: 'utf8' });
  assert.match(output, /ok/);
});
