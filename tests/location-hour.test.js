const test = require('node:test');
const assert = require('assert/strict');
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const model = path.join(root, 'ios/Jaccuweather/Models/JSONMap.swift');
const check = path.join(root, 'tests/location-hour-check.swift');

test('location hour ignores the phone timezone', () => {
  assert.ok(fs.existsSync(model));
  const binary = path.join('/tmp', 'location-hour-check');
  const sdk = execFileSync('xcrun', ['--sdk', 'macosx', '--show-sdk-path'], { encoding: 'utf8' }).trim();
  execFileSync('xcrun', ['swiftc', '-sdk', sdk, '-o', binary, model, check], { cwd: root, stdio: 'pipe' });
  const output = execFileSync(binary, { encoding: 'utf8' });
  assert.match(output, /ok/);
});
