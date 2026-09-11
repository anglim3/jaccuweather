const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..');

function loadPatchApplier() {
  const source = fs.readFileSync(path.join(root, 'lockdown-worker.js'), 'utf8');
  const start = source.indexOf('function parseHunks');
  const end = source.indexOf('function extractJsonStringConst');
  const sandbox = { console };
  vm.runInNewContext(`${source.slice(start, end)}; this.applyUnifiedDiff = applyUnifiedDiff;`, sandbox);
  return sandbox.applyUnifiedDiff;
}

function patchedAppJs() {
  const applyUnifiedDiff = loadPatchApplier();
  let js = fs.readFileSync(path.join(root, 'public', 'app.js'), 'utf8');
  const dir = path.join(root, 'patches');
  const early = fs.readdirSync(dir).filter((f) => /^app-0[1-7]\.patch$/.test(f)).sort();
  js = applyUnifiedDiff(js, early.map((f) => fs.readFileSync(path.join(dir, f), 'utf8')).join(''));
  js = applyUnifiedDiff(js, fs.readFileSync(path.join(dir, 'app-08.patch'), 'utf8'));
  js = applyUnifiedDiff(js, fs.readFileSync(path.join(dir, 'app-09.patch'), 'utf8'));
  js = applyUnifiedDiff(js, fs.readFileSync(path.join(dir, 'app-10.patch'), 'utf8'));
  return js;
}

function loadHelperFromSource(source) {
  const match = source.match(/function formatInstantInLocation\(instant, utcOffsetSeconds[\s\S]*?\n\}/);
  assert.ok(match, 'expected formatInstantInLocation helper in app.js');
  const sandbox = {};
  vm.runInNewContext(`${match[0]}; this.formatInstantInLocation = formatInstantInLocation;`, sandbox);
  return sandbox.formatInstantInLocation;
}

// Independent expectation: shift the true instant by the location offset,
// then read the wall clock with getUTC* (no browser-zone dependence).
function expectedClock(instantMs, utcOffsetSeconds) {
  const shifted = new Date(instantMs + (Number(utcOffsetSeconds) || 0) * 1000);
  let h = shifted.getUTCHours();
  const mi = String(shifted.getUTCMinutes()).padStart(2, '0');
  const ampm = h >= 12 ? 'PM' : 'AM';
  h = h % 12 || 12;
  return `${h}:${mi} ${ampm}`;
}

test('SunCalc instant formats in the location offset, not browser local', () => {
  const js = fs.readFileSync(path.join(root, 'public', 'app.js'), 'utf8');
  const formatInstantInLocation = loadHelperFromSource(js);

  // Simulate a SunCalc moonrise instant: 2026-08-29T12:00:00Z.
  const instant = new Date(Date.UTC(2026, 7, 29, 12, 0, 0));
  const tokyoOffset = 9 * 3600;
  const nycOffset = -4 * 3600;

  assert.equal(formatInstantInLocation(instant, tokyoOffset), '9:00 PM');
  assert.equal(formatInstantInLocation(instant, tokyoOffset), expectedClock(instant.getTime(), tokyoOffset));
  assert.equal(formatInstantInLocation(instant, 0), '12:00 PM');
  assert.equal(formatInstantInLocation(instant, nycOffset), expectedClock(instant.getTime(), nycOffset));

  // A large offset must move the clock: Tokyo and UTC disagree by 9h here,
  // and Tokyo vs New York disagree regardless of the browser timezone.
  assert.notEqual(
    formatInstantInLocation(instant, tokyoOffset),
    formatInstantInLocation(instant, 0)
  );
  assert.notEqual(
    formatInstantInLocation(instant, tokyoOffset),
    formatInstantInLocation(instant, nycOffset)
  );
});

test('helper does not misread a ...Z ISO the way formatIsoLocalClock would', () => {
  const js = fs.readFileSync(path.join(root, 'public', 'app.js'), 'utf8');
  const formatInstantInLocation = loadHelperFromSource(js);
  const instant = new Date('2026-08-29T12:00:00.000Z');
  const tokyoOffset = 9 * 3600;
  // Naive wall-clock reader would print the UTC hour as if it were local.
  assert.equal(formatInstantInLocation(instant, tokyoOffset), '9:00 PM');
  assert.notEqual(formatInstantInLocation(instant, tokyoOffset), '12:00 PM');
  assert.equal(formatInstantInLocation('not-a-date', tokyoOffset), 'N/A');
});

test('moon modal uses the shared helper with the forecast offset and keeps polar handling', () => {
  const js = fs.readFileSync(path.join(root, 'public', 'app.js'), 'utf8');
  const modal = js.slice(js.indexOf('function openMoonDetailsModal'), js.indexOf('function formatTime12Hour'));
  assert.ok(modal.includes('moonClockOffset'), 'modal should derive an offset for moon clocks');
  assert.ok(modal.includes('currentWeatherData'), 'modal offset should come from the current forecast');
  assert.ok(modal.includes('utc_offset_seconds'), 'modal offset should use utc_offset_seconds');
  assert.ok(
    modal.includes('formatInstantInLocation(riseSet.rise, moonClockOffset)'),
    'moonrise should format via the shared helper'
  );
  assert.ok(
    modal.includes('formatInstantInLocation(riseSet.set, moonClockOffset)'),
    'moonset should format via the shared helper'
  );
  assert.equal(modal.includes('formatTime12Hour(riseSet.rise)'), false);
  assert.equal(modal.includes('formatTime12Hour(riseSet.set)'), false);
  assert.ok(modal.includes("'Always up'"), 'polar always-up handling must stay');
  assert.ok(modal.includes("'Always down'"), 'polar always-down handling must stay');
});

test('helper lives next to the timezone helpers and survives lockdown patches', () => {
  const js = fs.readFileSync(path.join(root, 'public', 'app.js'), 'utf8');
  const helperAt = js.indexOf('function formatInstantInLocation');
  const isoClockAt = js.indexOf('function formatIsoLocalClock');
  const parseAt = js.indexOf('function parseLocationLocalIso');
  assert.ok(helperAt > -1 && isoClockAt > -1 && parseAt > -1);
  assert.ok(Math.abs(helperAt - isoClockAt) < 2000, 'helper should sit next to the timezone helpers');

  const patched = patchedAppJs();
  assert.ok(patched.includes('function formatInstantInLocation'), 'helper must survive app-08/09/10');
  assert.ok(patched.includes('formatInstantInLocation(riseSet.rise, moonClockOffset)'));
  assert.ok(patched.includes('formatInstantInLocation(riseSet.set, moonClockOffset)'));
});
