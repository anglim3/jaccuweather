const test = require('node:test');
const assert = require('assert/strict');
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const shared = path.join(root, 'ios/Shared/ControlOpen.swift');
const model = path.join(root, 'ios/Jaccuweather/Services/ConditionsShareCopy.swift');
const check = path.join(root, 'tests/conditions-share-check.swift');

test('current conditions share summary', () => {
  assert.ok(fs.existsSync(shared));
  assert.ok(fs.existsSync(model));
  const binary = path.join('/tmp', 'conditions-share-check');
  execFileSync('xcrun', [
    'swiftc',
    '-sdk', execFileSync('xcrun', ['--sdk', 'macosx', '--show-sdk-path'], { encoding: 'utf8' }).trim(),
    '-o', binary,
    shared,
    model,
    check
  ], { cwd: root, stdio: 'pipe' });
  const output = execFileSync(binary, { encoding: 'utf8' });
  assert.match(output, /ok/);
});
