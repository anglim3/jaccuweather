const test = require('node:test');
const assert = require('assert/strict');
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const models = path.join(root, 'ios/Jaccuweather/Models/LocationModels.swift');
const check = path.join(root, 'tests/place-name-check.swift');

test('blank reverse-geocode cities and stale search results stay off the place list', () => {
  assert.ok(fs.existsSync(models));
  const binary = path.join('/tmp', 'place-name-check');
  const sdk = execFileSync('xcrun', ['--sdk', 'macosx', '--show-sdk-path'], { encoding: 'utf8' }).trim();
  execFileSync('xcrun', ['swiftc', '-sdk', sdk, '-o', binary, models, check], { cwd: root, stdio: 'pipe' });
  const output = execFileSync(binary, { encoding: 'utf8' });
  assert.match(output, /ok/);
});
