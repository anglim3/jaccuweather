const test = require('node:test');
const assert = require('assert/strict');
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const sources = [
  'ios/JaccuweatherWatchWidgets/WatchComplicationCopy.swift',
  'tests/watch-complication-families-check.swift',
];

test('watch complications add inline and corner beside circular and rectangular', () => {
  const widget = fs.readFileSync(
    path.join(root, 'ios/JaccuweatherWatchWidgets/ConditionsComplication.swift'),
    'utf8'
  );
  const copy = fs.readFileSync(
    path.join(root, 'ios/JaccuweatherWatchWidgets/WatchComplicationCopy.swift'),
    'utf8'
  );
  for (const family of ['accessoryCircular', 'accessoryRectangular', 'accessoryInline', 'accessoryCorner']) {
    assert.match(widget, new RegExp(`\\.${family}\\b`));
    assert.match(copy, new RegExp(`"${family}"`));
  }
  assert.match(widget, /widgetURL\(WatchPlaceLink\.url/);
  assert.match(widget, /private var circular/);
  assert.match(widget, /private var rectangular/);
  assert.doesNotMatch(widget, /sunrise|sunset|\buv\b|\bwind\b/i);

  const binary = path.join('/tmp', 'watch-complication-families-check');
  const sdk = execFileSync('xcrun', ['--sdk', 'macosx', '--show-sdk-path'], { encoding: 'utf8' }).trim();
  execFileSync('xcrun', ['swiftc', '-sdk', sdk, '-o', binary, ...sources], { cwd: root, stdio: 'pipe' });
  const output = execFileSync(binary, { encoding: 'utf8' });
  assert.match(output, /ok/);
});
