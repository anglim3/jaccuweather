const test = require('node:test');
const assert = require('assert/strict');
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const source = path.join(root, 'ios/Jaccuweather/Views/ForecastDisplay.swift');
const check = path.join(root, 'tests/forecast-display-check.swift');

test('forecast display keeps 12-hour clocks and one unit style', () => {
  assert.ok(fs.existsSync(source));
  const binary = path.join('/tmp', 'forecast-display-check');
  const sdk = execFileSync('xcrun', ['--sdk', 'macosx', '--show-sdk-path'], { encoding: 'utf8' }).trim();
  execFileSync('xcrun', ['swiftc', '-sdk', sdk, '-o', binary, source, check], { cwd: root, stdio: 'pipe' });
  const output = execFileSync(binary, { encoding: 'utf8' });
  assert.match(output, /ok/);
});
