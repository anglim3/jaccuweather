const test = require('node:test');
const assert = require('assert/strict');
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const model = path.join(root, 'ios/Jaccuweather/Models/SnowTotals.swift');
const check = path.join(root, 'tests/weekly-snow-check.swift');

test('weekly snow periods and NWS 48h overlap', () => {
  assert.ok(fs.existsSync(model));
  const binary = path.join('/tmp', 'weekly-snow-check');
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
