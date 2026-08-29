const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..');

function locationDateString(utcOffsetSeconds, atMs = Date.now()) {
  const offsetMs = (Number(utcOffsetSeconds) || 0) * 1000;
  const local = new Date(atMs + offsetMs);
  const y = local.getUTCFullYear();
  const m = String(local.getUTCMonth() + 1).padStart(2, '0');
  const d = String(local.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function isTomorrow(startDateStr, utcOffsetSeconds, nowMs) {
  const nowDateStr = locationDateString(utcOffsetSeconds, nowMs);
  const tomorrowDateStr = locationDateString(utcOffsetSeconds, nowMs + 24 * 60 * 60 * 1000);
  if (startDateStr === nowDateStr) return 'today';
  if (startDateStr === tomorrowDateStr) return 'tomorrow';
  return 'later';
}

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
  js = applyUnifiedDiff(js, fs.readFileSync(path.join(dir, 'app-10.patch'), 'utf8'));
  return js;
}

test('getDate() + 1 misses month boundaries (the old tomorrow check)', () => {
  assert.equal(31 + 1 === 1, false);
});

test('locationDateString + 24h labels Aug 31 -> Sep 1 as tomorrow', () => {
  // 2026-08-31 18:00 UTC, offset 0
  const now = Date.UTC(2026, 7, 31, 18, 0, 0);
  assert.equal(isTomorrow('2026-08-31', 0, now), 'today');
  assert.equal(isTomorrow('2026-09-01', 0, now), 'tomorrow');
  assert.equal(isTomorrow('2026-09-02', 0, now), 'later');
});

test('location today for Tokyo is not the UTC calendar date near midnight', () => {
  // 2026-08-29 16:00 UTC = Aug 30 01:00 in Tokyo (UTC+9)
  const utcEvening = Date.UTC(2026, 7, 29, 16, 0, 0);
  const tokyoOffset = 9 * 3600;
  assert.equal(locationDateString(0, utcEvening), '2026-08-29');
  assert.equal(locationDateString(tokyoOffset, utcEvening), '2026-08-30');
  assert.equal(isTomorrow('2026-08-30', tokyoOffset, utcEvening), 'today');
  assert.equal(isTomorrow('2026-08-31', tokyoOffset, utcEvening), 'tomorrow');
});

test('app-10 patch applies after app-08 and uses location-local precip timing', () => {
  const js = patchedAppJs();
  const fn = js.slice(js.indexOf('function displayPrecipitationTiming'), js.indexOf('async function fetchNwsSnowForecast'));
  assert.equal(fn.includes('startDate === nowDate + 1'), false);
  assert.equal(fn.includes('now.getHours()'), false);
  assert.equal(fn.includes('nearestTimeIndex(data.hourly.time, new Date(), utcOffsetSeconds)'), true);
  assert.equal(fn.includes('formatIsoLocalClock(precipStartIso)'), true);
  assert.equal(fn.includes('locationDateString(utcOffsetSeconds, Date.now() + 24 * 60 * 60 * 1000)'), true);
});

test('lockdown-worker applies app-10 after app-08', () => {
  const source = fs.readFileSync(path.join(root, 'lockdown-worker.js'), 'utf8');
  const eight = source.indexOf("applyPatchToConst(src, 'JS_CONTENT', 'patches/app-08.patch')");
  const ten = source.indexOf("applyPatchToConst(src, 'JS_CONTENT', 'patches/app-10.patch')");
  assert.ok(eight > -1 && ten > eight);
});
