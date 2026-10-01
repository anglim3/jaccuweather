const test = require('node:test');
const assert = require('assert/strict');
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const plan = path.join(root, 'ios/Shared/WidgetTimelinePlan.swift');
const loader = path.join(root, 'ios/JaccuweatherWidgets/ConditionsWidget.swift');
const check = path.join(root, 'tests/widget-timeline-plan-check.swift');

test('widget timelines keep the chosen place when the app snapshot is somewhere else', () => {
  assert.ok(fs.existsSync(plan));
  const source = fs.readFileSync(loader, 'utf8');
  assert.match(source, /WidgetTimelinePlan\.decide/);
  assert.match(source, /WidgetTimelinePlan\.samePlace/);
  assert.match(source, /WidgetTimelinePlan\.afterFailedFetch/);
  assert.doesNotMatch(source, /if let stored, stored\.isFresh \{\s*return Loaded\(snapshot: stored/s);
  const binary = path.join('/tmp', 'widget-timeline-plan-check');
  execFileSync('xcrun', [
    'swiftc',
    '-sdk', execFileSync('xcrun', ['--sdk', 'macosx', '--show-sdk-path'], { encoding: 'utf8' }).trim(),
    '-o', binary,
    plan,
    check
  ], { cwd: root, stdio: 'pipe' });
  const output = execFileSync(binary, { encoding: 'utf8' });
  assert.match(output, /ok/);
});
