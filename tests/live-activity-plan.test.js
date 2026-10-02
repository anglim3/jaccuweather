const test = require('node:test');
const assert = require('assert/strict');
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const model = path.join(root, 'ios/Jaccuweather/Services/LiveActivityPlan.swift');
const sync = path.join(root, 'ios/Jaccuweather/Services/WeatherLiveActivitySync.swift');
const check = path.join(root, 'tests/live-activity-plan-check.swift');

test('live activity place changes replace attributes instead of updating them', () => {
  assert.ok(fs.existsSync(model));
  const syncSource = fs.readFileSync(sync, 'utf8');
  assert.match(syncSource, /LiveActivityPlan\.decide/);
  assert.doesNotMatch(syncSource, /\bprint\(/);
  const binary = path.join('/tmp', 'live-activity-plan-check');
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
