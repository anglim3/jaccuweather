const test = require('node:test');
const assert = require('assert/strict');
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const model = path.join(root, 'ios/Jaccuweather/Services/NOAARadarModel.swift');
const check = path.join(root, 'tests/noaa-mrms-check.swift');

test('NOAA mosaic math, WMS axis order, and playback stamps', () => {
  assert.ok(fs.existsSync(model));
  const binary = path.join('/tmp', 'noaa-mrms-check');
  execFileSync('xcrun', [
    'swiftc',
    '-sdk', execFileSync('xcrun', ['--sdk', 'macosx', '--show-sdk-path'], { encoding: 'utf8' }).trim(),
    '-framework', 'MapKit',
    '-framework', 'CoreLocation',
    '-o', binary,
    model,
    check
  ], { cwd: root, stdio: 'pipe' });
  const output = execFileSync(binary, { encoding: 'utf8' });
  assert.match(output, /ok/);
});
