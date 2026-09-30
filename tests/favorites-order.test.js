const test = require('node:test');
const assert = require('assert/strict');
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const store = path.join(root, 'ios/Jaccuweather/Services/FavoritesStore.swift');
const models = path.join(root, 'ios/Jaccuweather/Models/LocationModels.swift');
const check = path.join(root, 'tests/favorites-order-check.swift');

test('favorites reorder persists in UserDefaults', () => {
  assert.ok(fs.existsSync(store));
  assert.ok(fs.existsSync(models));
  const binary = path.join('/tmp', 'favorites-order-check');
  const sdk = execFileSync('xcrun', ['--sdk', 'macosx', '--show-sdk-path'], { encoding: 'utf8' }).trim();
  execFileSync('xcrun', [
    'swiftc',
    '-sdk', sdk,
    '-o', binary,
    models,
    store,
    check
  ], { cwd: root, stdio: 'pipe' });
  const output = execFileSync(binary, { encoding: 'utf8' });
  assert.match(output, /ok/);
});
