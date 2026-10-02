const test = require('node:test');
const assert = require('assert/strict');
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const freeze = path.join(root, 'ios/Jaccuweather/Services/FreezeWarningCopy.swift');
const wind = path.join(root, 'ios/Jaccuweather/Services/WindGustNotificationCopy.swift');
const check = path.join(root, 'tests/notification-route-isolation-check.swift');

test('freeze and high-wind notices do not claim each other', () => {
  assert.ok(fs.existsSync(freeze));
  assert.ok(fs.existsSync(wind));
  const binary = path.join('/tmp', 'notification-route-isolation-check');
  execFileSync('xcrun', [
    'swiftc',
    '-sdk', execFileSync('xcrun', ['--sdk', 'macosx', '--show-sdk-path'], { encoding: 'utf8' }).trim(),
    '-o', binary,
    freeze,
    wind,
    check
  ], { cwd: root, stdio: 'pipe' });
  const output = execFileSync(binary, { encoding: 'utf8' });
  assert.match(output, /ok/);
});
