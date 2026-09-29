const test = require('node:test');
const assert = require('assert/strict');
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const model = path.join(root, 'ios/Jaccuweather/Services/AlertNotificationCopy.swift');
const check = path.join(root, 'tests/alert-notification-check.swift');

test('local NWS alert notification copy and id dedupe', () => {
  assert.ok(fs.existsSync(model));
  const binary = path.join('/tmp', 'alert-notification-check');
  execFileSync('xcrun', [
    'swiftc',
    '-sdk', execFileSync('xcrun', ['--sdk', 'macosx', '--show-sdk-path'], { encoding: 'utf8' }).trim(),
    '-o', binary,
    model,
    check
  ], { cwd: root, stdio: 'pipe' });
  const output = execFileSync(binary, { encoding: 'utf8' });
  assert.match(output, /ok/);
});
